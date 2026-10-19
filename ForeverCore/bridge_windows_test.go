//go:build windows

package main

import "testing"

// The old closure allocated a permanent Windows callback on every poll and
// exhausted Go's callback table before this many enumerations completed.
// Run on a real Windows runner, with or without a WoW window present.
func TestWowOriginCallbackReuse(t *testing.T) {
	callback := wowWindowCallback
	for i := 0; i < 4096; i++ {
		wowOrigin()
	}
	if wowWindowCallback != callback {
		t.Fatal("window enumeration callback changed")
	}
}
