# ForeverRoutes HUD

ForeverRoutes has its own frames, saved settings and locally packaged textures. It can run without ForeverSimBridge or ForeverCore. Its panel, buttons and connection crystal reuse the existing ForeverSim artwork; no ForeverSim source files are modified.

The current route task appears above its live quest objectives and authored item requirements. The HUD previews the next three unfinished steps, exposes persistent side tasks when supplied by route data, warns at one or fewer free bag slots, and supports skipping with undo. Quest completion always follows the game quest log. Manual confirmation is enabled only for otherwise unobservable tasks such as a dungeon visit or a note.

The arrow shows world-coordinate distance and arrival on the same continent. Arrival does not complete a quest. Map conversion validates normalized coordinates before creating a TomTom waypoint or a native map pin. The arrow hides in instances and clears obsolete route waypoints. The status distinguishes a live plan, stored route and guide fallback. A blue crystal requires an actual ForeverCore response in this session.

Quest rows open the quest log when clicked and show objective details on hover. Read-only hooks augment identifiable native tracker quest headers, and objective lines that explicitly expose an objective index. Unknown tracker layouts are left alone. A creature preview requires an explicit NPC identity in route metadata; target names/counts do not manufacture a model. The current exporter does not provide that metadata for every quest, so models and authored side/shopping tasks appear only where data is present.

`/fr` toggles the HUD. Other commands:

| Command | Effect |
| --- | --- |
| `/fr show`, `/fr hide` | Show or hide the route panel |
| `/fr skip`, `/fr back` | Skip current task or undo the last manual action |
| `/fr done` | Confirm an eligible manual task |
| `/fr options` | Open dungeon, optional-route and restoration controls |
| `/fr option 1` | Toggle an authored route option by number |
| `/fr solo`, `/fr dungeon` | Select the stored route variant |
| `/fr compact` | Toggle upcoming steps and side tasks |
| `/fr lock` | Lock or unlock panel and arrow dragging |
| `/fr arrow` | Toggle the independent arrow |
| `/fr scale 1.1` | Set panel scale, clamped to 0.65–1.5 |
| `/fr position` | Restore default panel and arrow positions |
| `/fr restore` | Restore skipped steps and hidden side tasks |

Right-click an authored side task to hide it; restore it through the options menu. Movement, scale and panel visibility persist across reloads.

## Validation

From the repository root, run `python3 _dev/run_lua.py _dev/harness/routes_hud_test.lua` on a host with `liblua5.4.so.0`. The harness checks progression, undo, live-plan replacement, item counts, invalid navigation, arrival, TomTom reuse, dungeon suspension, tracker recycling and UI event dispatch. It is a mocked client integration test, not in-game visual verification. The addon uses Lua 5.1-compatible syntax; in-game mouseovers, model rendering, arrow orientation and final artwork sizing still require a WoW Forever client check.
