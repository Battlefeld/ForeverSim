// Keeps the overlay sources out of the ForeverCore module: they compile only inside a MythicSim
// checkout (apply_overlay.py copies them there).
module forevercore/engine-overlay-files

go 1.24
