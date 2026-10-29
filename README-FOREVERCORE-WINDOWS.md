# ForeverCore 1.0 – Windows-Zentrale, One-EXE-Installation und ForeverSim-Umbau

> **STATUS: KONZEPT / UMBAU-SPEZIFIKATION, NICHT IMPLEMENTIERT.**
>
> Dieses ergänzende README definiert den angestrebten Umbau. Es ersetzt nicht die bestehende README.md, ändert keine Laufzeitfunktionen und behauptet keine abgeschlossene Ingame-Validierung.
> Gegenstück: [ForeverRoutes – Windows-Integration](https://github.com/Battlefeld/ForeverRoutes/blob/main/README-FOREVERCORE-WINDOWS.md).
> **Ziel:** Nutzer lädt **eine** signierte Datei `ForeverCore.exe` herunter, startet sie per Doppelklick und erledigt die gesamte Installation, Einrichtung, Aktualisierung, Simulation und Routenverwaltung grafisch. Kein CMD/PowerShell, keine manuell zu installierende `MythicSim.exe`, `foreverroutes.exe`, `Lua.exe` oder Addon-ZIP.

## 1. Verbindliche Produktaufteilung

| Bestandteil | Verantwortung |
|---|---|
| **ForeverCore.exe (Windows)** | Alle Einstellungen, GUI, Datenquellen, Import/Update, Profil- und Item-Simulationen, Talent-/Rotations-Editor, Routen-Editor, Job-Queue, Installer, Diagnose und Bridge-Host |
| **ForeverCoreBridge (WoW)** | Minimaler Transport, Charakter-/Questzustand und Cache, Zustands-/Versionskontrolle; keine schweren Simulationen |
| **ForeverSimBridge / ForeverSim HUD (WoW)** | Vergleichsprozente, Item-/Loot-/Dungeon-Hinweise, aktuell gültige Rotation/HUD, relevante Live-Ereignisse; kein vollwertiger Simulationseditor |
| **ForeverRoutes HUD (WoW)** | Eigenständige Pfeil-/Quest-/Routenanzeige und kleine Live-Aktionen; Routenplanung erfolgt auf Windows |
| **ForeverRoutes-Engine (Go)** | Routenbaukasten, Timeline, Replays, Datenvalidierung, Export; vom Windows-Core über versionierte API aufgerufen |
| **MythicSim / ForeverSim Engine** | Offline-Kampfrechnungen, Profilserien, Ausrüstungs-/Talent-/Rotationsoptimierung; niemals im WoW-Addon |

**Ein sichtbarer Prozess und ein Startpunkt:** Nur `ForeverCore.exe` wird vom Nutzer gestartet. Bestehende Go-Module bevorzugt als Bibliotheken in den Windows-Host integrieren. Wenn eine Engine technisch als Subprozess nötig bleibt: im einzigen Release-EXE eingebettet, intern versioniert und ohne Konsole in einem privaten App-Verzeichnis entpackt/gestartet; keine zusätzlichen nutzerseitigen Downloads oder CLI-Schritte. „Eine EXE“ bedeutet **ein herunterladbares/gestartetes Produkt**, nicht die unrealistische Zusage, dass WoW-Addons, Daten und Windows-Runtime keine Dateien auf der Festplatte benötigen.

## 2. Ist-Stand und konkrete Umbauorte

- `ForeverCore/main.go`: bisher Kommandozeilen-Startpunkt, `Config` (u. a. `Engine`, `Lua`, `Routes`, `RoutesData`, `AutoSync`), Job-/Antwort-Schema. **Umbau:** wiederverwendbaren Service/Backend-Kern vom CLI-Start entkoppeln; GUI-Lifecycle, Ein-Instanz-Start und ordentliche Shutdown-/Task-Abbruchregeln.
- `ForeverCore/routenext.go`: startet derzeit `foreverroutes.exe next` mit Dateipfaden/Prozessaufruf. **Umbau:** versionierte, in-process Routen-API bevorzugen; bis dahin nur interne, mitgelieferte Sidecar-Engine als Zwischenlösung, keinerlei Pfadsuche/CLI für Endnutzer.
- Existierende `ForeverCore.exe`, `MythicSim.exe`, `Lua.exe`, `ForeverCoreBridge` und `ForeverSimBridge` aus README.md nicht blind neu implementieren: Services, Cache, Transfer und Klassenmodule erhalten und gezielt einkapseln.
- `/fus`-Fenster mit Talent-/Rotations-/Beute-Reitern und den vorhandenen Engine-Aufträgen in **ForeverSim Studio (Windows)** verlagern. Ingame bleiben nur HUD, Tooltips, Dungeon-/Loot-Kurzinfos, Kristall und zwingende Sofortaktionen. Bisherige Favoriten/Presets mit Migrationspfad übernehmen.
- Das aktuelle Transferdesign nutzt Pixelrahmen, DXGI-Desktopaufnahme und LoadOnDemand-Antwortslots (2.048 Slots/Sitzung). **Vor Erweiterung der Übertragungsmengen echte Client-Tests:** Antwortlimits, Race-Conditions, Vollbild-/Mehrmonitorbetrieb, `/reload`, WoW-/Bridge-Version, Kampfzustand und Wiederverbindung.

## 3. Windows-App und Navigation

**Vorgeschlagener Stack:** zuerst Go-basierte Windows-Desktop-Shell mit eingebettetem React/TypeScript-Frontend (z. B. Wails) als Machbarkeits-Prototyp; so bleiben vorhandene Go-Dienste und DXGI-Anbindung wiederverwendbar. Alternative Tauri + eingebetteter Go-Worker erst vergleichen, falls Wails/WebView2/Packaging oder GPU-Capture Einschränkungen zeigen. Desktop-Abhängigkeiten (z. B. WebView2) beim ersten Start erkennen und **grafisch** installieren/anleiten; offlinefähiger Installationspfad ist ausdrücklich zu testen.

Navigationsstruktur:
1. **Dashboard:** Spiel/Bridge verbunden? Game-Build, Core/Sim/Routes-Versionen, Quellrevisionen, letzter validierter Stand, Builds, Installations- und Updatezustand, Warnungen.
2. **ForeverSim Studio:** Klassen-/Rassenprofile, importierte MythicSim- und eigene Datensätze, Talente, Rotationen/APL, Testgegner, Gear, Pre-BiS, Buffs, VZ, Item-/Dungeon-Drops; Einzel- und Stapelberechnung mit nachvollziehbarem Referenzzustand.
3. **ForeverRoutes Studio:** Auto-Builder und mehrspuriger Drag-and-drop-Zeitstrahl des Routes-Repos, Variantenvergleich, XP-/Zeit-/Gold-Bilanz, Export an das HUD.
4. **Datenbankzentrum:** QuestieDB, ForeverDB, WarcraftDB, weitere belegte Quellen, Client-Build-/Hotfix-Differenzen, Rohdaten/Normalisierung/Quellpriorität, Importprotokoll, Validierung, Historie, Rollback.
5. **Addon- & Update-Center:** erkannte WoW-Installationen, Komponentenstände, installierbare Pakete, Updatevorschau, Installieren/Reparieren, Fortschritt und Rücksetzen.
6. **Diagnose:** lesbare Fehler/Logs, Bridge-Verbindungstest, Cache-/Datengeneration, Export eines Datenschutz-geprüften Diagnosepakets.
7. **Einstellungen:** Theme, Layout, HUD-Konfiguration, Updateintervall, Quellenzugang, optionale Profile, WoW-Pfad, Datenschutz.

Alle Aktionen per GUI; keine sichtbare Shell, keine Konsolenlogs als primäre Bedienung. Aufwendige Rechnungen asynchron zum GUI-Thread, mit Fortschritt, Abbrechen, Priorität und deterministischem Ergebnis-Snapshot. Bei einem Engine-Absturz muss GUI/letzter gültiger Datenstand weiter funktionieren.

## 4. Ein-Datei-Auslieferung und automatisches Setup

**Veröffentlichungsartefakt:** genau **eine** Windows-x64-`ForeverCore.exe` pro Version, mit eingebetteter UI, Versionmanifest, Runtime/Engine-Payloads, installierbaren Addons, Lizenztexten und minimaler Start-Datenbasis. Keine separate manuelle ZIP-, Go-, Python-, Lua- oder CMD-Installation. Windows 11 x64 als primäre Zielplattform; Windows 10 nur nach tatsächlicher Kompatibilitätsprüfung zusagen.

**Erststart-Wizard (ohne Terminal):**
1. WoW-Forever-Pfad anhand vorhandener Installationen/Prozess/Launcher-Hinweise **nur lesend** suchen; mehrere Installationen auswählbar. Bei Nichterkennung Windows-Ordnerdialog.
2. Gefundene Installation und AddOn-Ziel `<WoW>\Interface\AddOns` anzeigen, Plausibilität prüfen und **vor Schreibzugriff bestätigen**; geschützte Verzeichnisse: gezielte UAC-Freigabe oder anderes Ziel anbieten, nicht still fehlschlagen.
3. Spielstatus ermitteln. Laufendes WoW niemals als sofort aktualisiert ausgeben; Installationsdateien kontrolliert nach sicherem Schließen erneuern. Änderungen am Addon-Code wirken erst nach dem erforderlichen Neustart/`/reload`; bei unsicherem Zustand Spielneustart verlangen.
4. Betroffene **eigene** Addon-Ordner versioniert sichern, Dateien in Staging-Verzeichnis schreiben, Hash und Manifest prüfen, anschließend atomar bzw. mit Recovery-Journal einspielen. Fremdaddons und `WTF/SavedVariables` nie pauschal löschen oder überschreiben. Nur ausdrücklich verwaltete alte Dateien nach Manifest entfernen.
5. Installieren/prüfen: `ForeverCoreBridge`, `ForeverSimBridge`, `ForeverRoutes`, zugehörige Medien/Datengenerationen und – solange nötig – Antwortslots `FC3_S0001...FC3_S2048`. Letztere **nicht still entfernen**, bevor ein alternativer nachweislich funktionierender Rückkanal existiert.
6. App-Verknüpfung, optional Autostart/Start mit WoW, Startstatus/Verbindungstest; WoW-Start optional per GUI. Offline starten und mit letzter geprüfter Generation spielbar bleiben.
7. Update/Reparieren/Deinstallieren unterstützen dieselbe Backup-/Wiederherstellungslogik. „Ein Klick Reparieren“ ohne manuelles Kopieren.

Für echte **Ein-Datei-Auslieferung** muss der Release-Build Nutzdaten und benötigte Binärteile einbetten (Go `embed`/Ressourcen). Dynamische Quellen-/Cache-Dateien dürfen nach dem Start unter `%LOCALAPPDATA%\ForeverCore` liegen. Benutzerbezogene Profile nicht neben der EXE im geschützten Installationsordner schreiben. Optionales Startmenü/Uninstall über grafische App-Funktion – keine separate EXE für Endnutzer erforderlich.

## 5. ForeverSim Studio: was aus dem Addon nach Windows wandert

- **Imports:** MythicSim-Manifest/Engine-Revisionsdaten und eigene ForeverSim-Imports nebeneinander einlesen; Schema prüfen, Quelle/Datum/Berechtigung dokumentieren, Konflikte anzeigen, nur bestätigte Daten freigeben. Keine imaginären Clientdaten auslesen.
- **Szenarien:** Klassen, Rassen, Level, Gear, Talente, Rotation/APL, Gegner, Buffs, Zauberstab, VZ und Consumables; gespeicherte Presets, Kopieren, Import/Export und Massenvergleich.
- **Rechnungen:** DPS/Rotation/Stat-/Itemvergleiche, Pre-BiS, Buff-/Enchant-/Dungeon-Szenarien auf Windows; Baseline, Seed, Modellrevision und ausgeschlossene Effekte je Ergebnis sichtbar.
- **Vergleichslogik:** Prozentwert im WoW-Tooltip immer gegen passenden Live-Stand und kompatible Revision; keine Addition unabhängiger DPS-Prozentgewinne; nicht modellierte Effekte als unbekannt anzeigen.
- **Routenkopplung:** Forge `KillProfile`/veränderliche Charakter-Snapshots mit Gear-/Wand-/Talentwechsel ab konkretem Routenzeitpunkt. Jede Änderung invalidiert nur betroffene Segmentergebnisse; Freeze/Versionierung je Simulationslauf.
- **HUD:** nur aktuelle Rota/Procs (falls API tatsächlich bestätigt), minimale Item-/Loot- und Upgradeanzeige, Kristall sowie Status/Fehler. Kein Ingame-Tab für lange Modellrechnungen nötig. HUD-Fallback bei getrenntem Core: letzter kompatibler Cache, sichtbar als „offline/veraltet“.
- **Spielschutz:** keine Simulation im Kampf, keine geschützten Aktionen, keine verdeckte Client-Manipulation; Live-Eingaben nur über zulässige Addon-Ereignisse/API.

## 6. Gemeinsame ForeverCore-/ForeverRoutes-Schnittstelle

Eine gemeinsame versionierte Spezifikation mit JSON-Schemas oder generierten Go-/TS-Typen, z. B. `forevercore.contract.v1`:
- `AppStatus`, `GameInstall`, `AddonManifest`, `DataRevision`, `SimulationSnapshot`, `CharacterSnapshot`
- `SimScenario`, `SimResult`, `KillProfile`, `PlanSpec`, `RouteEvent`, `RouteResult`, `HUDSnapshot`
- Operationen: `core.status`, `core.install`, `core.updateCheck`, `sim.import`, `sim.evaluate`, `sim.compare`, `sim.killProfile`, `routes.generate`, `routes.replay`, `routes.optimize`, `routes.export`, `routes.next`.

**Eigentümer:** ForeverSim/ForeverCore besitzt Windows-Host, GUI, Installer, Bridge und Sim-Service; ForeverRoutes besitzt Routen-Engine, Routenmodelle und Routes-HUD. An Repo-Grenzen keine zyklischen Bibliotheksabhängigkeiten: gemeinsame unveränderliche Datenverträge und gepinnte Artefaktversionen. Jede Antwort enthält `schemaVersion`, `gameBuild`, `coreVersion`, `engineRevision`, `datasetHash`, `characterRevision` soweit relevant. Alte Ergebnisse bei Mismatch nicht als frisch markieren.

**Datenschutz & Update:** keine automatische Preisgabe von Charakterdaten. Remote-Datenabrufe nur aus ausdrücklich erlaubten Quellen, mit Auth-/Rate-Limits, Quellbelegen und Lizenzprüfung. Hotfix/Blue-Post-Signale stoßen nur **Prüfung** an; ein Update gilt erst nach erfolgreichem Import, Diff, Test und atomarer Veröffentlichung als „aktuell“. Fehlgeschlagenes Update lässt die letzte validierte Generation stehen. Keine automatische Aktivierung der bislang gesperrten Combat-Feedback-Schnittstelle (siehe ForeverRoutes `docs/foreversim-feedback.md`).

## 7. Meilensteine – in dieser Reihenfolge umsetzen

- **M0 – Architektur-Audit:** Branch/Build/Assets/Go-Versionen, MythicSim-Lizenz, Ressourcen und vorhandenen Installer/Bridge erfassen; unveränderbare Vertragsfixtures festlegen.
- **M1 – GUI-Shell/Start:** eine Windows-EXE mit Dashboard, Einstellungen, Logging und bestehenden read-only Status-Services, ohne CMD; vorhandener Bridge-Betrieb weiterhin möglich.
- **M2 – Installer:** Erststart-Erkennung, Mehrfachinstallationen, Sicherung, überprüfbarer Addon-Install, Reinstall, Offline-Start, Rollback und Update-GUI.
- **M3 – Sim Studio:** Ingame-Editoren nach Windows überführen, Engine-Adapter, reproduzierbare Imports/Presets und Ergebnis-Caches. HUD-Layouts/Tooltip-Verträge beibehalten.
- **M4 – Routes Studio:** integrierte Go-Engine/API, Auto-Bausteine, Timeline und Export; separate Routen-CLI in produktivem GUI-Betrieb entbehrlich (für Entwickler optional weiter möglich).
- **M5 – Bridge/Live:** Host-Handshake, Version-/Sessionprüfung, Paketgrößen, echte Ingame-Abnahme, Disconnect-/Reload-Fallback, HUD-Snapshot-Sync. Bestehenden Pixel-/Slotkanal bis zu einem belegten Ersatz behalten.
- **M6 – Release:** gepinnte Cross-Repo-Builds, Reproduzierbarkeit, Signatur/Hash, vollständige Lizenzen, GitHub Release mit **nur einem benötigten Download** und geprüfter frischer Installation.

## 8. Tests / Definition of Done (nicht als erledigt markieren, bevor gemessen)

- [ ] Frischer Windows-Rechner: eine EXE downloaden, doppelklicken, korrektes deutsches GUI, **keine Konsole**, keine manuelle Laufzeit/Addon-Datei.
- [ ] WoW-Forever-Pfad automatisch gefunden **oder** komfortabler Ordnerdialog; mehrere Installationen, Pfade mit Leerzeichen/Umlauten, Standardbenutzer getestet.
- [ ] Beide HUD-Addons plus CoreBridge und nötige Antwortmodule automatisch vollständig installiert, im Addon-Menü erkannt; bestehende `WTF`-Daten unangetastet.
- [ ] Sicherer Update-, Reparatur-, Rollback- und Offline-Pfad; kein inkonsistenter halbinstallierter Zustand bei Abbruch/Stromausfall.
- [ ] Simulationsimports, Gear-/DPS-/Rotation-/Buff-Vergleich funktionieren komplett in Windows; gleiche Engine/Gear/Seed -> reproduzierbares Ergebnis.
- [ ] Routes-Autobuilder und manueller Editor verwenden dieselbe Daten- und Kampfbasis; veröffentlichte Route im Spiel nutzbar.
- [ ] Bridge-Verbindung, Live-Zustand, Tooltip/HUD, `/reload`, Gameplay/Combat, Slotlimit und Mehrmonitor/DXGI auf echtem Client geprüft; keine unzulässigen Client-Eingriffe.
- [ ] Dokumentierte Migrations-/Rollbackstrategie für bisherige `/fus`-Einstellungen, `/fc`-Kommandos und SavedVariables.
- [ ] Lizenz-/Quellenprüfung sämtlicher eingebetteter MythicSim-/Guide-/Questdaten und externen Assets abgeschlossen.
- [ ] Windows Release-Pipeline erstellt die eine EXE aus **zueinander kompatiblen, festgelegten** ForeverSim-/ForeverRoutes-Revisionen und testet den Erststart.

## 9. Nicht-Ziele und wichtige Klarstellungen

Kein Browser-Zwang, kein Terminal für Nutzer, keine separaten manuell startbaren Tools, keine Ingame-Vollsimulation, keine ungeprüften „immer aktuelle“ Daten, kein stilles Umschreiben fremder Addons oder geschützter WoW-Daten. Die installierten WoW-Addonordner sind technisch **notwendig**; „nur eine Datei“ bezeichnet den einen Nutzer-Download/Startpunkt. Keine Garantie für Hot-Swap während laufendem WoW und keine Aussage über Leistung/Sicherheit, ehe echte Tests bestanden wurden.

**Hinweis für Implementierer:** Dieses README ist ein Plan. Der vorhandene Code bleibt unverändert, bis die Umsetzung gesondert beauftragt wird.
