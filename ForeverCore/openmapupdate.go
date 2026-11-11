package main

import (
	"context"
	"path/filepath"
	"strings"
)

// OpenMap (openmap-world/openmap, MIT; a seamless world map for Forever) is too big for ForeverCore.exe (its map art
// alone is over 100 MB). The workflow "OpenMap" packs its newest version for Forever into the release "openmap" of
// this repository; ForeverCore installs it into WoW's AddOns folder and brings it to every new version, checked
// against its SHA-256, the same way as the ForeverRoutes addon.
const (
	openMapRelease = "https://github.com/Battlefeld/ForeverSim/releases/download/openmap/"
	openMapMarker  = "OpenMap.version"
	openMapLimit   = 400 << 20
)

// openMapBase is the release folder; a test points it at its own server.
var openMapBase = openMapRelease

func updateOpenMap(ctx context.Context, cfg Config) error {
	if cfg.Addons == "" {
		return nil // no WoW folder set up
	}
	vb, err := fetchBounded(ctx, openMapBase+"OpenMap.version", 4<<10)
	if err != nil {
		return err
	}
	version := strings.TrimSpace(string(vb))
	if version == "" {
		return nil
	}
	return installAddonPackage(ctx, addonPackage{
		Addons: cfg.Addons, Name: "OpenMap", Version: version,
		Marker: filepath.Join(filepath.Dir(routesDir(cfg)), openMapMarker),
		ZipURL: openMapBase + "OpenMap.zip", SHAURL: openMapBase + "OpenMap.zip.sha256", Limit: openMapLimit,
	})
}
