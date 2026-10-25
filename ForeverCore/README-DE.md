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
  überspringt einen Schritt, `/fr back` geht einen zurück, `/fr reset` beginnt von vorn.
- **Routen-Update:** ForeverCore holt beim Start und danach alle 12 Stunden die neuesten Routen und Daten von
  ForeverRoutes (geprüft per SHA-256; ein fehlerhafter Download ändert nichts). Abschalten: `"routesNoUpdate": true`
  in `config.json`.
- **Auktionshaus:** Leiste rechts am Fenster: Scannen, Berechnen, dann `/reload` – danach steht das beste Item je
  Platz in der Liste.

Alles Weitere (Befehle, Filter, Grenzen): `README.md`.
