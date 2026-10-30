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
		while m.zustand != MatchController.Zustand.ENDE and schritte < 60 * 60 * 12:
			m.step(1.0 / 60.0)
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
	# Grober Rahmen für KI gegen KI (2 × 4 Minuten). Feintuning passiert im Playtest.
	pruefe(summe["tore"] / n >= 2.0 and summe["tore"] / n <= 14.0, "Torschnitt plausibel (2–14)")
	pruefe(summe["rot"] / n <= 1.0, "Höchstens 1 Platzverweis pro Spiel im Schnitt")
	pruefe(summe["schuesse"] > 0, "Es wird geschossen")


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
