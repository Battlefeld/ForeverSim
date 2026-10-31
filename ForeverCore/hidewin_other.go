//go:build !windows

package main

import "os/exec"

func noWindow(cmd *exec.Cmd) *exec.Cmd { return cmd }
