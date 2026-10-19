package main

import (
	"bytes"
	"testing"
)

func TestPixelCalibration(t *testing.T) {
	want := Fragment{ID: 1234, Index: 1, Total: 3, Data: bytes.Repeat([]byte("pixel test "), 20)}
	frame := encodeFrame(want)
	for _, layout := range []pixelLayout{{cell: 3}, {cell: 4}, {cell: 4.5}, {cell: 2.25, x: 2, y: 1}, {cell: 6, x: 3, y: 3}} {
		w, h := Columns*maxPixelCell+4, Rows*maxPixelCell+4
		raw := make([]byte, w*h*4)
		for y := 0; y < h; y++ {
			for x := 0; x < w; x++ {
				if x < layout.x || y < layout.y { continue }
				col, row := int(float64(x-layout.x)/layout.cell), int(float64(y-layout.y)/layout.cell)
				if col >= Columns || row >= Rows { continue }
				i := row*Columns+col
				if frame[i/8] & (1 << uint(7-i%8)) != 0 {
					o := (y*w+x)*4
					raw[o], raw[o+1], raw[o+2] = 255, 255, 255
				}
			}
		}
		f, _, err := findPixelLayout(raw, w, h)
		if err != nil || f.ID != want.ID || f.Index != want.Index || f.Total != want.Total || !bytes.Equal(f.Data, want.Data) {
			t.Fatalf("layout %+v: frame %+v error %v", layout, f, err)
		}
		// A bit error in the data must be rejected even when the header matches.
		i := HeaderBytes*8
		x := layout.x+int((float64(i%Columns)+0.5)*layout.cell)
		y := layout.y+int((float64(i/Columns)+0.5)*layout.cell)
		o := (y*w+x)*4
		raw[o], raw[o+1], raw[o+2] = 255-raw[o], 255-raw[o+1], 255-raw[o+2]
		if _, err := frameAtPixels(raw, w, h, layout); err == nil {
			t.Fatal("corrupted frame accepted")
		}
	}
}

func TestPixelCalibrationRejectsBlank(t *testing.T) {
	w, h := Columns*maxPixelCell+4, Rows*maxPixelCell+4
	if _, _, err := findPixelLayout(make([]byte,w*h*4),w,h); err == nil {
		t.Fatal("blank capture accepted")
	}
	if _, ok := samplePixels(nil,w,h,pixelLayout{cell:3},32); ok {
		t.Fatal("short buffer accepted")
	}
}
