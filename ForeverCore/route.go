package main

import (
	"context"
	"encoding/json"
	"fmt"
	lua "github.com/yuin/gopher-lua"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

type RouteService struct {
	Root       string
	Lua        string
	ScriptRoot string
	mu         sync.Mutex
}

func toLua(L *lua.LState, v any) lua.LValue {
	switch v := v.(type) {
	case nil:
		return lua.LNil
	case bool:
		return lua.LBool(v)
	case string:
		return lua.LString(v)
	case float64:
		return lua.LNumber(v)
	case int:
		return lua.LNumber(v)
	case []any:
		t := L.NewTable()
		for _, x := range v {
			t.Append(toLua(L, x))
		}
		return t
	case map[string]any:
		t := L.NewTable()
		for k, x := range v {
			if n, e := strconv.Atoi(k); e == nil {
				t.RawSetInt(n, toLua(L, x))
			} else {
				t.RawSetString(k, toLua(L, x))
			}
		}
		return t
	}
	return lua.LNil
}
func fromLua(v lua.LValue, depth int, seen map[*lua.LTable]bool) any {
	if depth > 18 {
		return nil
	}
	switch x := v.(type) {
	case lua.LString:
		return string(x)
	case lua.LNumber:
		return float64(x)
	case lua.LBool:
		return bool(x)
	case *lua.LTable:
		if seen[x] {
			return nil
		}
		seen[x] = true
		defer delete(seen, x)
		n := x.Len()
		array := n > 0
		count := 0
		x.ForEach(func(k, v lua.LValue) {
			count++
			if k.Type() != lua.LTNumber || float64(k.(lua.LNumber)) < 1 || float64(k.(lua.LNumber)) > float64(n) {
				array = false
			}
		})
		if count != n {
			array = false
		}
		if array {
			out := make([]any, n)
			for i := 1; i <= n; i++ {
				out[i-1] = fromLua(x.RawGetInt(i), depth+1, seen)
			}
			return out
		}
		out := map[string]any{}
		x.ForEach(func(k, v lua.LValue) {
			if v.Type() != lua.LTFunction && v.Type() != lua.LTUserData {
				value := fromLua(v, depth+1, seen)
				if value != nil {
					out[k.String()] = value
				}
			}
		})
		return out
	}
	return nil
}
func (s *RouteService) Build(ctx context.Context, state map[string]any) (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if str(state, "race") == "" || str(state, "class") == "" || num(state, "level") < 1 {
		return nil, fmt.Errorf("Charakterprofil fehlt")
	}
	if s.Lua != "" {
		dir, e := os.MkdirTemp("", "forevercore-route-")
		if e != nil {
			return nil, e
		}
		defer os.RemoveAll(dir)
		out := filepath.Join(dir, "result.json")
		programRoot := s.ScriptRoot
		if programRoot == "" {
			programRoot = s.Root
		}
		bootstrap := "FC_ROOT=" + luaLiteral(filepath.ToSlash(s.Root), 0) + ";FC_INPUT=" + luaLiteral(state, 0) + ";FC_OUT=" + luaLiteral(filepath.ToSlash(out), 0) + ";dofile(" + luaLiteral(filepath.ToSlash(filepath.Join(programRoot, "ForeverCore", "headless.lua")), 0) + ")"
		file := filepath.Join(dir, "run.lua")
		if e = os.WriteFile(file, []byte(bootstrap), 0600); e != nil {
			return nil, e
		}
		ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
		defer cancel()
		cmd := exec.CommandContext(ctx, s.Lua, file)
		logs, e := cmd.CombinedOutput()
		if e != nil {
			return nil, fmt.Errorf("Routenlauf: %v: %.1000s", e, logs)
		}
		var result map[string]any
		if e = loadJSON(out, &result); e != nil {
			return nil, e
		}
		return result, nil
	}
	L := lua.NewState()
	defer L.Close()
	ctx, cancel := context.WithTimeout(ctx, 90*time.Second)
	defer cancel()
	L.SetContext(ctx)
	L.SetGlobal("FC_ROOT", lua.LString(filepath.ToSlash(s.Root)))
	L.SetGlobal("FC_INPUT", toLua(L, state))
	// Compatibility for the pinned Lua 5.1 route modules; no game APIs are read here.
	if err := L.DoFile(filepath.Join(s.Root, "ForeverCore", "headless.lua")); err != nil {
		return nil, fmt.Errorf("Routenlauf: %w", err)
	}
	v := fromLua(L.GetGlobal("FC_OUTPUT"), 0, map[*lua.LTable]bool{})
	out, ok := v.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Routenlauf lieferte kein Ergebnis")
	}
	return out, nil
}
func str(m map[string]any, k string) string { v, _ := m[k].(string); return v }
func num(m map[string]any, k string) float64 {
	switch v := m[k].(type) {
	case float64:
		return v
	case int:
		return float64(v)
	case int32:
		return float64(v)
	case int64:
		return float64(v)
	case json.Number:
		n, _ := v.Float64()
		return n
	}
	return 0
}
func atomicWrite(path string, b []byte) error {
	if e := os.MkdirAll(filepath.Dir(path), 0755); e != nil {
		return e
	}
	tmp := path + ".new"
	if e := os.WriteFile(tmp, b, 0644); e != nil {
		return e
	}
	return replaceFile(tmp, path)
}
func loadJSON(path string, v any) error {
	b, e := os.ReadFile(path)
	if e != nil {
		return e
	}
	return json.Unmarshal(b, v)
}
func jsonBytes(v any) []byte { b, _ := json.MarshalIndent(v, "", "  "); return append(b, '\n') }
func luaLiteral(v any, depth int) string {
	if depth > 22 {
		return "nil"
	}
	switch x := v.(type) {
	case nil:
		return "nil"
	case string:
		var b strings.Builder
		b.WriteByte('"')
		for _, c := range []byte(x) {
			switch c {
			case '\\', '"':
				b.WriteByte('\\')
				b.WriteByte(c)
			default:
				if c < 32 || c == 127 {
					fmt.Fprintf(&b, "\\%03d", c)
				} else {
					b.WriteByte(c)
				}
			}
		}
		b.WriteByte('"')
		return b.String()
	case bool:
		if x {
			return "true"
		}
		return "false"
	case float64:
		return strconv.FormatFloat(x, 'g', -1, 64)
	case int:
		return strconv.Itoa(x)
	case []any:
		out := make([]string, len(x))
		for i, z := range x {
			out[i] = luaLiteral(z, depth+1)
		}
		return "{" + strings.Join(out, ",") + "}"
	case map[string]any:
		var out []string
		for k, z := range x {
			key := luaLiteral(k, depth+1)
			if n, e := strconv.Atoi(k); e == nil && n >= 0 {
				key = strconv.Itoa(n)
			}
			out = append(out, "["+key+"]="+luaLiteral(z, depth+1))
		}
		return "{" + strings.Join(out, ",") + "}"
	}
	b, e := json.Marshal(v)
	if e != nil {
		return "nil"
	}
	var a any
	if json.Unmarshal(b, &a) != nil {
		return "nil"
	}
	return luaLiteral(a, depth+1)
}
