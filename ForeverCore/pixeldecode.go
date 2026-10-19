package main

import "fmt"

// The displayed grid can differ from three desktop pixels per cell because
// WoW's UI and render scaling are independent of Windows' desktop coordinates.
// Calibrate against the protocol header, then accept only a CRC-valid frame.
const maxPixelCell = 8

type pixelLayout struct {
	cell float64
	x, y int
}

func samplePixels(raw []byte, width, height int, layout pixelLayout, count int) ([]byte, bool) {
	if width <= 0 || height <= 0 || len(raw) < width*height*4 || layout.cell < 1 || count < 1 || count > Columns*Rows {
		return nil, false
	}
	b := make([]byte, (count+7)/8)
	for i := 0; i < count; i++ {
		x := layout.x + int((float64(i%Columns)+0.5)*layout.cell)
		y := layout.y + int((float64(i/Columns)+0.5)*layout.cell)
		if x < 0 || y < 0 || x >= width || y >= height {
			return nil, false
		}
		o := (y*width+x)*4
		if int(raw[o])+int(raw[o+1])+int(raw[o+2]) >= 384 {
			b[i/8] |= 1 << uint(7-i%8)
		}
	}
	return b, true
}

func frameAtPixels(raw []byte, width, height int, layout pixelLayout) (Fragment, error) {
	header, ok := samplePixels(raw, width, height, layout, 32)
	if !ok || string(header) != "FC3\x03" {
		return Fragment{}, fmt.Errorf("header")
	}
	b, ok := samplePixels(raw, width, height, layout, Columns*Rows)
	if !ok {
		return Fragment{}, fmt.Errorf("grid outside capture")
	}
	return decodeFrame(b)
}

func findPixelLayout(raw []byte, width, height int) (Fragment, pixelLayout, error) {
	standard := pixelLayout{cell: CellSize}
	if f, err := frameAtPixels(raw, width, height, standard); err == nil {
		return f, standard, nil
	}
	// Fractional cells occur when WoW resamples the UI. Center sampling avoids
	// interpolated edges. Small offsets tolerate rounding at the UI origin.
	for y := 0; y <= 3; y++ {
		for x := 0; x <= 3; x++ {
			for step := 32; step <= maxPixelCell*32; step++ {
				layout := pixelLayout{cell: float64(step)/32, x: x, y: y}
				if f, err := frameAtPixels(raw, width, height, layout); err == nil {
					return f, layout, nil
				}
			}
		}
	}
	return Fragment{}, pixelLayout{}, fmt.Errorf("kein CRC-gueltiges FC3-Pixelfeld")
}
