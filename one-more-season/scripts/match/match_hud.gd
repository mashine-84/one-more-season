extends Node2D
## Anzeige: Spielstand, Zeit, Meldungen, Schusskraft, Halbzeit- und Endbildschirm.

var match_ref: MatchController


func _draw() -> void:
	if match_ref == null:
		return
	var m := match_ref
	var font := ThemeDB.fallback_font
	# Kopfzeile
	draw_rect(Rect2(0, 0, 1152, 60), Color("#13202b"))
	var heim := m.teams[0]
	var gast := m.teams[1]
	draw_rect(Rect2(330, 12, 14, 36), heim.farbe)
	draw_rect(Rect2(808, 12, 14, 36), gast.farbe)
	_text(font, heim.name, Vector2(352, 38), 20, Color.WHITE)
	var gast_breite := font.get_string_size(gast.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	_text(font, gast.name, Vector2(800 - gast_breite, 38), 20, Color.WHITE)
	var stand := "%d : %d" % [m.ergebnis.tore[0], m.ergebnis.tore[1]]
	_zentriert(font, stand, Vector2(576, 40), 30, Color("#f7dc6f"))
	_zentriert(font, "%d'  ·  %d. Halbzeit" % [m.minute(), m.halbzeit], Vector2(576, 56), 12, Color(1, 1, 1, 0.7))
	_text(font, "Taktik: %s" % MatchController.TAKTIK_NAMEN[m.taktik[0]], Vector2(16, 24), 13, Color(1, 1, 1, 0.8))
	_text(font, "Wechsel: %d/%d" % [m.wechsel[0], MatchController.MAX_WECHSEL], Vector2(16, 44), 13, Color(1, 1, 1, 0.8))
	_text(font, "Unterzahl" if m.aktive(0).size() < 6 else "", Vector2(130, 44), 13, Color("#e74c3c"))
	_karten(font, m)

	# Schusskraft
	if m.schuss_laedt and m.kontrolliert:
		var p := m.kontrolliert.position + Vector2(-20, 20)
		draw_rect(Rect2(p, Vector2(40, 6)), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(p, Vector2(40 * m.schuss_kraft, 6)), Color("#f39c12").lerp(Color("#e74c3c"), m.schuss_kraft))

	# Meldungen unten
	draw_rect(Rect2(0, 622, 1152, 26), Color(0.07, 0.12, 0.17, 0.92))
	if not m.meldungen.is_empty():
		_text(font, m.meldungen[0], Vector2(16, 640), 14, Color.WHITE)
	_text(font, "K/A Pass · L/X Steil · I/Y Lupfer · J/B Schuss (halten) / Grätsche · L/X Tackling · Shift/RT Sprint · Q/LB Taktik",
		Vector2(470, 640), 11, Color(1, 1, 1, 0.5))

	_standard_hinweis(font, m)

	if m.gross_meldung_zeit > 0.0 and m.zustand != MatchController.Zustand.HALBZEIT:
		var a := clampf(m.gross_meldung_zeit * 2.0, 0.0, 1.0)
		draw_rect(Rect2(326, 300, 500, 70), Color(0, 0, 0, 0.55 * a))
		_zentriert(font, m.gross_meldung, Vector2(576, 346), 32, Color(1, 1, 1, a))

	if m.zustand == MatchController.Zustand.HALBZEIT:
		_halbzeit(font, m)
	elif m.zustand == MatchController.Zustand.ENDE:
		_ende(font, m)


func _karten(font: Font, m: MatchController) -> void:
	for t in 2:
		var x := 900 if t == 1 else 230
		var y := 20
		for f: Footballer in m.spieler[t]:
			if f.gelb_im_spiel > 0 or f.platzverweis:
				var c := Color("#e74c3c") if f.platzverweis else Color("#f4d03f")
				draw_rect(Rect2(x, y - 9, 7, 10), c)
				_text(font, f.daten.nachname, Vector2(x + 10, y), 10, Color(1, 1, 1, 0.75))
				y += 13
				if y > 58:
					break


func _halbzeit(font: Font, m: MatchController) -> void:
	draw_rect(Rect2(226, 120, 700, 430), Color(0.05, 0.08, 0.12, 0.95))
	_zentriert(font, "HALBZEIT  %d : %d" % [m.ergebnis.tore[0], m.ergebnis.tore[1]], Vector2(576, 160), 26, Color("#f7dc6f"))
	_zentriert(font, "Schüsse %d : %d   ·   Fouls %d : %d" % [m.ergebnis.schuesse[0], m.ergebnis.schuesse[1], m.ergebnis.fouls[0], m.ergebnis.fouls[1]],
		Vector2(576, 186), 14, Color(1, 1, 1, 0.75))
	_text(font, "Auf dem Platz", Vector2(260, 220), 15, Color.WHITE)
	_text(font, "Bank", Vector2(620, 220), 15, Color.WHITE)
	var feld := m.aktive(0, false)
	for i in feld.size():
		var f: Footballer = feld[i]
		var c := Color("#f7dc6f") if i == m.halbzeit_feld_auswahl else Color(1, 1, 1, 0.85)
		_text(font, "%2d %-14s  Fitness %3d%%%s" % [f.daten.rueckennummer, f.daten.nachname, int(f.daten.fitness), "  (gelb)" if f.gelb_im_spiel > 0 else ""],
			Vector2(260, 248 + i * 24), 14, c)
	var b: Array = m.bank[0]
	for i in b.size():
		var p: PlayerData = b[i]
		var c := Color("#f7dc6f") if i == m.halbzeit_bank_auswahl else Color(1, 1, 1, 0.85)
		_text(font, "%2d %-14s %s  Stärke %.1f" % [p.rueckennummer, p.nachname, "TW" if p.ist_torwart() else "  ", p.staerke()],
			Vector2(620, 248 + i * 24), 14, c)
	_zentriert(font, "Hoch/Runter: Feldspieler · Links/Rechts: Bank · K/A: Wechseln (%d/%d) · Esc/Start: Weiter" % [m.wechsel[0], MatchController.MAX_WECHSEL],
		Vector2(576, 530), 13, Color(1, 1, 1, 0.7))


func _ende(font: Font, m: MatchController) -> void:
	draw_rect(Rect2(226, 120, 700, 430), Color(0.05, 0.08, 0.12, 0.95))
	_zentriert(font, "ABPFIFF", Vector2(576, 160), 18, Color(1, 1, 1, 0.7))
	_zentriert(font, "%s  %d : %d  %s" % [m.teams[0].kurz, m.ergebnis.tore[0], m.ergebnis.tore[1], m.teams[1].kurz], Vector2(576, 198), 30, Color("#f7dc6f"))
	_zentriert(font, "Schüsse %d : %d   ·   Fouls %d : %d" % [m.ergebnis.schuesse[0], m.ergebnis.schuesse[1], m.ergebnis.fouls[0], m.ergebnis.fouls[1]],
		Vector2(576, 226), 14, Color(1, 1, 1, 0.75))
	var y := 262
	for e: Dictionary in m.ergebnis.ereignisse:
		if e["typ"] in ["tor", "gelb", "gelb_rot", "rot", "verletzung"] and y < 440:
			_text(font, "%2d'  %s  %s – %s" % [e["minute"], m.teams[e["team"]].kurz, e["text"], e["spieler"]], Vector2(270, y), 13, Color(1, 1, 1, 0.85))
			y += 18
	y = maxi(y + 8, 300)
	if not m.folgen.is_empty():
		_text(font, "Folgen fürs nächste Spiel:", Vector2(270, y), 14, Color("#f5b041"))
		y += 20
		for z in m.folgen:
			if y < 520:
				_text(font, z, Vector2(270, y), 13, Color(1, 1, 1, 0.85))
				y += 18
	_zentriert(font, "Esc/Start: Neues Spiel", Vector2(576, 535), 13, Color(1, 1, 1, 0.7))


func _text(font: Font, s: String, pos: Vector2, groesse: int, farbe: Color) -> void:
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, groesse, farbe)


func _zentriert(font: Font, s: String, pos: Vector2, groesse: int, farbe: Color) -> void:
	var b := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, groesse).x
	draw_string(font, Vector2(pos.x - b / 2.0, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, groesse, farbe)


const STANDARD_HILFE := {
	MatchController.Standard.ANSTOSS: "Anstoß: K/A Pass · L/X Steil · I/Y Lupfer",
	MatchController.Standard.EINWURF: "Einwurf: K/A kurz · I/Y oder J/B weit",
	MatchController.Standard.ECKE: "Ecke: K/A kurz · I/Y oder J/B Flanke",
	MatchController.Standard.ABSTOSS: "Abstoß: K/A Pass · I/Y Lupfer · J/B Abschlag (halten)",
	MatchController.Standard.FREISTOSS: "Freistoß: K/A Pass · L/X Steil · I/Y Lupfer · J/B Schuss (halten)",
	MatchController.Standard.ELFMETER: "Elfmeter: Richtung wählen · J/B halten und loslassen",
}


func _standard_hinweis(font: Font, m: MatchController) -> void:
	if m.zustand != MatchController.Zustand.LAEUFT or m.ball.besitzer == null:
		return
	var b := m.ball.besitzer
	if not m.ist_mensch(b.team_idx):
		return
	var text := ""
	if m.standard_laeuft and b == m.standard_ausfuehrer:
		text = STANDARD_HILFE[m.standard_typ]
		# Zielrichtung anzeigen
		for i in 5:
			var a := b.position + b.blick * (22.0 + i * 14.0)
			draw_line(a, a + b.blick * 7.0, Color(1, 1, 1, 0.8 - i * 0.12), 2.0)
	elif b.ist_torwart:
		text = "Torwart: K/A Pass · I/Y Lupfer · J/B Abschlag (halten) · noch %d s" % ceili(maxf(0.0, b.halte_zeit))
	if text == "":
		return
	var breite := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x + 24.0
	draw_rect(Rect2(576 - breite / 2.0, 110, breite, 26), Color(0, 0, 0, 0.6))
	_zentriert(font, text, Vector2(576, 128), 14, Color("#f7dc6f"))
