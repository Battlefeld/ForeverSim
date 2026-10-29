package main

import (
	"crypto/sha256"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
)

func validateClientCache(raw []byte) (uint32, error) {
	if len(raw) < 44 || string(raw[:4]) != "XFTH" || binary.LittleEndian.Uint32(raw[4:8]) != 9 {
		return 0, fmt.Errorf("Unbekanntes Hotfix-Cacheformat")
	}
	build := binary.LittleEndian.Uint32(raw[8:12])
	if build == 0 {
		return 0, fmt.Errorf("Hotfix-Cache ohne Build")
	}
	count := 0
	for offset := 44; offset < len(raw); count++ {
		if len(raw)-offset < 32 || string(raw[offset:offset+4]) != "XFTH" {
			return 0, fmt.Errorf("Unvollstaendiger Hotfix-Cache")
		}
		size := int64(int32(binary.LittleEndian.Uint32(raw[offset+24 : offset+28])))
		if size < 0 || size > int64(len(raw)-offset-32) {
			return 0, fmt.Errorf("Ungueltige Hotfix-Datensatzgroesse")
		}
		offset += 32 + int(size)
	}
	if count == 0 {
		return 0, fmt.Errorf("Leerer Hotfix-Cache")
	}
	return build, nil
}
func (s *Service) captureClientCaches() {
	root := filepath.Dir(filepath.Dir(filepath.Clean(s.cfg.Addons)))
	// Only the selected installation's cache, never another client's or account files.
	files, _ := filepath.Glob(filepath.Join(root, "Cache", "ADB", "*", "DBCache.bin"))
	for _, path := range files {
		info, err := os.Stat(path)
		if err != nil || info.Size() > 64<<20 {
			continue
		}
		stamp := fmt.Sprintf("%d/%d", info.ModTime().UnixNano(), info.Size())
		s.clientMu.Lock()
		unchanged := s.clientCacheSeen[path] == stamp
		s.clientMu.Unlock()
		if unchanged {
			continue
		}
		raw, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		after, err := os.Stat(path)
		if err != nil || after.Size() != info.Size() || !after.ModTime().Equal(info.ModTime()) {
			continue
		}
		build, err := validateClientCache(raw)
		if err != nil {
			continue
		}
		hash := fmt.Sprintf("%x", sha256.Sum256(raw))
		destination := filepath.Join(s.cfg.Data, "ClientData", "HotfixCaches", fmt.Sprint(build), hash+".bin")
		if _, err := os.Stat(destination); os.IsNotExist(err) {
			if err := atomicWrite(destination, raw); err != nil {
				continue
			}
		}
		s.clientMu.Lock()
		if s.clientCacheSeen == nil {
			s.clientCacheSeen = map[string]string{}
		}
		s.clientCacheSeen[path] = stamp
		oldHash := s.clientStatus.LocalCacheSHA
		s.clientStatus.LocalCacheSHA = hash
		s.clientStatus.LocalCacheBuild = build
		if oldHash != hash && s.clientStatus.Status != "checking" {
			s.clientStatus.Status = "warning"
			s.clientStatus.Message = "Hotfix-Pruefung ausstehend; letzter gueltiger Datenstand aktiv."
		}
		s.clientMu.Unlock()
	}
}
