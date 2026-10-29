package main

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func questCaptureJSON(title string, seen int) []byte {
	return jsonBytes(map[string]any{"schema": 1, "captures": map[string]any{"1.60.1.70685/3/enUS": map[string]any{"build": "1.60.1.70685", "region": 3, "locale": "enUS", "quests": map[string]any{"971": map[string]any{"id": 971, "title": title, "seenAt": seen}}, "turnins": map[string]any{}}}})
}
func TestAutomaticQuestImportPreservesLastGoodData(t *testing.T) {
	cfg := Config{Data: t.TempDir()}
	if n, err := importClientQuests(cfg, questCaptureJSON("Client title", 200)); err != nil || n != 1 {
		t.Fatalf("import: %d %v", n, err)
	}
	if _, err := importClientQuests(cfg, questCaptureJSON("Older", 100)); err != nil {
		t.Fatal(err)
	}
	before, _ := os.ReadFile(clientQuestsPath(cfg))
	d, err := validateClientQuests(before)
	if err != nil || d.Captures["1.60.1.70685/3/enUS"].Quests["971"].Title != "Client title" {
		t.Fatal("newer observation lost")
	}
	for _, bad := range [][]byte{questCaptureJSON("Conflicting", 200), []byte(`{"schema":99}`), []byte(strings.ReplaceAll(string(questCaptureJSON("Wrong game", 300)), "1.60.1.70685", "12.0.0.123"))} {
		if _, err := importClientQuests(cfg, bad); err == nil {
			t.Fatal("invalid capture accepted")
		}
		after, _ := os.ReadFile(clientQuestsPath(cfg))
		if string(after) != string(before) {
			t.Fatal("invalid capture overwrote last good data")
		}
	}
}
func TestSavedQuestExportNeverExecutesLua(t *testing.T) {
	raw := []byte("while true do end\nForeverRoutesQuestExport = \"{\\\"title\\\":\\\"\\195\\164\\\"}\"")
	got, err := questExportString(raw)
	if err != nil || string(got) != `{"title":"ä"}` {
		t.Fatalf("%s %v", got, err)
	}
	if _, err := questExportString([]byte("ForeverRoutesQuestExport = \"unfinished")); err == nil {
		t.Fatal("truncated export accepted")
	}
}
func TestHotfixCacheBoundariesAndBuild(t *testing.T) {
	raw := make([]byte, 79)
	copy(raw, "XFTH")
	binary.LittleEndian.PutUint32(raw[4:8], 9)
	binary.LittleEndian.PutUint32(raw[8:12], 70685)
	copy(raw[44:], "XFTH")
	binary.LittleEndian.PutUint32(raw[68:72], 3)
	if build, err := validateClientCache(raw); err != nil || build != 70685 {
		t.Fatalf("%d %v", build, err)
	}
	if _, err := validateClientCache(raw[:78]); err == nil {
		t.Fatal("truncated payload accepted")
	}
}
func TestConnectCheckIsDailyAndCannotClaimUnappliedHotfixes(t *testing.T) {
	var hits atomic.Int32
	report := map[string]any{"checkedAt": time.Now().UTC().Format(time.RFC3339), "products": map[string]any{"wowf": map[string]any{"row": map[string]any{"VersionsName": "1.60.1.70685"}}}, "effectiveBuild": "1.60.1.70685", "exportedCacheSHA256": "hotfix-sha", "clientExtraction": map[string]string{"status": "complete"}}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		raw, _ := json.Marshal(report)
		json.NewEncoder(w).Encode(map[string]string{"encoding": "base64", "content": base64.StdEncoding.EncodeToString(raw)})
	}))
	defer srv.Close()
	oldAPI := routesAPI
	routesAPI = srv.URL
	defer func() { routesAPI = oldAPI }()
	root := t.TempDir()
	cfg := Config{Data: root, Runtime: root, RoutesNoUpdate: true}
	if err := atomicWrite(filepath.Join(root, "ForeverCore", "engine-data.json"), jsonBytes(map[string]string{"clientBuild": "1.60.1.70685"})); err != nil {
		t.Fatal(err)
	}
	s := &Service{cfg: cfg, clientStatus: clientDataStatus{ClientBuild: "1.60.1.70685"}}
	s.checkClientData(context.Background())
	s.checkClientData(context.Background())
	if hits.Load() != 1 {
		t.Fatalf("repeated network check on same day: %d", hits.Load())
	}
	if state := s.dataStatus(); state.Status != "warning" || state.CheckedAt.IsZero() {
		t.Fatalf("unapplied hotfixes reported current: %+v", state)
	}
	// Only a matching compiled hotfix identity may be green.
	if err := atomicWrite(filepath.Join(root, "ForeverCore", "engine-data.json"), jsonBytes(map[string]string{"clientBuild": "1.60.1.70685", "hotfixCacheSHA256": "hotfix-sha"})); err != nil {
		t.Fatal(err)
	}
	s.clientMu.Lock()
	s.clientStatus.LocalCacheSHA = "hotfix-sha"
	s.clientStatus.CheckedAt = time.Time{}
	s.clientStatus.AttemptedAt = time.Time{}
	s.clientMu.Unlock()
	s.checkClientData(context.Background())
	if s.dataStatus().Status != "ready" {
		t.Fatal("matching validated identities not recognized")
	}
	// Metadata for another effective build must not make the engine look current.
	report["effectiveBuild"] = "1.60.1.70425"
	s.clientMu.Lock()
	s.clientStatus.CheckedAt = time.Time{}
	s.clientStatus.AttemptedAt = time.Time{}
	s.clientMu.Unlock()
	s.checkClientData(context.Background())
	if s.dataStatus().Status != "warning" {
		t.Fatal("old effective build reported current")
	}
}
func TestPrivateGitHubCredentialsAreRestrictedToGitHub(t *testing.T) {
	for _, url := range []string{"https://evil.test/x", "https://github.com.evil.test/x", "http://api.github.com/x"} {
		if githubHost(url) {
			t.Fatalf("credential host accepted: %s", url)
		}
	}
	if !githubHost("https://api.github.com/repos/x/y") {
		t.Fatal("GitHub API rejected")
	}
}
