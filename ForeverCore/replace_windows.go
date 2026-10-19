//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

var moveFileEx = syscall.NewLazyDLL("kernel32.dll").NewProc("MoveFileExW")

func replaceFile(a, b string) error {
	x, e := syscall.UTF16PtrFromString(a)
	if e != nil {
		return e
	}
	y, e := syscall.UTF16PtrFromString(b)
	if e != nil {
		return e
	}
	ok, _, err := moveFileEx.Call(uintptr(unsafe.Pointer(x)), uintptr(unsafe.Pointer(y)), 0x1|0x8)
	if ok == 0 {
		return err
	}
	return nil
}
