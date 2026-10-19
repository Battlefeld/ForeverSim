package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

func foreverPositions(v any) []any {
	list, _ := v.([]any)
	var out []any
	for _, x := range list {
		m, ok := x.(map[string]any)
		if !ok {
			continue
		}
		locations := array(m, "at")
		if len(locations) == 0 {
			locations = []any{m}
		}
		for _, raw := range locations {
			p, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			mapID, x, y := num(p, "m"), num(p, "x"), num(p, "y")
			if mapID > 0 && x >= 0 && x <= 100 && y >= 0 && y <= 100 {
				if _, ok := p["x"]; !ok {
					continue
				}
				if _, ok := p["y"]; !ok {
					continue
				}
				out = append(out, map[string]any{"kind": str(m, "kind"), "id": num(m, "id"), "map": mapID, "x": x, "y": y})
			}
		}
	}
	return out
}
func foreverEvidence(ctx context.Context, cfg Config) (string, string, error) {
	type shard struct {
		index int
		b     []byte
		e     error
	}
	jobs := make(chan int, 64)
	results := make(chan shard, 64)
	var wg sync.WaitGroup
	for w := 0; w < 6; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := range jobs {
				path := filepath.Join(cfg.Data, "ForeverDB", fmt.Sprintf("%02d.json", i))
				b, e := os.ReadFile(path)
				info, statErr := os.Stat(path)
				if e != nil || statErr != nil || time.Since(info.ModTime()) > 6*time.Hour {
					b, e = fetchBounded(ctx, fmt.Sprintf("https://foreverdb.net/data/questguides/%d.json", i), 8<<20)
					if e == nil {
						var obj map[string]any
						if json.Unmarshal(b, &obj) != nil || len(obj) == 0 {
							e = fmt.Errorf("ForeverDB-Shard %d ungueltig", i)
						} else {
							e = atomicWrite(path, b)
						}
					}
				}
				results <- shard{i, b, e}
			}
		}()
	}
	for i := 0; i < 64; i++ {
		jobs <- i
	}
	close(jobs)
	wg.Wait()
	close(results)
	all := make([][]byte, 64)
	records := map[int]map[string]any{}
	for s := range results {
		if s.e != nil {
			return "", "", s.e
		}
		all[s.index] = s.b
		var data map[string]any
		if e := json.Unmarshal(s.b, &data); e != nil {
			return "", "", e
		}
		for key, v := range data {
			id, e := strconv.Atoi(key)
			m, ok := v.(map[string]any)
			if e != nil || id < 1 || !ok {
				return "", "", fmt.Errorf("ForeverDB-Schema in Shard %d", s.index)
			}
			if existing := records[id]; existing != nil {
				return "", "", fmt.Errorf("ForeverDB-ID mehrfach: %d", id)
			}
			records[id] = m
		}
	}
	h := sha256.New()
	for _, b := range all {
		h.Write(b)
	}
	hash := hex.EncodeToString(h.Sum(nil))
	ids := make([]int, 0, len(records))
	for id := range records {
		ids = append(ids, id)
	}
	sort.Ints(ids)
	var out strings.Builder
	out.WriteString("local _,ns=...\nlocal E=ns.ForeverDBQuestEvidence or {};ns.ForeverDBQuestEvidence=E\nlocal function set(id,fresh)local previous=E[id]or{};for k,v in pairs(fresh)do previous[k]=v end;E[id]=previous end\n")
	for _, id := range ids {
		r := records[id]
		status := str(r, "src")
		if status != "forever" && status != "classic" && status != "unknown" {
			continue
		}
		record := map[string]any{"status": status, "seenBy": num(r, "seenBy"), "date": str(r, "updated"), "url": fmt.Sprintf("https://foreverdb.net/quest/%d", id), "observedPositions": map[string]any{"from": foreverPositions(r["from"]), "to": foreverPositions(r["to"])}}
		fmt.Fprintf(&out, "set(%d,%s)\n", id, luaLiteral(record, 0))
	}
	out.WriteString("if ns.DataProvider then ns.DataProvider.Invalidate()end\n")
	return out.String(), hash, nil
}
