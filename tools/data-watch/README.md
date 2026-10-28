# Direkte Forever-Datenprüfung

`watch.py` liest Blizzards HTTPS-Versionsdienst direkt. `wowf` und `wow_classic_beta`
bleiben getrennt: am 28.10.2026 lieferten sie 70658 beziehungsweise 70532.
Der Workflow prüft stündlich und hält den letzten gültigen Stand im Artefakt-Branch.
Er verändert keine produktiven Simulationswerte allein aufgrund einer Buildnummer.

## Clienttabellen und Änderungen ohne Patchnote

```sh
python tools/data-watch/run_export.py --work /tmp/forever-exporter --output /tmp/forever-data --previous /path/to/state.json.gz
```

Der Linux-Exporter ist auf wow.tools.local 0.9.9 samt SHA-256 festgelegt. Er läuft
lokal mit `useWago=false`, ohne Community-CDN-Spiegel. CASC-Inhalte stammen aus
Blizzards CDN oder einer eigenen Installation. WoWDBDefs, Dateinamen und öffentliche
TACT-Schlüssel bleiben externe Formatbeschreibungen, keine Balance-Datenquellen.
Jede Tabelle wird ohne und mit Hotfix-Overlay exportiert. Verglichen werden IDs,
Felder, hinzugefügte und entfernte Zeilen, auch bei identischer Buildnummer.
Beschreibungen aus Patchnotes sind für die Erkennung nicht erforderlich.

Mit `--wow-folder /path/to/World\ of\ Warcraft` wird zusätzlich der dort vorhandene
Hotfix-Cache erfasst. Vorher Spiel schließen. Bei manchen Installationen liegt der
Cache im Produkt-Unterordner; `watch.py --cache-dir` kann diesen explizit angeben.
Der Cache muss auch vom lokalen Exporter geladen sein; ein Fingerabdruck allein
dekodiert keine Hotfixes. Ohne Cache lautet der Status ausdrücklich
`missing_client_cache`. Ein unveränderter Export ist dann kein Beleg, dass keine
Hotfixes existieren. Ein einzelner Cache ist keine vollständige globale Erhebung.

`report.json` trennt Client-Deltas, effektive Deltas und Hotfix-Overlay. Die erste
Erhebung ist ein Basisstand, keine Liste neu eingeführter Änderungen. Änderungen
werden zunächst als `documentationStatus=not_assessed` geführt: ohne Patchnote
gefunden bedeutet nicht automatisch undokumentiert. Serverseitige Regeln ohne
Client- oder Cache-Eintrag müssen durch kontrollierte Messungen im Spiel geprüft
werden. Tooltip-Differenzen allein beweisen keine Änderung an der Kampfberechnung.

Leere, fehlerhafte oder unvollständige Exporte ersetzen keine vorhandene Basis.
In dieser Arbeitsumgebung scheiterte der CASC-Start am CDN-Zugriff. Der direkte
Versionsabruf und die Vergleichslogik wurden geprüft; der vollständige Export ist
noch auf einem Rechner mit CDN-Zugang beziehungsweise eigener Installation zu prüfen.
