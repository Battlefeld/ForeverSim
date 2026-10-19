package main

import (
	"fmt"
	lua "github.com/yuin/gopher-lua"
)

func newTestLua() *lua.LState          { return lua.NewState() }
func mapLuaSeen() map[*lua.LTable]bool { return map[*lua.LTable]bool{} }
func slotName(i int) string            { return fmt.Sprintf("FC3_S%04d", i) }
