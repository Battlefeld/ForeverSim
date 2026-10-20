package main

import (
	"context"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
)

func liveTalentEntries(snap map[string]any) []any {
	var entries []any
	for _, raw := range array(snap, "talents") {
		if tree, ok := raw.(map[string]any); ok {
			entries = append(entries, array(tree, "entries")...)
		}
	}
	return entries
}

// Resolve talents using upstream identifiers. Local addon keys are only a fallback;
// their abbreviated names are not MythicSim's protobuf field names.
func encodeTalentEntries(trees, entries []any, validate bool, budget int) (string, map[string]int, error) {
	nodes := map[string]map[string]any{}
	byID := map[int]string{}
	byDefinition := map[int]string{}
	for _, tr := range trees {
		for _, raw := range array(tr.(map[string]any), "talents") {
			n := raw.(map[string]any)
			key := str(n, "fieldName")
			nodes[key] = n
			if id := int(num(n, "spellId")); id > 0 {
				byID[id] = key
			}
			if id := int(num(n, "definitionId")); id > 0 {
				byDefinition[id] = key
			}
			for _, id := range array(n, "spellIds") {
				byID[int(id.(float64))] = key
			}
		}
	}
	ranks := map[string]int{}
	total := 0
	for _, raw := range entries {
		e, ok := raw.(map[string]any)
		if !ok {
			return "", nil, fmt.Errorf("Ungueltiger Talenteintrag")
		}
		v := num(e, "rank")
		rank := int(v)
		if v != float64(rank) || rank < 0 {
			return "", nil, fmt.Errorf("Ungueltiger Talentrang")
		}
		if rank == 0 {
			continue
		}
		// An entry from the addon's talent editor or from a preset names its place in the tree: treeIndex (1-based),
		// rowIdx, colIdx. That is the most reliable identity, the addon's own spell ids can differ from the engine's.
		key := ""
		if ti := int(num(e, "treeIndex")); ti >= 1 && ti <= len(trees) && e["rowIdx"] != nil && e["colIdx"] != nil {
			for _, raw := range array(trees[ti-1].(map[string]any), "talents") {
				n := raw.(map[string]any)
				loc := child(n, "location")
				if num(loc, "rowIdx") == num(e, "rowIdx") && num(loc, "colIdx") == num(e, "colIdx") {
					key = str(n, "fieldName")
					break
				}
			}
		}
		if key == "" {
			key = byID[int(num(e, "spellID"))]
		}
		if key == "" {
			key = byID[int(num(e, "spellId"))]
		}
		if key == "" {
			key = byDefinition[int(num(e, "definitionID"))]
		}
		if key == "" {
			key = byID[int(num(e, "modelSpellID"))]
		}
		if key == "" && nodes[str(e, "classKey")] != nil {
			key = str(e, "classKey")
		}
		if key == "" && nodes[str(e, "fieldName")] != nil {
			key = str(e, "fieldName")
		}
		if key == "" {
			return "", nil, fmt.Errorf("Talent nicht eindeutig zugeordnet: %s / %.0f", str(e, "classKey"), num(e, "spellID"))
		}
		if _, exists := ranks[key]; exists {
			return "", nil, fmt.Errorf("Doppelter Talenteintrag: %s", key)
		}
		if rank > int(num(nodes[key], "maxPoints")) {
			return "", nil, fmt.Errorf("Talentrang passt nicht: %s", key)
		}
		ranks[key] = rank
		total += rank
	}
	if validate && total > budget {
		return "", nil, fmt.Errorf("Entwurf nutzt %d Punkte, verfuegbar sind %d", total, budget)
	}
	var encoded []string
	for _, tr := range trees {
		talents := array(tr.(map[string]any), "talents")
		var b strings.Builder
		for _, raw := range talents {
			n := raw.(map[string]any)
			key := str(n, "fieldName")
			r := ranks[key]
			b.WriteString(strconv.Itoa(r))
			if !validate || r == 0 {
				continue
			}
			loc := child(n, "location")
			row := num(loc, "rowIdx")
			below := 0
			for _, other := range talents {
				nn := other.(map[string]any)
				if num(child(nn, "location"), "rowIdx") < row {
					below += ranks[str(nn, "fieldName")]
				}
			}
			if below < int(row)*5 {
				return "", nil, fmt.Errorf("Zu wenige Punkte unterhalb von %s", key)
			}
			if prereq := child(n, "prereqLocation"); prereq != nil {
				found := false
				for _, other := range talents {
					nn := other.(map[string]any)
					l := child(nn, "location")
					if num(l, "rowIdx") == num(prereq, "rowIdx") && num(l, "colIdx") == num(prereq, "colIdx") {
						found = ranks[str(nn, "fieldName")] == int(num(nn, "maxPoints"))
					}
				}
				if !found {
					return "", nil, fmt.Errorf("Talentvoraussetzung fehlt: %s", key)
				}
			}
		}
		encoded = append(encoded, strings.TrimRight(b.String(), "0"))
	}
	return strings.Join(encoded, "-"), ranks, nil
}

func (s *SimService) compareTalents(ctx context.Context, req, base map[string]any, j Job) (any, error) {
	var manifest map[string]any
	if e := loadJSON(filepath.Join(s.Config.Runtime, "ForeverCore", "engine-data.json"), &manifest); e != nil {
		return nil, e
	}
	player, _ := playerOf(req)
	cl := strings.ToLower(strings.TrimPrefix(str(player, "class"), "Class"))
	profile := child(child(manifest, "classes"), cl)
	if profile == nil {
		return nil, fmt.Errorf("Talentbaum fehlt")
	}
	// Budget comes from the actual snapshot; imported profiles may redistribute their current points.
	budget := 0
	for _, ch := range str(player, "talentsString") {
		if ch >= '0' && ch <= '9' {
			budget += int(ch - '0')
		}
	}
	snap := child(j.State, "sim")
	if snap != nil {
		budget += int(num(snap, "unspentTalentPoints"))
	}
	encoded, draftRanks, e := encodeTalentEntries(array(profile, "trees"), array(j.Payload, "talents"), true, budget)
	if e != nil {
		return nil, e
	}
	candidate := cloneMap(req)
	p, _ := playerOf(candidate)
	p["talentsString"] = encoded
	grantDraftSpells(candidate, array(profile, "trees"), draftRanks)
	if rotation := child(j.Payload, "rotation"); rotation != nil {
		p["rotation"] = rotation
	}
	result, e := s.once(ctx, candidate)
	if e != nil {
		return nil, e
	}
	before := simDPS(base)
	after := simDPS(result)
	return withResultContext(map[string]any{"engine": "MythicSim Go", "engineRevision": s.Config.EngineRevision, "base": before, "cand": after, "pct": 100 * (after - before) / before, "talentsString": encoded, "per": map[string]any{}, "comparison": "Gleiches Szenario, gleiche Rotation, gleicher Seed; keine unabhaengige Optimierung beider Builds"}, req), nil
}

 
// recommendNextTalent compares every currently legal one-point allocation across
// all three talent trees with the SAME pinned MythicSim scenario and rotation.
// No speculative scores: unsupported or invalid talents are reported as errors.
func (s *SimService) recommendNextTalent(ctx context.Context, req, base map[string]any, j Job) (any, error) {
	var manifest map[string]any
	if e := loadJSON(filepath.Join(s.Config.Runtime,"ForeverCore","engine-data.json"),&manifest);e!=nil{return nil,e}
	player,_ := playerOf(req)
	cl:=strings.ToLower(strings.TrimPrefix(str(player,"class"),"Class"))
	profile:=child(child(manifest,"classes"),cl)
	if profile==nil{return nil,fmt.Errorf("Talentbaum fehlt")}
	budget:=0
	for _,ch:=range str(player,"talentsString"){if ch>='0'&&ch<='9'{budget+=int(ch-'0')}}
	budget+=int(num(child(j.State,"sim"),"unspentTalentPoints"))
	options:=array(j.Payload,"candidates")
	if len(options)==0 || len(options)>24{return nil,fmt.Errorf("1-24 gueltige Talentvorschlaege erforderlich")}
	startDPS:=simDPS(base)
	if startDPS<=0{return nil,fmt.Errorf("Referenz-DPS fehlen")}
	rows:=[]any{}
	best:=map[string]any(nil)
	// A survival/filler talent with 0 DPS is not a damage recommendation.
	// Both builds use the same engine, encounter and seed.
	for _,raw:=range options {
		option,ok:=raw.(map[string]any);if !ok{continue}
		row:=map[string]any{"key":str(option,"key"),"name":str(option,"name"),"tree":option["tree"]}
		encoded,ranks,e:=encodeTalentEntries(array(profile,"trees"),array(option,"talents"),true,budget)
		if e==nil {
			candidate:=cloneMap(req);p,_:=playerOf(candidate)
			p["talentsString"]=encoded
			grantDraftSpells(candidate,array(profile,"trees"),ranks)
			var result map[string]any
			result,e=s.once(ctx,candidate)
			if e==nil{
				after:=simDPS(result)
				row["dps"]=after
				row["delta"]=after-startDPS
				row["percent"]=100*(after-startDPS)/startDPS
				if after>startDPS && (best==nil || after>num(best,"dps")){best=row}
			}
		}
		if e!=nil{row["error"]=e.Error()}
		rows=append(rows,row)
	}
	if best==nil{
		valid:=false
		for _,raw:=range rows{row:=raw.(map[string]any);if _,ok:=row["dps"];ok{valid=true;break}}
		status:="unsupported"
		if valid{status="no-dps-gain"}
		return withResultContext(map[string]any{"base":startDPS,"rows":rows,"status":status},req),nil
	}
	return withResultContext(map[string]any{"base":startDPS,"rows":rows,"best":best,"status":"ok","engine":"MythicSim Go"},req),nil
}
