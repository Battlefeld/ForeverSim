package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

const clientQuestLimit = 64 << 20

var clientQuestMu sync.Mutex
var foreverClientBuild = regexp.MustCompile(`^1\.60\.\d+\.\d+$`)

type clientQuestObservation struct {
	ID         int             `json:"id"`
	Title      string          `json:"title"`
	SeenAt     int64           `json:"seenAt"`
	Objectives json.RawMessage `json:"objectives,omitempty"`
}
type clientQuestCapture struct {
	Build   string                            `json:"build"`
	Region  int                               `json:"region"`
	Locale  string                            `json:"locale"`
	Quests  map[string]clientQuestObservation `json:"quests"`
	Turnins map[string]json.RawMessage        `json:"turnins,omitempty"`
}
type clientQuestDocument struct {
	Schema   int                           `json:"schema"`
	Captures map[string]clientQuestCapture `json:"captures"`
}

func clientQuestsPath(cfg Config) string {
	return filepath.Join(cfg.Data, "ClientData", "client-quests.json")
}
func validateClientQuests(raw []byte) (clientQuestDocument, error) {
	var d clientQuestDocument
	if len(raw) > clientQuestLimit {
		return d, fmt.Errorf("Questexport zu gross")
	}
	if err := json.Unmarshal(raw, &d); err != nil {
		return d, err
	}
	if d.Schema != 1 || d.Captures == nil {
		return d, fmt.Errorf("Ungueltiger Questexport")
	}
	locales := map[string]bool{"enUS": true, "enGB": true, "deDE": true, "frFR": true, "esES": true, "esMX": true, "itIT": true, "ptBR": true, "ruRU": true, "koKR": true, "zhCN": true, "zhTW": true}
	for key, c := range d.Captures {
		if !foreverClientBuild.MatchString(c.Build) || !locales[c.Locale] || c.Region < 0 || c.Region > 5 || key != fmt.Sprintf("%s/%d/%s", c.Build, c.Region, c.Locale) || c.Quests == nil {
			return d, fmt.Errorf("Ungueltige Questexport-Identitaet")
		}
		for id, q := range c.Quests {
			if q.ID <= 0 || strconv.Itoa(q.ID) != id || q.Title == "" || len(q.Title) > 4096 || q.SeenAt <= 0 {
				return d, fmt.Errorf("Ungueltige Questbeobachtung %s", id)
			}
		}
	}
	return d, nil
}
func importClientQuests(cfg Config, raw []byte) (int, error) {
	incoming, err := validateClientQuests(raw)
	if err != nil {
		return 0, err
	}
	clientQuestMu.Lock()
	defer clientQuestMu.Unlock()
	path := clientQuestsPath(cfg)
	old := clientQuestDocument{Schema: 1, Captures: map[string]clientQuestCapture{}}
	if b, e := os.ReadFile(path); e == nil {
		old, err = validateClientQuests(b)
		if err != nil {
			return 0, err
		}
	} else if !os.IsNotExist(e) {
		return 0, e
	}
	for key, c := range incoming.Captures {
		prev, ok := old.Captures[key]
		if !ok {
			prev = c
			prev.Quests = map[string]clientQuestObservation{}
			prev.Turnins = map[string]json.RawMessage{}
		}
		for id, q := range c.Quests {
			have, ok := prev.Quests[id]
			if ok && have.SeenAt == q.SeenAt && have.Title != q.Title {
				return 0, fmt.Errorf("Widerspruechlicher Questtitel %s", id)
			}
			if !ok || q.SeenAt >= have.SeenAt {
				if len(q.Objectives) == 0 {
					q.Objectives = have.Objectives
				}
				prev.Quests[id] = q
			}
		}
		// Stable content keys deduplicate observations across accounts/reloads without storing account identities.
		if prev.Turnins == nil {
			prev.Turnins = map[string]json.RawMessage{}
		}
		for _, v := range c.Turnins {
			key := fmt.Sprintf("%x", sha256.Sum256(v))
			prev.Turnins[key] = v
		}
		old.Captures[key] = prev
	}
	count := 0
	for _, c := range old.Captures {
		count += len(c.Quests)
	}
	encoded, err := json.Marshal(old)
	if err != nil {
		return 0, err
	}
	if len(encoded) > clientQuestLimit {
		return 0, fmt.Errorf("Gesammelter Questexport zu gross")
	}
	if err := atomicWrite(path, encoded); err != nil {
		return 0, err
	}
	return count, nil
}

// Parse just the exported Lua string; never execute SavedVariables as code.
func questExportString(raw []byte) ([]byte, error) {
	re := regexp.MustCompile(`(?m)^ForeverRoutesQuestExport\s*=\s*"`)
	index := re.FindIndex(raw)
	if index == nil {
		return nil, fmt.Errorf("Noch kein Questexport gespeichert")
	}
	var out bytes.Buffer
	for i := index[1]; i < len(raw); i++ {
		c := raw[i]
		if c == '"' {
			return out.Bytes(), nil
		}
		if c != '\\' {
			out.WriteByte(c)
			continue
		}
		i++
		if i >= len(raw) {
			break
		}
		c = raw[i]
		if c >= '0' && c <= '9' {
			n := int(c - '0')
			for k := 0; k < 2 && i+1 < len(raw) && raw[i+1] >= '0' && raw[i+1] <= '9'; k++ {
				i++
				n = n*10 + int(raw[i]-'0')
			}
			if n > 255 {
				return nil, fmt.Errorf("Ungueltiges Lua-Escape")
			}
			out.WriteByte(byte(n))
			continue
		}
		switch c {
		case '\\', '"', '\'':
			out.WriteByte(c)
		case 'n', '\n':
			out.WriteByte('\n')
		case 'r':
			out.WriteByte('\r')
		case 't':
			out.WriteByte('\t')
		default:
			return nil, fmt.Errorf("Unbekanntes Lua-Escape")
		}
	}
	return nil, fmt.Errorf("Unvollstaendiger Questexport")
}
func questSavedVariablesFiles(addons string) []string {
	if addons == "" {
		return nil
	}
	root := filepath.Dir(filepath.Dir(filepath.Clean(addons)))
	files, _ := filepath.Glob(filepath.Join(root, "WTF", "Account", "*", "SavedVariables", "ForeverRoutes.lua"))
	return files
}
func (s *Service) watchClientQuests(ctx context.Context) {
	seen := map[string]time.Time{}
	scan := func() {
		s.captureClientCaches()
		for _, path := range questSavedVariablesFiles(s.cfg.Addons) {
			info, err := os.Stat(path)
			if err != nil || !info.ModTime().After(seen[path]) || info.Size() > clientQuestLimit {
				continue
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				continue
			}
			raw, err = questExportString(raw)
			if err != nil {
				continue
			}
			n, err := importClientQuests(s.cfg, raw)
			if err != nil {
				continue
			}
			seen[path] = info.ModTime()
			s.clientMu.Lock()
			s.clientStatus.Quests = n
			s.clientMu.Unlock()
		}
	}
	scan()
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			scan()
		}
	}
}
func routesSupportClientQuests(cfg Config) bool {
	var m struct {
		Features []string `json:"features"`
	}
	if loadJSON(filepath.Join(routesDir(cfg), routesManifest), &m) != nil {
		return false
	}
	for _, f := range m.Features {
		if strings.EqualFold(f, "client-quests-v1") {
			return true
		}
	}
	return false
}
