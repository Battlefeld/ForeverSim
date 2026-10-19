package main

import (
	"fmt"
	"os"
	"path/filepath"
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// Routes need the quest/route addon ForeverDungeonQuest, which is not part of this repository (it is being rebuilt).
// The native route tests run only when it is present next to the other addons.
func skipWithoutRouteAddon(t *testing.T, root string) {
	t.Helper()
	if _, e := os.Stat(filepath.Join(root, "ForeverDungeonQuest", "ForeverDungeonQuest.toc")); e != nil {
		t.Skip("ForeverDungeonQuest (Routen-Addon) ist nicht vorhanden")
	}
}

func newTestLua() *lua.LState          { return lua.NewState() }
func mapLuaSeen() map[*lua.LTable]bool { return map[*lua.LTable]bool{} }
func slotName(i int) string            { return fmt.Sprintf("FC3_S%04d", i) }
