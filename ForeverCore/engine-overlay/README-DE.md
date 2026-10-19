# Level-Overlay für MythicSim (Level 10–60)

MythicSim bleibt die unveränderte Basis und wird täglich aktualisiert. Dieses Overlay legt sich beim Bauen darüber und macht aus der festen Stufe 60 eine Laufzeitstufe 10–60. Es gibt keine Zeilen-Patches, die bei jeder Upstream-Änderung brechen.

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
| `GetAPLSpell` | Eine Rotation, die den Stufe-60-Rang nennt, drückt den höchsten gelernten Rang. |
| `GetAuraByID` | Rotationsbedingungen auf Stufe-60-Auren lesen die Aura des gewirkten Rangs. |
| `Spell.CanCast`, `Spell.Cast`, `CanCastOrQueue` | Ein Zauber über der Stufe wird nie gewirkt. |
| `UnitLevelFloat64` (optional) | Ziele unter dem Spieler (Questgegner) fallen nicht mehr in Upstreams +3-Boss-Zweig. |
| `mechanics_mirror_test.go` (optional) | Typumwandlung im Upstream-Test. |
| `hunter.go` nach `applyAmmoDPS()` | Munitions-DPS aus dem Client (`FOREVERCORE_HUNTER`), auch fuer Munition ohne Enum. |
| `warlock/pets.go` Grundwerte, Nahkampf, Feuerblitz, Peitschenschmerz | Werte des aktiven Daemons und seines gelernten Zauberrangs aus dem Client (`FOREVERCORE_WARLOCK`). |
| `pet.go` `BaseStats`, `BaseDamageMin/Max` | Grundwerte und Grundschaden des Begleiters auf seinem Level aus dem Client statt Level-60-Konstanten. |

## Garantie für Stufe 60

Ohne `FOREVERCORE_LEVEL` oder mit `60` antwortet keine Overlay-Funktion. Die Update-Pipeline prüft das dreifach:

1. Alle Upstream-Go-Tests laufen mit Overlay unverändert grün.
2. Die Referenzanfragen liefern mit und ohne Overlay identische Ergebnisse (nach Sortierung der ungeordneten Listen, siehe `compare_results.py`).
3. `TestForeverCoreLevel60RowMatchesUpstream` vergleicht die Leveldaten mit Upstreams Stufe-60-Tabellen.

## Prüfung unter 60

`engine_update.py` lässt alle 28 Spec-Suites von Upstream auf mehreren Stufen laufen und zwei Referenzanfragen über die CLI. Fehler sind:

- ein Absturz;
- ein gewirkter Zauberrang über der Stufe;
- sinkender DPS bei steigender Stufe (mehr als 3 % Toleranz).

## Bekannte Grenzen

- **Feste Stufe-60-Stellen:** `apply_overlay.py` meldet Klassen-Code mit festen Stufe-60-Literalen unter `levelLiterals` im Bericht. Aktuell ist das nur der Ausweichschutz in `target.go` (Stufe 63).
- **Rotationen:** Upstreams Rotationen sind für 60 geschrieben. Ränge werden umgelenkt, aber eine echte Leveling-Rotation (etwa ohne Zauber, die erst später kommen) muss ForeverCore selbst liefern.
- **Grund-Krit und Kampfwerte:** Grund-Krit, Kampfwertungen und Wut-Umrechnung bleiben auf Upstreams Werten.
- **Ziele unter 60:** Rüstung und Leben der Ziele sind ohne Gegnerdatensatz geschätzt. Das ist als `foreverCoreTargetArmorEstimated` markiert.
