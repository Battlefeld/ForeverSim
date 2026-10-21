package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"
)

const Version = "0.6.0-hotfix2"

type Config struct {
	Addons         string `json:"addons"`
	Engine         string `json:"engine"`
	EngineRevision string `json:"engineRevision"`
	Runtime        string `json:"runtime"`
	Data           string `json:"data"`
	AutoSync       bool   `json:"autoSync"`
	Lua            string `json:"lua"`
}
type Job struct {
	Schema     int            `json:"schema"`
	Session    string         `json:"session"`
	Sequence   int            `json:"sequence"`
	Revision   string         `json:"revision"`
	Kind       string         `json:"kind"`
	State      map[string]any `json:"state"`
	StateKey   string         `json:"stateKey,omitempty"`
	Payload    map[string]any `json:"payload"`
	ReplyStart int            `json:"replyStart"`
}
type Reply struct {
	Schema     int    `json:"schema"`
	Session    string `json:"session"`
	Sequence   int    `json:"sequence"`
	Revision   string `json:"revision"`
	Kind       string `json:"kind"`
	Status     string `json:"status"`
	Message    string `json:"message,omitempty"`
	Result     any    `json:"result,omitempty"`
	ReplyStart int    `json:"-"`
}
type Service struct {
	cfg    Config
	routes *RouteService
	sim    *SimService
}

func (s *Service) Execute(ctx context.Context, j Job) (r Reply) {
	r = Reply{Schema: 3, Session: j.Session, Sequence: j.Sequence, Revision: j.Revision, Kind: j.Kind, Status: "ok", ReplyStart: j.ReplyStart}
	defer func() {
		if issue := recover(); issue != nil {
			r.Status = "error"
			r.Message = fmt.Sprintf("Auftrag abgelehnt: %v", issue)
			r.Result = nil
		}
	}()
	if j.Schema != 3 || j.Session == "" || j.Sequence < 1 || j.Revision == "" {
		r.Status = "error"
		r.Message = "Ungueltiger Auftrag"
		return r
	}
	// A job may refer to a state sent earlier instead of carrying it again (see statecache.go).
	freshState := j.StateKey != "" && j.State != nil
	if j.StateKey != "" && j.State == nil {
		known, ok := stateStore.get(j.StateKey)
		if !ok {
			r.Status = "error"
			r.Message = stateUnknown + ": Zustand nicht gespeichert, wird erneut gesendet"
			return r
		}
		j.State = known
	}
	if j.State != nil {
		hash := sha256.Sum256([]byte(j.Session))
		_ = atomicWrite(filepath.Join(s.cfg.Data, "Observations", hex.EncodeToString(hash[:8]), fmt.Sprintf("%06d.json", j.Sequence)), jsonBytes(map[string]any{"received": time.Now().UTC().Format(time.RFC3339), "state": j.State, "revision": j.Revision}))
	}
	var e error
	switch j.Kind {
	case "ping":
		r.Result = map[string]any{"version": Version, "engineRevision": s.cfg.EngineRevision, "engine": "MythicSim Go", "stateRefs": true}
	case "route":
		sourceMu.RLock()
		service := &RouteService{Root: activeRuntime(s.cfg), Lua: s.cfg.Lua, ScriptRoot: s.cfg.Runtime}
		r.Result, e = service.Build(ctx, j.State)
		sourceMu.RUnlock()
	case "sim", "item", "rotation", "talents", "talent-next", "talent-build", "weights", "analysis", "leveling", "presets", "talent-compare", "build-detail", "rota-tune", "enhancements":
		r.Result, e = s.sim.Run(ctx, j)
	case "sources":
		go func() { result, issue := syncSources(ctx, s.cfg); log.Printf("Quellen: %v %v", result, issue) }()
		r.Result = map[string]any{"status": "background", "message": "Quellen werden im Hintergrund geprueft. Bestehende Routen bleiben aktiv."}
	default:
		e = fmt.Errorf("Unbekannter Auftrag: %s", j.Kind)
	}
	if e != nil {
		r.Status = "error"
		r.Message = e.Error()
	} else if freshState {
		stateStore.put(j.StateKey, j.State)
	}
	return r
}
func main() {
	config := flag.String("config", "config.json", "Konfiguration")
	request := flag.String("request", "", "JSON-Auftrag fuer Datei-Test")
	output := flag.String("output", "", "JSON-Antwort")
	root := flag.String("runtime", "", "Routen-Laufzeit")
	addons := flag.String("addons", "", "WoW Interface/AddOns")
	syncOnly := flag.Bool("sync", false, "Quellen aktualisieren")
	noCapture := flag.Bool("keine-aufnahme", false, "keine Bildschirmaufnahme: nur Auktionshaus-Auftraege aus der SavedVariables-Datei")
	captureTest := flag.Bool("capturetest", false, "Bildschirmaufnahme testen (ohne WoW), nur Zahlen, keine Bilder")
	flag.Parse()
	if *captureTest {
		if e := captureSelfTest(); e != nil {
			log.Fatal(e)
		}
		return
	}
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	if !filepath.IsAbs(*config) {
		*config = filepath.Join(base, *config)
	}
	cfg := Config{Lua: filepath.Join(base, "Lua.exe"), Runtime: filepath.Join(base, "Runtime"), Engine: filepath.Join(base, "MythicSim.exe"), Data: filepath.Join(base, "Data")}
	if e := loadJSON(*config, &cfg); e != nil && !os.IsNotExist(e) {
		log.Fatal(e)
	}
	if *root != "" {
		cfg.Runtime = *root
	}
	if *addons != "" {
		cfg.Addons = *addons
	}
	if !filepath.IsAbs(cfg.Lua) {
		cfg.Lua = filepath.Join(base, cfg.Lua)
	}
	if !filepath.IsAbs(cfg.Engine) {
		cfg.Engine = filepath.Join(base, cfg.Engine)
	}
	if !filepath.IsAbs(cfg.Runtime) {
		cfg.Runtime = filepath.Join(base, cfg.Runtime)
	}
	if !filepath.IsAbs(cfg.Data) {
		cfg.Data = filepath.Join(base, cfg.Data)
	}
	s := &Service{cfg: cfg, routes: &RouteService{Root: cfg.Runtime, Lua: cfg.Lua}, sim: &SimService{Config: cfg}}
	ctx := context.Background()
	if *syncOnly {
		r, e := syncSources(ctx, cfg)
		if e != nil {
			log.Fatal(e)
		}
		fmt.Println(string(jsonBytes(r)))
		return
	}
	if *request != "" {
		var j Job
		if e := loadJSON(*request, &j); e != nil {
			log.Fatal(e)
		}
		r := s.Execute(ctx, j)
		b := jsonBytes(r)
		if *output == "" {
			fmt.Print(string(b))
		} else if e := atomicWrite(*output, b); e != nil {
			log.Fatal(e)
		}
		if r.Status != "ok" {
			os.Exit(1)
		}
		return
	}
	if cfg.Addons == "" {
		log.Fatal("Installation.ps1 ausfuehren oder -addons angeben")
	}
	log.Printf("ForeverCore %s | MythicSim %s | %s", Version, cfg.EngineRevision, cfg.Addons)
	if *noCapture {
		log.Printf("Bildschirmaufnahme AUS: nur Auktionshaus-Auftraege aus der SavedVariables-Datei (im Spiel /fc pixel aus; nach FC Berechnen /reload). Es wird nichts vom Bildschirm gelesen.")
		watchSavedVariables(ctx, s)
		return
	}
	go watchSavedVariables(ctx, s)
	if e := runBridge(ctx, s); e != nil {
		log.Fatal(e)
	}
}
func decodeJob(b []byte) (Job, error) { var j Job; e := json.Unmarshal(b, &j); return j, e }
