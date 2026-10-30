//go:build !payload

package main

import "io/fs"

// A ForeverCore.exe built without the installation package (development, tests) cannot install; it runs an existing
// installation.
func embeddedPayload() fs.FS { return nil }
