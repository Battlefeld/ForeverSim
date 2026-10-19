package main

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

var sourceMu sync.RWMutex
var syncMu sync.Mutex

type SourceState struct {
	Repo     string `json:"repo"`
	Revision string `json:"revision"`
	SHA256   string `json:"sha256"`
	Checked  string `json:"checked"`
	Status   string `json:"status"`
	Error    string `json:"error,omitempty"`
}

func fetchBounded(ctx context.Context, url string, max int64) ([]byte, error) {
	req, e := http.NewRequestWithContext(ctx, "GET", url, nil)
	if e != nil {
		return nil, e
	}
	req.Header.Set("User-Agent", "ForeverCore/"+Version)
	client := &http.Client{Timeout: 90 * time.Second}
	r, e := client.Do(req)
	if e != nil {
		return nil, e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d: %s", r.StatusCode, url)
	}
	b, e := io.ReadAll(io.LimitReader(r.Body, max+1))
	if e != nil {
		return nil, e
	}
	if int64(len(b)) > max {
		return nil, fmt.Errorf("Quelle ueberschreitet Downloadgrenze")
	}
	return b, nil
}
func extractSource(b []byte, root string) error {
	r, e := zip.NewReader(bytes.NewReader(b), int64(len(b)))
	if e != nil {
		return e
	}
	var total int64
	for _, f := range r.File {
		if f.FileInfo().IsDir() {
			continue
		}
		if f.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("Symlink im Quellarchiv")
		}
		parts := strings.SplitN(f.Name, "/", 2)
		if len(parts) != 2 {
			continue
		}
		rel := parts[1]
		clean := filepath.Clean(filepath.FromSlash(rel))
		if filepath.IsAbs(clean) || clean == ".." || strings.HasPrefix(clean, ".."+string(os.PathSeparator)) {
			return fmt.Errorf("Unsicherer Archivpfad")
		}
		ext := strings.ToLower(filepath.Ext(clean))
		if ext != ".lua" && ext != ".json" && ext != ".toc" && ext != ".xml" && ext != ".md" && ext != ".txt" && filepath.Base(clean) != "LICENSE" {
			continue
		}
		if f.UncompressedSize64 > 32<<20 {
			return fmt.Errorf("Quelldatei zu gross")
		}
		total += int64(f.UncompressedSize64)
		if total > 350<<20 {
			return fmt.Errorf("Quellarchiv entpackt zu gross")
		}
		in, e := f.Open()
		if e != nil {
			return e
		}
		data, e := io.ReadAll(io.LimitReader(in, 32<<20+1))
		in.Close()
		if e != nil {
			return e
		}
		if e = atomicWrite(filepath.Join(root, clean), data); e != nil {
			return e
		}
	}
	return nil
}
func copyTree(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d os.DirEntry, e error) error {
		if e != nil {
			return e
		}
		rel, _ := filepath.Rel(src, path)
		if d.IsDir() {
			return os.MkdirAll(filepath.Join(dst, rel), 0755)
		}
		if d.Type()&os.ModeSymlink != 0 {
			return fmt.Errorf("Symlink in Runtime")
		}
		b, e := os.ReadFile(path)
		if e != nil {
			return e
		}
		return os.WriteFile(filepath.Join(dst, rel), b, 0644)
	})
}
func luaProgram(ctx context.Context, cfg Config, cwd, script string, args []string, env map[string]string) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	cmd := exec.CommandContext(ctx, cfg.Lua, append([]string{script}, args...)...)
	cmd.Dir = cwd
	cmd.Env = os.Environ()
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	out, e := cmd.CombinedOutput()
	if e != nil {
		return fmt.Errorf("%s: %v: %.1200s", filepath.Base(script), e, out)
	}
	return nil
}
func activeRuntime(cfg Config) string {
	var p map[string]any
	if loadJSON(filepath.Join(cfg.Data, "active.json"), &p) == nil {
		if id := str(p, "generation"); id != "" && filepath.Base(id) == id {
			path := filepath.Join(cfg.Data, "Generations", id, "Runtime")
			if _, e := os.Stat(filepath.Join(path, "ForeverCore", "headless.lua")); e == nil {
				return path
			}
		}
	}
	return cfg.Runtime
}
func syncSources(ctx context.Context, cfg Config) (any, error) {
	if !syncMu.TryLock() {
		return map[string]any{"status": "running", "message": "Quellenaufbau laeuft bereits; aktiver Stand bleibt verwendbar"}, nil
	}
	defer syncMu.Unlock()
	sources := []string{"RestedXP/RXPGuides", "Questie/QuestieDB"}
	var report []SourceState
	roots := map[string]string{}
	changed := false
	for _, repo := range sources {
		state := SourceState{Repo: repo, Checked: time.Now().UTC().Format(time.RFC3339), Status: "error"}
		var meta map[string]any
		b, e := fetchBounded(ctx, "https://api.github.com/repos/"+repo+"/commits?per_page=1", 2<<20)
		if e == nil {
			var commits []map[string]any
			e = json.Unmarshal(b, &commits)
			if e == nil && len(commits) > 0 {
				meta = commits[0]
			} else if e == nil {
				e = fmt.Errorf("Commitliste leer")
			}
		}
		if e != nil {
			state.Error = e.Error()
			report = append(report, state)
			continue
		}
		rev := str(meta, "sha")
		if len(rev) != 40 {
			state.Error = "Revision fehlt"
			report = append(report, state)
			continue
		}
		state.Revision = rev
		dir := filepath.Join(cfg.Data, "Sources", strings.ReplaceAll(repo, "/", "_"), rev)
		var prior SourceState
		if loadJSON(filepath.Join(dir, "source.json"), &prior) == nil && prior.Revision == rev {
			state = prior
			state.Checked = time.Now().UTC().Format(time.RFC3339)
			state.Status = "cached"
			roots[repo] = dir
			report = append(report, state)
			continue
		}
		b, e = fetchBounded(ctx, "https://codeload.github.com/"+repo+"/zip/"+rev, 100<<20)
		if e == nil {
			e = extractSource(b, dir)
		}
		if e != nil {
			state.Error = e.Error()
			report = append(report, state)
			continue
		}
		hash := sha256.Sum256(b)
		state.SHA256 = hex.EncodeToString(hash[:])
		state.Status = "downloaded"
		if e = atomicWrite(filepath.Join(dir, "source.json"), jsonBytes(state)); e != nil {
			return nil, e
		}
		changed = true
		roots[repo] = dir
		report = append(report, state)
	}
	result := map[string]any{"sources": report, "activated": false, "engine": "Pinned MythicSim; Datenupdates aendern keine Kampfformeln"}
	_ = atomicWrite(filepath.Join(cfg.Data, "sources.json"), jsonBytes(result))
	if len(roots) != len(sources) {
		return result, fmt.Errorf("Nicht alle Routenquellen verfuegbar; letzter funktionierender Stand bleibt aktiv")
	}
	var active map[string]any
	_ = loadJSON(filepath.Join(cfg.Data, "active.json"), &active)
	revs := report[0].Revision + "/" + report[1].Revision
	evidence, evidenceHash, evidenceError := foreverEvidence(ctx, cfg)
	if evidenceError != nil {
		result["foreverdb"] = map[string]any{"status": "unavailable", "message": evidenceError.Error()}
	} else {
		result["foreverdb"] = map[string]any{"status": "validated", "shards": 64, "sha256": evidenceHash}
	}
	runtimeHash, hashError := routeRuntimeHash(cfg.Runtime)
	if hashError != nil {
		return result, hashError
	}
	if !changed && str(active, "runtimeHash") == runtimeHash && str(active, "sources") == revs && (evidenceError != nil || str(active, "foreverdbHash") == evidenceHash) {
		result["activated"] = true
		result["generation"] = active["generation"]
		return result, nil
	}
	id := time.Now().UTC().Format("20060102T150405.000000000")
	stage := filepath.Join(cfg.Data, "Generations", id, "Runtime")
	activated := false
	defer func() {
		if !activated {
			_ = os.RemoveAll(filepath.Dir(stage))
		}
	}()
	if e := copyTree(cfg.Runtime, stage); e != nil {
		return result, e
	}
	if evidenceError == nil {
		if e := atomicWrite(filepath.Join(stage, "ForeverDungeonQuest", "QuestForeverDBUpdate.lua"), []byte(evidence)); e != nil {
			return result, e
		}
	}
	H := filepath.Join(stage, "_dev", "harness")
	qdb := roots["Questie/QuestieDB"]
	// Explicit upstream exporter; generated data is checked by its round-trip validation.
	if e := luaProgram(ctx, cfg, qdb, "tools/export-forever.lua", []string{"--include-authored"}, nil); e != nil {
		return result, e
	}
	for _, entry := range []struct{ script, out string }{{"update_layer.lua", "QuestieForeverUpdate.lua"}, {"update_layer60.lua", "QuestieForeverUpdate60.lua"}} {
		args := []string{H, stage, qdb, filepath.Join(stage, "ForeverDungeonQuest", entry.out), report[1].Revision}
		if e := luaProgram(ctx, cfg, stage, filepath.Join(stage, "_dev", "questie", entry.script), args, nil); e != nil {
			return result, e
		}
	}
	variants := []struct{ key, file string }{{"skip", "Schnell_RXP.lua"}, {"dungeon", "Schnell_Dungeon_RXP.lua"}, {"balanced", "Balanced_RXP.lua"}, {"completion", "Vollstaendig_RXP.lua"}}
	for _, level := range []int{30, 60} {
		for _, v := range variants {
			folder, file := "ForeverDungeonQuest/Routen", v.file
			if level == 60 {
				folder = "ForeverDungeonQuestRoutes60"
				file = strings.TrimSuffix(v.file, ".lua") + "_60.lua"
			}
			args := []string{H, stage, roots["RestedXP/RXPGuides"], filepath.Join(stage, folder, file), filepath.Join(stage, "ForeverCore", fmt.Sprintf("%s-%d-source-report.txt", v.key, level)), report[0].Revision}
			if e := luaProgram(ctx, cfg, stage, filepath.Join(stage, "_dev", "rxp", "compile.lua"), args, map[string]string{"RXP_TARGET_LEVEL": fmt.Sprint(level), "RXP_VARIANT": v.key}); e != nil {
				return result, e
			}
		}
	}
	check := &RouteService{Root: stage, Lua: cfg.Lua}
	for _, mode := range []string{"speed", "balanced", "completion"} {
		_, e := check.Build(ctx, map[string]any{"race": "Human", "class": "WARRIOR", "faction": "Alliance", "level": float64(1), "map": float64(1429), "x": float64(48), "y": float64(42), "xp": float64(0), "xpMax": float64(400), "money": float64(0), "mode": mode})
		if e != nil {
			return result, fmt.Errorf("Neue Routendaten abgelehnt: %w", e)
		}
	}
	for _, sample := range []struct {
		race, class, faction, mode string
		level                      int
	}{
		{"Human", "WARRIOR", "Alliance", "speed", 35}, {"Orc", "SHAMAN", "Horde", "balanced", 45}, {"NightElf", "DRUID", "Alliance", "completion", 59},
	} {
		state := map[string]any{"race": sample.race, "class": sample.class, "faction": sample.faction, "mode": sample.mode, "level": float64(sample.level), "xp": float64(0), "money": float64(0)}
		route, e := check.Build(ctx, state)
		if e != nil {
			return result, fmt.Errorf("Neue Level-%d-Route abgelehnt: %w", sample.level, e)
		}
		if len(array(route, "chapters")) == 0 {
			return result, fmt.Errorf("Neue Level-%d-Route enthaelt keine Kapitel", sample.level)
		}
	}
	sourceMu.Lock()
	e := atomicWrite(filepath.Join(cfg.Data, "active.json"), jsonBytes(map[string]any{"generation": id, "sources": revs, "foreverdbHash": evidenceHash, "runtimeHash": runtimeHash}))
	sourceMu.Unlock()
	if e != nil {
		return result, e
	}
	activated = true
	result["activated"] = true
	result["generation"] = id
	_ = atomicWrite(filepath.Join(cfg.Data, "sources.json"), jsonBytes(result))
	return result, nil
}

// Recompile when the shipped planner or its inputs change, even when upstream refs do not.
func routeRuntimeHash(root string) (string, error) {
	hash := sha256.New()
	for _, folder := range []string{"ForeverDungeonQuest", "ForeverDungeonQuestRoutes60", "_dev"} {
		e := filepath.WalkDir(filepath.Join(root, folder), func(path string, entry os.DirEntry, issue error) error {
			if issue != nil {
				return issue
			}
			if entry.IsDir() {
				return nil
			}
			ext := filepath.Ext(path)
			if ext != ".lua" && ext != ".toc" {
				return nil
			}
			rel, e := filepath.Rel(root, path)
			if e != nil {
				return e
			}
			b, e := os.ReadFile(path)
			if e != nil {
				return e
			}
			hash.Write([]byte(filepath.ToSlash(rel)))
			hash.Write([]byte{0})
			hash.Write(b)
			hash.Write([]byte{0})
			return nil
		})
		if e != nil {
			return "", e
		}
	}
	return hex.EncodeToString(hash.Sum(nil)), nil
}
