//go:build !windows

package main

import (
	"context"
	"fmt"
)

func captureSelfTest() error { return fmt.Errorf("Bildschirmaufnahme-Test benoetigt Windows") }

func runBridge(context.Context, *Service) error {
	return fmt.Errorf("Bildschirm-Bridge benoetigt Windows; -request funktioniert plattformunabhaengig")
}
