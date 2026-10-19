package core

import "testing"

func TestForeverCoreManaAffordabilityBoundary(t *testing.T) {
	old := foreverCoreLevelActive
	defer func() { foreverCoreLevelActive = old }()
	foreverCoreLevelActive = true
	if !foreverCoreManaEnough(38.25-1e-12, 38.25) {
		t.Fatal("rounding drift changed cast availability")
	}
	if foreverCoreManaEnough(38.25-1e-5, 38.25) {
		t.Fatal("genuinely missing mana was granted")
	}
	if foreverCoreManaRemainder(-1e-12) != 0 || foreverCoreManaRemainder(-1) != -1 {
		t.Fatal("invalid rounding clamp")
	}
	foreverCoreLevelActive = false
	if foreverCoreManaEnough(38.25-1e-12, 38.25) || foreverCoreManaRemainder(-1e-12) == 0 {
		t.Fatal("upstream level-60 behaviour changed")
	}
}
