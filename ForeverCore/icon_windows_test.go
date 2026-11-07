//go:build windows

package main

import (
	"bytes"
	"encoding/binary"
	"testing"
	"unsafe"

	"golang.org/x/sys/windows"
)

// Check the linked executable through the Windows resource loader, rather than
// merely checking that an icon file or resource object exists in the checkout.
func TestWindowsIconResource(t *testing.T) {
	if len(appIcon) < 6 || binary.LittleEndian.Uint16(appIcon[:2]) != 0 || binary.LittleEndian.Uint16(appIcon[2:4]) != 1 {
		t.Fatal("application icon is not an ICO file")
	}
	count := int(binary.LittleEndian.Uint16(appIcon[4:6]))
	if count == 0 || len(appIcon) < 6+16*count {
		t.Fatal("application icon directory is incomplete")
	}

	// Enumerate the group name: the resource compiler may choose any ID.
	var groups []windows.ResourceIDOrString
	callback := windows.NewCallback(func(module, resourceType uintptr, name *uint16, param uintptr) uintptr {
		if id := uintptr(unsafe.Pointer(name)); id <= 0xffff {
			groups = append(groups, windows.ResourceID(id))
		} else {
			groups = append(groups, windows.UTF16PtrToString(name))
		}
		return 1
	})
	enumerate := windows.NewLazySystemDLL("kernel32.dll").NewProc("EnumResourceNamesW")
	if ok, _, err := enumerate.Call(0, uintptr(windows.RT_GROUP_ICON), callback, 0); ok == 0 {
		t.Fatalf("enumerate linked application icons: %v", err)
	}
	if len(groups) != 1 {
		t.Fatalf("expected one unambiguous application icon group, got %d", len(groups))
	}
	readResource := func(name windows.ResourceIDOrString, kind windows.ResourceID) []byte {
		t.Helper()
		info, err := windows.FindResource(0, name, kind)
		if err != nil {
			t.Fatalf("find linked resource %v of type %d: %v", name, kind, err)
		}
		data, err := windows.LoadResourceData(0, info)
		if err != nil {
			t.Fatalf("load linked resource %v of type %d: %v", name, kind, err)
		}
		return data
	}
	group := readResource(groups[0], windows.RT_GROUP_ICON)
	if len(group) != 6+14*count || !bytes.Equal(group[:6], appIcon[:6]) {
		t.Fatal("linked icon group directory differs from the application ICO")
	}
	for i := 0; i < count; i++ {
		entry := appIcon[6+16*i : 6+16*(i+1)]
		linked := group[6+14*i : 6+14*(i+1)]
		if !bytes.Equal(linked[:12], entry[:12]) {
			t.Fatalf("linked icon image %d has different dimensions, format or size", i)
		}
		size := uint64(binary.LittleEndian.Uint32(entry[8:12]))
		offset := uint64(binary.LittleEndian.Uint32(entry[12:16]))
		if size == 0 || offset+size > uint64(len(appIcon)) {
			t.Fatalf("application icon image %d is truncated", i)
		}
		id := windows.ResourceID(binary.LittleEndian.Uint16(linked[12:14]))
		if !bytes.Equal(readResource(id, windows.RT_ICON), appIcon[offset:offset+size]) {
			t.Fatalf("linked icon image %d differs from the application ICO", i)
		}
	}
}
