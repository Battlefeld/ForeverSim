package main

import (
	"fmt"
	"strings"
)

func resolveSimProfile(manifest, snap map[string]any, explicit string) (map[string]any, error) {
	cl := strings.ToLower(str(snap, "class"))
	specs := child(manifest, "specs")
	key := explicit
	if key == "" {
		key = str(child(child(manifest, "classes"), cl), "spec")
		largest, tree := 0, 0
		for i, raw := range array(snap, "talents") {
			points := 0
			for _, entry := range array(raw.(map[string]any), "entries") {
				points += int(num(entry.(map[string]any), "rank"))
			}
			if points > largest {
				largest = points
				tree = i
			}
		}
		switch cl {
		case "druid":
			if str(snap, "form") == "bear" {
				key = "feralBearDruid"
			} else if str(snap, "form") == "cat" || tree == 1 {
				key = "feralCatDruid"
			} else if tree == 2 {
				return nil, fmt.Errorf("Heilerprofil benoetigt ein Heilungsszenario; kein automatischer Balance-DPS-Vergleich")
			}
		case "shaman":
			if tree == 1 {
				key = "enhancementShaman"
			} else if tree == 2 {
				return nil, fmt.Errorf("Heilerprofil benoetigt ein Heilungsszenario; kein automatischer Elementar-DPS-Vergleich")
			}
		case "paladin":
			if tree == 1 {
				key = "protectionPaladin"
			} else if tree == 0 && largest > 0 {
				return nil, fmt.Errorf("Heilerprofil benoetigt ein Heilungsszenario; kein automatischer Vergelter-DPS-Vergleich")
			}
		case "warrior":
			if tree == 2 {
				key = "protectionWarrior"
			}
		}
	}
	profile := child(specs, key)
	if profile == nil || str(profile, "class") != cl {
		return nil, fmt.Errorf("MythicSim-Spezialisierung passt nicht: %s / %s", cl, key)
	}
	return profile, nil
}
