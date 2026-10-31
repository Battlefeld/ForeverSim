package main

import (
	"fmt"
	"strings"
)

func resolveSimProfile(manifest, snap map[string]any, explicit string) (map[string]any, error) {
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
	return resolveSimProfileFor(manifest, strings.ToLower(str(snap, "class")), str(snap, "form"), tree, largest, explicit)
}

// resolveSimProfileFor picks the engine spec for a class from the tree that holds the most points (largest points,
// tree index) and, for druids, the shapeshift form. An explicit spec key wins.
func resolveSimProfileFor(manifest map[string]any, cl, form string, tree, largest int, explicit string) (map[string]any, error) {
	specs := child(manifest, "specs")
	key := explicit
	if key == "" {
		key = str(child(child(manifest, "classes"), cl), "spec")
		switch cl {
		case "druid":
			if form == "bear" {
				key = "feralBearDruid"
			} else if form == "cat" || tree == 1 {
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
		return nil, fmt.Errorf("Engine-Spezialisierung passt nicht: %s / %s", cl, key)
	}
	return profile, nil
}
