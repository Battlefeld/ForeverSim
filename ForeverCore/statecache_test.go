package main

import (
	"context"
	"strings"
	"testing"
)

func TestStateReference(t *testing.T) {
	s := Service{cfg: Config{Data: t.TempDir()}}
	ctx := context.Background()
	state := map[string]any{"sim": map[string]any{"level": float64(12)}}
	full := Job{Schema: 3, Session: "s", Sequence: 1, Revision: "1", Kind: "ping", StateKey: "k1", State: state}
	if r := s.Execute(ctx, full); r.Status != "ok" {
		t.Fatal(r)
	}
	ref := Job{Schema: 3, Session: "s", Sequence: 2, Revision: "1", Kind: "ping", StateKey: "k1"}
	if r := s.Execute(ctx, ref); r.Status != "ok" {
		t.Fatal("known key must be accepted", r)
	}
	unknown := Job{Schema: 3, Session: "s", Sequence: 3, Revision: "1", Kind: "ping", StateKey: "other"}
	if r := s.Execute(ctx, unknown); r.Status != "error" || !strings.HasPrefix(r.Message, stateUnknown) {
		t.Fatal("unknown key must ask for the full state", r)
	}
	// a failed job must not leave its state behind
	bad := Job{Schema: 3, Session: "s", Sequence: 4, Revision: "1", Kind: "bogus", StateKey: "k2", State: state}
	if r := s.Execute(ctx, bad); r.Status != "error" {
		t.Fatal(r)
	}
	if _, ok := stateStore.get("k2"); ok {
		t.Fatal("state of a failed job was stored")
	}
	// only the latest few states are kept
	for i := 0; i < 10; i++ {
		stateStore.put(string(rune('a'+i)), state)
	}
	if _, ok := stateStore.get("a"); ok {
		t.Fatal("oldest state must be dropped")
	}
	if _, ok := stateStore.get("j"); !ok {
		t.Fatal("newest state must be kept")
	}
}
