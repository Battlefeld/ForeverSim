//go:build payload

package main

import (
	"archive/zip"
	"bytes"
	_ "embed"
	"io/fs"
)

// The installation package built into the release ForeverCore.exe (package.py, build tag payload): the engine, Lua,
// the runtime and the addons.
//
//go:embed payload.zip
var payloadZip []byte

func embeddedPayload() fs.FS {
	z, err := zip.NewReader(bytes.NewReader(payloadZip), int64(len(payloadZip)))
	if err != nil {
		return nil
	}
	return payloadRoot(z)
}
