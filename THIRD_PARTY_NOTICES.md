# Lizenzen und Quellen

ForeverSim (ForeverCore.exe, ForeverCoreBridge, ForeverSimBridge) besteht aus eigenem Code und aus Teilen, die von
fremden Projekten stammen. Jeder Teil behält die Lizenz seiner Quelle.

## Was unter welcher Lizenz steht

| Teil | Lizenz | Lizenztext |
|---|---|---|
| Eigener Code: `ForeverCore/` (Go, Python, Lua), `ForeverCoreBridge/`, `ForeverSimBridge/`, `_dev/`, `tools/`; Grafiken (eigenes Art-Pack, erzeugt mit `_dev/tools/build_media.py`) | MIT, © 2026 Battlefeld | [`LICENSE`](LICENSE) |
| Dungeon-Katalog `ForeverSimBridge/DungeonCatalogData.lua` (aus NorgannonDB, Item-Plätze auch aus cmangos) | GPL-3.0 | [`LICENSES/GPL-3.0.txt`](LICENSES/GPL-3.0.txt), im Addon `ForeverSimBridge/GPL-3.0.txt` |
| Leerwandler-/Wichtelwerte `ForeverCore/warlock-demons.json` (aus cmangos classic-db) | GPL-3.0 | [`LICENSES/GPL-3.0.txt`](LICENSES/GPL-3.0.txt) |
| Zauber, Talentkurven und Kampfregeln aus WoWSims Forever (in `ForeverSimBridge`, `ForeverCore/engine-*`) und die gebaute Engine `ForeverEngine.exe` | MIT, © 2022 wowsims team | [`ForeverSimBridge/THIRD_PARTY_LICENSES.txt`](ForeverSimBridge/THIRD_PARTY_LICENSES.txt), im Paket `Lizenzen/Engine-MIT.txt` |
| `Lua.exe` (Lua 5.1, im Paket) | MIT, © Lua.org, PUC-Rio | im Paket `Lizenzen/Lua.txt` |
| Mitgeliefertes Addon ForeverRoutes und seine Routen | Code MIT; Routen und Datensatz GPL-3.0; RestedXP-Abschnitte CC BY-NC-SA 4.0 | im Addon-Ordner; [ForeverRoutes](https://github.com/Battlefeld/ForeverRoutes/blob/main/THIRD_PARTY_NOTICES.md) |

Wer nur den eigenen Code weiterverwendet (ohne Katalog und `warlock-demons.json`), braucht nur die MIT-Lizenz.

## Quellen

| Quelle | Was daraus stammt | Lizenz |
|---|---|---|
| [WoWSims Forever](https://github.com/wowsims/forever) | Kampf-Simulation, Item-Datenbank, Zauber und Talente | MIT |
| [NorgannonDB](https://github.com/zmarotrix/NorgannonDB) | Dungeons, Stufen, Bosse, Beute, Dropchancen (Instanzen aus DungeonJournal by Exehn) | GPL-3.0 |
| [cmangos classic-db](https://github.com/cmangos/classic-db) | Werte der Hexenmeister-Begleiter je Stufe, Ausrüstungsplätze von Items | GPL-3.0 |
| [QuestieDB](https://github.com/Questie/QuestieDB) | Quest-Angaben für die Routenberechnung | GPL-3.0 nach Angabe des Questie-Teams |
| [ForeverDB.net](https://foreverdb.net) | Quest-Beobachtungen und die Tooltips der Zauber (Gegenprobe der Zahlen, Spell-Check), live abgefragt. Data from ForeverDB.net. | keine Lizenz genannt; Nutzung mit Quellenangabe |
| [Wowhead Forever](https://www.wowhead.com/forever), [ForeverChanges](https://foreverchanges.pro) | Einzelne Werte zu Essen, Verzauberungen und Talenten, jeweils mit Link in der Datei; Grundwerte je Klasse und Stufe 10–60 (`ForeverCore/leveling-basestats.json`, Gear-Planer von Wowhead Forever) | einzelne Fakten mit Quellenangabe |
| Tabellen des Spielclients (`PlayerExpectedStat`) | Grundwerte je Klasse und Stufe in `leveling-data.json` | Spielinhalt von Blizzard Entertainment |

## Spielinhalte

World of Warcraft, die Namen, Texte und Daten des Spiels gehören Blizzard Entertainment. ForeverSim ist ein
inoffizielles Fan-Werkzeug und steht in keiner Verbindung zu Blizzard Entertainment, zum Betreiber von WoW Forever
oder zu den oben genannten Projekten.
