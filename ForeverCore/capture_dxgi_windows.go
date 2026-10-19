//go:build windows

package main

// Screen capture through DXGI Desktop Duplication, the same Windows interface OBS and Discord use for
// display capture. The GPU copies only the few rows of the pixel strip into a tiny staging texture and
// only that texture is read by the CPU. Unlike GetDC/BitBlt on the screen it needs no read-back of the
// whole desktop and does not interfere with the compositor, the mouse cursor or the game.
//
// The package github.com/kirides/go-d3d (MIT) provides the COM bindings.

import (
	"fmt"
	"syscall"
	"unsafe"

	"github.com/kirides/go-d3d"
	"github.com/kirides/go-d3d/d3d11"
	"github.com/kirides/go-d3d/dxgi"
)

var modD3D11 = syscall.NewLazyDLL("d3d11.dll")
var procD3D11CreateDevice = modD3D11.NewProc("D3D11CreateDevice")

const (
	dxgiFormatB8G8R8A8 = 87
	dxgiFormatR8G8B8A8 = 28
	d3d11SDKVersion    = 7
)

// dxgiCapture duplicates ONE output (monitor) and copies a small region of it per read.
type dxgiCapture struct {
	device      *d3d11.ID3D11Device
	ctx         *d3d11.ID3D11DeviceContext
	dxgiDevice1 *dxgi.IDXGIDevice1
	dup         *dxgi.IDXGIOutputDuplication
	staging     *d3d11.ID3D11Texture2D
	surface     *dxgi.IDXGISurface
	stageW      int
	stageH      int
	format      uint32

	// geometry of the duplicated output in virtual desktop coordinates
	left, top, right, bottom int
	adapterName              string
	outputName               string

	w, h int    // size of the bitmap callers see (stride w*4, BGRA or RGBA, both sum the same)
	buf  []byte // persistent bitmap; rows outside the last copied region keep older content
}

func hr(v int32) d3d.HRESULT { return d3d.HRESULT(uint32(v)) }

func utf16ToString(s []uint16) string {
	n := 0
	for n < len(s) && s[n] != 0 {
		n++
	}
	return syscall.UTF16ToString(s[:n])
}

// createDeviceFor makes a D3D11 device on exactly the adapter that drives the monitor. The default device
// can sit on another GPU (for example the integrated one) and could not duplicate that monitor.
func createDeviceFor(adapter *dxgi.IDXGIAdapter1) (*d3d11.ID3D11Device, *d3d11.ID3D11DeviceContext, error) {
	levels := [...]uint32{0xb100, 0xb000, 0xa100, 0xa000}
	var device *d3d11.ID3D11Device
	var ctx *d3d11.ID3D11DeviceContext
	featureLevel := 0
	const driverTypeUnknown = 0
	ret, _, _ := syscall.SyscallN(procD3D11CreateDevice.Addr(),
		uintptr(unsafe.Pointer(adapter)), uintptr(driverTypeUnknown), 0, 0,
		uintptr(unsafe.Pointer(&levels[0])), uintptr(len(levels)), uintptr(d3d11SDKVersion),
		uintptr(unsafe.Pointer(&device)), uintptr(unsafe.Pointer(&featureLevel)), uintptr(unsafe.Pointer(&ctx)))
	if ret != 0 {
		return nil, nil, fmt.Errorf("D3D11CreateDevice: %w", d3d.HRESULT(ret))
	}
	if device == nil || ctx == nil {
		return nil, nil, fmt.Errorf("D3D11CreateDevice lieferte kein Geraet")
	}
	return device, ctx, nil
}

// newDXGICapture finds the monitor that contains (x, y) and starts duplicating it. w and h are the largest
// region that will ever be requested (the bitmap size).
func newDXGICapture(x, y, w, h int) (*dxgiCapture, error) {
	var factory *dxgi.IDXGIFactory1
	if err := dxgi.CreateDXGIFactory1(&factory); err != nil {
		return nil, fmt.Errorf("CreateDXGIFactory1: %w", err)
	}
	defer factory.Release()

	// Pass 1: list all monitors that are attached to the desktop (no COM object is kept).
	type outInfo struct {
		ai, oi uint32
		desc   dxgi.DXGI_OUTPUT_DESC
		name   string
	}
	var infos []outInfo
	for ai := uint32(0); ; ai++ {
		var adapter *dxgi.IDXGIAdapter1
		if hr(factory.EnumAdapters1(ai, &adapter)).Failed() {
			break
		}
		var adesc dxgi.DXGI_ADAPTER_DESC1
		adapter.GetDesc1(&adesc)
		if adesc.Flags&dxgi.DXGI_ADAPTER_FLAG_SOFTWARE == 0 {
			for oi := uint32(0); ; oi++ {
				var output *dxgi.IDXGIOutput
				if hr(int32(adapter.EnumOutputs(oi, &output))).Failed() {
					break
				}
				var output5 *dxgi.IDXGIOutput5
				if !hr(output.QueryInterface(dxgi.IID_IDXGIOutput5, &output5)).Failed() {
					var od dxgi.DXGI_OUTPUT_DESC
					if !hr(output5.GetDesc(&od)).Failed() && od.AttachedToDesktop != 0 {
						infos = append(infos, outInfo{ai: ai, oi: oi, desc: od, name: adesc.DescriptionString()})
					}
					output5.Release()
				}
				output.Release()
			}
		}
		adapter.Release()
	}
	if len(infos) == 0 {
		return nil, fmt.Errorf("kein Bildschirm fuer die Aufnahme gefunden")
	}
	pick := 0
	for i, inf := range infos {
		r := inf.desc.DesktopCoordinates
		if int(r.Left) <= x && x < int(r.Right) && int(r.Top) <= y && y < int(r.Bottom) {
			pick = i
			break
		}
	}
	chosen := infos[pick]

	// Pass 2: open exactly that adapter and output.
	var adapter *dxgi.IDXGIAdapter1
	if r := hr(factory.EnumAdapters1(chosen.ai, &adapter)); r.Failed() {
		return nil, fmt.Errorf("Grafikkarte: %w", r)
	}
	defer adapter.Release()
	var output *dxgi.IDXGIOutput
	if r := hr(int32(adapter.EnumOutputs(chosen.oi, &output))); r.Failed() {
		return nil, fmt.Errorf("Bildschirmausgang: %w", r)
	}
	defer output.Release()

	device, ctx, err := createDeviceFor(adapter)
	if err != nil {
		return nil, err
	}
	dc := chosen.desc.DesktopCoordinates
	c := &dxgiCapture{device: device, ctx: ctx, w: w, h: h, buf: make([]byte, w*h*4),
		adapterName: chosen.name, outputName: utf16ToString(chosen.desc.DeviceName[:]),
		left: int(dc.Left), top: int(dc.Top), right: int(dc.Right), bottom: int(dc.Bottom)}

	if r := hr(device.QueryInterface(dxgi.IID_IDXGIDevice1, &c.dxgiDevice1)); r.Failed() {
		c.Close()
		return nil, fmt.Errorf("IDXGIDevice1: %w", r)
	}
	// Ask for 8-bit output; on HDR desktops the system then converts to SDR for us.
	var output5 *dxgi.IDXGIOutput5
	if r := hr(output.QueryInterface(dxgi.IID_IDXGIOutput5, &output5)); r.Failed() {
		c.Close()
		return nil, fmt.Errorf("IDXGIOutput5: %w", r)
	}
	r := hr(output5.DuplicateOutput1(c.dxgiDevice1, 0, []dxgi.DXGI_FORMAT{dxgi.DXGI_FORMAT(dxgiFormatB8G8R8A8)}, &c.dup))
	output5.Release()
	if r.Failed() {
		var output1 *dxgi.IDXGIOutput1
		if r2 := hr(output.QueryInterface(dxgi.IID_IDXGIOutput1, &output1)); r2.Failed() {
			c.Close()
			return nil, fmt.Errorf("DuplicateOutput1: %v; IDXGIOutput1: %v", r, r2)
		}
		r = hr(output1.DuplicateOutput(c.dxgiDevice1, &c.dup))
		output1.Release()
		if r.Failed() {
			c.Close()
			return nil, fmt.Errorf("DuplicateOutput: %w", r)
		}
	}
	return c, nil
}

func (c *dxgiCapture) Contains(x, y int) bool {
	return c != nil && c.left <= x && x < c.right && c.top <= y && y < c.bottom
}

func (c *dxgiCapture) Close() {
	if c == nil {
		return
	}
	if c.dup != nil {
		c.dup.Release()
		c.dup = nil
	}
	if c.surface != nil {
		c.surface.Release()
		c.surface = nil
	}
	if c.staging != nil {
		c.staging.Release()
		c.staging = nil
	}
	if c.dxgiDevice1 != nil {
		c.dxgiDevice1.Release()
		c.dxgiDevice1 = nil
	}
	if c.ctx != nil {
		c.ctx.Release()
		c.ctx = nil
	}
	if c.device != nil {
		c.device.Release()
		c.device = nil
	}
}

func (c *dxgiCapture) ensureStaging(width, height int, format uint32) error {
	if c.staging != nil && c.stageW == width && c.stageH == height && c.format == format {
		return nil
	}
	if c.surface != nil {
		c.surface.Release()
		c.surface = nil
	}
	if c.staging != nil {
		c.staging.Release()
		c.staging = nil
	}
	desc := d3d11.D3D11_TEXTURE2D_DESC{Width: uint32(width), Height: uint32(height), MipLevels: 1, ArraySize: 1, Format: format,
		SampleDesc: dxgi.DXGI_SAMPLE_DESC{Count: 1}, Usage: d3d11.D3D11_USAGE_STAGING, CPUAccessFlags: d3d11.D3D11_CPU_ACCESS_READ}
	if r := hr(c.device.CreateTexture2D(&desc, &c.staging)); r.Failed() {
		return fmt.Errorf("CreateTexture2D: %w", r)
	}
	if r := hr(c.staging.QueryInterface(dxgi.IID_IDXGISurface, &c.surface)); r.Failed() {
		return fmt.Errorf("IDXGISurface: %w", r)
	}
	c.stageW, c.stageH, c.format = width, height, format
	return nil
}

// errCaptureLost means the duplication has to be rebuilt (mode change, secure desktop, driver reset).
var errCaptureLost = fmt.Errorf("Aufnahme verloren")

// read copies the w x h region whose top-left corner is the desktop position (x, y) into the bitmap and
// returns the whole bitmap (stride = c.w*4). If no new desktop frame arrived it returns the previous
// content; that is fine because the strip is static between two 100 ms frames.
func (c *dxgiCapture) read(x, y, w, h int) ([]byte, error) {
	if w < 1 || w > c.w {
		w = c.w
	}
	if h < 1 || h > c.h {
		h = c.h
	}
	rx, ry := x-c.left, y-c.top
	if rx < 0 || ry < 0 || rx >= c.right-c.left || ry >= c.bottom-c.top {
		return nil, errCaptureLost // the window moved to another monitor
	}
	if rx+w > c.right-c.left {
		w = c.right - c.left - rx
	}
	if ry+h > c.bottom-c.top {
		h = c.bottom - c.top - ry
	}

	var info dxgi.DXGI_OUTDUPL_FRAME_INFO
	var resource *dxgi.IDXGIResource
	ret := d3d.HRESULT(c.dup.AcquireNextFrame(20, &info, &resource))
	switch {
	case ret == d3d.DXGI_ERROR_WAIT_TIMEOUT:
		return c.buf, nil
	case ret == d3d.DXGI_ERROR_ACCESS_LOST || ret == d3d.DXGI_ERROR_DEVICE_REMOVED || ret == d3d.DXGI_ERROR_DEVICE_RESET ||
		ret == d3d.DXGI_ERROR_ACCESS_DENIED || ret == d3d.DXGI_ERROR_SESSION_DISCONNECTED || ret == d3d.DXGI_ERROR_INVALID_CALL:
		return nil, errCaptureLost
	case ret.Failed():
		return nil, fmt.Errorf("AcquireNextFrame: %w", ret)
	}
	defer c.dup.ReleaseFrame()
	defer resource.Release()
	if info.AccumulatedFrames == 0 {
		return c.buf, nil
	}

	var tex *d3d11.ID3D11Texture2D
	if r := hr(resource.QueryInterface(d3d11.IID_ID3D11Texture2D, &tex)); r.Failed() {
		return nil, fmt.Errorf("Textur: %w", r)
	}
	defer tex.Release()
	var td d3d11.D3D11_TEXTURE2D_DESC
	tex.GetDesc(&td)
	if td.Format != dxgiFormatB8G8R8A8 && td.Format != dxgiFormatR8G8B8A8 {
		return nil, fmt.Errorf("Bildformat %d wird nicht unterstuetzt (HDR/10 Bit)", td.Format)
	}
	if err := c.ensureStaging(w, h, td.Format); err != nil {
		return nil, err
	}
	box := d3d11.D3D11_BOX{Left: uint32(rx), Top: uint32(ry), Right: uint32(rx + w), Bottom: uint32(ry + h), Front: 0, Back: 1}
	c.ctx.CopySubresourceRegion2D(c.staging, 0, 0, 0, 0, tex, 0, &box)

	var mapped dxgi.DXGI_MAPPED_RECT
	if r := hr(c.surface.Map(&mapped, dxgi.DXGI_MAP_READ)); r.Failed() {
		return nil, fmt.Errorf("Map: %w", r)
	}
	defer c.surface.Unmap()
	pitch := int(mapped.Pitch)
	src := unsafe.Slice((*byte)(mapped.PBits), pitch*h)
	for row := 0; row < h; row++ {
		copy(c.buf[row*c.w*4:row*c.w*4+w*4], src[row*pitch:row*pitch+w*4])
	}
	return c.buf, nil
}
