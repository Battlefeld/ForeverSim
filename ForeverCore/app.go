package main

// ForeverCore as an app: started without arguments it opens its window (a page served on this computer only, shown
// in an app window of Edge, window_windows.go) instead of a console. The window installs and repairs, shows the
// state of the connection to WoW and starts and stops it. The connection runs in this process; closing the window
// leaves it running, starting ForeverCore.exe again opens the window of the running one. With arguments
// (-request, -sync, -config ...) ForeverCore works as before.

import (
	"context"
	"crypto/rand"
	_ "embed"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

//go:embed app.html
var appPage string

// appInfoName: where the running app says how to reach it (a second start opens its window).
const appInfoName = "app.json"

// appMode: started without arguments, ForeverCore runs as an app: always on Windows, elsewhere with FC_APP=1.
func appMode(base string) bool { return appPlatform || os.Getenv("FC_APP") == "1" }

// appDir is where ForeverCore keeps its programs and data: the folder of a portable package (it has its config.json
// beside the program), else the user's app folder.
func appDir(base string) string {
	if _, err := os.Stat(filepath.Join(base, "config.json")); err == nil {
		return base
	}
	if d := os.Getenv("FC_APP_DIR"); d != "" {
		return d
	}
	if d, err := os.UserConfigDir(); err == nil && appPlatform {
		if local := os.Getenv("LOCALAPPDATA"); local != "" {
			d = local
		}
		return filepath.Join(d, "ForeverCore")
	}
	if d, err := os.UserConfigDir(); err == nil {
		return filepath.Join(d, "ForeverCore")
	}
	return base
}

type app struct {
	dir     string
	token   string
	payload fs.FS
	log     *logRing

	mu        sync.Mutex
	cancel    context.CancelFunc // the running connection
	bridgeErr string
	busy      string // an installation running
	quit      func()
	update    updateState
	ready     string // a downloaded program, checked, to swap in
	restart   string // the program to start after quitting (an update or going back)
}

// runApp serves the window and keeps the connection running until the window says to quit.
func runApp(base string) {
	dir := appDir(base)
	os.MkdirAll(dir, 0o755)
	ring := &logRing{max: 400}
	if f, err := os.OpenFile(filepath.Join(dir, "ForeverCore.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644); err == nil {
		log.SetOutput(io.MultiWriter(f, ring))
	} else {
		log.SetOutput(ring)
	}
	// a running ForeverCore opens its window instead
	var info struct {
		URL string `json:"url"`
	}
	if loadJSON(filepath.Join(dir, appInfoName), &info) == nil && info.URL != "" {
		c := http.Client{Timeout: 2 * time.Second}
		if r, err := c.Get(strings.Replace(info.URL, "/?t=", "/api/ping?t=", 1)); err == nil {
			r.Body.Close()
			if r.StatusCode == http.StatusOK {
				openWindow(info.URL)
				return
			}
		}
	}
	a := &app{dir: dir, token: randomToken(), payload: embeddedPayload(), log: ring}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		log.Fatal(err)
	}
	url := fmt.Sprintf("http://%s/?t=%s", ln.Addr(), a.token)
	atomicWrite(filepath.Join(dir, appInfoName), jsonBytes(map[string]any{"url": url, "pid": os.Getpid(), "version": Version}))
	defer os.Remove(filepath.Join(dir, appInfoName))
	log.Printf("ForeverCore %s gestartet (%s)", Version, dir)
	srv := &http.Server{Handler: a.routes()}
	quit := make(chan struct{})
	var once sync.Once
	a.quit = func() { once.Do(func() { close(quit) }) }
	go srv.Serve(ln)
	if bad, err := verifyInstall(dir); err == nil && len(bad) == 0 {
		a.startBridge()
	}
	bg, stop := context.WithCancel(context.Background())
	go a.keepUpToDate(bg)
	openWindow(url)
	<-quit
	stop()
	a.stopBridge()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	srv.Shutdown(ctx)
	os.Remove(filepath.Join(dir, appInfoName))
	if a.restart != "" {
		log.Printf("Neustart: %s", a.restart)
		startProgram(a.restart)
	}
}

// installedLabel: the version an installation records (the build number with it, for a release).
func installedLabel() string {
	if Build != "" {
		return Version + "+" + Build
	}
	return Version
}

// keepUpToDate looks for a new program after the start and then every six hours, and installs the addons this
// program carries once WoW is closed, when the installation has those of an older program.
func (a *app) keepUpToDate(ctx context.Context) {
	a.mu.Lock()
	a.update.Enabled = updatePublicKey != "" && Build != ""
	a.mu.Unlock()
	next := time.Now().Add(20 * time.Second)
	for {
		if a.addonsPending() && !wowRunning() {
			var m installManifest
			if loadJSON(filepath.Join(a.dir, installManifestName), &m) == nil {
				log.Printf("Addons dieser Version werden eingespielt (WoW ist geschlossen)")
				a.install(m.Addons)
			}
		}
		if time.Now().After(next) {
			next = time.Now().Add(6 * time.Hour)
			path, m, err := checkUpdate(ctx, a.dir)
			a.mu.Lock()
			a.update.Checked = time.Now().Format("02.01. 15:04")
			a.update.Error = ""
			if err != nil {
				a.update.Error = err.Error()
			} else if path != "" && m != nil {
				if a.ready != path {
					log.Printf("Update %s (%s) bereit", m.Version, m.Build)
				}
				a.ready, a.update.Available = path, m.Version+" ("+m.Build+")"
			}
			a.mu.Unlock()
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(30 * time.Second):
		}
	}
}

// addonsPending: the installation holds the addons of another program than this one.
func (a *app) addonsPending() bool {
	if checkPayload(a.payload) != nil {
		return false
	}
	var m installManifest
	if loadJSON(filepath.Join(a.dir, installManifestName), &m) != nil || m.Addons == "" {
		return false
	}
	return m.Version != installedLabel()
}

// applyUpdate swaps the downloaded program in and restarts with it; goBackUpdate starts the previous one again.
func (a *app) applyUpdate() error {
	a.mu.Lock()
	ready := a.ready
	a.mu.Unlock()
	if ready == "" {
		return fmt.Errorf("kein Update bereit")
	}
	if err := swapProgram(a.dir, ready); err != nil {
		return err
	}
	a.restart = filepath.Join(a.dir, "ForeverCore.exe")
	go func() { time.Sleep(300 * time.Millisecond); a.quit() }()
	return nil
}

func (a *app) goBackUpdate() error {
	if err := goBack(a.dir); err != nil {
		return err
	}
	a.restart = filepath.Join(a.dir, "ForeverCore.exe")
	go func() { time.Sleep(300 * time.Millisecond); a.quit() }()
	return nil
}

func randomToken() string {
	b := make([]byte, 16)
	rand.Read(b)
	return hex.EncodeToString(b)
}

func (a *app) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" || r.URL.Query().Get("t") != a.token {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'")
		io.WriteString(w, strings.ReplaceAll(appPage, "{{TOKEN}}", a.token))
	})
	api := func(path, method string, h func(r *http.Request) (any, error)) {
		mux.HandleFunc(path, func(w http.ResponseWriter, r *http.Request) {
			// only the window: the token, and no request from another page
			if r.URL.Query().Get("t") != a.token && r.Header.Get("X-FC-Token") != a.token {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			if o := r.Header.Get("Origin"); o != "" && o != "http://"+r.Host {
				http.Error(w, "forbidden", http.StatusForbidden)
				return
			}
			if r.Method != method {
				http.Error(w, "method", http.StatusMethodNotAllowed)
				return
			}
			v, err := h(r)
			w.Header().Set("Content-Type", "application/json")
			if err != nil {
				w.WriteHeader(http.StatusBadRequest)
				json.NewEncoder(w).Encode(map[string]string{"error": err.Error()})
				return
			}
			json.NewEncoder(w).Encode(v)
		})
	}
	api("/api/ping", http.MethodGet, func(*http.Request) (any, error) { return map[string]string{"version": Version}, nil })
	api("/api/status", http.MethodGet, func(*http.Request) (any, error) { return a.status(), nil })
	api("/api/wow", http.MethodGet, func(*http.Request) (any, error) { return a.wowChoices(), nil })
	api("/api/install", http.MethodPost, func(r *http.Request) (any, error) {
		var req struct {
			Addons string `json:"addons"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&req); err != nil {
			return nil, err
		}
		return a.install(strings.Trim(strings.TrimSpace(req.Addons), `"`))
	})
	api("/api/bridge", http.MethodPost, func(r *http.Request) (any, error) {
		var req struct {
			On bool `json:"on"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<10)).Decode(&req); err != nil {
			return nil, err
		}
		if req.On {
			a.startBridge()
		} else {
			a.stopBridge()
		}
		return a.status(), nil
	})
	api("/api/update", http.MethodPost, func(r *http.Request) (any, error) {
		var req struct {
			Back bool `json:"back"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<10)).Decode(&req); err != nil {
			return nil, err
		}
		if req.Back {
			return map[string]bool{"restarting": true}, a.goBackUpdate()
		}
		return map[string]bool{"restarting": true}, a.applyUpdate()
	})
	api("/api/log", http.MethodGet, func(*http.Request) (any, error) { return a.log.lines(), nil })
	api("/api/folder", http.MethodPost, func(*http.Request) (any, error) { openFolder(a.dir); return map[string]bool{"ok": true}, nil })
	api("/api/quit", http.MethodPost, func(*http.Request) (any, error) {
		go func() { time.Sleep(200 * time.Millisecond); a.quit() }()
		return map[string]bool{"ok": true}, nil
	})
	return mux
}

// appStatus is what the window shows.
type appStatus struct {
	Version     string        `json:"version"`
	Dir         string        `json:"dir"`
	Installed   bool          `json:"installed"`
	Damaged     []string      `json:"damaged,omitempty"`
	Addons      string        `json:"addons,omitempty"`
	Package     bool          `json:"package"`     // this program carries an installation package
	PackageInfo string        `json:"packageInfo"` // why it cannot install, when it cannot
	Bridge      bool          `json:"bridge"`      // the connection runs
	BridgeError string        `json:"bridgeError,omitempty"`
	Busy        string        `json:"busy,omitempty"`
	WoW         bool          `json:"wow"`  // a WoW client runs
	Data        any           `json:"data"` // the data check (ForeverCore's own status)
	Backup      string        `json:"backup,omitempty"`
	Installs    []WoWInstall  `json:"installs,omitempty"`
	Routes      *routesStatus `json:"routes,omitempty"`
	Update      updateState   `json:"update"`
	Pending     bool          `json:"addonsPending"` // the addons of this version wait for WoW to close
}

type routesStatus struct {
	Version string `json:"version"`
}

func (a *app) status() appStatus {
	st := appStatus{Version: installedLabel(), Dir: a.dir, WoW: wowRunning()}
	bad, err := verifyInstall(a.dir)
	st.Installed = err == nil && len(bad) == 0
	if err == nil {
		st.Damaged = bad
		var m installManifest
		if loadJSON(filepath.Join(a.dir, installManifestName), &m) == nil {
			st.Addons, st.Backup = m.Addons, m.Backup
		}
	}
	if err := checkPayload(a.payload); err != nil {
		st.PackageInfo = err.Error()
	} else {
		st.Package = true
	}
	var man struct {
		Version string `json:"version"`
	}
	if loadJSON(filepath.Join(a.dir, "ForeverRoutes", routesManifest), &man) == nil && man.Version != "" {
		st.Routes = &routesStatus{Version: man.Version}
	}
	a.mu.Lock()
	st.Bridge, st.BridgeError, st.Busy, st.Update = a.cancel != nil, a.bridgeErr, a.busy, a.update
	a.mu.Unlock()
	_, err = os.Stat(filepath.Join(a.dir, "ForeverCore.old.exe"))
	st.Update.Previous = err == nil
	st.Pending = a.addonsPending()
	return st
}

func (a *app) wowChoices() []WoWInstall {
	cur := ""
	var m installManifest
	if loadJSON(filepath.Join(a.dir, installManifestName), &m) == nil {
		cur = m.Addons
	}
	return wowInstalls(append(wowRoots(), cur), cur)
}

func (a *app) install(addons string) (any, error) {
	a.mu.Lock()
	if a.busy != "" {
		a.mu.Unlock()
		return nil, fmt.Errorf("Es laeuft bereits: %s", a.busy)
	}
	a.busy = "Installation"
	a.mu.Unlock()
	defer func() { a.mu.Lock(); a.busy = ""; a.mu.Unlock() }()
	running := a.stopBridge()
	rep, err := install(a.payload, addons, a.dir, installedLabel(), time.Now())
	if err != nil {
		log.Printf("Installation fehlgeschlagen: %v", err)
		if running {
			a.startBridge()
		}
		return nil, err
	}
	log.Printf("Installiert: %d Programmdateien, Addons %s, %d Antwortslots, Sicherung %s", rep.Files, strings.Join(rep.AddonSet, ", "), rep.Slots, rep.Backup)
	if err := placeProgram(a.dir); err != nil {
		log.Printf("Verknuepfungen: %v", err)
	}
	a.startBridge()
	return rep, nil
}

// startBridge starts the connection to WoW with the installed configuration, unless it runs.
func (a *app) startBridge() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.cancel != nil {
		return true
	}
	cfg, err := loadConfig(a.dir, filepath.Join(a.dir, "config.json"))
	if err != nil || cfg.Addons == "" {
		a.bridgeErr = "Noch nicht installiert"
		return false
	}
	ctx, cancel := context.WithCancel(context.Background())
	a.cancel, a.bridgeErr = cancel, ""
	s := newService(cfg)
	go func() {
		log.Printf("Verbindung zu WoW gestartet (%s)", cfg.Addons)
		s.startClientData(ctx)
		go watchSavedVariables(ctx, s)
		err := runBridge(ctx, s)
		a.mu.Lock()
		if ctx.Err() == nil && err != nil {
			a.bridgeErr = err.Error()
			log.Printf("Verbindung beendet: %v", err)
		}
		if a.cancel != nil && ctx.Err() == nil {
			a.cancel = nil
		}
		a.mu.Unlock()
	}()
	return true
}

// stopBridge stops the connection; it says whether one ran.
func (a *app) stopBridge() bool {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.cancel == nil {
		return false
	}
	a.cancel()
	a.cancel = nil
	log.Printf("Verbindung zu WoW angehalten")
	return true
}

// logRing keeps the last lines of the log for the window.
type logRing struct {
	mu  sync.Mutex
	max int
	buf []string
}

func (l *logRing) Write(p []byte) (int, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	for _, line := range strings.Split(strings.TrimRight(string(p), "\n"), "\n") {
		l.buf = append(l.buf, line)
	}
	if len(l.buf) > l.max {
		l.buf = l.buf[len(l.buf)-l.max:]
	}
	return len(p), nil
}

func (l *logRing) lines() []string {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]string(nil), l.buf...)
}
