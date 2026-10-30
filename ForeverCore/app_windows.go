//go:build windows

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

// appPlatform: ForeverCore runs as an app without arguments on Windows.
const appPlatform = true

func init() { wowRunning = wowProcess }

// openWindow shows the page in an app window of Edge (no address bar), else in the default browser.
func openWindow(url string) {
	for _, base := range []string{os.Getenv("ProgramFiles(x86)"), os.Getenv("ProgramFiles"), os.Getenv("LOCALAPPDATA")} {
		edge := filepath.Join(base, "Microsoft", "Edge", "Application", "msedge.exe")
		if base != "" && fileExists(edge) {
			if exec.Command(edge, "--app="+url, "--window-size=1040,780", "--no-first-run").Start() == nil {
				return
			}
		}
	}
	exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
}

func openFolder(dir string) { exec.Command("explorer.exe", dir).Start() }

func fileExists(p string) bool { _, err := os.Stat(p); return err == nil }

// wowProcess: a WoW client runs (Wow.exe, WowClassic.exe, WowClassicB.exe, ...).
func wowProcess() bool {
	snap, err := windows.CreateToolhelp32Snapshot(windows.TH32CS_SNAPPROCESS, 0)
	if err != nil {
		return false
	}
	defer windows.CloseHandle(snap)
	var e windows.ProcessEntry32
	e.Size = uint32(unsafe.Sizeof(e))
	for err = windows.Process32First(snap, &e); err == nil; err = windows.Process32Next(snap, &e) {
		name := strings.ToLower(windows.UTF16ToString(e.ExeFile[:]))
		if strings.HasPrefix(name, "wow") && strings.HasSuffix(name, ".exe") {
			return true
		}
	}
	return false
}

// wowRoots: where WoW is installed: the Battle.net registry entries and the usual folders on every drive.
func wowRoots() []string {
	var out []string
	for _, key := range []string{`SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft`, `SOFTWARE\Blizzard Entertainment\World of Warcraft`} {
		if k, err := registry.OpenKey(registry.LOCAL_MACHINE, key, registry.QUERY_VALUE); err == nil {
			if p, _, err := k.GetStringValue("InstallPath"); err == nil && p != "" {
				p = filepath.Clean(p)
				out = append(out, p)
				if strings.HasPrefix(filepath.Base(p), "_") {
					out = append(out, filepath.Dir(p))
				}
			}
			k.Close()
		}
	}
	drives, _ := windows.GetLogicalDrives()
	for i := 0; i < 26; i++ {
		if drives&(1<<i) == 0 {
			continue
		}
		d := string(rune('A'+i)) + `:\`
		for _, sub := range []string{`Program Files (x86)\World of Warcraft`, `Program Files\World of Warcraft`, `World of Warcraft`,
			`Games\World of Warcraft`, `Battle.net\World of Warcraft`, `Blizzard\World of Warcraft`} {
			if p := filepath.Join(d, sub); isDir(p) {
				out = append(out, p)
			}
		}
	}
	return out
}

// placeProgram puts this program into the app folder (unless it runs from there) and adds it to the Start menu
// and the desktop, so it is started from there from now on.
func placeProgram(dir string) error {
	self, err := os.Executable()
	if err != nil {
		return err
	}
	target := filepath.Join(dir, "ForeverCore.exe")
	if !strings.EqualFold(filepath.Clean(self), filepath.Clean(target)) {
		b, err := os.ReadFile(self)
		if err != nil {
			return err
		}
		if err := atomicWrite(target, b); err != nil {
			return err
		}
	}
	// shortcuts through the Windows Script Host, in a hidden process
	script := `$s=New-Object -ComObject WScript.Shell;` +
		`foreach($p in @([Environment]::GetFolderPath('Programs'),[Environment]::GetFolderPath('Desktop'))){` +
		`$l=$s.CreateShortcut((Join-Path $p 'ForeverCore.lnk'));$l.TargetPath=$env:FC_TARGET;$l.WorkingDirectory=$env:FC_DIR;` +
		`$l.IconLocation=$env:FC_TARGET;$l.Save()}`
	cmd := exec.Command("powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script)
	cmd.Env = append(os.Environ(), "FC_TARGET="+target, "FC_DIR="+dir)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true, CreationFlags: windows.CREATE_NO_WINDOW}
	return cmd.Run()
}

// startProgram starts a program detached from this one (the updated ForeverCore after this one quits).
func startProgram(path string) {
	cmd := exec.Command(path)
	cmd.Dir = filepath.Dir(path)
	cmd.SysProcAttr = &syscall.SysProcAttr{CreationFlags: windows.DETACHED_PROCESS | windows.CREATE_NEW_PROCESS_GROUP}
	cmd.Start()
}
