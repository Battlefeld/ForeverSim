# ForeverCore – Was das Programm macht und wie

Stand: 18.10.2026 · Zielclient: WoW: Forever 1.60.x · Sprache der Oberfläche: Deutsch

> **Ehrlicher Hinweis vorab:** Alles hier ist mit Lua-Tests und Mocks geprüft, nicht im
> echten Client. Der Transport über den Bildschirm, die Pixelstreifen-Anpassung und die
> Dungeon-Vorberechnung müssen auf deinem Rechner bestätigt werden. Was nicht bewiesen ist,
> steht unter [Grenzen](#11-grenzen-und-was-nicht-bewiesen-ist).

---

## 1. Kurzfassung

ForeverCore bewertet Ausrüstung für dein WoW-Forever-Spiel. Gerechnet
wird **nicht im Spiel**, sondern auf deinem PC. Die Addons im Spiel lesen deinen Charakter,
schicken ihn per Pixelstreifen an ein Programm auf dem PC, das die Simulation rechnet, und
bekommen das Ergebnis über winzige Addon-Module zurück. Im Spiel siehst du nur die Ergebnisse:
Prozentwerte an Items und Drop-Chancen im Tooltip.

Was automatisch passiert (und sonst nichts):

| Ereignis | Was geschieht |
|---|---|
| Du siehst ein Item (Tooltip, Quest-Belohnung, Würfelfenster) | Der Wert gegenüber deinem getragenen Item wird bewertet |
| Du betrittst einen Dungeon | Alle Boss- und Trash-Drops werden vorberechnet |

Das Auktionshaus rechnest **du** per Knopfdruck. Rotation und Talente sind vorerst entfernt und werden neu gebaut
(siehe 6.7).
Buffs, Auren, Mana, Taschen und Zonenwechsel lösen **keine** Simulation aus. Im Kampf wird nichts
berechnet.

---

## 2. Die Bestandteile

| Teil | Wo | Aufgabe |
|---|---|---|
| **ForeverCoreBridge** | WoW-Addon | Transport und Aufträge: Warteschlange, Pixelstreifen, Antwortmodule, Cache, `/fc` |
| **ForeverSimBridge** | WoW-Addon | Liest den Charakter (Gear, Talente, Zauberbuch, Jäger-Daten), zeigt Item-Prozente |
| **FC3_S0001 … FC3_S2048** | 2.048 winzige Addons | Antwortslots: der PC schreibt hier seine Antworten hinein |
| **ForeverCore.exe** | PC | Liest den Pixelstreifen, nimmt Aufträge an, startet die Simulation, schreibt Antworten, pflegt Datenquellen |
| **MythicSim.exe** | PC | Die Kampf-Simulation (WoWSims-Forever-Engine) plus ein Level-Layer für Level 10–60 |
| **Lua.exe** | PC | Lua 5.1 für die Routenberechnung auf dem PC |
| **Data/** | PC | Zwischengespeicherte Quellen (QuestieDB, RestedXP, ForeverDB) und geprüfte Datengenerationen; wird im Sim-Paket nicht mehr automatisch aktualisiert (`autoSync = false`) |

**ForeverDungeonQuest ist nicht mehr Teil dieses Pakets.** Es wird neu gebaut; der bisherige Stand liegt
in der Git-Historie. Die Sim braucht es nicht: Dungeons, Bosse,
Drops und Drop-Chancen liefert ein eigener Katalog in ForeverSimBridge (siehe Abschnitt 6). Routen
werden nur berechnet, wenn ein Routen-Addon `_G.ForeverCoreFDQ` bereitstellt.

---

## 3. Wie ein Auftrag abläuft (Transport)

```
Spiel (Addon)                                   PC (ForeverCore.exe)
─────────────                                   ────────────────────
1. Auslöser → Auftrag in Warteschlange
2. Charakter lesen → JSON (max. 64 KiB)
3. JSON in Rahmen zu je 238 Byte zerlegen
4. Rahmen als Schwarz/Grau-Streifen oben links ─► 5. Fenster abfotografieren, Rahmen
   malen (je 0,10 s ein Rahmen, im Kreis)            zusammensetzen, CRC32 prüfen
                                                  6. Auftrag ausführen, MythicSim rechnen
7. Alle 2 s LoadAddOn("FC3_S0001") …   ◄───────── Antwort in Slot FC3_Snnnn schreiben
8. Antwort prüfen: Sitzung, Auftragsnummer,
   Revision, Art stimmen? sonst verwerfen
9. Ergebnis anzeigen / in Cache schreiben
```

Einzelheiten:

- **Pixelstreifen:** Raster 512 × 4 Zellen = 2.048 Bit = 256 Byte pro Rahmen
  (18 Byte Kopf `FC3` + Längen + CRC32, 238 Byte Nutzdaten). Eine Zelle ist 1 bis 8 Desktop-Pixel
  groß. Der Streifen ist **nur sichtbar, solange ein Auftrag gesendet wird**, sonst versteckt.
- **Lesen auf dem PC:** `ForeverCore.exe` nimmt das Fenster auf und wertet pro Zelle
  `R+G+B ≥ 384` als „1" aus. Die Zellgröße 1–8 erkennt sie selbst (Kalibrierung über den
  Rahmenkopf und die Prüfsumme).
- **Dauer eines Auftrags:** Ein Item-Auftrag besteht aus rund 35 Rahmen. Bei 0,10 s pro Rahmen dauert
  ein Durchlauf 3,5 s (vorher 6,3 s); dazu kommt die Abfrage der Antwort alle 2 s. Deshalb werden mehrere
  Items in **einem** Auftrag gebündelt (siehe 5.4).
- **Bildschirmaufnahme (EXE):** Die EXE benutzt **DXGI Desktop Duplication**, dieselbe Windows-Schnittstelle,
  die OBS und Discord für die Bildschirmaufnahme verwenden. Die Grafikkarte kopiert nur die wenigen Zeilen des
  Streifens in eine winzige Zwischentextur; nur diese wird vom Prozessor gelesen. Das frühere `GetDC`/`BitBlt`
  (Auslesen des ganzen Bildschirm-Kontexts) wurde entfernt: Es verursachte auf einer AMD RX 9060 XT mit WoW
  (D3D12) grüne Flächen und einen Ausfall des Bildsignals. Die EXE sucht den Monitor, auf dem das WoW-Fenster
  liegt (auch bei mehreren Grafikkarten, z. B. zusätzlich die integrierte), und baut die Aufnahme selbst neu auf,
  wenn sie unterbrochen wird (Moduswechsel, Sperrbildschirm, Treiber) oder WoW auf einen anderen Monitor zieht.
  Bis der Streifen gefunden ist, wird ein Bereich von 1540 x 16 Pixeln gelesen; nach der Kalibrierung nur noch der
  echte Streifen (bei 1,4 Pixeln je Zelle etwa 724 x 10). Ein Vollscan (4100 x 36) läuft nur alle 3 bzw. 8 s.
  HDR-Desktops werden vom System auf 8 Bit umgerechnet.
- **Aufnahme-Test:** `ForeverCore.exe -capturetest` (in einer Konsole im ForeverCore-Ordner) prüft die Aufnahme drei Sekunden lang
  ohne WoW und ohne Addon und gibt nur Zahlen aus (Dauer, Helligkeit); es werden keine Bilder gespeichert.
- **Rückweg:** `LoadOnDemand`-Addons. Jedes Modul kann pro Sitzung einmal geladen werden, daher
  die Grenze von 2.048 Antworten. Danach hilft nur `/reload`.
- **Zeitlimit:** 180 s pro Auftrag (20 s beim Anpassen des Streifens). Danach Meldung, im
  Zweifel Rückfall auf größeren Kontrast bzw. Standardgröße.
- **Sicherheit der Zuordnung:** Eine Antwort wird nur akzeptiert, wenn Sitzung, Auftragsnummer,
  Revision und Auftragsart passen. Veraltete Antworten werden abgewiesen.
- **Kampf:** Im Kampf wird weder gelesen noch gesendet noch gemalt.

Der PC erkennt außerdem den Spielstart. Beim ersten Erkennen eines sichtbaren WoW-Fensters prüft
er (nur bei `autoSync = true`, im Sim-Paket aus) die angebundenen Quellen; ein fehlerhaftes Update ersetzt nie eine
vorher geprüfte Generation.

---

## 4. Was Aufträge auslöst – und was nicht

### 4.1 Zwei Revisionen

Die Bridge führt zwei Zähler, damit Ereignisse nicht unnötig Ergebnisse verwerfen:

| Zähler | Steigt bei | Wirkt auf |
|---|---|---|
| `revision` (Route) | jedem „harten" Ereignis, auch Quests | Routenergebnisse (nur mit Routen-Addon) |
| `simRevision` (Simulation) | Levelup, Ausrüstung, Talente, Talentbaum, Zauberbuch, Begleiter (`UNIT_PET`), Level | Item-Ergebnisse |

Quest-, Beutel- und Zonen-Ereignisse berühren nur die Route, nie laufende Simulationen.

### 4.2 Weiche und harte Ereignisse

| Ereignis | Art | Wirkung |
|---|---|---|
| `QUEST_LOG_UPDATE`, `BAG_UPDATE_DELAYED`, `PET_UI_UPDATE`, `SKILL_LINES_CHANGED` | weich | nur mit Routen-Addon: Routenaktualisierung in frühestens 5 s, Revision bleibt gleich |
| `ZONE_CHANGED_NEW_AREA`, `GROUP_ROSTER_UPDATE` | weich | in frühestens 3 s |
| Quests angenommen/abgegeben, Levelup, Ausrüstung, Talente, Zauberbuch, Begleiter | hart | in 1,5 s, Revision steigt |
| Buffs, Auren, Mana, Wut, Haltung, Taschen, Reiten | – | **nichts** |

Regeln, die alles zusammen begrenzen:

- **Entprellung ohne Verlängerung:** Ein laufender Countdown wird nie verlängert, nur verkürzt.
  Dauerfeuer von Ereignissen kann die Aktualisierung also nicht aushungern oder endlos aufschieben.
- **Mindestabstand:** zwischen automatischen Routenaufträgen mindestens 6 s.
- **Keine Doppelaufträge:** `ping` und `route` stehen höchstens einmal in der Schlange.
- **Item-Deckel:** höchstens 5 wartende Item-Aufträge; die Dungeon-Vorberechnung fragt alle 2 s
  nach (bis zu 45 Mal), bis jedes Item angefragt wurde.
- `/fc off` leert Warteschlange und Automatik sofort.

### 4.3 Nur auf Knopfdruck

Auktionshaus scannen und berechnen, `/fc sim` (Grund-DPS), Dungeon-Liste im Chat. Rotation und Talente gibt es
im Addon vorerst nicht (siehe 6.7).

---

## 5. Item-Bewertung und Cache

### 5.1 Wo Items bewertet werden

Tooltip, Quest-Belohnung, Würfelfenster und Taschen/Bank. Jede Zahl ist eine
vollständige Simulation gegenüber dem getragenen Item im selben Slot, keine Summe von Stat-Punkten.
Effekte, die die Engine nicht kennt, zeigen **„?"** statt einer Schätzung.

### 5.2 Persistenter Cache

Ergebnisse werden in `ForeverCoreBridge.lua` (SavedVariables, Eintrag `simItemCache`) gespeichert
und überleben `/reload` und Neustart.

Der Cache-Schlüssel besteht **nur aus dem, was einen Itemvergleich wirklich ändert**:

Klasse, Level, Rasse/Fraktion, getragenes Gear, Talente, Zauberbuch, Gegnerprofil, Doppelwaffen,
Jäger-Munition/-Köcher, Begleiterfamilie und -level, Engine-Version und Charakter-GUID.

Nicht im Schlüssel: Buffs, Auren, aktuelle Ressourcen, Verbrauchsgüter, Seelensplitter,
Waffenverzauberungen auf Zeit, Haltung/Form, laufende Begleiterwerte, Taschen und Questbelohnungen.
Dadurch löst ein Buff **keine** Neuberechnung aus. Ein Fehler wie "Munition konnte nicht gelesen werden"
(Tooltips direkt nach dem Login noch nicht geladen) wird bis zu viermal im Abstand von 3 s wiederholt und nicht
dauerhaft gespeichert.

- Limit: 1.200 Einträge (ältester fliegt zuerst raus), Cache-Version 3.
- Die zuletzt bekannte Engine-Version wird mitgespeichert, damit der Cache direkt nach dem Login
  greift, noch bevor der PC antwortet. Ändert sich die Engine, wird neu gerechnet.

### 5.3 Wann der Cache ungültig wird

Nur bei echten Änderungen. ForeverSim vergleicht dafür eine **Zustandssignatur** aus
Level + getragenen Item-Links + Talentpunkten (`P.stateSignature`). Ereignisse wie
Zonenwechsel oder Aura-Änderungen verändern sie nicht und werden ignoriert.

### 5.4 Bündeln und Vorprüfung

- Item-Anfragen werden 0,35 s lang gesammelt und als **ein** Auftrag gesendet (bis 12 Items; der PC kann 24).
  Drei Quest-Belohnungen kosten so einen Durchlauf statt drei.
- Items, die der Charakter nicht tragen kann (Level, Fraktion, Rüstungs-/Waffenart, Zweihand, Einzigartig),
  werden **im Addon** beantwortet ("nicht anlegbar"), weil ein einziger unpassender Kandidat den ganzen
  Auftrag auf dem PC ablehnen würde.
- Schlägt ein gebündelter Auftrag trotzdem fehl, wird jedes Item einzeln angefragt.
- **Schlanke Kandidaten:** Zuerst werden nur Item-ID, Slot und die kleinen Tragbarkeitsdaten gesendet. Kennt die
  Engine-Datenbank des PCs das Item nicht, antwortet er mit "need" und das Addon sendet nur dieses Item noch einmal
  mit allen Werten.
- **Gelernte Item-Werte:** Items, die die Datenbank der EXE nicht kennt (neue Forever-Items, Varianten wie
  "of Agility"), schickt das Addon einmal mit allen Werten. Die EXE speichert sie auf der Platte
  (`DataItemslearned.json`, 7 Tage gültig). Danach reicht die ID: Ein Dungeon-Auftrag besteht nur noch aus den
  Item-IDs, der Zustand des Charakters ist der EXE schon bekannt (auch nach `/reload`, solange dieselbe EXE läuft).
- **Parallel rechnen:** Die EXE startet bis zu 6 Engine-Läufe gleichzeitig (halbe Zahl der Prozessorkerne) statt
  einen nach dem anderen. Bis zu 24 Items pro Auftrag, Zeitlimit 170 s.
- **Schnellere Antwort:** Nach dem ersten vollständigen Bilddurchlauf fragt das Addon jede Sekunde nach der Antwort
  (vorher alle 2 s).
- **Zustand nur einmal senden:** Der Charakterzustand (Ausrüstung, Talente, Zauberbuch) ist rund 10 KB und wurde
  bisher bei jedem Auftrag mitgeschickt, das sind etwa 45 Rahmen allein dafür. Jetzt sendet das Addon ihn einmal, die
  EXE merkt sich die letzten sechs Zustände, und weitere Aufträge verweisen nur noch auf einen Schlüssel. Ein
  Hover-Auftrag schrumpft damit von rund 11 KB auf unter 1 KB. Kennt die EXE den Schlüssel nicht (Neustart), antwortet
  sie mit `STATE_UNKNOWN`, und das Addon sendet den Zustand einmal komplett nach. Das Addon benutzt Verweise nur, wenn
  die EXE es in der Ping-Antwort ankündigt (`stateRefs`); mit einer älteren EXE wird immer alles gesendet.
- Pixel-Bilddauer 0,10 s; nach einem Zeitlimit stellt sich das Addon zuerst auf 0,18 s zurück
  (`/fc pixel tempo schnell|normal`).

---

## 6. Dungeons: Drop-Listen, Drop-Chancen, Vorberechnung

### 6.1 Der Dungeon-Katalog der Sim

Alles liegt in ForeverSimBridge; es wird kein anderes Addon gebraucht.

| Datei | Inhalt |
|---|---|
| `DungeonCatalogData.lua` (erzeugt) | 31 Dungeons mit Levelbereich, Instanz-IDs, Bossen (Name, NPC-ID, Level), Trash-Gruppen und Items: 1.291 Zeilen, davon 950 mit Drop-Chance in %, dazu das Mindestlevel bestätigter Drops |
| `DungeonCatalog.lua` | Schnittstelle `ForeverSimDungeonAPI`: Dungeonliste, Bosse, Kontext des aktuellen Dungeons, Loot-Kandidaten, Drop-Chance-Text |
| Engine-Datenbank (MythicSim) | 10.769 Items mit Werten; deckt ca. 82–93 % der Dungeon-Drops ab |

Quellen: Dungeon-Journal (bisheriger FDQ-Stand) und **Forever Guide 1.35.1**, verwendet mit Erlaubnis des
Datenautors (der Guide stützt sich auf ForeverChanges, Wowhead Forever/Classic und cmangos). Die Quelle
steht im Dateikopf von `DungeonCatalogData.lua`. Neu erzeugen (die Ordner werden nur gelesen):

```
Lua.exe _dev/tools/build_dungeon_catalog.lua "<FDQ-Ordner oder -Archiv>" "<Forever-Guide-Ordner>" > ForeverSimBridge/DungeonCatalogData.lua
```

### 6.2 Was beim Betreten eines Dungeons passiert

1. `ForeverSimDungeonAPI.InstanceContext()` erkennt den Dungeon über die Instanz-ID (sprachunabhängig),
   bei unbekannter ID über den englischen Namen. Instanzen mit mehreren Flügeln (*Dire Maul*,
   *Blackrock Spire*, *Stratholme*) werden zusammengeführt; *Scarlet Monastery* wird über die Karte
   auf Graveyard/Library eingegrenzt, sonst werden alle Flügel zusammengefasst.
2. Aus allen Boss- und Trash-Drops entsteht die Item-Liste.
3. ForeverCoreBridge (DungeonReport.lua) fragt die Items beim PC an, gefiltert nach Klasse und nützlichen
   Werten, nie im Kampf, und zeigt die Verbesserungen im Dungeon-Fenster, sobald sie da sind.
4. Die Ergebnisse landen im Cache aus 5.2. Beim Würfeln liegt der Wert dann bereit.
5. Im Item-Tooltip steht zusätzlich "Drop-Chance: x % - Boss".

Abschalten: `/fc dungeon auto off` oder der Schalter in der Übersicht (wieder an: `/fc dungeon auto on`).

**Vorschau ohne Stufenprüfung:** Dungeon-Drops werden berechnet, auch wenn die Stufenanforderung noch nicht
erreicht ist und die Rüstungsstufe (z. B. Kette ab 40) noch fehlt. Gefiltert wird nur nach dem, was die Klasse überhaupt
tragen kann, und nach nützlichen Werten. Das gilt **nur für Dungeon-Drops**: Im Auktionshaus und beim normalen Hover
bleibt die Stufenprüfung (Kandidat-Markierung `ignoreLevel`, Schlüssel `…#preview`).

**Liste im Chat:** `/fc dungeon` zeigt die Drops des Dungeons, in dem du stehst, nach Boss geordnet, mit
Drop-Chance und dem DPS-Gewinn für deinen Charakter (nur Verbesserungen; `/fc dungeon alle` zeigt alles Tragbare).
Werte, die noch berechnet werden, werden bis zu 12 Sekunden abgewartet. Die Liste erscheint auch von selbst etwa
8 Sekunden nach dem Betreten (`/fc dungeon auto off` schaltet das ab). Die Datei `DungeonReport.lua` steht neu in
der `.toc`, WoW muss dafür einmal komplett neu gestartet werden.
Das ist der **einzige automatische Lesevorgang außerhalb des Schutzmodus**; er liest nur
Item-IDs, nie im Kampf.

Grenzen: Auf einem nicht-englischen Client werden Dungeons ohne bekannte Instanz-ID nicht über den
Namen erkannt. Die Instanz-IDs der klassischen Dungeons sind die Standardwerte von Classic und im
Forever-Client noch nicht einzeln bestätigt.

### 6.3 Auktionshaus: ganze Liste auf einmal berechnen

Hunderte Items passen nicht durch den Pixelstreifen. Deshalb gibt es für das Auktionshaus einen zweiten Weg
über die Datei, die WoW beim `/reload` schreibt (SavedVariables):

1. Auktionshaus öffnen, **FC Scan** drücken (oder `/fc ah scan`). Das Addon liest die ganze Liste
   (`C_AuctionHouse.ReplicateItems`, falls der Client das kann; sonst die Treffer der Kategorien, die du
   durchblätterst) und merkt sich Item-ID und niedrigsten Preis. Nur tragbare Ausrüstung wird gemerkt.
2. **FC Berechnen** (oder `/fc ah calc`): Das Addon sortiert Unpassendes und schon Bekanntes aus und legt bis zu
   400 Items als **einen** Auftrag in `WTF\Account\<Konto>\SavedVariables\ForeverCoreBridge.lua`. Danach tippst du `/reload` (ein Addon darf das Spiel nicht selbst neu laden).
   Dabei schreibt WoW die Datei.
3. `ForeverCore.exe` liest die Datei (alle 3 s geprüft), rechnet bis zu 6 Items gleichzeitig und schreibt die
   Antwort in die Antwort-Slots. Nach dem Neuladen holt das Addon sie ab, speichert jedes Ergebnis im normalen
   Item-Cache (die Tooltips zeigen sie sofort) und meldet "Auktionshaus fertig".
4. `/fc ah top` zeigt das **Beste für jeden Platz** (Kopf, Brust, Waffen, …; Ringe und Schmuck die zwei besten) mit
   Gewinn und Preis. Varianten desselben Items ("of the Bear", "of the Monkey") zählen als ein Item: Gezeigt wird die
   beste, die anderen werden gezählt. `/fc ah top 3` zeigt drei pro Platz. `/fc ah clear` löscht die gemerkten Daten.

Was dabei aussortiert wird (die Zahlen stehen im Chat, damit man es nachprüfen kann):

- **Beim Scan:** alles, was keine Ausrüstung ist; Rüstungsarten, die deine Klasse auf deiner Stufe nicht tragen
  kann (z. B. Platte für einen Jäger auf Stufe 12); Waffenarten, die die Klasse nicht benutzt. Mehrere Angebote
  desselben Items werden zu **einem** Kandidaten mit dem niedrigsten Preis. Items mit Zufallssuffix
  ("des Bären") bleiben getrennte Kandidaten.
- **Bei FC Berechnen:** zu hohe Stufe, falsche Fraktion, einzigartig anlegbar, und Items **ohne einen einzigen
  Wert, der für die Klasse zählt** (Jäger: Beweglichkeit, Stärke, Intelligenz, Angriffskraft, Crit/Hit/Tempo;
  Magier und Hexenmeister: Intelligenz, Zauberkraft, Crit/Hit/Tempo; Priester zusätzlich Willenskraft;
  Hybridklassen behalten alles Offensive). Waffen werden immer berechnet. Items, die das Spiel noch laden muss,
  werden bis zu dreimal im Abstand von 3 s nachgefragt.
- **Berufe und Klassen:** Items, die einen Beruf brauchen, den du nicht hast ("Benötigt Ingenieurskunst (215)"), oder
  die nur andere Klassen tragen dürfen ("Klassen: Krieger"), werden aussortiert. Hast du den Beruf, aber mit zu
  niedrigem Wert, gilt das Item ebenfalls als nicht tragbar (bei Dungeon-Drops zählt nur, ob du den Beruf hast). Die
  Voraussetzungen stehen im Tooltip; das Addon liest sie mit den Textvorlagen des Spiels, also in jeder Sprache.
  Auch Völker-Beschränkungen werden aussortiert. Die Bestenliste prüft die angezeigten Zeilen zusätzlich noch einmal,
  damit alte Ergebnisse von vor einer Prüfung nicht stehen bleiben.
- **Ringe und Schmuckstücke:** Es werden zwei getragen. Ist der beste nicht einzigartig („Einzigartig" /
  „Einzigartig anlegbar" im Tooltip) und gibt es ihn mindestens zweimal im Auktionshaus, steht er einmal mit „2x" in
  der Liste statt eines zweiten, schwächeren Items. Der Gewinn gilt für ein Exemplar. Die Zahl der Angebote kennt die
  Liste erst nach dem nächsten Scan; bis dahin wird „2x" ohne Anzahl gezeigt.
- **Verzauberungen zählen nie:** Ein verzaubertes Item wird wie das unverzauberte bewertet (Auktionshaus, Hover,
  Dungeon, Würfeln); verzauberte und unverzauberte Angebote desselben Items sind ein Eintrag mit dem niedrigeren Preis.
  Auch die getragene Ausrüstung wird ohne Verzauberung gerechnet, sonst wäre das getragene Item mit seiner
  Verzauberung immer im Vorteil. Vorübergehende Waffenverzauberungen (Gifte, Öle, Schamanen-Waffenzauber) zählen weiter.
- Die Liste ist **je Charakter** gespeichert (Klasse und Stufe bestimmen, was sie enthält). Nach einer
  Stufenerhöhung `FC Scan` wiederholen.
- Der Auftrag bekommt ein **eigenes Antwort-Fenster** (Slots 1800–1927). Sonst würde die Antwort auf den
  automatischen Ping nach dem `/reload` die Antwort überschreiben.

Grenzen: Der Gesamtscan klappt zuverlässig nur direkt nach einem **kompletten Neustart von WoW**; nach `/reload` bleibt die Antwort des Servers oft aus (beobachtet, die genaue Regel ist nicht bekannt). Der Knopf ist deshalb nie gesperrt. Die gemerkte Liste bleibt gespeichert, und `FC Berechnen` geht auch ohne neuen Scan. `/fc ah scans` zeigt die letzten Scan-Versuche. Ändert sich Ausrüstung, Talente oder Stufe
zwischen Auftrag und Antwort, wird das Ergebnis verworfen. Items, die das Spiel noch nicht geladen hat, werden
angefordert und beim nächsten `/fc ah calc` berücksichtigt. Vorgehen und Dateiformat sind vom Client-Verhalten
abhängig und im Spiel noch nicht erprobt.

### 6.4 Betrieb ohne Bildschirmaufnahme

Die Bildschirmaufnahme der EXE (DXGI Desktop Duplication) ist der einzige Teil, der die Grafikkarte berührt.
Auf einigen Systemen (beobachtet: AMD RX 9060 XT mit einer zweiten Grafikeinheit, YouTube im Hintergrund) führte
das zu grünen Bildern oder einem schwarzen Monitor. Für diesen Fall gibt es einen Modus, der **gar nichts vom
Bildschirm liest**:

1. Im Spiel `/fc pixel aus`. Das Addon malt dann keinen Streifen mehr und stellt keine Pixel-Aufträge in die Warteschlange.
2. `ForeverCore.exe -keine-aufnahme` statt `Starten.cmd`.
3. Auktionshaus wie beschrieben: FC Scan, FC Berechnen, `/reload`. Das läuft nur über Dateien.

Nicht verfügbar in diesem Modus: Hover-Werte für neue Items, Quest-Belohnungen und Dungeon-Vorberechnung über den PC.
Zurück: `/fc pixel an` und `Starten.cmd`.

**Bekannter Auslöser für schwarze Bildschirme: DirectX 12 in WoW.** Auf einem System mit AMD RX 9060 XT (zwei
Monitore, 144 Hz und 60 Hz) wurde der Bildschirm schwarz oder grün, sobald auf dem zweiten Monitor etwas anderes
bedient wurde, auch bei geschlossener ForeverCore.exe und ausgeschalteten Addons. Mit der **Grafik-API
DirectX 11** (WoW: Optionen, System, Grafik) trat es nicht mehr auf. Das Problem liegt also am D3D12-Pfad der Beta
mit dem Treiber, nicht an ForeverCore. Wer es sieht, sollte zuerst DirectX 11 einstellen, bevor er die
Bildschirmaufnahme der EXE verdächtigt.


### 6.5 Ab Stufe 5 nutzbar

Talente lassen sich mit Legacy-Punkten schon ab Stufe 5 vergeben, deshalb rechnet das Programm **ab Stufe 5** (früher ab 10).
Die Engine hat ihre Stufentabellen erst ab Stufe 10. Stufe 5 bis 9 werden deshalb **mit Stufe 10 genähert**. Items,
Talente und Zauberbuch bleiben echt, und jedes Ergebnis trägt den Hinweis „Stufe N: … genähert". Das Talentbudget
kennt den Fall (der erste Punkt kommt mit Legacy-Punkten bei Stufe 5). Unter Stufe 5 wird nichts gerechnet.
Ist für einen Charakter das Sim-Addon (ForeverSimBridge) nicht geladen, sagt `FC Scan`/`FC Berechnen` das mit klarem
Text statt eines Fehlers.

### 6.6 So sieht es im Spiel aus

Die Oberfläche zeigt nur an, was ohnehin berechnet wurde; sie startet selbst keine Berechnung (außer den Knöpfen
Scannen/Berechnen). Alles sind eigene Fenster, Blizzard-Fenster dienen nur als Anker.

- **Minimap-Knopf:** Ein Punkt zeigt den Zustand – grün bereit, gelb rechnet, rot letzter Auftrag fehlgeschlagen,
  grau ForeverCore.exe noch nicht gemeldet bzw. Pixelstreifen aus. Linksklick öffnet die Übersicht (Knöpfe für
  Dungeon-Liste, Auktionshaus, Protokoll, Verbindung und die Schalter unten), Rechtsklick das kopierbare Protokoll.
  Ziehen verschiebt ihn am Minimap-Rand. `/fc minimap aus|an`.
- **Ruhiger Chat:** In den Chat kommen nur noch Probleme, die Aufforderung „/reload" (zusätzlich in der
  Bildschirmmitte) und Antworten auf getippte `/fc`-Befehle. Alles andere steht im Protokoll (`/fc log`). Wer alles
  im Chat will: `/fc chat alles` (zurück mit `/fc chat ruhig`) oder der Schalter in der Übersicht.
- **Tooltip:** Eine Zeile mit grünem bzw. rotem Pfeil, „+10,7 % DPS" und rechts dem DPS-Wert. Warnungen, das
  ersetzte Item, Gegner und der Hinweis zur Dungeon-Vorschau erscheinen mit gedrückter Shift-Taste (oder immer, wenn
  der Schalter „Tooltip immer ausführlich" an ist).
- **Auktionshaus:** Rechts am Auktionshausfenster hängt eine Leiste mit Scannen/Berechnen, dem Fortschritt und dem
  besten Item je Platz. Klick auf eine Zeile sucht das Item im Auktionshaus, Shift-Klick setzt den Link in den Chat.
  „Bericht im Chat" und „Liste im Chat" geben `/fc ah report` bzw. `/fc ah top` aus. Ohne Auktionshaus öffnet der
  Knopf in der Übersicht dieselbe Liste als freies Fenster.
- **Dungeon:** Statt der Chat-Liste erscheint ein Fenster mit Boss, Item, Gewinn und Drop-Chance, sobald ein Drop
  deinen Schaden verbessert. Es schließt sich beim Verlassen des Dungeons. `/fc dungeon` schreibt die Liste weiterhin
  in den Chat.
- **Würfeln:** Unter dem Würfelfenster steht der Gewinn aus derselben Berechnung wie die Dungeon-Liste; bei einer
  Verbesserung bekommt der Bedarf-Knopf einen goldenen Rahmen. (Ohne ForeverCore bleibt die alte Schätzung.)
- **Pfeile auf Items:** Grüner Pfeil oben links auf Items, die deinen Schaden verbessern – in den Taschen, in der
  Auktionshaus-Liste und im Beutefenster. Im Auktionshaus und Beutefenster nur mit schon vorhandenen Werten (keine
  neue Berechnung). Schalter „Upgrade-Pfeile auf Items".

### 6.7 Aufgeräumt: was im Addon steckt

Entfernt wurden zuerst alle Teile, die weder die Item-Berechnung noch Rotation und Talente brauchten: Szenario-Studio,
Stat-Gewichte (Fenster und Tabellen), Insights-Fenster, Ausrüstungsplan, die alte Dungeon-Vorberechnung und die
Routen-Brücke (ersetzt durch die Dungeon-Liste von ForeverCore), das Notiz-Protokoll und nie geladene Altdateien.

Danach wurden **das ForeverSim-Fenster, Rotation und Talente entfernt**, damit sie neu gestaltet werden können:
das Fenster mit allen Seiten (Übersicht, Ausrüstung, Rotation Style, Talente, Quests, Erweitert/Mehr), der Talentplaner
und der Talententwurf, das Rotations-HUD, der Rotations-Optimierer im Spiel (auch sein Start nach dem Login), die
Talentempfehlung über ForeverCore, Leveling-Modell, Kampfverlauf, Kampfaudit, Gegnerauswahl, die XN-Vorlagen und die
Bilder des Fensters. Der Minimap-Knopf öffnet die ForeverCore-Übersicht; statt „ForeverSim" steht dort „Verbindung".

Was bleibt: Das Addon liest weiterhin deine Talente und dein Zauberbuch, denn jede Item-Rechnung schickt sie mit.
Die Klassenmodule, die Lua-Rechnung (nur noch Rückfall für Items ohne ForeverCore) und die Job-Warteschlange bleiben
aus demselben Grund. Auf dem PC kennt `ForeverCore.exe` die Aufträge `rotation`, `talents`, `talent-next`,
`talent-build`, `weights`, `analysis` und `leveling` weiterhin; das Addon schickt sie nur nicht mehr.

Der Generator des Dungeon-Katalogs liegt in `_dev/tools`, die Entwicklerdateien der Klassenmodule in
`_dev/ForeverSimBridge-Development` (nicht im Addon).

---

## 7. Der Pixelstreifen: Aussehen, Größe, Anpassung

- **Ort:** oben links im WoW-Fenster, nur während der Übertragung sichtbar.
- **Kontrast:** Standard „schwach" – zwei Grautöne nahe Mittelgrau (112 und 143 von 255), beide
  mit rund 45 Punkten Abstand zur Entscheidungsschwelle des PCs. Alternativ „normal"
  (Schwarz/Weiß).
- **Größe:** Zelle 1 bis 8 Pixel. Der Streifen behält immer das Seitenverhältnis 128 : 1:
  Zelle 1 = 512 × 4 px, 2 = 1024 × 8 px, 3 = 1536 × 12 px … Breiter und gleichzeitig dünner
  geht ohne Änderung an `ForeverCore.exe` nicht.
- **Nur Änderungen malen:** Es werden nur die Bytes neu gezeichnet, die sich zwischen zwei
  Rahmen ändern.
- **Bilddauer:** 0,10 s pro Rahmen (Standard) statt 0,18 s. Der PC liest alle 40 ms. Nach einem Zeitlimit
  stellt sich das Addon zuerst auf 0,18 s zurück, dann auf normalen Kontrast, dann auf Zelle 2.
- **Automatische Anpassung:** Beim ersten Start probiert das Addon nacheinander
  1) Zelle 1 schwach, 2) Zelle 2 schwach, 3) Zelle 2 normal, 4) Zelle 3 normal, jeweils mit
  20 s Zeitlimit per Ping. Die erste Variante, die der PC liest, wird gespeichert. Klappt
  keine, gelten Standardwerte (Zelle 2, schwach) und die Statuszeile nennt den Grund
  (meist: `ForeverCore.exe` läuft nicht).
- **Rückfall:** Läuft später ein Auftrag in ein Zeitlimit, geht das Addon erst auf normalen
  Kontrast, dann auf Zelle 2 zurück.
- Die Größe wird gegen die Bildschirmbreite geprüft (Zelle × 512 Pixel).

---

## 8. Befehle

| Befehl | Wirkung |
|---|---|
| `/fc` | Übersicht (wie Linksklick auf den Minimap-Knopf) |
| `/fc ping` | Verbindung testen |
| `/fc on` / `/fc off` | Externe Berechnung ein/aus (`off` leert die Warteschlange) |
| `/fc route` | Route berechnen (nur mit einem Routen-Addon; sonst kommt ein Hinweis) |
| `/fc sim` | Grund-DPS deines Charakters rechnen (Ergebnis im Chat) |
| `/fc quests` | Quest-Übersicht (nur mit einem Routen-Addon) |
| `/fc test` | Diagnose speichern (Zauberbuch, Begleiter, Munition, Köcher …) |
| `/fc sources` | Quellen prüfen |
| `/fc status` | Statusfenster |
| `/fc pixel auto` | Streifen-Anpassung neu starten |
| `/fc pixel low` / `normal` | Kontrast von Hand |
| `/fc pixel size 1…8` | Zellgröße von Hand (beendet die Automatik) |
| `/fc dungeon` / `/fc dungeon alle` | Dungeon-Liste (Verbesserungen / alle Drops) in den Chat |
| `/fc dungeon auto on|off` | Dungeon-Fenster beim Betreten ein/aus |
| `/fc pixel tempo schnell` / `normal` | Bilddauer 0,10 s / 0,18 s |
| `/fc chat alles` / `ruhig` | Alle Meldungen im Chat / nur Probleme und Antworten (Standard) |
| `/fc minimap aus` / `an` | Minimap-Knopf aus- bzw. einblenden |
| `/fc log` | Kopierbares Protokoll aller Meldungen |
| `/fus` | Alter Kurzbefehl (weiterhin gültig) |

---

## 9. Installation und Start

1. WoW **vollständig beenden**, auch den Launcher.
2. `Installieren.cmd` starten (oder `Install.ps1 -Addons "<Pfad>\Interface\AddOns"`).
   Das Skript sichert vorhandene Addon-Ordner nach `Backups\<Zeitstempel>`, kopiert die zwei
   Addons (ForeverSimBridge, ForeverCoreBridge), erzeugt die 2.048 Antwortslots und schreibt `config.json`
   mit `autoSync = false`. Ein altes ForeverDungeonQuest im AddOns-Ordner wird nicht angefasst, aber gemeldet.
   SavedVariables (`WTF`) werden **nicht** angefasst.
3. **Zuerst `ForeverCore.exe` starten** (`Starten.cmd`), Konsolenfenster offen lassen.
4. WoW starten, im Fenster- oder Fenster-Vollbildmodus. Die obere linke Ecke muss sichtbar sein.
5. Im Spiel: `/fc ping`, dann `/fc on`. Die Statuszeile sollte „Verbunden" zeigen.
6. Alte MiniLab-/FSBridgeTest-Addons deaktivieren.

Zurückspielen: WoW und ForeverCore schließen, `Restore.ps1` ausführen.

---

## 10. Wo was gespeichert wird

| Was | Wo |
|---|---|
| Item-Cache, Streifen-Einstellung, letzte Engine-Version | `WTF\Account\<Konto>\SavedVariables\ForeverCoreBridge.lua` |
| Einstellungen von ForeverSim | `…\SavedVariables\ForeverSimBridge.lua` |
| Dungeon-Katalog (feste Daten) | `…\AddOns\ForeverSimBridge\DungeonCatalogData.lua` |
| PC-Konfiguration | `config.json` neben `ForeverCore.exe` |
| Gepr. Datengenerationen und Quellen | `Data\` |
| Sicherungen (nur wenn `Installieren.cmd` läuft) | `Backups\` |

Cache zurücksetzen: WoW schließen und den Block `simItemCache` aus `ForeverCoreBridge.lua`
löschen. Er baut sich beim Spielen neu auf.

---

## 11. Grenzen und was nicht bewiesen ist

- **Kein Echtclient-Nachweis** für Transport, Pixelstreifen-Anpassung, Dungeon-Automatik,
  Begleiterwerte und Köcher-Erkennung. Dafür gibt es die Testliste unten.
- **Antwortslots:** 2.048 pro Sitzung; jede Abfrage verbraucht einen. Jedes Item ist ein eigener
  Auftrag; Bündelung bräuchte eine Änderung am Go-Programm.
- **Modellgrenzen:** Unter Level 10 keine DPS-Simulation. Level 10–59 ist ein
  Modell mit eigenem Level-Layer, kein im Spiel bewiesener Vollsimulator. Heilerrollen sind keine
  Freigabe. Gegnerwerte unter Level 60 sind teils geschätzt und markiert.
- **Nicht modelliert** (wird im Ergebnis genannt): Frostrüstung, Dämonenhaut, Waffensteine,
  Gifte/Öle/Wetzsteine auf Leveling-Stufe, Fremd- und Gruppenbuffs, Teufelswache.
- **Routen 1–30** je Klasse/Rasse sind nicht ingame nachgewiesen; generierte Abschnitte gelten
  nicht als originale RestedXP-Route.
- **Quellenstand:** Patches gelten erst als verarbeitet, wenn Daten, Build und Tests passen.
- **Nur Lesen öffentlicher Daten:** Das Addon liest keine geschützten Kampfdaten und führt keine
  Aktionen aus. Der Pixelkanal ist rein optisch gedämpft, nicht verborgen.

---

## 12. Tests

Lua-Suiten (ohne WoW, mit Mock-Client), aufrufbar mit `lua5.1 ForeverCore/tests/<name>.lua .`:

| Test | Prüft |
|---|---|
| `bridge_test` | Transport, Rahmen, Antwortslots, veraltete Antworten |
| `integration_test` | Alle Addons zusammen, Routen, Analyse |
| `hunter_capture_test` | Jäger-Erfassung, Begleiter, Munition |
| `request_storm_test` | Ereignissturm führt nicht zu Dauer-Aufträgen |
| `item_cache_test` | Buffs/Aura/Zonen ändern nichts; Gear, Level, Talente schon |
| `sim_cache_key_test` | Cache-Schlüssel stabil bei flüchtigem Zustand |
| `dungeon_catalog_test` | Dungeonliste, Bosse, Instanz-Erkennung (ID, Name, Flügel), Drop-Chance, Vorberechnung |
| `item_batch_test` | Bündeln, Vorprüfung, Rückfall auf Einzelaufträge, Wiederholung bei Tooltip-Fehlern |
| `pixel_style_test` | Kontrastgrenzen, Größen, Rückfall |
| `pixel_tune_test` | Automatische Streifen-Anpassung |

Go-Tests, Vet und Windows-Build laufen im GitHub-Workflow *ForeverCore integration*.

### Deine Ingame-Prüfliste

1. `ForeverCore.exe` starten, dann WoW. `/fc ping` und `/fc on` → „Verbunden".
2. Ein Item ansehen → Prozentwert. Buffen/Reiten → gleicher Wert, keine neue Rechnung.
3. `/reload` → dieselben Werte sofort wieder da.
4. Dungeon betreten → Drops werden vorberechnet; Journal zeigt „Drop-Chance".
5. Würfeln → Wert ohne Wartezeit.
6. `/fc test` → Begleiterwerte nicht 0? Köcher erkannt?
7. Streifen: Wie sieht er aus, welche Variante wurde gewählt (Statuszeile)?

---

## 13. Fehlersuche

| Symptom | Ursache / Abhilfe |
|---|---|
| Statuszeile „Zeitlimit" | `ForeverCore.exe` läuft nicht, WoW nicht im Fenstermodus oder obere linke Ecke verdeckt. `/fc pixel normal`, dann `/fc ping` |
| „Antwortslots verbraucht: /reload erforderlich" | 2.048 Antworten in der Sitzung aufgebraucht → `/reload` |
| „Zustand geändert: Ergebnis verworfen" | Gear/Level/Talente änderten sich während der Rechnung; wird automatisch neu gestartet |
| Item zeigt „?" | Effekt oder Item nicht modelliert; kein Schätzwert |
| Item zeigt gar nichts | `/fc on` prüfen; Level < 10; im Kampf wird nicht berechnet |
| Alle Werte neu gerechnet nach Engine-Update | Gewollt: andere Engine = andere Ergebnisse |
| Fehler im Addon | `/fc log` (kopierbares Protokoll); Lua-Fehler zeigt WoW nach `/console scriptErrors 1` |

---

## 14. Änderungen dieser Version

- **ForeverSim-Fenster, Rotation und Talente entfernt** (siehe 6.7). Sie werden neu gebaut.
- **Dauer-Simulation behoben:** weiche/harte Ereignisse, Entprellung ohne Verlängerung,
  Mindestabstand, Doppelaufträge entfernt, getrennte Revisionen für Route und Simulation,
  Rebuild-Hook löst keine Revisionsänderung mehr aus.
- **Item-Cache:** stabiler Schlüssel (ohne Buffs/Auren/Ressourcen), 1.200 Einträge, Persistenz
  inkl. letzter Engine-Version, Zustandssignatur statt Ereignissen.
- **Keine automatische Rotation** mehr.
- **Dungeon-Katalog in der Sim:** 31 Dungeons, Drop-Chancen im Tooltip, Dungeon-Kontext beim Betreten,
  unabhängig von ForeverDungeonQuest (das archiviert ist).
- **Tempo:** Item-Aufträge werden gebündelt, nicht tragbare Items vorab beantwortet, Bilddauer 0,10 s.
- **Routen:** werden nur noch mit einem Routen-Addon berechnet; Installer und Paket enthalten nur die Sim.
- **Bildschirmaufnahme der EXE:** `BitBlt` entfernt, jetzt DXGI Desktop Duplication (wie OBS/Discord) mit winzigem
  Aufnahmebereich, Selbstheilung und Aufnahme-Test. Behebt grüne Flächen und den Bildsignal-Ausfall.
- **Pixelstreifen:** schwacher Kontrast, Größe 1–8, automatische Anpassung, Rückfall,
  nur geänderte Bytes malen.
- **Kleinere Fixes:** Begleiterwerte-Fallback, HUD-Animation abgesichert, Fehlerlog ohne Duplikate.

---

## 15. Quellen und Lizenzen

- MythicSim / WoWSims Forever: <https://github.com/sage3648/mythicsim-forever-engine-go> ·
  <https://github.com/wowsims/forever> (MIT)
- QuestieDB: <https://github.com/Questie/QuestieDB> · RestedXP: <https://github.com/RestedXP/RXPGuides>
- ForeverDB: <https://foreverdb.net>
- Guide-Loot: Forever Guide 1.35.1 (mit Erlaubnis des Datenautors)
- Lizenztexte: Ordner `Lizenzen\`

Die Bridge-Addons sind unabhängige Fan-Werkzeuge und stehen in keiner Verbindung zu Blizzard
Entertainment.
