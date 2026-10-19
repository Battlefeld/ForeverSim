package core

// Mana sums and multiplicative discounts may differ by a few floating-point ulps after resets.
// At an exact affordability boundary this used to change the next cast between ST/MT runs.
// The tolerance is far below one mana point and is disabled for upstream level-60 references.
const foreverCoreManaEpsilon = 1e-9

func foreverCoreManaEnough(current, cost float64) bool {
	return current >= cost || (foreverCoreLevelActive && cost-current <= foreverCoreManaEpsilon)
}
func foreverCoreManaRemainder(value float64) float64 {
	if foreverCoreLevelActive && value < 0 && value >= -foreverCoreManaEpsilon {
		return 0
	}
	return value
}
