package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	lua "github.com/yuin/gopher-lua"
)

// Bulk path for the auction house: the addon cannot send hundreds of items through the pixel strip in
// reasonable time, so it stores one complete job in its SavedVariables (ForeverCoreBridgeDB.ahJob.json)
// and reloads the UI. WoW writes the file on reload; this watcher reads it, computes the job and
// publishes the reply into the same answer slots as every other job (the job asks for slot 1).

// savedVariablesFiles lists the account-wide ForeverCoreBridge.lua files below the WoW folder that
// belongs to the AddOns folder (…\_classic_beta_\Interface\AddOns → …\_classic_beta_\WTF).
func savedVariablesFiles(addons string) []string {
	if addons == "" {
		return nil
	}
	wow := filepath.Dir(filepath.Dir(filepath.Clean(addons)))
	files, _ := filepath.Glob(filepath.Join(wow, "WTF", "Account", "*", "SavedVariables", "ForeverCoreBridge.lua"))
	return files
}

// readAHJob evaluates a SavedVariables file in an empty Lua state (no libraries, nothing but the data
// assignments WoW writes) and returns the stored job; ok is false when the file holds no job.
func readAHJob(path string) (j Job, ok bool, err error) {
	L := lua.NewState(lua.Options{SkipOpenLibs: true})
	defer L.Close()
	if err = L.DoFile(path); err != nil {
		return j, false, err
	}
	db, isTable := L.GetGlobal("ForeverCoreBridgeDB").(*lua.LTable)
	if !isTable {
		return j, false, nil
	}
	entry, isTable := db.RawGetString("ahJob").(*lua.LTable)
	if !isTable {
		return j, false, nil
	}
	text, isString := entry.RawGetString("json").(lua.LString)
	if !isString || len(text) == 0 {
		return j, false, nil
	}
	j, err = decodeJob([]byte(text))
	if err != nil {
		return j, false, err
	}
	return j, true, nil
}

func watchSavedVariables(ctx context.Context, s *Service) {
	if s.cfg.Addons == "" {
		return
	}
	seen := map[string]time.Time{}
	done := ""
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		for _, path := range savedVariablesFiles(s.cfg.Addons) {
			info, e := os.Stat(path)
			if e != nil || !info.ModTime().After(seen[path]) {
				continue
			}
			j, ok, e := readAHJob(path)
			if e != nil {
				continue // probably still being written; try again on the next tick
			}
			seen[path] = info.ModTime()
			key := fmt.Sprintf("%s/%d", j.Session, j.Sequence)
			if !ok || j.Kind != "item" || key == done {
				continue
			}
			done = key
			log.Printf("Auktionshaus-Auftrag aus %s: %d Items", filepath.Base(path), len(array(j.Payload, "items")))
			go func(j Job) {
				t0 := time.Now()
				r := s.Execute(ctx, j)
				if e := publishReply(s.cfg.Addons, r); e != nil {
					log.Printf("Antwort konnte nicht geschrieben werden: %v", e)
					return
				}
				log.Printf("Auktionshaus-Auftrag fertig in %v: %s %s", time.Since(t0).Round(time.Millisecond), r.Status, r.Message)
			}(j)
		}
	}
}
