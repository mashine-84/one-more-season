extends SceneTree
## Headless-Tests und Balancing-Simulation.
## Aufruf:  godot --headless --path . --script res://tests/run_tests.gd
## Optional: -- --spiele=20   (Anzahl simulierter KI-gegen-KI-Spiele)

var fehler := 0


func _initialize() -> void:
	_laufen()


func _laufen() -> void:
	await process_frame
	var spiele := 10
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spiele="):
			spiele = int(arg.get_slice("=", 1))
	print("== Logik-Tests ==")
	_test_logik()
	print("== Simulation: %d Spiele KI gegen KI ==" % spiele)
	await _simulation(spiele)
	print("== Standards und Torwart ==")
	await _standard_tests()
	print("== Mensch-Steuerung mit zufälligen Eingaben ==")
	await _mensch_test()
	print("== %s (%d Fehler) ==" % ["OK" if fehler == 0 else "FEHLGESCHLAGEN", fehler])
	quit(1 if fehler > 0 else 0)


func pruefe(bedingung: bool, text: String) -> void:
	if bedingung:
		print("  ok   ", text)
	else:
		fehler += 1
		print("  FEHL ", text)


func _test_logik() -> void:
	var gen := PlayerGenerator.new(42)
	var team := gen.erzeuge_team(gen.vereine()[0], 11.0)
	pruefe(team.kader.size() == 11, "Kader hat 11 Spieler")
	pruefe(team.kader.filter(func(p: PlayerData) -> bool: return p.ist_torwart()).size() == 2, "Kader hat 2 Torhüter")
	var a := team.auto_aufstellung()
	pruefe(a["tw"] != null and (a["tw"] as PlayerData).ist_torwart(), "Aufstellung hat Torwart")
	pruefe((a["feld"] as Array).size() == 5, "Aufstellung hat 5 Feldspieler")

	# Gesperrte/verletzte Spieler fehlen in der Aufstellung
	var feld: Array = a["feld"]
	var gesperrt: PlayerData = feld[0]
	gesperrt.sperre_spiele = 1
	var a2 := team.auto_aufstellung()
	pruefe(not (a2["feld"] as Array).has(gesperrt) and not (a2["bank"] as Array).has(gesperrt), "Gesperrter Spieler nicht aufgestellt")
	gesperrt.sperre_spiele = 0

	# Fitness senkt Werte
	var p := PlayerData.new()
	p.attribute = {"tempo": 16}
	p.fitness = 100.0
	var voll := p.wert("tempo")
	p.fitness = 30.0
	pruefe(p.wert("tempo") < voll, "Niedrige Fitness senkt Attribute")

	# Foulchance: Grätsche von hinten > stehend von vorne, Disziplin wirkt
	var leicht := MatchRules.foul_chance(MatchRules.Tackling.STEHEND, 0.0, false, 12.0, 90.0)
	var hart := MatchRules.foul_chance(MatchRules.Tackling.GRAETSCHE, 1.0, true, 12.0, 90.0)
	pruefe(hart > leicht * 3.0, "Späte Grätsche von hinten deutlich foulträchtiger")
	pruefe(MatchRules.foul_chance(MatchRules.Tackling.STEHEND, 0.0, false, 4.0, 90.0) > leicht, "Wenig Disziplin = mehr Fouls")

	# Sperren
	var s := PlayerData.new()
	pruefe(MatchRules.sperre_nach_spiel(s, 0, true, false) == 2, "Rot sperrt 2 Spiele")
	pruefe(MatchRules.sperre_nach_spiel(s, 0, false, true) == 1, "Gelb-Rot sperrt 1 Spiel")
	var g := PlayerData.new()
	MatchRules.sperre_nach_spiel(g, 1, false, false)
	MatchRules.sperre_nach_spiel(g, 1, false, false)
	pruefe(MatchRules.sperre_nach_spiel(g, 1, false, false) == 1, "3. Gelbe sperrt 1 Spiel")

	# Notbremse ist immer Rot
	var rng := RandomNumberGenerator.new()
	pruefe(MatchRules.karte_fuer_foul(rng, MatchRules.Tackling.STEHEND, 0.0, true, 20.0) == MatchRules.Karte.ROT, "Notbremse = Rot")

	# Strafraum-Geometrie
	pruefe(Pitch.im_strafraum(Pitch.elfmeterpunkt(1), 1), "Elfmeterpunkt liegt im Strafraum")
	pruefe(not Pitch.im_strafraum(Pitch.mitte(), 1), "Mittelpunkt nicht im Strafraum")


func _simulation(anzahl: int) -> void:
	var summe := {"tore": 0, "schuesse": 0, "fouls": 0, "gelb": 0, "rot": 0, "verletzung": 0, "elfmeter": 0}
	var verstoesse := {"zone": 0, "bewegt": 0, "ballverlust": 0}
	var standards := 0
	for i in anzahl:
		var m := MatchController.new()
		m.autoplay = true
		m.seed_wert = 1000 + i
		root.add_child(m)
		if m.ball == null:
			await process_frame
		var schritte := 0
		var elf := 0
		var letzter_typ := -1
		var war_standard := false
		var start_pos := Vector2.ZERO
		while m.zustand != MatchController.Zustand.ENDE and schritte < 60 * 60 * 12:
			m.step(1.0 / 60.0)
			if m.standard_laeuft and not war_standard:
				start_pos = m.standard_ausfuehrer.position
				standards += 1
			if m.standard_laeuft:
				_pruefe_standard(m, start_pos, verstoesse)
			elif war_standard and m.zustand == MatchController.Zustand.LAEUFT and m.ball.besitzer != null \
					and m.ball.letzter_kontakt == m.standard_ausfuehrer:
				# Standard endete, ohne dass der Ball gespielt wurde
				verstoesse["ballverlust"] += 1
			war_standard = m.standard_laeuft
			if m.zustand == MatchController.Zustand.UNTERBRECHUNG and m.standard_typ != letzter_typ and m.standard_typ == MatchController.Standard.ELFMETER:
				elf += 1
			letzter_typ = m.standard_typ if m.zustand == MatchController.Zustand.UNTERBRECHUNG else -1
			schritte += 1
		var e := m.ergebnis
		pruefe(m.zustand == MatchController.Zustand.ENDE, "Spiel %d endet regulär" % (i + 1))
		var z := {"gelb": 0, "rot": 0, "verletzung": 0}
		for ev: Dictionary in e.ereignisse:
			if ev["typ"] == "gelb":
				z["gelb"] += 1
			elif ev["typ"] in ["rot", "gelb_rot"]:
				z["rot"] += 1
			elif ev["typ"] == "verletzung":
				z["verletzung"] += 1
		print("     %s %d:%d %s | Schüsse %d:%d | Fouls %d:%d | Gelb %d Rot %d Verl. %d Elfm. %d" % [
			e.heim.kurz, e.tore[0], e.tore[1], e.gast.kurz, e.schuesse[0], e.schuesse[1],
			e.fouls[0], e.fouls[1], z["gelb"], z["rot"], z["verletzung"], elf])
		summe["tore"] += e.tore[0] + e.tore[1]
		summe["schuesse"] += e.schuesse[0] + e.schuesse[1]
		summe["fouls"] += e.fouls[0] + e.fouls[1]
		summe["gelb"] += z["gelb"]
		summe["rot"] += z["rot"]
		summe["verletzung"] += z["verletzung"]
		summe["elfmeter"] += elf
		m.queue_free()
	var n := float(anzahl)
	print("  Schnitt pro Spiel: Tore %.1f · Schüsse %.1f · Fouls %.1f · Gelb %.1f · Rot %.2f · Verletzungen %.2f · Elfmeter %.2f" % [
		summe["tore"] / n, summe["schuesse"] / n, summe["fouls"] / n, summe["gelb"] / n,
		summe["rot"] / n, summe["verletzung"] / n, summe["elfmeter"] / n])
	print("  Standards: %d · Verstöße %s" % [standards, verstoesse])
	pruefe(standards > anzahl * 5, "Standards werden ausgeführt")
	pruefe(verstoesse["zone"] == 0, "Gegner bleiben bei Standards außerhalb der Schutzzone")
	pruefe(verstoesse["bewegt"] == 0, "Ausführender läuft beim Standard nicht los")
	pruefe(verstoesse["ballverlust"] == 0, "Standard endet immer mit Pass, Flanke oder Schuss")
	# Grober Rahmen für KI gegen KI (2 × 2 Minuten). Feintuning passiert im Playtest.
	pruefe(summe["tore"] / n >= 1.0 and summe["tore"] / n <= 8.0, "Torschnitt plausibel (1–8)")
	pruefe(summe["rot"] / n <= 1.0, "Höchstens 1 Platzverweis pro Spiel im Schnitt")
	pruefe(summe["schuesse"] > 0, "Es wird geschossen")


func _pruefe_standard(m: MatchController, start_pos: Vector2, v: Dictionary) -> void:
	var a := m.standard_ausfuehrer
	if a.position.distance_to(start_pos) > 3.0:
		v["bewegt"] += 1
	var t := m.standard_team
	for g in m.aktive(1 - t):
		match m.standard_typ:
			MatchController.Standard.ABSTOSS:
				if Pitch.im_strafraum(g.position, -m.richtung[t]):
					v["zone"] += 1
			MatchController.Standard.ELFMETER:
				if not g.ist_torwart and Pitch.im_strafraum(g.position, m.richtung[t]):
					v["zone"] += 1
			_:
				if g.position.distance_to(m.ball.position) < MatchController.SCHUTZ_RADIUS - 1.0:
					v["zone"] += 1


## Erzwingt einen Standard für das eigene Team und wartet, bis er freigegeben ist.
func _standard_erzwingen(m: MatchController, typ: MatchController.Standard, pos: Vector2) -> void:
	m._unterbrechung(typ, 0, pos, 0.2)
	while m.zustand != MatchController.Zustand.LAEUFT:
		m.step(1.0 / 60.0)


func _taste(m: MatchController, aktion: String, frames: int) -> void:
	Input.action_press(aktion)
	for i in frames:
		await process_frame
		m.step(1.0 / 60.0)
	Input.action_release(aktion)
	await process_frame
	m.step(1.0 / 60.0)


func _standard_tests() -> void:
	var m := MatchController.new()
	m.seed_wert = 21
	root.add_child(m)
	if m.ball == null:
		await process_frame

	# Freistoß: Ausführender wird gesteuert, läuft nicht los, Gegner halten Abstand
	_standard_erzwingen(m, MatchController.Standard.FREISTOSS, Pitch.mitte() + Vector2(-80, 40))
	var a := m.standard_ausfuehrer
	pruefe(m.kontrolliert == a and m.ball.besitzer == a and m.standard_laeuft, "Freistoß: eigener Ausführender hat den Ball")
	var start := a.position
	await _taste(m, "om_rechts", 40)
	pruefe(a.position.distance_to(start) < 3.0, "Freistoß: Spieler läuft nicht los, sondern zielt nur")
	pruefe(m.standard_laeuft and m.ball.besitzer == a, "Freistoß: Gegner nimmt den Ball nicht weg")
	var nah := false
	for g in m.aktive(1):
		if g.position.distance_to(m.ball.position) < MatchController.SCHUTZ_RADIUS - 1.0:
			nah = true
	pruefe(not nah, "Freistoß: alle Gegner außerhalb der Kreiszone")
	await _taste(m, "om_pass", 1)
	pruefe(not m.standard_laeuft and m.ball.besitzer != a, "Freistoß: Pass spielt den Ball")

	# Abstoß: eigener Torwart wird gesteuert und kann passen
	_standard_erzwingen(m, MatchController.Standard.ABSTOSS, Pitch.tor_mitte(-m.richtung[0]))
	var tw := m.torwart(0)
	pruefe(m.standard_ausfuehrer == tw and m.kontrolliert == tw, "Abstoß: eigener Torwart wird gesteuert")
	var im_raum := false
	for g in m.aktive(1):
		if Pitch.im_strafraum(g.position, -m.richtung[0]):
			im_raum = true
	pruefe(not im_raum, "Abstoß: kein Gegner im Strafraum")
	await _taste(m, "om_pass", 1)
	pruefe(m.ball.besitzer != tw and m.ball.letzter_kontakt == tw, "Abstoß: Torwart passt")

	# Torwart mit Ball in der Hand: Abschlag per Schuss-Taste
	m._ballannahme(tw)
	pruefe(m.kontrolliert == tw, "Gefangener Ball: Torwart wird gesteuert")
	await _taste(m, "om_schuss", 30)
	pruefe(m.ball.besitzer != tw and m.ball.letzter_kontakt == tw and m.ball.vel.length() > 300.0, "Torwart: Abschlag mit der Schuss-Taste")

	# Einwurf: Schuss-Taste wirft weit statt zu schießen
	var schuesse_vor := m.ergebnis.schuesse[0]
	_standard_erzwingen(m, MatchController.Standard.EINWURF, Vector2(Pitch.mitte().x, Pitch.FELD.position.y))
	await _taste(m, "om_schuss", 10)
	pruefe(not m.standard_laeuft and m.ergebnis.schuesse[0] == schuesse_vor, "Einwurf: kein Torschuss möglich")

	# Ecke: Flanke landet im Strafraum-Bereich
	var seite := m.richtung[0]
	_standard_erzwingen(m, MatchController.Standard.ECKE, Vector2(Pitch.FELD.end.x if seite > 0 else Pitch.FELD.position.x, Pitch.FELD.position.y))
	await _taste(m, "om_lupfer", 1)
	pruefe(not m.standard_laeuft and m.ball.z > 0.0, "Ecke: Flanke ist ein hoher Ball")
	m.queue_free()


## Spielt mit zufälligen Tasten, um alle Wege der direkten Steuerung zu durchlaufen.
func _mensch_test() -> void:
	pruefe(InputMap.has_action("om_pass"), "Steuerung ist angelegt")
	var m := MatchController.new()
	m.seed_wert = 5
	m.halbzeit_sekunden = 60.0
	root.add_child(m)
	if m.ball == null:
		await process_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var knoepfe := ["om_pass", "om_schuss", "om_steil", "om_lupfer", "om_sprint", "om_taktik"]
	var richtungen := ["om_links", "om_rechts", "om_hoch", "om_runter"]
	var gedrueckt: Array = []
	var schritte := 0
	var halbzeit_gesehen := false
	while m.zustand != MatchController.Zustand.ENDE and schritte < 60 * 60 * 4:
		if schritte % 12 == 0:
			for a in gedrueckt:
				Input.action_release(a)
			gedrueckt.clear()
			var r: String = richtungen[rng.randi() % richtungen.size()]
			Input.action_press(r)
			gedrueckt.append(r)
			if rng.randf() < 0.5:
				var k: String = knoepfe[rng.randi() % knoepfe.size()]
				Input.action_press(k)
				gedrueckt.append(k)
		if m.zustand == MatchController.Zustand.HALBZEIT:
			halbzeit_gesehen = true
			Input.action_press("om_pass")
			await process_frame
			Input.action_release("om_pass")
			Input.action_press("om_pause")
			await process_frame
			Input.action_release("om_pause")
		m.step(1.0 / 60.0)
		schritte += 1
		if schritte % 6 == 0:
			await process_frame
	for a in gedrueckt:
		Input.action_release(a)
	pruefe(halbzeit_gesehen, "Halbzeitbildschirm erreicht")
	pruefe(m.zustand == MatchController.Zustand.ENDE, "Spiel mit Mensch-Steuerung endet")
	print("     Ergebnis %d:%d, Wechsel %d, Schüsse %d" % [m.ergebnis.tore[0], m.ergebnis.tore[1], m.wechsel[0], m.ergebnis.schuesse[0]])
	m.queue_free()
