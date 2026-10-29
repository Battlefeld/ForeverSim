//go:build windows

package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"sync"
	"syscall"
	"time"
	"unsafe"
)

var user32 = syscall.NewLazyDLL("user32.dll")
var enumWindows = user32.NewProc("EnumWindows")
var getWindowText = user32.NewProc("GetWindowTextW")
var isWindowVisible = user32.NewProc("IsWindowVisible")
var clientToScreen = user32.NewProc("ClientToScreen")
var setDPIAware = user32.NewProc("SetProcessDPIAware")

type point struct{ X, Y int32 }

// Largest region the decoder may need: all cell sizes up to maxPixelCell (see findPixelLayout).
const (
	bitmapW = Columns*maxPixelCell + 4
	bitmapH = Rows*maxPixelCell + 4
)

// NewCallback registrations live for the process lifetime. Register exactly once,
// not once per 40 ms poll. EnumWindows invokes this callback synchronously;
// wowWindowMu serializes the complete enumeration and its shared result.
var wowWindowMu sync.Mutex
var wowWindowFound uintptr
var wowWindowCallback = syscall.NewCallback(func(hwnd, lp uintptr) uintptr {
	v, _, _ := isWindowVisible.Call(hwnd)
	if v == 0 {
		return 1
	}
	name := make([]uint16, 256)
	n, _, _ := getWindowText.Call(hwnd, uintptr(unsafe.Pointer(&name[0])), 256)
	if n > 0 && strings.Contains(strings.ToLower(syscall.UTF16ToString(name[:n])), "world of warcraft") {
		wowWindowFound = hwnd
		return 0
	}
	return 1
})

func wowOrigin() (int, int, bool) {
	wowWindowMu.Lock()
	defer wowWindowMu.Unlock()
	wowWindowFound = 0
	enumWindows.Call(wowWindowCallback, 0)
	found := wowWindowFound
	if found == 0 {
		return 0, 0, false
	}
	var p point
	ok, _, _ := clientToScreen.Call(found, uintptr(unsafe.Pointer(&p)))
	return int(p.X), int(p.Y), ok != 0
}

func runBridge(ctx context.Context, s *Service) error {
	setDPIAware.Call()
	ticker := time.NewTicker(40 * time.Millisecond)
	defer ticker.Stop()
	var a Assembler
	last := ""
	answers := make(chan Reply, 1)
	busy := false
	wasRunning := false
	layout := pixelLayout{cell: CellSize}
	var lastScan, lastDiagnostic, lastOrigin, lastCaptureTry time.Time
	var originX, originY int
	var originOK bool
	validFrames := 0
	// Until the strip was found, read the area for cells up to 3 px (1540x16); afterwards only the
	// area of the calibrated strip. A full scan (4100x36, all cell sizes) runs rarely.
	readW, readH := Columns*3+4, Rows*3+4
	calibrated := false
	var capture *dxgiCapture
	defer func() { capture.Close() }()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case r := <-answers:
			busy = false
			if e := publishReply(s.cfg.Addons, r); e != nil {
				log.Printf("Antwort konnte nicht geschrieben werden: %v", e)
				last = ""
			} else {
				log.Printf("%s #%d: %s %s", r.Kind, r.Sequence, r.Status, r.Message)
			}
		case <-ticker.C:
			if busy {
				continue
			}
			if time.Since(lastOrigin) > 500*time.Millisecond {
				originX, originY, originOK = wowOrigin()
				lastOrigin = time.Now()
			}
			x, y, ok := originX, originY, originOK
			if !ok {
				if wasRunning {
					capture.Close()
					capture = nil
				}
				wasRunning = false
				continue
			}
			if !wasRunning {
				wasRunning = true
				log.Printf("WoW-Fenster erkannt; Client-Ursprung %d,%d", x, y)
				go s.checkClientData(ctx)
				if s.cfg.AutoSync {
					go func() {
						result, issue := syncSources(ctx, s.cfg)
						log.Printf("Quellenpruefung bei erkanntem WoW-Start: %v %v", result, issue)
					}()
				}
			}
			if capture != nil && !capture.Contains(x, y) {
				log.Printf("WoW liegt jetzt auf einem anderen Bildschirm; Aufnahme wird neu gestartet")
				capture.Close()
				capture = nil
			}
			if capture == nil {
				if time.Since(lastCaptureTry) < 2*time.Second {
					continue
				}
				lastCaptureTry = time.Now()
				c, e := newDXGICapture(x, y, bitmapW, bitmapH)
				if e != nil {
					log.Printf("Bildschirmaufnahme nicht verfuegbar: %v", e)
					continue
				}
				capture = c
				log.Printf("Bildschirmaufnahme: DXGI Desktop Duplication auf %s, %s (%dx%d)", c.adapterName, c.outputName, c.right-c.left, c.bottom-c.top)
			}
			raw, e := capture.read(x, y, readW, readH)
			if e != nil {
				if errors.Is(e, errCaptureLost) {
					log.Printf("Bildschirmaufnahme unterbrochen (Moduswechsel, Sperrbildschirm oder Treiber); wird neu aufgebaut")
					capture.Close()
					capture = nil
				} else if time.Since(lastDiagnostic) > 10*time.Second {
					log.Printf("Bildschirmaufnahme fehlgeschlagen: %v", e)
					lastDiagnostic = time.Now()
				}
				continue
			}
			f, e := frameAtPixels(raw, bitmapW, bitmapH, layout)
			scanEvery := 3 * time.Second
			if calibrated {
				scanEvery = 8 * time.Second
			}
			if e != nil && time.Since(lastScan) > scanEvery {
				lastScan = time.Now()
				// The strip is hidden while idle, so most scans find nothing; they need the full area.
				if full, fe := capture.read(x, y, bitmapW, bitmapH); fe == nil {
					var found pixelLayout
					f, found, e = findPixelLayout(full, bitmapW, bitmapH)
					if e == nil {
						layout = found
						calibrated = true
						readW = min(bitmapW, layout.x+int(float64(Columns)*layout.cell)+4)
						readH = min(bitmapH, layout.y+int(float64(Rows)*layout.cell)+4)
						log.Printf("Pixelfeld kalibriert: %.3f Pixel/Zelle, Versatz %d,%d (Aufnahmebereich %dx%d)", layout.cell, layout.x, layout.y, readW, readH)
					}
				}
			}
			if e != nil {
				if time.Since(lastDiagnostic) > 10*time.Second {
					log.Printf("WoW %d,%d: kein gueltiges Pixelfeld; WoW im Vordergrund und /fc ping senden (gueltige Frames bisher: %d)", x, y, validFrames)
					lastDiagnostic = time.Now()
				}
				continue
			}
			validFrames++
			if validFrames == 1 {
				log.Printf("Erster gueltiger Pixel-Frame: Teil %d/%d", f.Index+1, f.Total)
			}
			msg, e := a.Add(f)
			if e != nil || msg == nil {
				continue
			}
			j, e := decodeJob(msg)
			if e != nil {
				continue
			}
			key := fmt.Sprintf("%s/%d/%s", j.Session, j.Sequence, j.Revision)
			if key == last {
				continue
			}
			log.Printf("Anfrage empfangen: %s #%d", j.Kind, j.Sequence)
			last = key
			busy = true
			go func() { r := s.Execute(ctx, j); answers <- r }()
		}
	}
}

// captureSelfTest checks the screen capture without WoW and without any addon: it duplicates the monitor
// that holds the WoW window (or the primary monitor), reads the strip area for a few seconds and prints
// numbers only (timings, brightness statistics); no pixels are stored or shown.
func captureSelfTest() error {
	setDPIAware.Call()
	x, y, ok := wowOrigin()
	if ok {
		log.Printf("WoW-Fenster gefunden, Client-Ursprung %d,%d", x, y)
	} else {
		x, y = 0, 0
		log.Printf("Kein WoW-Fenster gefunden; getestet wird der Bereich oben links am Hauptbildschirm (0,0)")
	}
	c, e := newDXGICapture(x, y, bitmapW, bitmapH)
	if e != nil {
		return fmt.Errorf("Aufnahme konnte nicht gestartet werden: %w", e)
	}
	defer c.Close()
	log.Printf("Aufnahme gestartet: %s, %s, %dx%d", c.adapterName, c.outputName, c.right-c.left, c.bottom-c.top)
	w, h := Columns*3+4, Rows*3+4
	var worst, total time.Duration
	reads, lost := 0, 0
	var bright, samples uint64
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		t0 := time.Now()
		raw, e := c.read(x, y, w, h)
		d := time.Since(t0)
		if e != nil {
			if errors.Is(e, errCaptureLost) {
				lost++
				time.Sleep(100 * time.Millisecond)
				continue
			}
			return fmt.Errorf("Lesen fehlgeschlagen: %w", e)
		}
		reads++
		total += d
		if d > worst {
			worst = d
		}
		for row := 0; row < h; row++ {
			base := row * bitmapW * 4
			for col := 0; col < w; col += 8 {
				i := base + col*4
				bright += uint64(raw[i]) + uint64(raw[i+1]) + uint64(raw[i+2])
				samples++
			}
		}
		time.Sleep(40 * time.Millisecond)
	}
	if reads == 0 {
		return fmt.Errorf("keine Daten gelesen (%d Verluste)", lost)
	}
	avg := total / time.Duration(reads)
	log.Printf("Gelesen: %d Mal, Dauer im Mittel %v, laengste %v, Verluste %d", reads, avg, worst, lost)
	if samples > 0 {
		log.Printf("Mittlere Helligkeit der gelesenen Stichproben (R+G+B): %d von 765", bright/samples)
	}
	if lost > 0 {
		log.Printf("Hinweis: Die Aufnahme musste %d Mal neu aufgebaut werden.", lost)
	}
	log.Printf("Selbsttest abgeschlossen: OK")
	return nil
}
