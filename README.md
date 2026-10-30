# One More Season

Roguelite-Fußballmanager: Saisonkarte wie in Slay the Spire, Kader-Management wie im Fußball Manager und selbst gespielte 5+1-Matches in 2D.

Engine: **Godot 4.7.2**, Sprache: **GDScript**. Das Godot-Projekt liegt im Ordner `one-more-season/`.

## Stand: Match-Prototyp

Ein spielbares 5+1-Match (2 × 2 Minuten) gegen die KI:

- Direkte Steuerung eines Spielers, die KI steuert den Rest (Formation 2-2-1)
- Pässe, Steilpässe, Lupfer, Schüsse mit Kraftaufladung, stehendes Tackling, Grätsche, Sprint, Taktik
- Fouls, Freistöße, Elfmeter, Gelb, Gelb-Rot, Rot (inkl. Notbremse), Verletzungen mit Pflichtwechsel
- Standards (Anstoß, Einwurf, Ecke, Abstoß, Freistoß, Elfmeter): Der Ausführende bleibt stehen und muss passen, flanken oder schießen. Gegner dürfen vorher nicht angreifen. Beim Abstoß bleiben sie außerhalb des Strafraums, sonst gilt ein unsichtbarer Kreis von 60 px um den Ball
- Der eigene Torwart ist steuerbar, sobald er den Ball hat: Pass, Lupfer oder Abschlag, höchstens 6 Sekunden in der Hand
- Torwart: lässt sich nicht wegschieben und ist gegen Grätschen immun
- Anstoß: Beide Teams bleiben bis zur Ausführung in ihrer Hälfte. Einwurf: Mitspieler laufen sich kurz, zurück und in die Tiefe frei
- Halbzeit mit bis zu 3 Wechseln, Endbildschirm mit Sperren und Ausfällen fürs nächste Spiel
- Alle Werte kommen aus den Spieler-Stats (1–20) und wirken direkt im Spiel
- Werbebanden und Namen lassen sich über den Ordner `mods/` austauschen (siehe `one-more-season/mods/README.md`)

## Starten

1. Godot 4.7.2 öffnen und `one-more-season/project.godot` importieren.
2. **F5** drücken. Jeder Start erzeugt neue, zufällige Teams.

## Steuerung

| Aktion | Controller | Tastatur |
| --- | --- | --- |
| Laufen | Linker Stick | WASD / Pfeiltasten |
| Sprint | RT | Shift |
| Pass (ohne Ball: Spieler wechseln) | A | K / Leertaste |
| Schuss halten & loslassen (ohne Ball: Grätsche) | B | J |
| Steilpass (ohne Ball: stehendes Tackling) | X | L |
| Lupfer (ohne Ball: Pressing anfordern) | Y | I |
| Taktik wechseln | LB | Q |
| Weiter / neues Spiel | Start | Esc / Enter |

Bei Standards zielt der Stick nur, der Spieler läuft nicht. Oben im Bild steht, welche Taste was macht:

| Standard | Tasten |
| --- | --- |
| Freistoß, Anstoß | Pass, Steil, Lupfer, Schuss (halten) |
| Ecke | Pass kurz, Lupfer oder Schuss = Flanke |
| Einwurf | Pass kurz, Lupfer oder Schuss = weiter Wurf |
| Abstoß / Torwart mit Ball | Pass, Lupfer, Schuss (halten) = Abschlag |
| Elfmeter | Richtung wählen, Schuss halten und loslassen |

In der Halbzeit: Hoch/Runter wählt den Feldspieler, Links/Rechts den Bankspieler, A/K wechselt.

## Tests und Balancing

```
godot --headless --path one-more-season --script res://tests/run_tests.gd -- --spiele=12
```

Führt Logik-Tests aus, simuliert KI-gegen-KI-Spiele (inkl. Prüfung aller Standards auf Schutzzonen), testet Standards und Torwart mit simulierten Tasten und spielt ein Match mit zufälligen Eingaben. Am Ende stehen Durchschnittswerte (Tore, Fouls, Karten, Verletzungen, Elfmeter).

Aktueller Schnitt bei 12 Spielen (2 × 2 Minuten): **2,1 Tore, 6 Schüsse, 6 Fouls, 1,1 Gelb, 0,4 Verletzungen, 15 Standards pro Spiel.**

## Aufbau

```
one-more-season/
├── data/namen.json            Standardnamen und Vereine
├── mods/                      Überschreibbare Banden und Namen
├── scenes/match.tscn          Startszene
├── scripts/
│   ├── core/game_input.gd     Tastenbelegung (Autoload)
│   ├── logic/                 Spiellogik ohne Grafik: Spieler, Teams, Regeln, Ergebnis
│   └── match/                 Darstellung und Ablauf des Matches
└── tests/run_tests.gd         Tests und Simulation
```

Alle Formeln, die Stats in Spielverhalten übersetzen, stehen in `scripts/logic/match_rules.gd`. Dort setzt das Balancing an.
