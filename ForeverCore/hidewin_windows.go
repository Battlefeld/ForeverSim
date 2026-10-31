//go:build windows

package main

import (
	"os/exec"
	"syscall"
)

// noWindow keeps a console program (Lua, Engine, the route planner) from opening a console window: ForeverCore
// itself has none, so Windows would give each child its own.
func noWindow(cmd *exec.Cmd) *exec.Cmd {
	if cmd.SysProcAttr == nil {
		cmd.SysProcAttr = &syscall.SysProcAttr{}
	}
	cmd.SysProcAttr.HideWindow = true
	cmd.SysProcAttr.CreationFlags |= 0x08000000 // CREATE_NO_WINDOW
	return cmd
}
