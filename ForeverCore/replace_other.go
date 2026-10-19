//go:build !windows

package main

import "os"

func replaceFile(a, b string) error { return os.Rename(a, b) }
