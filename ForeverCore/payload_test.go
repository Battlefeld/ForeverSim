//go:build payload

package main

import "testing"

// The package built into this ForeverCore.exe is complete (go test -tags payload, with payload.zip in place).
func TestEmbeddedPayloadComplete(t *testing.T) {
	if err := checkPayload(embeddedPayload()); err != nil {
		t.Fatal(err)
	}
	if got := payloadAddons(embeddedPayload()); len(got) < 2 {
		t.Fatalf("addons %v", got)
	}
}
