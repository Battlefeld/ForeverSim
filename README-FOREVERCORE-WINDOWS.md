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

**Ein sichtbarer Startpunkt (interne Prozesse sind bei Bedarf erlaubt):** Nur `ForeverCore.exe` wird vom Nutzer gestartet. Bestehende Go-Module bevorzugt als Bibliotheken in den Windows-Host integrieren. Wenn eine Engine technisch als Subprozess nötig bleibt: im einzigen Release-EXE eingebettet, intern versioniert und ohne Konsole in einem privaten App-Verzeichnis entpackt/gestartet; keine zusätzlichen nutzerseitigen Downloads oder CLI-Schritte. „Eine EXE“ bedeutet **ein herunterladbares/gestartetes Produkt**, nicht die unrealistische Zusage, dass WoW-Addons, Daten und Windows-Runtime keine Dateien auf der Festplatte benötigen.

## 2. Ist-Stand und konkrete Umbauorte

- `ForeverCore/main.go`: bisher Kommandozeilen-Startpunkt, `Config` (u. a. `Engine`, `Lua`, `Routes`, `RoutesData`, `AutoSync`), Job-/Antwort-Schema. **Umbau:** wiederverwendbaren Service/Backend-Kern vom CLI-Start entkoppeln; GUI-Lifecycle, Ein-Instanz-Start und ordentliche Shutdown-/Task-Abbruchregeln.
- `ForeverCore/routenext.go`: startet derzeit `foreverroutes.exe next` mit Dateipfaden/Prozessaufruf. **Umbau:** versionierte, in-process Routen-API bevorzugen; bis dahin nur interne, mitgelieferte Sidecar-Engine als Zwischenlösung, keinerlei Pfadsuche/CLI für Endnutzer.
- Existierende `ForeverCore.exe`, `MythicSim.exe`, `Lua.exe`, `ForeverCoreBridge` und `ForeverSimBridge` aus README.md nicht blind neu implementieren: Services, Cache, Transfer und Klassenmodule erhalten und gezielt einkapseln.
- `/fus`-Fenster mit Talent-/Rotations-/Beute-Reitern und den vorhandenen Engine-Aufträgen in **ForeverSim Studio (Windows)** verlagern. Ingame bleiben nur HUD, Tooltips, Dungeon-/Loot-Kurzinfos, Kristall und zwingende Sofortaktionen. Bisherige Favoriten/Presets mit Migrationspfad übernehmen.
- Das aktuelle Transferdesign nutzt Pixelrahmen, DXGI-Desktopaufnahme und LoadOnDemand-Antwortslots (2.048 Slots/Sitzung). **Vor Erweiterung der Übertragungsmengen echte Client-Tests:** Antwortlimits, Race-Conditions, Vollbild-/Mehrmonitorbetrieb, `/reload`, WoW-/Bridge-Version, Kampfzustand und Wiederverbindung.

## 3. Windows-App und Navigation

**Vorgeschlagener Stack (noch keine endgültige Technologieentscheidung):** zuerst Go-basierte Windows-Desktop-Shell mit eingebettetem React/TypeScript-Frontend (z. B. Wails) als Machbarkeits-Prototyp; so bleiben vorhandene Go-Dienste und DXGI-Anbindung wiederverwendbar. Alternative Tauri + eingebetteter Go-Worker erst vergleichen, falls Wails/WebView2/Packaging oder GPU-Capture Einschränkungen zeigen. Desktop-Abhängigkeiten (z. B. WebView2) beim ersten Start erkennen und **grafisch** installieren/anleiten; offlinefähiger Installationspfad ist ausdrücklich zu testen.

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

**Hinweis für Implementierer:** Dieses README ist ein Plan. Der vorhandene Code bleibt unverändert, bis die Umsetzung gesondert beauftragt wird. Die nachfolgenden Abschnitte 10–19 präzisieren den verbindlichen Migrations-, Integrations- und Prüfvertrag.

---

## 10. Verifizierte Altlasten / exakte Migrationsaufgaben

Dieser Abschnitt basiert auf konkreten Dateien aus dem `main`-Branch, nicht auf der Behauptung, dass die Zielarchitektur schon existiert.

| Heute im Code | Korrekte Zielmaßnahme | Ablösebedingung |
|---|---|---|
| `ForeverCore/setup/installer.go.txt` erzeugt `ForeverCore_AllesInEinem_Setup.exe`, entpackt eine ZIP-Datei auf den Desktop, fragt den Addon-Pfad via `stdin` ab und startet `powershell.exe` mit `Install.ps1` | **Keinen zweiten Console-/PowerShell-Installer für Endnutzer** ausliefern. GUI-Erststart/Updater als interne Services der tatsächlich heruntergeladenen `ForeverCore.exe` implementieren | Windows-Erstinstallation, Reparatur und Wiederherstellung vollständig GUI-getestet |
| `ForeverCore/Install.ps1` installiert derzeit nur `ForeverCoreBridge` und `ForeverSimBridge` und legt 2.048 Antwortslots an | Installer muss drei aktuelle Module (CoreBridge, SimBridge, Routes), kompatible Daten/Antwortslots installieren und nur ihre *verwalteten* Dateien anfassen | TOC-/Addon-Verzeichnis- und Ingame-Tests mit frischer sowie alter Installation |
| `ForeverCore/package.py` baut eine ZIP mit `ForeverCore.exe`, `MythicSim.exe`, `Lua.exe`, Entwickler-Source/Runtime und Skripten | Release-Bundle manifestbasiert trennen: nur nutzerrelevante, eingebettete Runtime/Engine-/Addon-Assets in eine EXE; Entwicklungsquellen und CI-Tools nicht in den Endnutzer-Payload | Extraktion nach AppData, Offline-Verifikation, Hash- und Lizenztests |
| `.github/workflows/forevercore-package.yml` erstellt derzeit ZIP und zusätzliche Setup-EXE unter Ubuntu mit `CGO_ENABLED=0` | Windows-Releasejob mit geeignetem Toolchain-/GUI-Framework-Build, reproduzierbaren Inputs, Packaging- und UI-Starttests einführen; das bisherige Testpaket nicht als fertiges 1.0 ausgeben | Ein validierter Endnutzer-Download und dokumentiertes Release-Manifest |
| `ForeverCore/main.go` enthält CLI-Service und `routenext.go` startet den externen Planer | GUI-Host/Services von `main` und `os/exec` entkoppeln, langfristig in-process Go-Routenbibliothek, CLI für Entwickler erhalten | Contract- und Regressionstests identischer Ergebnisse |
| `ForeverCore/routesupdate.go` lädt bereits manifest-/SHA-geprüfte ForeverRoutes-Pakete und tauscht Verzeichnisse | Den Updater wiederverwenden/vereinheitlichen; **kein** blindes „latest“ unabhängig vom gepinnten ForeverSim-Build; mit Paket-Snapshot, Test, Rollback und installer-gesteuerter Aktivierung | Abwärts-/Vorwärts-Kompatibilitätsmatrix, Unterbrechungstests |
| `ForeverCore/README-DE.md` dokumentiert Token-Umgebungsvariablen für private Repositories und lokale Client-/Hotfix-Prüfungen | UI-Anmelde-/Zugriffsfluss ergänzen, Cache-Status in Dashboard abbilden; weder Token-Umgebungsvariable noch Konsolen-Befehl für normale Benutzer verlangen | Private-Repo- und Ohne-Zugang-Szenarien getestet |
| Im ForeverSim-Repo existiert noch ein eigener Ordner `ForeverRoutes/` | **Veraltete Kopie niemals als aktuelle Quelle paketieren**; aktuelles HUD/Export nur aus `Battlefeld/ForeverRoutes` und dessen gepinnter, validierter Revision | CI verhindert, dass der alte Ordner in Endnutzer-Addons gelangt |

**Wichtige Kompatibilitätsentscheidung:** Das bereits existierende Setup-`EXE` und die neue Desktop-`ForeverCore.exe` sind **nicht** gleichzusetzen. In 1.0 soll genau die heruntergeladene `ForeverCore.exe` selbst First-Run-Installation, Launcher, GUI und Updates übernehmen. Bestehende Skripte bleiben höchstens intern als Legacy-/Entwicklermaterial vorhanden, nicht als stiller PowerShell-Ausweichpfad.

## 11. Präziser GUI-/Packaging-Entscheidungspunkt

Vor Implementierung einen kleinen technischen Proof of Concept für mindestens zwei Ansätze erstellen und dokumentiert auswählen:

- **Go + Wails/Windows-WebView:** einfacher Zugriff auf vorhandene Go-Services, React/TypeScript-UI; tatsächliche WebView2-Verfügbarkeit, Windows-Version, CGO-/Compilerbedarf, UAC, DXGI und Installer-/Signatur-Kompatibilität prüfen.
- **Native Windows UI oder alternative Shell:** nur wählen, wenn Ein-Datei-Auslieferung, sichere Bridge-Ausführung und Offline-Setup dadurch nachweislich zuverlässiger werden; bestehende Go-Engine nicht unnötig portieren.

**Verbindliche Gates:** Start ohne Konsole; keine unbekannte Browser-/WebView-/VC++-Abhängigkeit ohne grafisch behandelbaren Installationsweg; keine Entwicklungs-Toolchain auf Nutzer-PC; 64-Bit-Windows; DPI-Scaling 100–200 %, mehrere Monitore, Windows-Benutzerkonten ohne Adminrechte und Nicht-ASCII-Pfade. WebView2 darf als Windows-Komponente vorausgesetzt **nur wenn** auf den unterstützten Zielsystemen wirklich vorhanden/getestet; sonst die Benutzeranforderung „ein Download, keine weiteren manuellen Schritte“ durch mitgelieferte Runtime oder integrierten GUI-Installationsweg erfüllen. Signatur ist Release-Gate, kein bestehender Status.

## 12. GUI-Erststart, Wartung und Deinstallation – exakter Ablauf

**First Run:**
1. Integrierte Ressourcendateien/Manifest/Signatur auf Integrität prüfen. Falls Windows-Laufzeit fehlt, klarer grafischer Dialog; bei unbeaufsichtigtem Abbruch keine halbe Installation hinterlassen.
2. Scan nur auf plausible **Forever**-Installationen (nicht automatisch Retail/Classic als korrekt markieren): typische WoW-Ordner und vorhandene Konfigurationsorte, laufende Prozesse, gültiger `Interface/AddOns`-Unterordner, Spielbuild/TOC; unklare Treffer als Auswahl anbieten.
3. Pfad und geplante Module zeigen: `ForeverCoreBridge`, `ForeverSimBridge`, `ForeverRoutes`, Antwortslots solange technisch nötig. Benutzer bestätigt Schreibziel; eigene WoW-Dateien nicht ohne Einverständnis ändern.
4. Wenn WoW aktiv ist: zunächst nicht in die laufende Addon-Installation schreiben; auf sicheren Zeitpunkt warten oder bewusst für nächsten Start vormerken. Niemals „aktiv“ melden, solange kein wirklicher Reload/Neustart erfolgt ist.
5. Hash-verifizierte Pakete in staging-Verzeichnis **auf demselben Volume** vorbereiten. Sichere Pfadnormalisierung: keine `..`, Symlinks/Reparse-Point-Ausbrüche, reservierten Gerätepfade, doppelten/uneindeutigen Dateinamen oder ZIP-Bombs akzeptieren; Datei-/Entpackgrößen begrenzen.
6. Existierende *verwaltete* Addonordner und ihre Manifestversion in Backup/Journal aufnehmen, atomar oder per rücknehmbarer Sequenz ersetzen. `WTF` sowie fremde Addons nicht löschen; manuell veränderte eigene Dateien erst nach Konfliktanzeige überschreiben.
7. Manifest/TOC/API-/WoW-Build erneut prüfen; erfolgreiche Installation und „Neustart erforderlich“ im Dashboard anzeigen.
8. Ein-Klick-WoW-Start optional, aber nicht still. Verbindungsdiagnose erst nach echter WoW-/Bridge-Antwort als „verbunden“ markieren.

**Migrationsregel:** Legacy-`config.json`, alte `/fus`-Presets, HUD-Skalierung, Positionen, Caches, Charakterpräferenzen und Installationspfad nur per versioniertem Migrator übernehmen; vorher Backup; unbekannte alte Versionen mit hilfreicher Fehlermeldung nicht blind konvertieren. Veraltete `ForeverRoutes/`-Kopie aus ForeverSim nie über die echte Route-Version kopieren.

**Reparatur:** fehlende/mismatched Dateien neu herstellen; eigene Nutzerdaten respektieren. **Rollback:** letzte komplette, konsistente Generation aus Journal wiederherstellen. **Deinstallation:** UI-Auswahl „Nur App“, „Auch unsere Addons“, „Auch eigene Caches/Backups“; alle gefährlicheren Optionen einzeln bestätigen und SavedVariables standardmäßig behalten.

**Self-Update:** laufende EXE unter Windows nicht blind überschreiben. Validiertes neues Release sicher herunterladen/stagen, über definierte Start-/Exit-Handoff-Strategie aktivieren, Rollback-Punkt behalten. Falls für ein atomisches Update intern ein kurzlebiger Hilfsprozess gebraucht wird: er ist mitgeliefert, ohne Konsole, wird ausschließlich vom GUI verwaltet und widerspricht nicht dem Ein-Download-Ziel. Signatur **und** gepinnte SHA/Manifestwerte validieren; Hash allein beweist nicht die Vertrauenswürdigkeit eines Manifests.

## 13. Private GitHub-Repositories: Anmeldung ohne CMD

Aktuell beschreibt `ForeverCore/README-DE.md` die Umgebungsvariablen `FOREVER_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`. Diese dürfen Entwickler weiterhin nutzen, sind aber **kein Endnutzer-Setup**.

Verbindlicher UI-Flow für nicht öffentlich zugängliche Updates:
- Im Update-Center „Mit GitHub verbinden“: nur offizieller, legitim registrierter Browser-/Geräteauthentifizierungsfluss **sofern GitHub-App/OAuth-Konfiguration dies erlaubt**, sonst einmaliges **Fine-grained-Token** über ein sicheres Passwort-Eingabefeld als ausgewiesener Fallback. Keine vorgetäuschte automatische Anmeldung.
- Kleinste Rechte, vorzugsweise **Contents: read** für genau die beiden notwendigen Repositories. Private Repo-Zugriffe funktionieren nur, wenn das verbundene Konto tatsächlich berechtigt ist.
- Tokens niemals in EXE, GitHub-Logs, Query-Strings oder `config.json` einbetten. Speicherung ausschließlich verschlüsselt benutzergebunden, z. B. Windows Credential Manager/DPAPI; im Speicher begrenzen, Logout/Widerruf/Löschung über UI.
- Kein Token an fremde Domains, keine Account-/Charakter-/SavedVariables-Uploads. HTTP 401/403, fehlende Freigabe, Ratelimits, Offlinebetrieb und abgelaufene Berechtigungen **unterschiedlich** anzeigen.
- Bessere Alternative für ein öffentlich verteiltes Nutzerprodukt: signierte **separat freigegebene** Release-Artefakte mit geklärter Lizenz, sodass Endnutzer keinen Repo-Zugriff benötigen. „Privates GitHub-Repo“ niemals durch Einbetten eines Entwickler-Tokens umgehen.
- Ohne GitHub-Zugriff bleibt die ausgelieferte geprüfte Offline-Datenbasis nutzbar, aber der Status lautet „Update nicht prüfbar“, **nicht** „aktuell“.

## 14. Daten-/Patch-Status mit überprüfbarer Bedeutung

Dashboard führt **getrennte** Zeilen für: Windows-App-Version, ForeverCoreBridge-Protokoll, ForeverSim-Engine/Manifest, ForeverRoutes-Engine/Datensatz/HUD, Client-Spielbuild, Quellenrevisionen, lokalen Hotfix-/DB2-Abgleich, letzte erfolgreiche Datenprüfung, letzte erfolglose Prüfung und Hintergrundjobs.

Statuslogik:
- `CURRENT_VERIFIED`: Quellenstand, Spielbuild/Fingerprint, Engine-/Daten-Revisionen und notwendige Tests nachvollziehbar abgeglichen; geprüfter Zeitpunkt sichtbar.
- `UPDATE_AVAILABLE`: neue **validierte, kompatible** Generation verfügbar, noch nicht aktiviert.
- `CHECK_REQUIRED` / `CHECKING`: Ereignis/Blue Post/Hotfix-Indikator erkannt, noch keine inhaltliche Auswertung; keine Aktualitätsbehauptung.
- `UNKNOWN` / `ACCESS_REQUIRED`: Quelle oder API 403, Timeout, fehlender Token, fehlerhafte Beobachtungen; letzter gültiger Stand aktiv, Warnung sichtbar.
- `INVALID`: Tests/Schema/Hashes widersprechen einander, Generation nicht aktivieren; Grund nennen.
- `RESTART_REQUIRED`: Dateien installiert, WoW hat neue Lua-/TOC-Dateien noch nicht geladen.

Blizzard-/Clientdaten werden nur über erlaubte Quellen/öffentliche API oder zulässige Addon-/Dateibeobachtung verwendet; gespeicherte Client-Questtitel sind **keine** validierten Quest-XP-/Voraussetzungswerte und archivierte Hotfix-Caches allein **kein** Nachweis geänderter Kampfformeln. Gerade die `clientdata.go`-Logik und `Data/ClientData`-Bestände müssen bei der Migration erhalten bleiben. **Keine stündliche Vollabfrage**: täglicher validierter Abruf plus einmaliger ereignisgetriggerter Prüfauftrag mit Deduplizierung/Rate-Limits.

Jede Datenänderung: Quelle -> Roh-Snapshot -> Schema-/Plausibilitätsprüfung -> feldweise Provenienz/Diff -> Regression/Simulationsreplay -> signierte/gehashte Veröffentlichung -> atomare Aktivierung. Unbekannte Daten bleiben `unknown`, keine erfundenen XP/Stat-/Itemwerte. Nur kompatible Komponenten dürfen „synchron“ heißen.

## 15. ForeverCoreBridge: Kontrollfluss, Settings und tatsächliche Grenzen

**Transportmatrix (zu entwickeln und zu testen):**

| Nutzdaten | Richtung | Weg | Zeitpunkt/Limit |
|---|---|---|---|
| Charakter-/Quest-/Gear-Snapshot | WoW -> Host | vorhandene Pixelrahmen / zulässiger SavedVariables-Fallback | gepuffert, dedupliziert, keine Übertragung im geschützten Kampfkontext |
| Item-/Rotations-/Nächster-Routenschritt | Host -> WoW | vorhandene verifizierte Antwortslots/kompakte Cache-Antwort | nur akzeptierte Session/Sequence/Revision/Schema |
| Große Route/Daten-/HUD-Konfig | Host -> Addon-Datei | gepacktes Addon-Lua mit Manifest, sicher installiert | wirksam **erst nach nötigem Reload/Neustart** |
| Kleine UI-Änderung im Spiel | Host -> HUD | **nur nach PoC** über bestehenden Rückkanal; sonst beim nächsten Reload | kein „Live-Sync“ versprechen, solange nicht belegt |
| Messwerte/Beobachtungen | WoW -> Host | erlaubte Addon-API, begrenzter Pixelauftrag oder geschriebene SavedVariables | ohne heimliche Kampfdaten- oder Memory-Hooks |

**Technische Muss-Kriterien:**
1. Protocol-/Capability-Handshake mit `gameBuild`, `sessionId`, `schema`, `addonVersion`, `coreVersion`, `simRevision`, `routeRevision`, `datasetHash`; alte/incompatible/duplizierte Antworten ablehnen.
2. Bridge-Status `disconnected`, `connecting`, `connected`, `degraded`, `restart-required`; Kristall blau nur bei **echter Antwort dieser Sitzung**.
3. Die dokumentierten **2.048 LoadOnDemand-Slots pro Sitzung** sind ein hartes Kapazitätsrisiko. Budgetierung, Bündelung, Wiederholungslogik, Neustartwarnung und optionaler späterer Rückkanal-Prototyp; keinesfalls beliebig große Settings-/Routenlisten durch Slots senden.
4. Hohe Frequenz bei Quest-/Gear-Events entprellen, Jobs priorisieren (Tooltip/aktueller HUD-Schritt > Offline-Massenoptimierung), stale Resultate verwerfen, idempotente Queue mit Cancel/Timeout.
5. Windows-Host darf minimiert im Tray laufen; UI schließen != automatisch laufende Spiel-Bridge beenden, Nutzeroption. Ein Prozess/eine Sitzung pro gewähltem Client als Standard; mehrere WoW-Fenster nur mit sauberer Zuordnung.
6. WoW im Kampf/geschützte Aktionen: niemals unzulässige Steuerung, keine Injection, kein fremder Speicherzugriff, keine Simulation im Addon.
7. Offline ohne Host: letzter passender Cache und installierte Route; „offline/veraltet“ anzeigen. Wenn Versionen nicht passen, keinen falschen DPS-Gewinn anzeigen.
8. `/reload`, Logout, Client-Neustart, WoW-Patch, Displaywechsel/HDR/DXGI-Reset und Timeout in echter Spielumgebung testen; das vorhandene Pixel/Slot-Protokoll bis zu **belegter** Ersatzlösung beibehalten.

**Settings-Verantwortung:** Windows-UI ist der Editor/Source-of-Truth für Sim- und Routen-Presets; nur spielrelevante HUD-Einstellungen zur passenden Addon-Konfiguration synchronisieren. Ingame-Sofortaktionen (z. B. Skip/Zurück, HUD-Position) müssen lokal weiter funktionieren und konfliktfrei später synchronisiert werden. Konfliktregel: Charakter-/Installations-ID + Version + Zeitstempel, niemals eine zufällige globale „letzter Schreiber gewinnt“-Überschreibung.

## 16. Verifizierbare Cross-Repo-Release-Pipeline

- **Owner:** `Battlefeld/ForeverSim` bündelt finalen Endnutzer-Download; `Battlefeld/ForeverRoutes` liefert versionierte Go-Engine, Datensatz, Routen-/HUD-Export und Lizenzen. Der alte `Battlefeld/ForeverSim/ForeverRoutes/`-Ordner ist keine Releasequelle.
- **Revisionsmatrix:** `forevercore_version`, `foreversim_commit`, `foreverroutes_commit`, `mythicsim_engine_identity`, `route_dataset_sha256`, `game_build_compatibility`, `bridge_protocol_version`, `addon_toc_interface`, `manifest_schema`, `asset_hashes`, `license_inventory`. Nur eine vollständig geprüfte Kombination wird als 1.0 veröffentlicht.
- **Build:** expliziter Windows-Buildjob (bei GUI-Toolchain nicht nur Ubuntu-Crosscompile), Tests von Go-Core, MythicSim-Integration, Routes-Engine und Lua-HUD sowie E2E GUI-/Install-/Rollback-Tests in Windows. JSON-/Asset-/Signature-/Version-Konsistenz prüfen; unabhängig verifizieren, dass EXE und inneres Bundle dieselbe Engine-Revision nutzen.
- **Sicherheit:** keine GitHub-Token/CI-Secrets im Bundle, attestierte/vertrauenswürdige Manifestquelle, SHA-256 je Datei und signiertes Endprodukt; alle Dritt-/Addon-/Guide-Lizenzen prüfen (GPL-/CC-BY-NC-SA-Kombination insbesondere vor Distribution). Nicht freigegebene Daten nicht in öffentliche Releases einpacken.
- **Updates:** kompatible Release-Paare statt zweier unkontrollierter `latest`; atomare Generation mit vollständigem Rollback. Unabhängige Datensatz-Updates nur innerhalb explizit unterstützter Versionsbereiche.
- **Outputs:** ein Endnutzerartefakt namens `ForeverCore.exe`, optional nur für Entwickler separate Debugsymbole/Tests/Artefakte. GitHub Actions niemals als grün markieren, wenn Integration, Signatur oder Windows-Erststart nicht nachgewiesen ist.

## 17. Zustands- und Fehlerfälle, die jedes UI beschreiben muss

| Fall | Erwartete sichtbare Reaktion |
|---|---|
| WoW nicht gefunden | Verzeichnis auswählen, nichts installieren |
| Mehrere Forever-Installationen | installierte Clients auswählbar, je Client eigener Status |
| Spiel/Host während Update aktiv | sicheres Staging, angekündigter Reload/Neustart oder Abbruch |
| Private GitHub-Quelle 403 | „Berechtigung fehlt“, Offline-Generation bleibt aktiv |
| Quelle nicht erreichbar / Blue-Post nicht ausgewertet | „ungeprüft“, keine fälschliche Aktualitätsanzeige |
| Bridge verliert Fenster / DXGI-Reset | Verbindung neu aufbauen, Caches gültig lassen, Warnung |
| Antwortslots ausgeschöpft | verständliche Info, sichere Wiederherstellung durch Spiel-Reload statt Endlosschleife |
| Falsche Engine-/Dataset-Revision | alten kompatiblen Stand nutzen oder Vergleich deaktivieren |
| Daten- oder Installationspaket beschädigt | Hash-Test verweigert Aktivierung, Rollback |
| Simulation hängt / Nutzer bricht ab | Job abbrechen, letztes Ergebnis behalten, GUI bedienbar |
| Unbekannte Item-/Questwerte | sichtbar „unbekannt“ und Herkunft, nie ausgedachte Zahlen |

## 18. Ergänzende DoD-Tests (zu Abschnitt 8)

- [ ] Endnutzer startet **ausschließlich** die heruntergeladene `ForeverCore.exe` und wird nie zur Konsole/PowerShell/Token-Umgebungsvariable weitergeleitet.
- [ ] Der bestehende `setup/installer.go.txt`-/`Install.ps1`-Pfad ist für das **neue** Endnutzerprodukt wirklich abgelöst, nicht nur hinter einer hübschen Startoberfläche versteckt.
- [ ] Desktop-/`_retail_`-Fehlzuordnung ausgeschlossen; aktuelle Forever-Installation über Build und TOC geprüft.
- [ ] Aktuelles ForeverRoutes-HUD ausschließlich aus gepinntem Routes-Release, nicht aus altem ForeverSim-Unterordner.
- [ ] Private-Repo-Zugang über sichere GUI, Tokenwiderruf, Offline, 401/403/429 und Benutzer ohne Rechte getestet.
- [ ] Bridge-Limits (2.048), großer Route-Export, HUD-Settings, Cache-Persistenz und echte Client-Reloads getestet.
- [ ] Datenstatus „aktuell“ nur bei nachprüfbarem Hotfix-/Spielbuild-/Engine-/Dataset-Abgleich; 403/fremder Build = Warnung.
- [ ] Installation/Reparatur/Uninstall/Rollback mit Mehrfachclients, Altversion, Unterbrechung und Nicht-Admin-Nutzer geprüft.
- [ ] Update einer **laufenden** ForeverCore.exe über geprüften Handoff ohne beschädigte Installation; keine Secrets im Release.
- [ ] CI liefert nur kompatibles, lizenziertes, durch Windows-Tests geprüftes One-Download-Release.

## 19. Abschlussregeln / kein automatisches „fertig“

Umsetzung erst dann „vollständig“, wenn ein **frischer Windows-PC** ohne Entwicklerwerkzeuge das Release mit einem Download installieren/starten kann, beide aktuellen WoW-Addons im richtigen Client auftauchen, der Live-Handshake funktioniert und Auto-Builder/Timeline/Sim Studio **ohne CMD** funktionieren. Jede noch offene Client-/Patch-/Lizenzprüfung bleibt explizit als Blocker markiert; Dokumentation allein erfüllt keine dieser Checkboxen.

**Dieses Dokument ist ausschließlich ein Umsetzungsplan.**
