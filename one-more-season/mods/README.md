# Mods: eigene Banden und Namen

Dieser Ordner wird vom Spiel beim Start gelesen. Godot importiert ihn nicht (`.gdignore`).
Im fertigen Spiel liegt der Ordner `mods/` direkt neben der `.exe`.

## Werbebanden – `mods/banden/`

- Einfach PNG-, JPG- oder WEBP-Dateien hineinlegen.
- Empfohlenes Format: **340 × 52 Pixel** (Seitenverhältnis ca. 6,5 : 1).
- Die Bilder werden alphabetisch sortiert und reihum auf die Banden oben und unten verteilt.
- Ist der Ordner leer, zeigt das Spiel fiktive Platzhalter-Werbung.

## Namen – `mods/daten/namen.json`

- Kopiere `data/namen.json` aus dem Projekt nach `mods/daten/namen.json` und ändere sie dort.
- `vornamen` und `nachnamen`: Listen, aus denen zufällige Spieler gebaut werden.
- `vereine`: Name, Kürzel (3 Buchstaben) und Trikotfarbe als Hex-Wert.
- Ist die Datei fehlerhaft, nutzt das Spiel automatisch die Standardnamen.
