# ForeverSim / ForeverCore

Ausrüstung, Talente und Rotation für **WoW Forever**, berechnet mit einer echten Kampf-Simulation, angezeigt direkt im
Spiel. Gerechnet wird nicht im Spiel, sondern auf deinem PC: Die Addons lesen deinen Charakter, `ForeverCore.exe`
simuliert mit der Engine-Engine (WoWSims Forever) und schickt das Ergebnis zurück, ohne `/reload`.

ForeverSim ist ein inoffizielles Fan-Projekt und steht in keiner Verbindung zu Blizzard Entertainment.

## Was es kann

- **Item-Vergleich im Tooltip:** „+x % DPS“ gegenüber dem, was du trägst, bei Quest-Belohnungen, Beute, Würfelfenster
  und Taschen; Belohnungen der Quests im Log und Taschen-Items werden vorab gerechnet, damit das Ergebnis beim Ansehen
  schon da ist.
- **Dungeons:** Beim Betreten die Drops, die dich verbessern, mit Boss und Dropchance (29 Dungeons).
- **Auktionshaus:** das beste Angebot je Ausrüstungsplatz auf Knopfdruck.
- **ForeverSim-Fenster (`/fus`):** beste Skillung, Rotation, Kampf-HUD und Auswertung, Beute, Verzauberungen und Buffs.
- **Levelroute:** Das mitgelieferte Addon [ForeverRoutes](https://github.com/Battlefeld/ForeverRoutes) zeigt die beste
  Route bis Stufe 20 und plant mit ForeverCore live ab deinem Stand.
- **Updates:** ForeverCore aktualisiert sich selbst (signiert, mit Weg zurück zur vorherigen Version), die Addons und
  die Routen.

## Installation

1. **[ForeverCore.exe herunterladen](https://github.com/Battlefeld/ForeverSim/releases/download/forevercore/ForeverCore.exe)**
   (eine Datei, alles enthalten: beide Addons, die Simulation, die Routen). Mehr brauchst du nicht herunterzuladen.
2. WoW vollständig schließen und `ForeverCore.exe` starten. Es öffnet sich das ForeverCore-Fenster.
3. Die gefundene WoW-Installation wählen (WoW: Forever steht oben) und **Installieren** klicken. ForeverCore installiert
   ForeverSimBridge, ForeverCoreBridge und ForeverRoutes, sichert ältere Versionen dieser Addons und legt sich ins
   Startmenü und auf den Desktop. Andere Addons und deine Einstellungen (`WTF`) bleiben unverändert.
4. Ab jetzt: ForeverCore starten, dann WoW im **Fenster- oder Fenster-Vollbildmodus** (die obere linke Ecke muss
   sichtbar sein). Der Punkt am Minimap-Knopf zeigt den Zustand: grün bereit, gelb rechnet, rot keine Verbindung.

Windows zeigt beim ersten Start eventuell „Der Computer wurde durch Windows geschützt“, weil das Programm nicht mit einem
gekauften Zertifikat signiert ist: **Weitere Informationen → Trotzdem ausführen**. Der Quellcode liegt hier, das
Programm wird von GitHub Actions aus genau diesem Code gebaut.

Ausführlich: [Start-Anleitung](ForeverCore/README-DE.md) · [Ingame-Testanleitung](https://github.com/Battlefeld/ForeverRoutes/blob/main/docs/ingame-test.md)

## Wichtige Befehle

| Befehl | Wirkung |
|---|---|
| `/fc` | Übersicht (wie Linksklick auf den Minimap-Knopf) |
| `/fc ping` | Verbindung testen |
| `/fc on` / `/fc off` | Berechnung ein/aus |
| `/fc dungeon` | Drops des Dungeons, in dem du stehst |
| `/fc prefetch an` / `aus` | Vorausberechnung ein/aus |
| `/fc log` | Kopierbares Protokoll |
| `/fus` | ForeverSim-Fenster |
| `/fr` | ForeverRoutes-Fenster |

Alle Befehle: [Funktionsweise, Abschnitt 8](docs/FUNKTIONSWEISE.md#8-befehle).

## Grenzen

Die Rechenwege sind mit Lua- und Go-Tests geprüft, aber noch nicht vollständig im echten Client bestätigt. Was offen
ist, steht in [Grenzen und was nicht bewiesen ist](docs/FUNKTIONSWEISE.md#11-grenzen-und-was-nicht-bewiesen-ist).
Bei schwarzen Bildschirmen zuerst die Grafik-API in WoW auf DirectX 11 stellen
([Abschnitt 6.4](docs/FUNKTIONSWEISE.md#64-betrieb-ohne-bildschirmaufnahme)).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `ForeverCore/` | Das Windows-Programm (Go): Fenster, Installation, Updates, Verbindung zu WoW, Simulationsaufträge; Build-Werkzeuge |
| `ForeverCoreBridge/` | Addon: Transport (Pixelstreifen hin, Antwortslots zurück), Warteschlange, Cache, Auktionshaus, Dungeon-Liste |
| `ForeverSimBridge/` | Addon: liest Charakter, Talente, Zauberbuch; ForeverSim-Fenster; Dungeon-Katalog |
| `_dev/` | Test-Harness, Werkzeuge für Katalog und Grafiken, Entwicklungsdaten |
| `docs/` | [Funktionsweise im Detail](docs/FUNKTIONSWEISE.md), [ursprüngliches Konzept der EXE](docs/konzept-forevercore-windows.md), [Review](docs/review-2026-10-20.md) |

Bauen und testen: Workflows unter `.github/workflows` (`forevercore-offline` für alle Tests, `forevercore-package` baut
die EXE und veröffentlicht sie im [Release „forevercore“](https://github.com/Battlefeld/ForeverSim/releases/tag/forevercore)). Lokal: `cd ForeverCore && go test ./...` und die Lua-Tests unter `ForeverCore/tests`.

## Lizenz

- **Eigener Code und Grafiken:** MIT, siehe [`LICENSE`](LICENSE).
- **Dungeon-Katalog** (aus NorgannonDB) und **Hexenmeister-Begleiterwerte** (aus cmangos classic-db): GPL-3.0, siehe
  [`LICENSES/GPL-3.0.txt`](LICENSES/GPL-3.0.txt).
- **Engine / WoWSims:** MIT, siehe [`ForeverSimBridge/THIRD_PARTY_LICENSES.txt`](ForeverSimBridge/THIRD_PARTY_LICENSES.txt).
- Das mitgelieferte **ForeverRoutes** hat eigene Lizenzen (Code MIT, Routen GPL-3.0, RestedXP-Abschnitte CC BY-NC-SA 4.0).

Alle Quellen, ihre Lizenzen und Hinweise: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Im installierten Programm
liegen die Lizenztexte im Ordner `Lizenzen`.
