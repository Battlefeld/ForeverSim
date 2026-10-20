package main

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"sync"
)

// Reading the engine manifest once: it is several MB and the build jobs need it for every request.
type manifestCache struct {
	mu    sync.Mutex
	path  string
	stamp int64
	data  map[string]any
}

func (s *SimService) manifest() (map[string]any, error) {
	path := manifestPath(s.Config)
	s.manifests.mu.Lock()
	defer s.manifests.mu.Unlock()
	stamp := fileStamp(path)
	if s.manifests.data != nil && s.manifests.path == path && s.manifests.stamp == stamp {
		return s.manifests.data, nil
	}
	var m map[string]any
	if e := loadJSON(path, &m); e != nil {
		return nil, fmt.Errorf("Engine-Manifest fehlt: %w", e)
	}
	s.manifests.path, s.manifests.stamp, s.manifests.data = path, stamp, m
	return m, nil
}

// classKey is the lower-case class name the manifest uses ("mage").
func classKeyOf(snap map[string]any) string { return strings.ToLower(str(snap, "class")) }

// presetEntries lists a decoded talent build with the identities the addon can match against its own tree:
// engine field name, spell id, definition id and the place in the tree.
func presetEntries(trees []any, ranks map[string]int) []any {
	out := []any{}
	for ti, raw := range trees {
		for _, n := range array(raw.(map[string]any), "talents") {
			node := n.(map[string]any)
			r := ranks[str(node, "fieldName")]
			if r < 1 {
				continue
			}
			loc := child(node, "location")
			out = append(out, map[string]any{"tree": float64(ti + 1), "row": num(loc, "rowIdx"), "col": num(loc, "colIdx"),
				"fieldName": str(node, "fieldName"), "spellId": node["spellId"], "definitionId": node["definitionId"], "rank": float64(r)})
		}
	}
	return out
}

// presetsFor answers the "presets" job: the talent builds and gear sets MythicSim ships for the class, with every
// talent text checked against the current talent tree. A text that is not a legal 51 point build is kept but marked,
// so the addon can show "passt nicht ganz zum Baum" instead of offering it as a finished build.
func (s *SimService) presetsFor(ctx context.Context, j Job) (any, error) {
	manifest, e := s.manifest()
	if e != nil {
		return nil, e
	}
	class := classKeyOf(child(j.State, "sim"))
	if class == "" {
		class = strings.ToLower(str(j.Payload, "class"))
	}
	profile := child(child(manifest, "classes"), class)
	if profile == nil {
		return nil, fmt.Errorf("Klasse nicht unterstuetzt")
	}
	trees := array(profile, "trees")
	set := child(child(manifest, "presets"), class)
	talents := []any{}
	for _, raw := range array(set, "talents") {
		p, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		row := map[string]any{"name": str(p, "name"), "talentsString": str(p, "talentsString")}
		if spec := str(p, "spec"); spec != "" {
			row["spec"] = spec
		}
		ranks, text, e := checkedTalentString(trees, str(p, "talentsString"), 51)
		if e != nil {
			// Not a legal build of the current tree: show what it would be, but do not offer it as a finished one.
			plain, e2 := decodeTalentString(trees, str(p, "talentsString"))
			if e2 != nil {
				row["valid"], row["error"] = false, e2.Error()
				talents = append(talents, row)
				continue
			}
			ranks, text = plain, str(p, "talentsString")
			row["valid"], row["error"] = false, e.Error()
		} else {
			row["valid"], row["talentsString"] = true, text
		}
		points := treePoints(trees, ranks)
		tree, _ := largestTreeOf(points)
		total := 0
		pts := make([]any, len(points))
		for i, v := range points {
			pts[i] = float64(v)
			total += v
		}
		row["points"], row["total"], row["tree"], row["entries"] = pts, float64(total), float64(tree+1), presetEntries(trees, ranks)
		if total != 51 {
			row["valid"] = false
			if row["error"] == nil {
				row["error"] = fmt.Sprintf("%d statt 51 Punkte", total)
			}
		}
		talents = append(talents, row)
	}
	gear := []any{}
	for _, raw := range array(set, "gear") {
		g, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		items := []any{}
		for slot, it := range array(g, "items") {
			if m, ok := it.(map[string]any); ok && num(m, "id") > 0 {
				items = append(items, map[string]any{"slot": float64(slot), "id": m["id"], "enchant": m["enchant"]})
			}
		}
		gear = append(gear, map[string]any{"name": str(g, "name"), "items": items})
	}
	builds := []any{}
	for _, raw := range array(set, "builds") {
		if b, ok := raw.(map[string]any); ok {
			builds = append(builds, b)
		}
	}
	return map[string]any{"engine": "MythicSim Go", "engineRevision": s.Config.EngineRevision, "class": class, "talents": talents, "gear": gear,
		"builds": builds, "layout": treeLayout(trees)}, nil
}

// presetGear finds a gear set of the class by name (case does not matter) and returns it as an engine equipment spec.
func presetGear(manifest map[string]any, class, name string) (map[string]any, error) {
	for _, raw := range array(child(child(manifest, "presets"), class), "gear") {
		g, ok := raw.(map[string]any)
		if ok && strings.EqualFold(str(g, "name"), name) {
			return map[string]any{"items": array(g, "items")}, nil
		}
	}
	return nil, fmt.Errorf("Ausruestungsvorlage nicht gefunden: %s", name)
}

// rotationNames lists the rotations of an engine spec in a fixed order.
func rotationNames(manifest map[string]any, spec string) []string {
	names := []string{}
	for name := range child(child(child(manifest, "specs"), spec), "rotations") {
		names = append(names, name)
	}
	sort.Strings(names)
	return names
}

// treeLayout lists every talent of the engine's tree with its place, its maximum rank and the talent it needs
// (preRow/preCol), so the addon's talent editor can apply the same rules as the engine.
func treeLayout(trees []any) []any {
	out := []any{}
	for ti, raw := range trees {
		for _, n := range array(raw.(map[string]any), "talents") {
			node := n.(map[string]any)
			loc := child(node, "location")
			e := map[string]any{"tree": float64(ti + 1), "row": num(loc, "rowIdx"), "col": num(loc, "colIdx"), "max": node["maxPoints"], "spellId": node["spellId"]}
			if p := child(node, "prereqLocation"); p != nil {
				e["preRow"], e["preCol"] = num(p, "rowIdx"), num(p, "colIdx")
			}
			out = append(out, e)
		}
	}
	return out
}
