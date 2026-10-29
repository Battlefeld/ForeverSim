# ForeverCore – Start

ForeverCore berechnet auf dem PC mit MythicSim, wie viel Schaden dir ein Item bringt, und zeigt das Ergebnis im
Spiel an. Zwei Addons gehören dazu: **ForeverSimBridge** (liest Charakter und Items) und **ForeverCoreBridge**
(Verbindung zum PC, Fenster, Auktionshaus, Dungeon-Liste).

## Einrichten (einmal)

1. WoW vollständig schließen.
2. `Installieren.cmd` starten und den AddOns-Ordner des Forever-Clients angeben
   (`…\World of Warcraft\_classic_beta_\Interface\AddOns`).

## Jedes Mal

1. `Starten.cmd` starten und das Konsolenfenster offen lassen.
2. WoW im Fenster- oder Fenster-Vollbildmodus starten (die obere linke Ecke muss sichtbar sein).
3. Im Spiel zeigt der Punkt am **Minimap-Knopf** den Zustand: grün bereit, gelb rechnet, rot ForeverCore.exe
   antwortet nicht. Linksklick öffnet die Übersicht, Rechtsklick das kopierbare Protokoll.

## Was automatisch passiert

- **Hover:** Item ansehen → Zeile im Tooltip mit Pfeil und „+x % DPS" (Details mit Shift).
- **Dungeon:** Beim Betreten erscheint das Dungeon-Fenster mit den Drops, die dich verbessern.
- **Levelroute:** Das Addon ForeverRoutes zeigt die beste Route für dein Volk und deine Klasse bis Level 20, mit
  Pfeil (TomTom, sonst die Kartenmarkierung des Spiels) und Death-Skip-Hinweisen. Es läuft auch ohne ForeverCore; mit
  ForeverCore plant es live von deinem aktuellen Stand aus. `/fr` zeigt oder versteckt das Fenster, `/fr skip`
  überspringt einen Schritt, `/fr back` geht einen zurück, `/fr reset` beginnt von vorn. Es gibt zwei Routen: **Solo ohne Dungeon** (Standard, `/fr solo`) und **Solo mit Dungeon** (`/fr dungeon`). Die Route mit Dungeon nimmt Dungeonquests unterwegs mit, schickt zum Eingang (für den Dungeon selbst eine Gruppe suchen) und gibt danach ab; die Route ohne Dungeon macht keine Dungeonquests. Empfohlen wird ein Lauf je Dungeon; läuft man einen Dungeon noch einmal, pausiert die Route darin (der Pfeil verschwindet im Dungeon) und geht danach beim nächsten offenen Schritt weiter (was inzwischen erledigt oder durch Stufenaufstieg überholt ist, wird übersprungen).
- **Routen-Update:** ForeverCore holt beim Start und danach alle 12 Stunden die neuesten Routen und Daten von
  ForeverRoutes (geprüft per SHA-256; ein fehlerhafter Download ändert nichts). Abschalten: `"routesNoUpdate": true`
  in `config.json`.
- **Auktionshaus:** Leiste rechts am Fenster: Scannen, Berechnen, dann `/reload` – danach steht das beste Item je
  Platz in der Liste.

Alles Weitere (Befehle, Filter, Grenzen): `README.md`.


## Automatische Datenpflege ab 0.6.0-autodata1

Nach einmaliger Installation der neuen ForeverCore-Version und des aktuellen,
separaten ForeverRoutes-Addons genügt der normale Start von ForeverCore und WoW.
Der Login führt auch mit bereits eingestellter Pixelverbindung einen Handshake aus.
Die Verbindung startet die Datenpflege im Hintergrund. Ein bereits erfolgreich
geprüfter Tagesstand wird über Neustarts hinweg wiederverwendet. Bei einem
laufenden Client erfolgt die nächste externe Prüfung nach 24 Stunden. Gleichzeitige
Anfragen starten keinen zweiten Download; Netzwerkfehler lassen den letzten gültigen
Stand aktiv. Der Status erscheint automatisch in der Übersicht und am Kristall.

- Aktuelle ForeverRoutes-Pakete werden mit SHA-256 geprüft und vor der Aktivierung
  vollständig vorbereitet. Eine laufende Routenplanung wird beim Tausch geschützt.
- Der ForeverRoutes-Collector übermittelt neue öffentliche Questtitel über eine
  freie Verbindung. Dafür braucht es weder Python noch `/reload`. Vollständige
  gespeicherte Beobachtungen liest ForeverCore beim nächsten Schreiben der
  SavedVariables zusätzlich ein (Ausloggen oder normaler UI-Neustart).
- Die lokale Datenbank liegt in `Data/ClientData/client-quests.json`, getrennt nach
  Build, Region und Sprache. Unterstützende Routenplaner erhalten sie automatisch.
  Englischsprachige bestätigte Titel bekannter Quests werden beim Planen eingelesen;
  beobachtete XP, Ziele ohne Ziel-ID und UI-Kartenpunkte verändern keine Basiswerte.
- Vorhandene Hotfix-Caches der ausgewählten Installation werden strukturell geprüft
  und lokal unter `Data/ClientData/HotfixCaches` archiviert. Es erfolgt kein Upload
  von Account-, Charakter- oder Cachedateien. Gesperrte oder teilweise geschriebene
  Dateien werden später erneut gelesen; Lua aus SavedVariables wird nicht ausgeführt.

Die tägliche Serverprüfung und der Bluepost-Tracker bleiben unabhängig vom laufenden
Spiel. Ein Cache-Download oder eine passende Buildnummer allein wird niemals als
aktueller Engine-Stand angezeigt: dafür müssen auch der geprüfte Export und der
Hotfix-Fingerabdruck der kompilierten Engine passen. Der derzeitige HTTP-403-Fehler
beim Blizzard-DB2-Abruf bleibt daher als ausstehende Hotfix-Prüfung sichtbar. Das
Archivieren eines lokalen Caches übersetzt dessen Werte noch nicht in Kampfformeln.

Bei privaten GitHub-Repositories braucht der PC einmalig Leseberechtigung für beide
Repositories. Der Client verwendet dafür eine vorhandene Umgebungsvariable
`FOREVER_GITHUB_TOKEN` (alternativ `GH_TOKEN` oder `GITHUB_TOKEN`). Das Token wird
nicht in Konfigurationsdateien oder Protokolle geschrieben und nur an GitHub gesendet.
Ohne Zugriff bleibt die Prüfung sichtbar fehlgeschlagen; sie meldet keine Aktualität.
ForeverRoutes wird ausschließlich aus seinem eigenen Release installiert; das
ForeverSim-Paket überschreibt das eigenständige HUD nicht mit einer alten Kopie.
