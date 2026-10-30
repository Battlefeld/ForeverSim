//go:build !windows

package main

import "fmt"

// appPlatform: ForeverCore runs as an app without arguments only on Windows.
const appPlatform = false

func openWindow(url string) { fmt.Println("ForeverCore:", url) }

func openFolder(string) {}

func wowRoots() []string { return nil }

func placeProgram(string) error { return nil }
