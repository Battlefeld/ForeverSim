package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// The engine database knows about ten thousand items, but not the new Forever items (ids like 272999) and not
// the variants ("of Agility"). For those the client has to send the item values once. The PC keeps them on disk,
// so from then on a job needs nothing but the item id: the addon sends lean candidates, and only an item this
// store has never seen is answered with "need".
type learnedItem struct {
	Snapshot map[string]any `json:"snapshot"`
	Saved    int64          `json:"saved"`
}

type itemStore struct {
	mu     sync.Mutex
	path   string
	items  map[string]learnedItem
	loaded bool
}

var learnedItems = &itemStore{}

const (
	learnedTTL = 7 * 24 * time.Hour // values are asked for again after a week: the game may change items
	learnedMax = 30000
)

func (st *itemStore) open(dir string) bool {
	if dir == "" {
		return false
	}
	path := filepath.Join(dir, "Items", "learned.json")
	if st.loaded && st.path == path {
		return true
	}
	st.path, st.loaded, st.items = path, true, map[string]learnedItem{}
	var raw map[string]learnedItem
	if loadJSON(path, &raw) == nil && raw != nil {
		st.items = raw
	}
	return true
}

func (st *itemStore) get(dir, key string) (map[string]any, bool) {
	st.mu.Lock()
	defer st.mu.Unlock()
	if !st.open(dir) {
		return nil, false
	}
	it, ok := st.items[key]
	if !ok || it.Snapshot == nil || time.Since(time.Unix(it.Saved, 0)) > learnedTTL {
		return nil, false
	}
	return cloneMap(it.Snapshot), true
}

func (st *itemStore) put(dir, key string, snapshot map[string]any) {
	if snapshot == nil || snapshot["statsComplete"] != true {
		return
	}
	st.mu.Lock()
	defer st.mu.Unlock()
	if !st.open(dir) {
		return
	}
	if len(st.items) >= learnedMax {
		oldest, oldestKey := int64(1<<62), ""
		for k, v := range st.items {
			if v.Saved < oldest {
				oldest, oldestKey = v.Saved, k
			}
		}
		delete(st.items, oldestKey)
	}
	st.items[key] = learnedItem{Snapshot: cloneMap(snapshot), Saved: time.Now().Unix()}
	if b, e := json.Marshal(st.items); e == nil {
		_ = os.MkdirAll(filepath.Dir(st.path), 0o755)
		_ = atomicWrite(st.path, b)
	}
}
