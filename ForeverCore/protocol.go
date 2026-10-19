package main

import (
	"bytes"
	"encoding/binary"
	"fmt"
	"hash/crc32"
	"os"
	"path/filepath"
	"time"
)

// Thin status-less pixel strip at the WoW top-left. The wire format stays 256 bytes.
const Columns = 512
const Rows = 4
const CellSize = 2
const FrameBytes = Columns * Rows / 8
const HeaderBytes = 18
const PayloadBytes = FrameBytes - HeaderBytes
const SlotCount = 2048
const MaxMessage = 64 * 1024

type Fragment struct {
	ID           uint32
	Index, Total uint16
	Data         []byte
}

func decodeFrame(b []byte) (Fragment, error) {
	var f Fragment
	if len(b) != FrameBytes || !bytes.Equal(b[:4], []byte{'F', 'C', '3', 3}) {
		return f, fmt.Errorf("header")
	}
	f.ID = binary.BigEndian.Uint32(b[4:8])
	f.Index = binary.BigEndian.Uint16(b[8:10])
	f.Total = binary.BigEndian.Uint16(b[10:12])
	n := int(binary.BigEndian.Uint16(b[12:14]))
	if n < 1 || n > PayloadBytes || f.Total < 1 || int(f.Total) > (MaxMessage+PayloadBytes-1)/PayloadBytes || f.Index >= f.Total {
		return f, fmt.Errorf("bounds")
	}
	f.Data = append([]byte(nil), b[18:18+n]...)
	sum := crc32.NewIEEE()
	sum.Write(b[:14])
	sum.Write(f.Data)
	if binary.BigEndian.Uint32(b[14:18]) != sum.Sum32() {
		return f, fmt.Errorf("crc")
	}
	return f, nil
}
func encodeFrame(f Fragment) []byte {
	b := make([]byte, FrameBytes)
	copy(b, []byte{'F', 'C', '3', 3})
	binary.BigEndian.PutUint32(b[4:8], f.ID)
	binary.BigEndian.PutUint16(b[8:10], f.Index)
	binary.BigEndian.PutUint16(b[10:12], f.Total)
	binary.BigEndian.PutUint16(b[12:14], uint16(len(f.Data)))
	copy(b[18:], f.Data)
	sum := crc32.NewIEEE()
	sum.Write(b[:14])
	sum.Write(f.Data)
	binary.BigEndian.PutUint32(b[14:18], sum.Sum32())
	return b
}

type Assembler struct {
	id    uint32
	total uint16
	parts map[uint16][]byte
	start time.Time
}

func (a *Assembler) Add(f Fragment) ([]byte, error) {
	if a.id != f.ID || a.total != f.Total || time.Since(a.start) > 2*time.Minute {
		a.id = f.ID
		a.total = f.Total
		a.parts = map[uint16][]byte{}
		a.start = time.Now()
	}
	if old, ok := a.parts[f.Index]; ok && !bytes.Equal(old, f.Data) {
		a.parts = nil
		return nil, fmt.Errorf("Widerspruechliches Fragment")
	}
	if a.parts == nil {
		return nil, fmt.Errorf("Ungueltiger Zustand")
	}
	a.parts[f.Index] = f.Data
	if len(a.parts) != int(a.total) {
		return nil, nil
	}
	var out []byte
	for i := uint16(0); i < a.total; i++ {
		out = append(out, a.parts[i]...)
	}
	if len(out) > MaxMessage {
		return nil, fmt.Errorf("Nachricht zu gross")
	}
	return out, nil
}
func publishReply(addons string, r Reply) error {
	payload := []byte("ForeverCore_Reply=" + luaLiteral(r, 0) + "\n")
	if len(payload) > 512*1024 {
		return fmt.Errorf("Antwort zu gross")
	}
	start := r.ReplyStart
	if start < 1 {
		start = 1
	}
	end := start + 127
	if end > SlotCount {
		end = SlotCount
	}
	for i := start; i <= end; i++ {
		p := filepath.Join(addons, fmt.Sprintf("FC3_S%04d", i), "Inbox.lua")
		if _, e := os.Stat(p); e != nil {
			return fmt.Errorf("Antwortslot fehlt: %s", p)
		}
		if e := atomicWrite(p, payload); e != nil {
			return e
		}
	}
	return nil
}
