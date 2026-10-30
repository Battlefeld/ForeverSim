//go:build !windows

package main

// Elsewhere the token is kept as it is (development and tests).
func protect(b []byte) ([]byte, error)   { return b, nil }
func unprotect(b []byte) ([]byte, error) { return b, nil }
