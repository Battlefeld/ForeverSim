package main

import (
	"fmt"
	"math"
	"sort"
)

// Leveling rating: turns a SIM DPS into time per kill and experience per hour for caller-supplied
// mobs. Mob health and experience are inputs (no measured mob table exists yet), so nothing here
// invents game data. The DPS is the SIM's single-target value against the reference target.
const (
	defaultKillDowntime = 8.0 // seconds per kill for looting/pulling; overridable via payload.downtime
	maxLevelingMobs     = 64
)

// A mob may carry its own "dps" (SIM against that mob); otherwise the reference DPS applies.
func levelingRating(dps float64, payload map[string]any) (map[string]any, error) {
	mobs := array(payload, "mobs")
	if len(mobs) == 0 || len(mobs) > maxLevelingMobs {
		return nil, fmt.Errorf("Leveling: 1-%d Gegner mit health und xp uebergeben", maxLevelingMobs)
	}
	downtime, regen := defaultKillDowntime, num(payload, "regenSeconds")
	if payload["downtime"] != nil {
		downtime = num(payload, "downtime")
	}
	if downtime < 0 || regen < 0 || math.IsNaN(downtime) || math.IsNaN(regen) {
		return nil, fmt.Errorf("Leveling: downtime/regenSeconds duerfen nicht negativ sein")
	}
	rows := make([]any, 0, len(mobs))
	for i, raw := range mobs {
		m, ok := raw.(map[string]any)
		health, xp := num(m, "health"), num(m, "xp")
		if !ok || !(health > 0) || xp < 0 || math.IsInf(health, 0) || math.IsInf(xp, 0) {
			return nil, fmt.Errorf("Leveling: Gegner %d braucht health > 0 und xp >= 0", i+1)
		}
		name := str(m, "name")
		if name == "" {
			name = fmt.Sprintf("Gegner %d", i+1)
		}
		mobDPS := dps
		if v := num(m, "dps"); m["dps"] != nil {
			mobDPS = v
		}
		if !(mobDPS > 0) || math.IsInf(mobDPS, 0) {
			return nil, fmt.Errorf("Leveling-Bewertung braucht positiven SIM-Schaden (%s)", name)
		}
		ttk := health / mobDPS
		cycle := ttk + downtime + regen
		row := map[string]any{}
		for k, v := range m {
			row[k] = v
		}
		for k, v := range map[string]any{"name": name, "dps": mobDPS, "timeToKill": ttk, "cycleSeconds": cycle, "killsPerHour": 3600 / cycle, "xpPerHour": xp * 3600 / cycle} {
			row[k] = v
		}
		rows = append(rows, row)
	}
	sort.SliceStable(rows, func(a, b int) bool {
		return num(rows[a].(map[string]any), "xpPerHour") > num(rows[b].(map[string]any), "xpPerHour")
	})
	best := rows[0].(map[string]any)
	return map[string]any{"dps": dps, "downtime": downtime, "regenSeconds": regen, "rows": rows, "best": best["name"], "bestXpPerHour": best["xpPerHour"],
		"comparison": "EP/Stunde = Gegner-EP / (Lebenspunkte/SIM-DPS + Pausen). Einzelziel, ohne Laufwege, Respawn und Gruppenpulls; Lebenspunkte und EP stammen aus dem Auftrag."}, nil
}

// A benchmark is explicitly an assumption, never a measured NPC record.
func levelingBenchmark(j Job) map[string]any {
 p:=cloneMap(j.Payload);if p==nil{p=map[string]any{}}
 level:=num(child(j.State,"sim"),"level")
 target:=num(p,"targetLevel");if target<1{target=level};p["targetLevel"]=target
 health:=num(p,"targetHealth");source:="Manuelle Gegner-Lebenspunkte"
 if health<=0{health=40+15*target+0.6*target*target;source="Generiertes HP-Benchmarkmodell; kein verifizierter NPC-Wert"}
 p["mobs"]=[]any{map[string]any{"name":"Level-Benchmark","health":health,"xp":float64(0)}}
 p["benchmarkSource"]=source
 return p
}
