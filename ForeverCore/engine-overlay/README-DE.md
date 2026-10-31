# Level-Overlay für die Engine (Level 10–60)

Die Engine ist [wowsims/forever](https://github.com/wowsims/forever) (Branch `master`) ohne eigene Kampf-Patches und bleibt die unveränderte Basis. Dieses Overlay legt sich beim Bauen darüber und macht aus der festen Stufe 60 eine Laufzeitstufe 10–60. Es gibt keine Zeilen-Patches, die bei jeder Upstream-Änderung brechen.

## Bestandteile

| Datei | Aufgabe |
|---|---|
| `files/sim/core/zz_forevercore_level.go` | Liest `FOREVERCORE_LEVEL` und setzt Stufe, Grundwerte, Mana, Krit pro Beweglichkeit/Intelligenz und die Angriffskraft-Formel pro Stufe. Enthält außerdem die Rang- und Aura-Ausweichlogik. |
| `files/sim/core/spelldata/zz_forevercore_ladder.go` | Rangwahl nach Lernstufe; Rangfamilien und Lernstufen aus dem Zauberspeicher. |
| `files/sim/core/zz_forevercore_level_test.go` | Prüft, dass die Stufe-60-Zeile der Leveldaten exakt Upstreams Tabellen entspricht. |
| `sim/core/zz_forevercore_leveldata.go` | Wird aus `../leveling-data.json` erzeugt (Client-Tabelle `PlayerExpectedStat`). |
| `files/sim/hunter/zz_forevercore_hunter.go` | Liest `FOREVERCORE_HUNTER` (Munitions-DPS, Begleiterwerte). Ohne Variable keine Wirkung; Test: upstreams eigene Werte ueber diesen Weg ergeben exakt upstream. |
| `overlay.json` | Die Umschreibungen mit Ankern. |
| `apply_overlay.py` | Wendet alles an. Bricht ab, wenn ein Pflichtanker nicht genau so oft vorkommt wie erwartet. |

## Umschreibungen in Upstream-Dateien

| Anker | Wirkung |
|---|---|
| `const CharacterLevel = 60` → Variable | Alle Upstream-Stellen mit `CharacterLevel` folgen der Stufe (Rangskalierung, Angriffstabelle relativ zum Ziel, Begleiter, Basiswerte). |
| `Ladder.Highest()` | Höchster bereits gelernter Rang statt Stufe-60-Rang. |
| `Ladder.Each()` | Registriert keine Ränge über der Stufe (außer dem untersten als Platzhalter). |
| `GetAPLSpell` | Eine Rotation, die den Stufe-60-Rang nennt (oder einen noch nicht gelernten), drückt den höchsten gelernten Rang. Passive Zauber und Proc-Zauber gleichen Namens zählen dabei nicht. |
| `GetAuraByID` | Rotationsbedingungen auf Stufe-60-Auren lesen die Aura des gewirkten Rangs. |
| `Spell.CanCast`, `Spell.Cast`, `CanCastOrQueue` | Ein Zauber über der Stufe wird nie gewirkt. |
| `Ladder.Rank(n)`, `Ladder.ByID(id)` | Registriert eine Klasse einen festen Rang (Frostbolt Rang 10, Shadow Bolt Rang 9 und 10), der noch nicht gelernt ist, bekommt sie den höchsten gelernten darunter. `RegisterSpell` gibt für einen solchen Ersatzrang den schon registrierten Zauber zurück. |
| `Mana-Prüfung` | Rundungsfehler beim Mana-Vergleich fallen unter 60 nicht ins Gewicht. |
| `shaman/ranks.go` | Upstream registriert Schamanen-Schadensränge erst ab Zauberstufe 44; unter 60 zählen alle gelernten Ränge. |
| `rogue/poisons.go` | Die Rangsuche eines Gifts läuft über die ganze Leiter statt über `Each`. |
| `mechanics_mirror_test.go` (optional) | Typumwandlung im Upstream-Test. |
| `hunter.go` `BonusRangedDps` | Munitions-DPS aus dem Client (`FOREVERCORE_HUNTER`), auch für Munition ohne Enum. |
| `hunter/pets.go`, `warlock/pets.go` | Grundwerte, Grundschaden, Nahkampf und Zauber der Begleiter auf ihrer Stufe aus dem Client statt Level-60-Konstanten (`FOREVERCORE_HUNTER`, `FOREVERCORE_WARLOCK`). |

Ziele unter dem Spieler (Questgegner) braucht keine Umschreibung mehr: Upstream rechnet den Stufenunterschied inzwischen selbst.

## Garantie für Stufe 60

Ohne `FOREVERCORE_LEVEL` oder mit `60` antwortet keine Overlay-Funktion. Die Update-Pipeline prüft das so:

1. Alle Upstream-Go-Tests laufen mit Overlay unverändert grün.
2. Die Referenzanfragen liefern mit und ohne Overlay identische Ergebnisse (nach Sortierung der ungeordneten Listen, siehe `compare_results.py`).
3. `TestForeverCoreLevel60RowMatchesUpstream` vergleicht die Leveldaten mit Upstreams Stufe-60-Tabellen.

## Prüfung unter 60

`engine_update.py` lässt die Spec-Suites von Upstream auf den Stufen 10, 20, 30, 45 und 59 laufen (nur die Fälle `CharacterStats` und `Settings`, die den DPS liefern; Stufe 60 läuft vollständig in den Paket-Tests) und zwei Referenzanfragen über die CLI. Fehler sind:

- ein Absturz oder eine Endlosschleife der Rotation;
- ein gewirkter Zauberrang über der Stufe;
- kein Schaden in einer Suite, die auf Stufe 60 Schaden macht;
- ein DPS-Einbruch von mehr als 20 % von einer Stufe zur nächsten. Kleinere Rückgänge sind möglich: Mit fester Endstufen-Ausrüstung kann ein höherer Rang weniger Schaden machen, weil er länger zum Wirken braucht.

Mit `--classes warlock,mage` läuft nur die Stufenprüfung für diese Klassen (zum Eingrenzen eines Fehlers); sie schreibt nichts, und vor einem Push gehört ein vollständiger Lauf dazu.

## Bekannte Grenzen

- **Feste Stufe-60-Stellen:** `apply_overlay.py` meldet Klassen-Code mit festen Stufe-60-Literalen unter `levelLiterals` im Bericht. Aktuell ist das nur der Ausweichschutz in `target.go` (Stufe 63).
- **Rotationen:** Upstreams Rotationen sind für 60 geschrieben. Ränge werden umgelenkt, aber eine echte Leveling-Rotation (etwa ohne Zauber, die erst später kommen) muss ForeverCore selbst liefern.
- **Grund-Krit und Kampfwerte:** Grund-Krit, Kampfwertungen und Wut-Umrechnung bleiben auf Upstreams Werten.
- **Ziele unter 60:** Rüstung und Leben der Ziele sind ohne Gegnerdatensatz geschätzt. Das ist als `foreverCoreTargetArmorEstimated` markiert.
