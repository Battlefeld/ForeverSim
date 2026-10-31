package main

import (
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// "Eigene Rota verfeinern": the best rotation of the engine, with its rows in a better order. A tuned rotation travels
// as a name, so every job that takes a rotation name can take it without any new field: "eigen:<engine rotation>:<order>",
// the order being the original positions of the rows in their new sequence ("eigen:fire:1,0,2,3").

const tunedPrefix = "eigen:"

// tunedRotationName builds the name of a rotation that is `base` with its rows in `order`.
func tunedRotationName(base string, order []int) string {
	parts := make([]string, len(order))
	for i, v := range order {
		parts[i] = strconv.Itoa(v)
	}
	return tunedPrefix + base + ":" + strings.Join(parts, ",")
}

// parseTunedName is the way back; ok is false for the name of an ordinary rotation or a broken one.
func parseTunedName(name string) (base string, order []int, ok bool) {
	if !strings.HasPrefix(name, tunedPrefix) {
		return "", nil, false
	}
	rest := strings.SplitN(strings.TrimPrefix(name, tunedPrefix), ":", 2)
	if len(rest) != 2 || rest[0] == "" || rest[1] == "" {
		return "", nil, false
	}
	for _, p := range strings.Split(rest[1], ",") {
		v, e := strconv.Atoi(p)
		if e != nil || v < 0 {
			return "", nil, false
		}
		order = append(order, v)
	}
	return rest[0], order, true
}

// reorderRotation returns a copy of the rotation whose priority list is the original rows in `order`.
func reorderRotation(rotation map[string]any, order []int) (map[string]any, error) {
	rows := array(rotation, "priorityList")
	if len(order) != len(rows) {
		return nil, fmt.Errorf("Reihenfolge muss alle Rotationszeilen enthalten")
	}
	seen := map[int]bool{}
	list := make([]any, 0, len(order))
	for _, i := range order {
		if i < 0 || i >= len(rows) || seen[i] {
			return nil, fmt.Errorf("Reihenfolge passt nicht zur Rotation")
		}
		seen[i] = true
		list = append(list, rows[i])
	}
	out := make(map[string]any, len(rotation))
	for k, v := range rotation {
		out[k] = v
	}
	out["priorityList"] = list
	return out, nil
}

// lookupRotation finds a rotation by name among the rotations of an engine spec, tuned names included.
func lookupRotation(rotations map[string]any, name string) (any, bool) {
	if r, ok := rotations[name]; ok {
		return r, true
	}
	base, order, ok := parseTunedName(name)
	if !ok {
		return nil, false
	}
	b, ok := rotations[base].(map[string]any)
	if !ok {
		return nil, false
	}
	r, e := reorderRotation(b, order)
	if e != nil {
		return nil, false
	}
	return r, true
}

// tuneNeighbours lists the orders that differ from `order` by one row moved up to `reach` places (each order once).
func tuneNeighbours(order []int, reach int) [][]int {
	seen := map[string]bool{strings.Trim(fmt.Sprint(order), "[]"): true}
	var out [][]int
	n := len(order)
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			if i == j || j-i > reach || i-j > reach {
				continue
			}
			next := make([]int, 0, n)
			for k, v := range order {
				if k != i {
					next = append(next, v)
				}
			}
			next = append(next[:j], append([]int{order[i]}, next[j:]...)...)
			key := strings.Trim(fmt.Sprint(next), "[]")
			if !seen[key] {
				seen[key] = true
				out = append(out, next)
			}
		}
	}
	return out
}

// rotaTune answers the "rota-tune" job: one step of the refinement. payload: build (as in build-detail), rotation (the
// engine rotation to start from), order (the current order; the original one when missing), iterations (the quick
// measurement). The answer holds the damage of the current order and of the best neighbour; the addon repeats the step
// while it brings something and then checks the result with the full count.
func (s *SimService) rotaTune(ctx context.Context, j Job) (any, error) {
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	class := classKeyOf(child(j.State, "sim"))
	b := child(j.Payload, "build")
	if b == nil {
		b = map[string]any{}
	}
	base := str(j.Payload, "rotation")
	if base == "" {
		return nil, fmt.Errorf("Rotation fehlt")
	}
	if inner, _, ok := parseTunedName(base); ok {
		base = inner
	}
	payload, e := buildPayload(j, manifest, class, b)
	if e != nil {
		return nil, e
	}
	payload["rotation"] = base
	req, e := s.liveRequest(Job{Schema: j.Schema, Kind: "sim", State: j.State, Payload: payload})
	if e != nil {
		return nil, e
	}
	spec := str(req, "foreverCoreSpec")
	rotation, ok := child(child(child(manifest, "specs"), spec), "rotations")[base].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Rotation fehlt: %s", base)
	}
	rows := len(array(rotation, "priorityList"))
	if rows < 2 {
		return nil, fmt.Errorf("Die Rotation hat zu wenige Zeilen zum Verfeinern")
	}
	order := make([]int, 0, rows)
	for _, v := range array(j.Payload, "order") {
		index, ok := v.(float64)
		if !ok || index < 0 || index >= float64(rows) || index != float64(int(index)) {
			return nil, fmt.Errorf("Ungueltige Rotationszeile")
		}
		order = append(order, int(index))
	}
	if len(order) == 0 {
		for i := 0; i < rows; i++ {
			order = append(order, i)
		}
	}
	if _, e := reorderRotation(rotation, order); e != nil || len(order) != rows {
		return nil, fmt.Errorf("Reihenfolge passt nicht zur Rotation")
	}
	iterations := int(num(j.Payload, "iterations"))
	if iterations < 50 || iterations > 5000 {
		iterations = 300
	}
	measure := func(o []int) (float64, error) {
		rot, e := reorderRotation(rotation, o)
		if e != nil {
			return 0, e
		}
		r := cloneMap(req)
		child(r, "simOptions")["iterations"] = float64(iterations)
		pl, _ := playerOf(r)
		pl["rotation"] = rot
		got, e := s.once(ctx, r)
		if e != nil {
			return 0, e
		}
		return simDPS(got), nil
	}
	current, e := measure(order)
	if e != nil {
		return nil, e
	}
	candidates := tuneNeighbours(order, 3)
	if len(candidates) > 120 {
		candidates = candidates[:120]
	}
	type scored struct {
		order []int
		dps   float64
	}
	results := make([]scored, len(candidates))
	sem := make(chan struct{}, variantWorkers(len(candidates)))
	var wg sync.WaitGroup
	for i, c := range candidates {
		sem <- struct{}{}
		wg.Add(1)
		go func(i int, c []int) {
			defer wg.Done()
			defer func() { <-sem }()
			defer func() { _ = recover() }()
			if d, e := measure(c); e == nil {
				results[i] = scored{c, d}
			}
		}(i, c)
	}
	wg.Wait()
	sort.SliceStable(results, func(a, c int) bool { return results[a].dps > results[c].dps })
	out := map[string]any{"engine": "Engine Go", "engineRevision": s.Config.EngineRevision, "rotation": base, "spec": spec,
		"rows": float64(rows), "order": intsToAny(order), "dps": current, "tried": float64(len(candidates))}
	if len(results) > 0 && results[0].dps > current {
		out["bestOrder"], out["bestDps"] = intsToAny(results[0].order), results[0].dps
		out["bestName"] = tunedRotationName(base, results[0].order)
	}
	return out, nil
}

func intsToAny(v []int) []any {
	out := make([]any, len(v))
	for i, x := range v {
		out[i] = float64(x)
	}
	return out
}
