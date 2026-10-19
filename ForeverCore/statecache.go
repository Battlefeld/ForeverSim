package main

import "sync"

// The character state is about 10 KB, far more than the item(s) a job asks about, and it travels through the
// pixel strip at about 240 bytes per frame. The addon therefore sends it once per stable state and refers to it
// by key (Job.StateKey) afterwards. The PC keeps the last few states; an unknown key is answered with an error
// that starts with stateUnknown, and the addon then sends the full state again.
const stateUnknown = "STATE_UNKNOWN"

type stateCache struct {
	mu    sync.Mutex
	items map[string]map[string]any
	order []string
	max   int
}

var stateStore = &stateCache{items: map[string]map[string]any{}, max: 6}

func (c *stateCache) get(key string) (map[string]any, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	st, ok := c.items[key]
	return st, ok
}

func (c *stateCache) put(key string, state map[string]any) {
	if key == "" || state == nil {
		return
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, exists := c.items[key]; !exists {
		c.order = append(c.order, key)
		for len(c.order) > c.max {
			delete(c.items, c.order[0])
			c.order = c.order[1:]
		}
	}
	c.items[key] = state
}
