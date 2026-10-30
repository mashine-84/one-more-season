class_name MatchController
extends Node2D
## Steuert ein 5+1-Match: Ablauf, Regeln, KI und die direkte Steuerung.

signal spiel_beendet(ergebnis: MatchResult)

enum Zustand { UNTERBRECHUNG, LAEUFT, HALBZEIT, ENDE }
enum Standard { ANSTOSS, EINWURF, ECKE, ABSTOSS, FREISTOSS, ELFMETER }
enum Taktik { DEFENSIV, AUSGEGLICHEN, OFFENSIV }

const TAKTIK_NAMEN := ["Defensiv", "Ausgeglichen", "Offensiv"]
const STANDARD_NAMEN := ["Anstoß", "Einwurf", "Ecke", "Abstoß", "Freistoß", "Elfmeter"]
## Abstand, den Gegner bei Freistoß, Einwurf, Ecke und Anstoß halten müssen.
const SCHUTZ_RADIUS := 60.0
## Wie lange der menschliche Torwart den Ball in der Hand halten darf.
const TW_HALTEZEIT_MENSCH := 6.0
const MAX_WECHSEL := 3
## Formation 2-2-1. x: 0 = eigenes Tor, 1 = gegnerisches Tor. y: 0 = oben, 1 = unten.
const FORMATION_221: Array[Vector2] = [
	Vector2(0.17, 0.3), Vector2(0.17, 0.7),
	Vector2(0.44, 0.24), Vector2(0.44, 0.76),
	Vector2(0.68, 0.5),
]

@export var halbzeit_sekunden := 120.0
@export var autoplay := false        ## Auch das eigene Team spielt per KI (Tests, Demo)
@export var seed_wert := -1

var teams: Array[TeamData] = []
var spieler: Array = [[], []]         # je Team: Array von Footballer
var bank: Array = [[], []]            # je Team: Array von PlayerData
var wechsel: Array[int] = [0, 0]
var taktik: Array[int] = [Taktik.AUSGEGLICHEN, Taktik.AUSGEGLICHEN]
var richtung: Array[int] = [1, -1]    # Angriffsrichtung in x je Team

var ball: MatchBall
var pitch: Pitch
var hud: Node2D
var rng := RandomNumberGenerator.new()
var ergebnis: MatchResult
var folgen: Array[String] = []
var _aktiv_cache: Dictionary = {}
var tor_arten: Array[String] = []   # Debug/Balancing: wie Tore entstehen
var statistik: Dictionary = {}       # Debug/Balancing: Zähler
var _schuss_hatte_parade := false

var zustand := Zustand.UNTERBRECHUNG
var halbzeit := 1
var spielzeit := 0.0
var pause_timer := 0.0
var standard_typ := Standard.ANSTOSS
var standard_team := 0
var standard_pos := Vector2.ZERO
var standard_ausfuehrer: Footballer
var standard_laeuft := false          # Ball liegt, Ausführender muss passen/flanken/schießen
var standard_ki_timer := 0.0

var kontrolliert: Footballer
var schuss_laedt := false
var schuss_kraft := 0.0
var meldungen: Array[String] = []
var gross_meldung := ""
var gross_meldung_zeit := 0.0
var halbzeit_feld_auswahl := 0
var halbzeit_bank_auswahl := 0


# ---------------------------------------------------------------- Aufbau

## Optional vor dem Hinzufügen zum Baum aufrufen, sonst werden Teams erzeugt.
func setup(heim: TeamData, gast: TeamData) -> void:
	teams = [heim, gast]


func _ready() -> void:
	if seed_wert >= 0:
		rng.seed = seed_wert
	else:
		rng.randomize()
	if teams.is_empty():
		var gen := PlayerGenerator.new(rng.randi())
		var vereine := gen.vereine()
		var heim_v: Dictionary = vereine[0] if vereine.size() > 0 else {}
		var gast_v: Dictionary = vereine[1 + rng.randi() % maxi(1, vereine.size() - 1)] if vereine.size() > 1 else {}
		teams = [gen.erzeuge_team(heim_v, 11.0), gen.erzeuge_team(gast_v, 10.5)]
	ergebnis = MatchResult.new()
	ergebnis.heim = teams[0]
	ergebnis.gast = teams[1]

	pitch = Pitch.new()
	add_child(pitch)
	for t in 2:
		var aufstellung := teams[t].auto_aufstellung()
		var tw: PlayerData = aufstellung["tw"]
		if tw:
			_erzeuge_footballer(t, tw, -1)
		var feld: Array = aufstellung["feld"]
		for i in feld.size():
			_erzeuge_footballer(t, feld[i], i)
		bank[t] = (aufstellung["bank"] as Array).duplicate()
	ball = MatchBall.new()
	ball.z_index = 5
	add_child(ball)
	hud = preload("res://scripts/match/match_hud.gd").new()
	hud.match_ref = self
	hud.z_index = 100
	add_child(hud)
	_unterbrechung(Standard.ANSTOSS, 0, Pitch.mitte(), 1.5)
	_gross("Anpfiff!", 1.5)


func _erzeuge_footballer(t: int, daten: PlayerData, slot: int) -> Footballer:
	var f := Footballer.new()
	f.daten = daten
	f.team_idx = t
	f.slot = slot
	f.ist_torwart = slot < 0
	f.farbe = teams[t].farbe
	f.farbe_hell = teams[t].farbe_hell
	add_child(f)
	(spieler[t] as Array).append(f)
	return f


# ---------------------------------------------------------------- Hilfen

func aktive(t: int, mit_torwart := true) -> Array[Footballer]:
	var key := t * 2 + (1 if mit_torwart else 0)
	if _aktiv_cache.has(key):
		return _aktiv_cache[key]
	var out: Array[Footballer] = []
	for f: Footballer in spieler[t]:
		if f.ist_aktiv() and (mit_torwart or not f.ist_torwart):
			out.append(f)
	_aktiv_cache[key] = out
	return out


## Nach Platzverweis/Wechsel neu aufbauen lassen.
func _cache_leeren() -> void:
	_aktiv_cache.clear()


func torwart(t: int) -> Footballer:
	for f: Footballer in spieler[t]:
		if f.ist_aktiv() and f.ist_torwart:
			return f
	return null


func minute() -> int:
	return mini(int((halbzeit - 1) * 45 + spielzeit / halbzeit_sekunden * 45.0) + 1, halbzeit * 45)


func besitz_team() -> int:
	return ball.besitzer.team_idx if ball.besitzer else -1


## Darf der Ball gerade nicht angegriffen werden?
## (Standard vor der Ausführung oder Torwart hält den Ball im Strafraum)
func ball_geschuetzt() -> bool:
	if standard_laeuft:
		return true
	var b := ball.besitzer
	return b != null and b.ist_torwart and Pitch.im_strafraum(b.position, -richtung[b.team_idx])


func ist_mensch(t: int) -> bool:
	return t == 0 and not autoplay


func _meldung(text: String) -> void:
	meldungen.push_front(text)
	if meldungen.size() > 4:
		meldungen.pop_back()


func _gross(text: String, dauer := 1.6) -> void:
	gross_meldung = text
	gross_meldung_zeit = dauer


## Wie weit ist der Ball aus Sicht von Team t nach vorne (0 eigenes Tor, 1 Gegnertor)?
func _fortschritt(t: int, pos: Vector2) -> float:
	var x := (pos.x - Pitch.FELD.position.x) / Pitch.FELD.size.x
	return x if richtung[t] == 1 else 1.0 - x


func _welt(t: int, norm: Vector2) -> Vector2:
	var x := norm.x if richtung[t] == 1 else 1.0 - norm.x
	return Pitch.FELD.position + Vector2(x * Pitch.FELD.size.x, norm.y * Pitch.FELD.size.y)


func formations_pos(f: Footballer, im_besitz: bool) -> Vector2:
	var t := f.team_idx
	var basis: Vector2 = FORMATION_221[clampi(f.slot, 0, 4)]
	var bp := _fortschritt(t, ball.position)
	var by := (ball.position.y - Pitch.FELD.position.y) / Pitch.FELD.size.y
	var x := basis.x + (bp - 0.5) * 0.38 + (0.12 if im_besitz else -0.05)
	x += (taktik[t] - 1) * 0.07
	var y := lerpf(basis.y, by, 0.22)
	return _welt(t, Vector2(clampf(x, 0.05, 0.93), clampf(y, 0.06, 0.94)))


func _naechster(t: int, pos: Vector2, ohne_torwart := true, ohne: Footballer = null) -> Footballer:
	var best: Footballer = null
	var bd := INF
	for f in aktive(t, not ohne_torwart):
		if f == ohne:
			continue
		var d := f.position.distance_to(pos)
		if d < bd:
			bd = d
			best = f
	return best


func _naechster_gegner_abstand(f: Footballer) -> float:
	var g := _naechster(1 - f.team_idx, f.position, false)
	return f.position.distance_to(g.position) if g else INF


func _von_hinten(taeter: Footballer, opfer: Footballer) -> float:
	var v := (taeter.position - opfer.position).normalized()
	return clampf(-opfer.blick.dot(v), 0.0, 1.0)


func _gehe_zu(f: Footballer, ziel: Vector2, tempo := 1.0) -> void:
	var diff := ziel - f.position
	var d := diff.length()
	f.wunsch_tempo = tempo
	if d < 5.0:
		f.wunsch_richtung = Vector2.ZERO
	else:
		f.wunsch_richtung = diff / d * minf(1.0, d / 45.0)


# ---------------------------------------------------------------- Hauptschleife

func _physics_process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	_cache_leeren()
	gross_meldung_zeit = maxf(0.0, gross_meldung_zeit - delta)
	match zustand:
		Zustand.LAEUFT:
			spielzeit += delta
			if spielzeit >= halbzeit_sekunden:
				_halbzeit_ende()
			else:
				if not autoplay:
					_mensch(delta)
				_ki(delta)
				_standard_regeln(delta)
				_bewege(delta)
				_schutzzonen()
				_torwart_in_der_hand()
				_ball_regeln()
		Zustand.UNTERBRECHUNG:
			pause_timer -= delta
			ball.step(delta)
			if pause_timer <= 0.0:
				_standard_ausfuehren()
		Zustand.HALBZEIT:
			if autoplay:
				_zweite_halbzeit()
			else:
				_halbzeit_eingabe()
		Zustand.ENDE:
			if not autoplay and Input.is_action_just_pressed("om_pause"):
				get_tree().reload_current_scene()
	hud.queue_redraw()


func _bewege(delta: float) -> void:
	for t in 2:
		for f in aktive(t):
			if ball.besitzer == f:
				f.wunsch_tempo *= 0.85
			f.step(delta)
	_kollisionen()
	ball.step(delta)
	if standard_laeuft:
		ball.position = standard_pos   # Ball liegt fest, der Spieler zielt nur


## Spieler können nicht durcheinander hindurchlaufen.
func _kollisionen() -> void:
	var alle: Array[Footballer] = []
	alle.append_array(aktive(0))
	alle.append_array(aktive(1))
	var min_abstand := Footballer.RADIUS * 2.0
	for i in alle.size():
		var a := alle[i]
		if a.graetsche_zeit > 0.0:
			continue
		for j in range(i + 1, alle.size()):
			var b := alle[j]
			if b.graetsche_zeit > 0.0:
				continue
			var v := b.position - a.position
			var d := v.length()
			if d < min_abstand and d > 0.01:
				var schub := v / d * (min_abstand - d) * 0.5
				if standard_laeuft and a == standard_ausfuehrer:
					b.position += schub * 2.0
				elif standard_laeuft and b == standard_ausfuehrer:
					a.position -= schub * 2.0
				else:
					a.position -= schub
					b.position += schub


# ---------------------------------------------------------------- Mensch

func _mensch(delta: float) -> void:
	# Den Torwart steuert man nur, solange er den Ball hat
	if kontrolliert == null or not kontrolliert.ist_aktiv() \
			or (kontrolliert.ist_torwart and ball.besitzer != kontrolliert):
		_wechsle_spieler()
	if kontrolliert == null:
		return
	var dir := Input.get_vector("om_links", "om_rechts", "om_hoch", "om_runter")
	var am_standard := standard_laeuft and ball.besitzer == kontrolliert
	if am_standard:
		# Beim Standard nur zielen, nicht laufen
		kontrolliert.wunsch_richtung = Vector2.ZERO
		if dir.length() > 0.2:
			kontrolliert.blick = dir.normalized()
	else:
		kontrolliert.wunsch_richtung = dir
	kontrolliert.wunsch_sprint = Input.is_action_pressed("om_sprint") and not am_standard
	kontrolliert.wunsch_tempo = 1.0

	if Input.is_action_just_pressed("om_taktik"):
		taktik[0] = (taktik[0] + 1) % 3
		_meldung("Taktik: %s" % TAKTIK_NAMEN[taktik[0]])

	if ball.besitzer == kontrolliert:
		var art: int = standard_typ if am_standard else -1
		var tw := kontrolliert.ist_torwart
		if tw:
			kontrolliert.halte_zeit -= delta
			if kontrolliert.halte_zeit <= 0.0:
				_meldung("6 Sekunden um – Abschlag")
				_abschlag(kontrolliert, dir, 0.7)
				return
		var nur_schuss := art == Standard.ELFMETER
		if Input.is_action_just_pressed("om_pass") and not nur_schuss:
			_mensch_pass(dir, false, false)
		elif Input.is_action_just_pressed("om_steil") and not nur_schuss:
			_mensch_pass(dir, true, false)
		elif Input.is_action_just_pressed("om_lupfer") and not nur_schuss:
			if art == Standard.ECKE:
				_flanke(kontrolliert, dir)
			else:
				_mensch_pass(dir, true, true)
		elif Input.is_action_pressed("om_schuss"):
			schuss_laedt = true
			schuss_kraft = minf(1.0, schuss_kraft + delta / 0.8)
		elif schuss_laedt:
			if tw:
				_abschlag(kontrolliert, dir, schuss_kraft)
			elif art == Standard.EINWURF:
				_mensch_pass(dir, false, true)
			elif art == Standard.ECKE:
				_flanke(kontrolliert, dir)
			else:
				_schiessen(kontrolliert, dir, schuss_kraft)
			schuss_laedt = false
			schuss_kraft = 0.0
	else:
		schuss_laedt = false
		schuss_kraft = 0.0
		if Input.is_action_just_pressed("om_pass"):
			_wechsle_spieler()
		elif Input.is_action_just_pressed("om_schuss"):
			if kontrolliert.kann_handeln() and kontrolliert.tackling_cooldown <= 0.0:
				var r := dir if dir.length() > 0.2 else (ball.position - kontrolliert.position)
				kontrolliert.starte_graetsche(r)
		elif Input.is_action_just_pressed("om_steil"):
			_stehendes_tackling(kontrolliert)
		elif Input.is_action_just_pressed("om_lupfer"):
			_pressing_anfordern(0)


func _setze_kontrolle(f: Footballer) -> void:
	if kontrolliert:
		kontrolliert.kontrolliert = false
	kontrolliert = f
	if f:
		f.kontrolliert = true


func _wechsle_spieler() -> void:
	var ziel := ball.position
	if ball.ist_frei() and ball.vel.length() > 50.0:
		ziel += ball.vel * 0.35
	_setze_kontrolle(_naechster(0, ziel, true, kontrolliert if kontrolliert and kontrolliert.ist_aktiv() and aktive(0, false).size() > 1 else null))


func _mensch_pass(dir: Vector2, steil: bool, lupfer: bool) -> void:
	var von := kontrolliert
	if dir.length() < 0.2:
		dir = von.blick
	var ziel := _mitspieler_in_richtung(von, dir)
	if ziel:
		_passen(von, ziel, steil, lupfer)
	else:
		_kick(von, dir.normalized() * 360.0, 220.0 if lupfer else 0.0)


func _mitspieler_in_richtung(von: Footballer, dir: Vector2) -> Footballer:
	var best: Footballer = null
	var best_wert := INF
	for m in aktive(von.team_idx, false):
		if m == von:
			continue
		var v := m.position - von.position
		var winkel := rad_to_deg(absf(dir.angle_to(v)))
		if winkel > 55.0:
			continue
		var wert := winkel * 1.2 + v.length() * 0.06
		if wert < best_wert:
			best_wert = wert
			best = m
	return best


func _pressing_anfordern(t: int) -> void:
	if besitz_team() != 1 - t:
		return
	var helfer := _naechster(t, ball.position, true, kontrolliert)
	if helfer:
		helfer.pressing_zeit = 3.0
		_meldung("%s presst!" % helfer.daten.nachname)


# ---------------------------------------------------------------- Ballaktionen

func _kick(von: Footballer, v: Vector2, vz := 0.0, schuss := false) -> void:
	if standard_laeuft:
		standard_laeuft = false
		_zaehle("standard_ausgefuehrt")
	var start := ball.position if ball.besitzer == von else von.position + v.normalized() * 12.0
	ball.besitzer = null
	ball.position = start
	ball.vel = v
	ball.vz = vz
	ball.z = 1.0 if vz > 0.0 else 0.0
	ball.letzter_kontakt = von
	ball.ist_schuss = schuss
	ball.schuss_start = von.position
	ball.ziel_spieler = null
	von.schuss_sperre = 0.35


func _passen(von: Footballer, an: Footballer, steil: bool, lupfer: bool) -> void:
	var ziel := an.position
	if steil:
		ziel += Vector2(richtung[von.team_idx], 0) * 75.0 + an.vel * 0.3
	ziel = ziel.clamp(Pitch.FELD.position + Vector2(10, 10), Pitch.FELD.end - Vector2(10, 10))
	var diff := ziel - von.position
	var dist := diff.length()
	var streuung := deg_to_rad(MatchRules.pass_streuung(von.daten.wert("passen")))
	var r := diff.normalized().rotated(rng.randf_range(-streuung, streuung) * 0.6)
	if lupfer:
		var vz := 230.0 + dist * 0.25
		var flugzeit := 2.0 * vz / MatchBall.SCHWERKRAFT
		_kick(von, r * (dist / flugzeit) * 0.92, vz)
	else:
		_kick(von, r * clampf(dist * 0.87 + 170.0, 230.0, 720.0))
	ball.ziel_spieler = an


## Hohe Hereingabe in den Strafraum (Ecke, Flanke). Mit Richtung: zum Mitspieler in dieser Richtung.
func _flanke(von: Footballer, dir := Vector2.ZERO) -> void:
	var t := von.team_idx
	var seite := richtung[t]
	var ziel_pos := Pitch.elfmeterpunkt(seite)
	var abnehmer: Footballer = null
	if dir.length() > 0.2:
		abnehmer = _mitspieler_in_richtung(von, dir)
	if abnehmer == null:
		abnehmer = _naechster(t, ziel_pos, true, von)
	if abnehmer and abnehmer.position.distance_to(Pitch.tor_mitte(seite)) < 220.0:
		ziel_pos = abnehmer.position
	ziel_pos += Vector2(rng.randf_range(-15.0, 15.0), rng.randf_range(-20.0, 20.0))
	var diff := ziel_pos - von.position
	var dist := diff.length()
	var streuung := deg_to_rad(MatchRules.pass_streuung(von.daten.wert("passen")))
	var r := diff.normalized().rotated(rng.randf_range(-streuung, streuung) * 0.5)
	var vz := 250.0 + dist * 0.18
	var flugzeit := 2.0 * vz / MatchBall.SCHWERKRAFT
	_kick(von, r * (dist / flugzeit) * 0.95, vz)
	ball.ziel_spieler = abnehmer


## Weiter Abschlag des Torwarts. Kraft 0–1 bestimmt die Weite.
func _abschlag(tw: Footballer, dir: Vector2, kraft: float) -> void:
	if dir.length() < 0.2:
		dir = Vector2(richtung[tw.team_idx], 0)
	_kick(tw, dir.normalized() * (380.0 + 300.0 * kraft), 200.0 + 160.0 * kraft)


func _schiessen(s: Footballer, dir: Vector2, kraft: float) -> void:
	var tor := Pitch.tor_mitte(richtung[s.team_idx])
	var zum_tor := (tor - s.position).normalized()
	var ziel: Vector2
	if dir.length() < 0.2:
		ziel = tor + Vector2(0, rng.randf_range(-0.6, 0.6) * Pitch.TOR_HALBE)
	elif dir.normalized().dot(zum_tor) > 0.25:
		ziel = tor + Vector2(0, clampf(dir.y, -1.0, 1.0) * Pitch.TOR_HALBE * 0.85)
	else:
		ziel = s.position + dir.normalized() * 400.0
	var streuung := deg_to_rad(MatchRules.schuss_streuung(s.daten.wert("schuss"), kraft))
	var r := (ziel - s.position).normalized().rotated(rng.randf_range(-streuung, streuung))
	var tempo := MatchRules.schussgeschwindigkeit(s.daten.wert("schuss"), kraft)
	var vz := rng.randf_range(0.0, 110.0) + kraft * 165.0
	ergebnis.schuesse[s.team_idx] += 1
	_zaehle("schuss_nah" if s.position.distance_to(tor) < 95.0 else "schuss")
	_schuss_hatte_parade = false
	var tw_g := torwart(1 - s.team_idx)
	if tw_g:
		statistik["tw_abstand_summe"] = float(statistik.get("tw_abstand_summe", 0.0)) + tw_g.position.distance_to(tor)
		if tw_g.betaeubt > 0.0:
			_zaehle("tw_blockiert_betaeubt")
		elif tw_g.schuss_sperre > 0.0:
			_zaehle("tw_blockiert_sperre")
		elif tw_g.graetsche_zeit > 0.0:
			_zaehle("tw_blockiert_graetsche")
	_kick(s, r * tempo, vz, true)


func _ballannahme(f: Footballer) -> void:
	ball.besitzer = f
	ball.letzter_kontakt = f
	ball.ist_schuss = false
	ball.ziel_spieler = null
	ball.z = 0.0
	ball.vz = 0.0
	if f.ist_torwart:
		f.halte_zeit = TW_HALTEZEIT_MENSCH if ist_mensch(f.team_idx) else 0.9
	if ist_mensch(f.team_idx):
		_setze_kontrolle(f)


func _stehendes_tackling(f: Footballer) -> void:
	if not f.kann_handeln() or f.tackling_cooldown > 0.0 or ball_geschuetzt():
		return
	f.tackling_cooldown = 0.7
	var gegner := ball.besitzer
	if gegner == null or gegner.team_idx == f.team_idx:
		return
	if f.position.distance_to(gegner.position) > 26.0:
		f.betaeubt = 0.25
		return
	var chance := MatchRules.tackling_erfolg(f.daten.wert("zweikampf"), gegner.daten.wert("dribbling"))
	if rng.randf() < chance:
		if rng.randf() < 0.6:
			_ballannahme(f)
		else:
			ball.besitzer = null
			ball.letzter_kontakt = f
			ball.vel = (gegner.position - f.position).normalized().rotated(rng.randf_range(-1.2, 1.2)) * 160.0
		gegner.betaeubt = 0.3
	else:
		f.betaeubt = 0.3
		var von_hinten := _von_hinten(f, gegner)
		var p := MatchRules.foul_chance(MatchRules.Tackling.STEHEND, von_hinten, false,
			f.daten.wert("disziplin"), f.daten.fitness)
		if rng.randf() < p:
			_foul(f, gegner, MatchRules.Tackling.STEHEND, von_hinten, true)


func _graetschen_pruefen() -> void:
	for t in 2:
		for f in aktive(t):
			if f.graetsche_zeit <= 0.0:
				continue
			if not f.graetsche_ball_beruehrt and not ball_geschuetzt() and ball.z < 10.0 \
					and f.position.distance_to(ball.position) < 17.0:
				f.graetsche_ball_beruehrt = true
				if ball.besitzer == null or ball.besitzer.team_idx != f.team_idx:
					if ball.besitzer:
						ball.besitzer.betaeubt = 0.35
					ball.besitzer = null
					ball.letzter_kontakt = f
					ball.ist_schuss = false
					ball.vel = f.graetsche_richtung.rotated(rng.randf_range(-0.5, 0.5)) * 230.0
			for g in aktive(1 - t):
				if f.graetsche_getroffen.has(g) or f.position.distance_to(g.position) > 17.0:
					continue
				f.graetsche_getroffen.append(g)
				var hatte_ball := ball.besitzer == g
				var von_hinten := _von_hinten(f, g)
				var zu_spaet := not hatte_ball and not f.graetsche_ball_beruehrt
				var p := 0.07
				if not f.graetsche_ball_beruehrt or zu_spaet:
					p = MatchRules.foul_chance(MatchRules.Tackling.GRAETSCHE, von_hinten, zu_spaet,
						f.daten.wert("disziplin"), f.daten.fitness)
				if rng.randf() < p:
					_foul(f, g, MatchRules.Tackling.GRAETSCHE, von_hinten, hatte_ball)
					return
				g.betaeubt = 0.45
				if hatte_ball:
					ball.besitzer = null
					ball.letzter_kontakt = f
					ball.vel = g.vel * 0.6


# ---------------------------------------------------------------- Fouls, Karten, Verletzungen

func _foul(taeter: Footballer, opfer: Footballer, art: MatchRules.Tackling, von_hinten: float, hatte_ball: bool) -> void:
	var t_opfer := opfer.team_idx
	ergebnis.fouls[taeter.team_idx] += 1
	var foul_pos := opfer.position
	var notbremse := hatte_ball and _ist_notbremse(taeter, opfer)
	var im_strafraum := Pitch.im_strafraum(foul_pos, richtung[t_opfer])
	var karte := MatchRules.karte_fuer_foul(rng, art, von_hinten, notbremse, taeter.daten.wert("disziplin"))
	# Keine Dreifachbestrafung: Notbremse im Strafraum mit Versuch, den Ball zu spielen = Elfmeter + Gelb
	if notbremse and im_strafraum:
		notbremse = false
		karte = MatchRules.Karte.GELB
	_meldung("Foul von %s an %s" % [taeter.daten.nachname, opfer.daten.nachname])
	ergebnis.ereignis(minute(), taeter.team_idx, "foul", taeter.daten, "Foul")
	var st := ergebnis.status(taeter.daten)
	if karte == MatchRules.Karte.GELB:
		taeter.gelb_im_spiel += 1
		if taeter.gelb_im_spiel >= 2:
			st["gelb_rot"] = true
			ergebnis.ereignis(minute(), taeter.team_idx, "gelb_rot", taeter.daten, "Gelb-Rot")
			_platzverweis(taeter, "GELB-ROT")
		else:
			st["gelb"] = int(st["gelb"]) + 1
			ergebnis.ereignis(minute(), taeter.team_idx, "gelb", taeter.daten, "Gelbe Karte")
			_gross("Gelb: %s" % taeter.daten.nachname, 1.4)
	elif karte == MatchRules.Karte.ROT:
		st["rot"] = true
		ergebnis.ereignis(minute(), taeter.team_idx, "rot", taeter.daten, "Notbremse" if notbremse else "Rote Karte")
		_platzverweis(taeter, "ROT%s" % (" (Notbremse)" if notbremse else ""))
	if rng.randf() < MatchRules.verletzungs_chance(art, von_hinten, opfer.daten.verletzungsanfaelligkeit):
		_verletzung(opfer)
	var elfmeter := im_strafraum
	if elfmeter:
		_gross("ELFMETER!", 1.6)
	_unterbrechung(Standard.ELFMETER if elfmeter else Standard.FREISTOSS, t_opfer, foul_pos, 1.6)


func _ist_notbremse(taeter: Footballer, opfer: Footballer) -> bool:
	var tor := Pitch.tor_mitte(richtung[opfer.team_idx])
	var d_opfer := opfer.position.distance_to(tor)
	# Klare Torchance: nah und zentral vor dem Tor
	if d_opfer > 230.0 or absf(opfer.position.y - tor.y) > 150.0:
		return false
	for d in aktive(taeter.team_idx, false):
		if d != taeter and d.position.distance_to(tor) < d_opfer:
			return false
	return true


func _platzverweis(f: Footballer, text: String) -> void:
	f.platzverweis = true
	f.visible = false
	_cache_leeren()
	if ball.besitzer == f:
		ball.besitzer = null
	if f == kontrolliert:
		_setze_kontrolle(null)
	_gross("%s: %s" % [text, f.daten.nachname], 1.8)
	_meldung("Platzverweis: %s (%s)" % [f.daten.nachname, teams[f.team_idx].kurz])


func _verletzung(f: Footballer) -> void:
	var v := MatchRules.wuerfle_verletzung(rng)
	if v["stufe"] == MatchRules.Verletzung.LEICHT:
		f.leicht_verletzt = true
		f.daten.fitness = maxf(0.0, f.daten.fitness - 20.0)
		_meldung("%s angeschlagen, spielt weiter" % f.daten.nachname)
		return
	ergebnis.status(f.daten)["verletzung_spiele"] = v["spiele"]
	ergebnis.ereignis(minute(), f.team_idx, "verletzung", f.daten, "Verletzt (%d Spiele)" % v["spiele"])
	_meldung("%s verletzt (%d Spiele)" % [f.daten.nachname, v["spiele"]])
	_auswechseln(f, true)


## Ersetzt f durch den besten passenden Bankspieler. Ohne Wechsel: Unterzahl.
func _auswechseln(f: Footballer, verletzt: bool, wunsch: PlayerData = null) -> bool:
	var t := f.team_idx
	var b: Array = bank[t]
	var neu: PlayerData = wunsch
	if neu == null and wechsel[t] < MAX_WECHSEL:
		var best_wert := -INF
		for p: PlayerData in b:
			var wert := p.staerke() + (20.0 if p.ist_torwart() == f.ist_torwart else 0.0)
			if wert > best_wert:
				best_wert = wert
				neu = p
	if neu == null or wechsel[t] >= MAX_WECHSEL:
		if verletzt:
			f.ausgewechselt = true
			f.visible = false
			_cache_leeren()
			if ball.besitzer == f:
				ball.besitzer = null
			if f == kontrolliert:
				_setze_kontrolle(null)
			_meldung("Keine Wechsel mehr: %s spielt in Unterzahl" % teams[t].kurz)
		return false
	b.erase(neu)
	wechsel[t] += 1
	var alt := f.daten
	f.daten = neu
	f.leicht_verletzt = false
	f.gelb_im_spiel = 0
	f.betaeubt = 0.0
	if not verletzt:
		b.append(alt)
	_meldung("Wechsel %s: %s für %s" % [teams[t].kurz, neu.nachname, alt.nachname])
	ergebnis.ereignis(minute(), t, "wechsel", neu, "für %s" % alt.voller_name())
	return true


# ---------------------------------------------------------------- Ballregeln

func _ball_regeln() -> void:
	_graetschen_pruefen()
	if zustand != Zustand.LAEUFT:
		return
	if ball.besitzer == null and ball.z < 45.0:
		_freier_ball()
	elif ball.besitzer:
		_ball_kontakt()
	if zustand == Zustand.LAEUFT:
		_aus_und_tore()


func _freier_ball() -> void:
	var best: Footballer = null
	var bd := INF
	var best_reichweite := 1.0
	for t in 2:
		for f in aktive(t):
			if not f.kann_handeln() or f.schuss_sperre > 0.0:
				continue
			var eigener_strafraum := f.ist_torwart and Pitch.im_strafraum(f.position, -richtung[t])
			var reichweite := 26.0 if eigener_strafraum else 15.0
			if eigener_strafraum and ball.ist_schuss:
				# Hechtsprung: Reichweite wächst mit den Reflexen
				reichweite = 34.0 + f.daten.wert("reflexe") * 1.8
			var max_hoehe := 45.0 if eigener_strafraum else 14.0
			if ball.z > max_hoehe:
				continue
			var d := f.position.distance_to(ball.position)
			if d < reichweite and d < bd:
				bd = d
				best = f
				best_reichweite = reichweite
	if best == null:
		return
	if ball.ist_schuss and ball.letzter_kontakt and ball.letzter_kontakt.team_idx != best.team_idx:
		if best.ist_torwart:
			_parade(best, bd / best_reichweite)
		else:
			# Block: Ball prallt ab
			_zaehle("block")
			best.schuss_sperre = 0.3
			ball.ist_schuss = false
			ball.letzter_kontakt = best
			ball.vel = -ball.vel.rotated(rng.randf_range(-0.9, 0.9)) * 0.35
		return
	_ballannahme(best)


## Läuft der Ballführer einem Gegner in die Beine, kann der den Ball erobern.
func _ball_kontakt() -> void:
	if ball_geschuetzt():
		return
	var owner := ball.besitzer
	for g in aktive(1 - owner.team_idx, false):
		if not g.kann_handeln() or g.tackling_cooldown > 0.0 or (ist_mensch(g.team_idx) and g == kontrolliert):
			continue
		if g.position.distance_to(ball.position) > 18.0:
			continue
		g.tackling_cooldown = 0.5
		var chance := MatchRules.tackling_erfolg(g.daten.wert("zweikampf"), owner.daten.wert("dribbling")) * 0.6
		if rng.randf() < chance:
			if rng.randf() < 0.5:
				_ballannahme(g)
			else:
				ball.besitzer = null
				ball.letzter_kontakt = g
				ball.vel = (ball.position - g.position).normalized().rotated(rng.randf_range(-1.0, 1.0)) * 150.0
			return


func _zaehle(key: String) -> void:
	statistik[key] = int(statistik.get(key, 0)) + 1


## streckung: 0 = Ball genau auf den Torwart, 1 = am Rand der Hechtreichweite.
func _parade(tw: Footballer, streckung: float) -> void:
	var tempo := ball.vel.length()
	var chance := MatchRules.parade_chance(tw.daten.wert("reflexe"), tw.daten.wert("eins_gegen_eins"),
		tempo, ball.schuss_start.distance_to(tw.position))
	chance *= lerpf(1.0, 0.75, clampf(streckung, 0.0, 1.0))
	_zaehle("parade_versuch")
	_schuss_hatte_parade = true
	if rng.randf() < chance:
		if tempo < 650.0 and rng.randf() < 0.6:
			_ballannahme(tw)
			_zaehle("gefangen")
			_meldung("%s hält!" % tw.daten.nachname)
		else:
			_zaehle("pariert")
			var angreifer := 1 - tw.team_idx
			if rng.randf() < 0.5:
				# Um den Pfosten gelenkt
				var eigen := -richtung[tw.team_idx]
				var ecke_y := Pitch.FELD.position.y if ball.position.y < Pitch.mitte().y else Pitch.FELD.end.y
				var ecke_x := Pitch.FELD.position.x if eigen < 0 else Pitch.FELD.end.x
				_meldung("Parade von %s – Ecke" % tw.daten.nachname)
				_unterbrechung(Standard.ECKE, angreifer, Vector2(ecke_x, ecke_y))
				return
			ball.ist_schuss = false
			ball.letzter_kontakt = tw
			# Zur Seite abwehren statt zurück in die Mitte
			var seitlich := signf(ball.position.y - Pitch.mitte().y)
			if seitlich == 0.0:
				seitlich = 1.0 if rng.randf() < 0.5 else -1.0
			ball.vel = Vector2(-ball.vel.x * 0.15, seitlich * tempo * rng.randf_range(0.6, 0.9))
			ball.vz = 160.0
			tw.schuss_sperre = 0.15
			_meldung("Parade von %s!" % tw.daten.nachname)
	else:
		tw.schuss_sperre = 0.35
		tw.betaeubt = 0.3


func _aus_und_tore() -> void:
	var p := ball.position
	var f := Pitch.FELD
	var letzt := ball.letzter_kontakt.team_idx if ball.letzter_kontakt else 0
	if p.x < f.position.x or p.x > f.end.x:
		var seite := -1 if p.x < f.position.x else 1
		var angreifer := 0 if richtung[0] == seite else 1
		var verteidiger := 1 - angreifer
		if absf(p.y - f.get_center().y) < Pitch.TOR_HALBE and ball.z < Pitch.TOR_HOEHE:
			_tor(angreifer)
		elif letzt == verteidiger:
			var ecke_y := f.position.y if p.y < f.get_center().y else f.end.y
			_unterbrechung(Standard.ECKE, angreifer, Vector2(f.position.x if seite < 0 else f.end.x, ecke_y))
		else:
			_unterbrechung(Standard.ABSTOSS, verteidiger, Pitch.tor_mitte(seite) - Vector2(seite * 45.0, 0))
	elif p.y < f.position.y or p.y > f.end.y:
		_unterbrechung(Standard.EINWURF, 1 - letzt, Vector2(p.x, f.position.y if p.y < f.position.y else f.end.y))


func _tor(t: int) -> void:
	tor_arten.append("besitz" if ball.besitzer else ("schuss" if ball.ist_schuss else "frei"))
	if ball.ist_schuss:
		_zaehle("tor_nach_parade" if _schuss_hatte_parade else "tor_ohne_parade")
	ergebnis.tore[t] += 1
	var schuetze := ball.letzter_kontakt
	var eigentor := schuetze != null and schuetze.team_idx != t
	var name := schuetze.daten.nachname if schuetze else "?"
	ergebnis.ereignis(minute(), t, "tor", schuetze.daten if schuetze else null, "Eigentor" if eigentor else "Tor")
	_gross("TOR! %s%s" % [name, " (ET)" if eigentor else ""], 2.4)
	_meldung("%d' Tor für %s – %s" % [minute(), teams[t].kurz, name])
	_unterbrechung(Standard.ANSTOSS, 1 - t, Pitch.mitte(), 2.4)


# ---------------------------------------------------------------- Unterbrechungen & Standards

func _unterbrechung(typ: Standard, t: int, pos: Vector2, dauer := 1.2) -> void:
	zustand = Zustand.UNTERBRECHUNG
	standard_laeuft = false
	pause_timer = dauer
	standard_typ = typ
	standard_team = t
	schuss_laedt = false
	schuss_kraft = 0.0
	ball.besitzer = null
	ball.vel = Vector2.ZERO
	ball.z = 0.0
	ball.vz = 0.0
	ball.ist_schuss = false
	match typ:
		Standard.ANSTOSS:
			standard_pos = Pitch.mitte()
		Standard.ELFMETER:
			standard_pos = Pitch.elfmeterpunkt(richtung[t])
		_:
			standard_pos = pos.clamp(Pitch.FELD.position, Pitch.FELD.end)
	ball.position = standard_pos
	_aufstellen()


func _aufstellen() -> void:
	var t := standard_team
	for tt in 2:
		for f in aktive(tt):
			f.vel = Vector2.ZERO
			f.betaeubt = 0.0
			f.graetsche_zeit = 0.0
			f.wunsch_richtung = Vector2.ZERO
			if f.ist_torwart:
				var eigen := -richtung[tt]
				f.position = Pitch.tor_mitte(eigen) - Vector2(eigen * 14.0, 0)
			elif standard_typ == Standard.ANSTOSS:
				var basis: Vector2 = FORMATION_221[clampi(f.slot, 0, 4)]
				f.position = _welt(tt, Vector2(minf(basis.x * 0.62, 0.43), basis.y))
			else:
				f.position = formations_pos(f, tt == t)
			f.queue_redraw()
	# Ausführender
	var ausfuehrer: Footballer
	if standard_typ == Standard.ABSTOSS:
		ausfuehrer = torwart(t)
	if ausfuehrer == null:
		ausfuehrer = _naechster(t, standard_pos, true)
	if ausfuehrer == null:
		ausfuehrer = _naechster(t, standard_pos, false)
	standard_ausfuehrer = ausfuehrer
	var zum_tor := Vector2(richtung[t], 0)
	if standard_typ in [Standard.EINWURF, Standard.ECKE]:
		zum_tor = (Pitch.mitte() - standard_pos).normalized()
	if ausfuehrer:
		ausfuehrer.position = standard_pos - zum_tor * 13.0
		ausfuehrer.blick = zum_tor
	# Gegner auf Abstand
	for g in aktive(1 - t):
		if g.ist_torwart and standard_typ == Standard.ELFMETER:
			continue
		var weg := g.position - standard_pos
		if weg.length() < 60.0:
			g.position = standard_pos + (weg.normalized() if weg.length() > 0.1 else -zum_tor) * 60.0
	if standard_typ == Standard.ELFMETER:
		var seite := richtung[t]
		for tt in 2:
			for f in aktive(tt):
				if f == ausfuehrer or f.ist_torwart:
					continue
				if Pitch.im_strafraum(f.position, seite):
					f.position.x = Pitch.tor_mitte(seite).x - seite * (Pitch.STRAFRAUM_TIEFE + 20.0)
	for tt in 2:
		for f in aktive(tt):
			f.position = f.position.clamp(Pitch.FELD.position - Vector2(14, 14), Pitch.FELD.end + Vector2(14, 14))
	if ist_mensch(t) and ausfuehrer:
		_setze_kontrolle(ausfuehrer)


func _standard_ausfuehren() -> void:
	zustand = Zustand.LAEUFT
	if standard_ausfuehrer == null or not standard_ausfuehrer.ist_aktiv():
		return
	ball.position = standard_pos
	_ballannahme(standard_ausfuehrer)
	standard_laeuft = true
	standard_ki_timer = rng.randf_range(0.5, 1.1)
	_zaehle("standard_%s" % STANDARD_NAMEN[standard_typ])


## Während eines Standards: Ausführender bleibt stehen, die KI entscheidet nach kurzer Zeit.
func _standard_regeln(delta: float) -> void:
	if not standard_laeuft:
		return
	var a := standard_ausfuehrer
	if a == null or not a.ist_aktiv() or ball.besitzer != a:
		standard_laeuft = false
		return
	a.wunsch_richtung = Vector2.ZERO
	a.wunsch_sprint = false
	if ist_mensch(a.team_idx):
		return
	standard_ki_timer -= delta
	if standard_ki_timer <= 0.0:
		_ki_standard(a)


func _ki_standard(a: Footballer) -> void:
	var t := a.team_idx
	var tor := Pitch.tor_mitte(richtung[t])
	match standard_typ:
		Standard.ELFMETER:
			_schiessen(a, Vector2(richtung[t], rng.randf_range(-0.9, 0.9)), rng.randf_range(0.6, 0.95))
		Standard.ECKE:
			if rng.randf() < 0.75:
				_flanke(a)
			else:
				_ki_standard_pass(a)
		Standard.FREISTOSS:
			var frei := not _schussbahn_zu(a, tor)
			if a.position.distance_to(tor) < 250.0 and frei and rng.randf() < 0.6:
				_schiessen(a, Vector2(richtung[t], rng.randf_range(-0.8, 0.8)), rng.randf_range(0.65, 1.0))
			elif _fortschritt(t, a.position) > 0.72 and rng.randf() < 0.5:
				_flanke(a)
			else:
				_ki_standard_pass(a)
		_:
			_ki_standard_pass(a)


func _ki_standard_pass(a: Footballer) -> void:
	var ziel := _bester_passempfaenger(a, true)
	if ziel == null:
		ziel = _naechster(a.team_idx, a.position, true, a)
	if ziel:
		_passen(a, ziel, false, a.position.distance_to(ziel.position) > 240.0)
	elif a.ist_torwart:
		_abschlag(a, Vector2.ZERO, 0.8)
	else:
		_kick(a, Vector2(richtung[a.team_idx], 0) * 380.0, 150.0)


## Gegner dürfen vor der Ausführung nicht in die Schutzzone.
func _schutzzonen() -> void:
	if not standard_laeuft:
		return
	var t := standard_team
	var gegner := 1 - t
	match standard_typ:
		Standard.ABSTOSS:
			# Gegner bleiben außerhalb des Strafraums
			var seite := -richtung[t]
			var linie := Pitch.tor_mitte(seite).x - seite * (Pitch.STRAFRAUM_TIEFE + Footballer.RADIUS + 2.0)
			for g in aktive(gegner):
				if Pitch.im_strafraum(g.position, seite) or absf(g.position.x - Pitch.tor_mitte(seite).x) < Pitch.STRAFRAUM_TIEFE + Footballer.RADIUS:
					if absf(g.position.y - Pitch.mitte().y) < Pitch.STRAFRAUM_HALBE + Footballer.RADIUS:
						g.position.x = linie
		Standard.ELFMETER:
			# Alle außer Schütze und Torwart bleiben außerhalb des Strafraums
			var seite := richtung[t]
			var tor := Pitch.tor_mitte(seite)
			var linie := tor.x - seite * (Pitch.STRAFRAUM_TIEFE + Footballer.RADIUS + 2.0)
			for tt in 2:
				for f in aktive(tt):
					if f == standard_ausfuehrer:
						continue
					if f.ist_torwart and tt == gegner:
						f.position.x = tor.x - seite * 10.0   # auf der Linie bleiben
						continue
					if Pitch.im_strafraum(f.position, seite) or f.position.distance_to(ball.position) < SCHUTZ_RADIUS:
						f.position.x = linie
		_:
			for g in aktive(gegner):
				var v := g.position - ball.position
				if v.length() < SCHUTZ_RADIUS:
					var n := v.normalized() if v.length() > 0.1 else Vector2(-richtung[t], 0)
					g.position = ball.position + n * SCHUTZ_RADIUS
				if standard_typ == Standard.ANSTOSS and _fortschritt(gegner, g.position) > 0.5:
					g.position.x = Pitch.mitte().x - richtung[gegner] * (Footballer.RADIUS + 1.0)


## Torwart mit Ball in der Hand bleibt im eigenen Strafraum.
func _torwart_in_der_hand() -> void:
	var tw := ball.besitzer
	if tw == null or not tw.ist_torwart:
		return
	var seite := -richtung[tw.team_idx]
	var tor := Pitch.tor_mitte(seite)
	var innen_x := tor.x - seite * (Pitch.STRAFRAUM_TIEFE - 4.0)
	var x_min := minf(tor.x, innen_x)
	var x_max := maxf(tor.x, innen_x)
	tw.position.x = clampf(tw.position.x, x_min + 2.0, x_max - 2.0)
	tw.position.y = clampf(tw.position.y, tor.y - Pitch.STRAFRAUM_HALBE + 4.0, tor.y + Pitch.STRAFRAUM_HALBE - 4.0)


# ---------------------------------------------------------------- Halbzeit & Ende

func _halbzeit_ende() -> void:
	if halbzeit == 1:
		zustand = Zustand.HALBZEIT
		_gross("Halbzeit", 1.0)
		halbzeit_feld_auswahl = 0
		halbzeit_bank_auswahl = 0
		for t in 2:
			for f in aktive(t):
				f.daten.fitness = minf(100.0, f.daten.fitness + 8.0)
	else:
		_spiel_ende()


func _halbzeit_eingabe() -> void:
	var feld := aktive(0, false)
	var b: Array = bank[0]
	if Input.is_action_just_pressed("ui_up"):
		halbzeit_feld_auswahl = posmod(halbzeit_feld_auswahl - 1, maxi(1, feld.size()))
	if Input.is_action_just_pressed("ui_down"):
		halbzeit_feld_auswahl = posmod(halbzeit_feld_auswahl + 1, maxi(1, feld.size()))
	if Input.is_action_just_pressed("ui_left"):
		halbzeit_bank_auswahl = posmod(halbzeit_bank_auswahl - 1, maxi(1, b.size()))
	if Input.is_action_just_pressed("ui_right"):
		halbzeit_bank_auswahl = posmod(halbzeit_bank_auswahl + 1, maxi(1, b.size()))
	if Input.is_action_just_pressed("om_pass") and not feld.is_empty() and not b.is_empty() and wechsel[0] < MAX_WECHSEL:
		var f: Footballer = feld[clampi(halbzeit_feld_auswahl, 0, feld.size() - 1)]
		var neu: PlayerData = b[clampi(halbzeit_bank_auswahl, 0, b.size() - 1)]
		_auswechseln(f, false, neu)
	if Input.is_action_just_pressed("om_pause"):
		_zweite_halbzeit()


func _zweite_halbzeit() -> void:
	halbzeit = 2
	spielzeit = 0.0
	richtung = [-1, 1]
	_gross("2. Halbzeit", 1.4)
	_unterbrechung(Standard.ANSTOSS, 1, Pitch.mitte(), 1.4)


func _spiel_ende() -> void:
	zustand = Zustand.ENDE
	_gross("Abpfiff", 2.0)
	folgen = ergebnis.anwenden()
	spiel_beendet.emit(ergebnis)


# ---------------------------------------------------------------- KI

func _ki(delta: float) -> void:
	var besitz := besitz_team()
	for t in 2:
		var mensch := ist_mensch(t)
		var jaeger := _naechster(t, ball.position + ball.vel * 0.2, true)
		for f in aktive(t):
			if mensch and f == kontrolliert:
				continue
			f.wunsch_sprint = false
			if f.ist_torwart:
				_ki_torwart(f, delta)
			elif ball.besitzer == f:
				if standard_laeuft:
					f.wunsch_richtung = Vector2.ZERO
				else:
					_ki_ballfuehrer(f, delta)
			elif besitz == t:
				_ki_freilaufen(f)
			elif besitz == -1:
				var mensch_naeher := mensch and kontrolliert != null \
					and kontrolliert.position.distance_to(ball.position) < f.position.distance_to(ball.position) * 1.3
				if f == jaeger and not mensch_naeher:
					_gehe_zu(f, ball.position + ball.vel * 0.25)
					f.wunsch_sprint = true
				elif ball.ziel_spieler == f:
					_gehe_zu(f, ball.position + ball.vel * 0.15)
				else:
					_gehe_zu(f, formations_pos(f, false), 0.8)
			else:
				var mensch_weit := mensch and (kontrolliert == null
					or kontrolliert.position.distance_to(ball.position) > 220.0)
				var nah_am_ball := f.position.distance_to(ball.position) < 45.0
				var soll_pressen := (f == jaeger and (not mensch or mensch_weit)) or f.pressing_zeit > 0.0 or nah_am_ball
				if soll_pressen:
					_ki_pressen(f, delta)
				elif f == _absicherer(t, jaeger):
					_ki_absichern(f)
				else:
					_ki_decken(f)
		_trennen(t)


func _ki_freilaufen(f: Footballer) -> void:
	var ziel := formations_pos(f, true)
	# Stürmer startet in die Tiefe
	if f.slot == 4:
		ziel.x += richtung[f.team_idx] * 30.0
	# Etwas Abstand zum nächsten Gegner suchen
	var g := _naechster(1 - f.team_idx, ziel, false)
	if g and g.position.distance_to(ziel) < 40.0:
		ziel += (ziel - g.position).normalized() * 25.0
	_gehe_zu(f, ziel, 0.9)


## Zweitnächster Spieler zum Ballführer sichert ab, wenn der Ball in der eigenen Hälfte ist.
func _absicherer(t: int, jaeger: Footballer) -> Footballer:
	if ball.besitzer == null or _fortschritt(t, ball.position) > 0.5:
		return null
	return _naechster(t, ball.position, true, jaeger)


func _ki_absichern(f: Footballer) -> void:
	var eigen_tor := Pitch.tor_mitte(-richtung[f.team_idx])
	_gehe_zu(f, ball.position.lerp(eigen_tor, 0.4))
	f.wunsch_sprint = f.position.distance_to(ball.position) > 120.0


func _ki_decken(f: Footballer) -> void:
	var ziel := formations_pos(f, false)
	var g := _naechster(1 - f.team_idx, ziel, true)
	if g:
		var eigen_tor := Pitch.tor_mitte(-richtung[f.team_idx])
		var torseitig := g.position + (eigen_tor - g.position).normalized() * 24.0
		ziel = ziel.lerp(torseitig, 0.55)
	_gehe_zu(f, ziel, 0.85)


func _ki_pressen(f: Footballer, delta: float) -> void:
	var gegner := ball.besitzer
	if gegner == null:
		return
	if ball_geschuetzt():
		# Nicht angreifen: auf Abstand gehen und decken
		_ki_decken(f)
		return
	var d := f.position.distance_to(gegner.position)
	_gehe_zu(f, gegner.position + gegner.vel * 0.2)
	f.wunsch_sprint = d > 70.0
	if f.tackling_cooldown > 0.0 or not f.kann_handeln():
		return
	var heisssporn := 1.0 if f.daten.hat_trait("Heißsporn") else 0.0
	if d < 24.0 and rng.randf() < delta * 4.0:
		_stehendes_tackling(f)
	elif d > 26.0 and d < 42.0 and rng.randf() < delta * (0.1 + 0.3 * heisssporn):
		f.starte_graetsche(gegner.position + gegner.vel * 0.15 - f.position)


func _ki_ballfuehrer(f: Footballer, delta: float) -> void:
	var t := f.team_idx
	var tor := Pitch.tor_mitte(richtung[t])
	var dist_tor := f.position.distance_to(tor)
	var druck := _naechster_gegner_abstand(f)
	if dist_tor < 270.0:
		var chance := delta * (0.45 if dist_tor < 180.0 else 0.08)
		if dist_tor < 95.0:
			chance = delta * 4.0
		if _schussbahn_zu(f, tor):
			chance *= 0.25
		if rng.randf() < chance:
			var y := rng.randf_range(-0.95, 0.95)
			_schiessen(f, Vector2(richtung[t], y).normalized(), rng.randf_range(0.55, 1.0))
			return
	if (druck < 48.0 and rng.randf() < delta * 3.5) or rng.randf() < delta * 0.5:
		var ziel := _bester_passempfaenger(f, druck < 48.0)
		if ziel:
			var dist := f.position.distance_to(ziel.position)
			_passen(f, ziel, rng.randf() < 0.3, dist > 220.0 and rng.randf() < 0.35)
			return
	var r := (tor - f.position).normalized()
	var g := _naechster(1 - t, f.position, false)
	if g and f.position.distance_to(g.position) < 70.0:
		var weg := (f.position - g.position).normalized()
		r = (r + weg * 0.9).normalized()
	# Nicht ins Seitenaus dribbeln
	var rand := 40.0
	if f.position.y < Pitch.FELD.position.y + rand:
		r.y = absf(r.y) + 0.3
	elif f.position.y > Pitch.FELD.end.y - rand:
		r.y = -absf(r.y) - 0.3
	f.wunsch_richtung = r.normalized()
	f.wunsch_tempo = 0.95
	f.wunsch_sprint = druck > 80.0 and f.daten.fitness > 40.0


## Steht ein Feldspieler des Gegners direkt in der Schussbahn?
func _schussbahn_zu(f: Footballer, tor: Vector2) -> bool:
	for g in aktive(1 - f.team_idx, false):
		if _abstand_zur_linie(g.position, f.position, tor) < 14.0:
			return true
	return false


func _bester_passempfaenger(f: Footballer, unter_druck: bool) -> Footballer:
	var t := f.team_idx
	var best: Footballer = null
	var best_wert := 0.15 if not unter_druck else -1.0
	for m in aktive(t, false):
		if m == f:
			continue
		var v := m.position - f.position
		var dist := v.length()
		if dist < 50.0 or dist > 420.0:
			continue
		var frei := INF
		for g in aktive(1 - t):
			frei = minf(frei, _abstand_zur_linie(g.position, f.position, m.position))
		if frei < 20.0:
			continue
		var vorwaerts := v.x * richtung[t] / 100.0
		var wert := vorwaerts + minf(frei, 80.0) / 40.0 - dist / 400.0
		if wert > best_wert:
			best_wert = wert
			best = m
	return best


func _abstand_zur_linie(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _ki_torwart(f: Footballer, delta: float) -> void:
	var t := f.team_idx
	var eigen := -richtung[t]
	var tor := Pitch.tor_mitte(eigen)
	if ball.besitzer == f:
		f.wunsch_richtung = Vector2.ZERO
		f.halte_zeit -= delta
		if f.halte_zeit <= 0.0 and not standard_laeuft:
			var ziel := _bester_passempfaenger(f, true)
			if ziel == null:
				ziel = _naechster(t, f.position, true, f)
			if ziel:
				_passen(f, ziel, false, f.position.distance_to(ziel.position) > 230.0)
			else:
				_kick(f, Vector2(richtung[t], 0) * 450.0, 200.0)
		return
	var b := ball.position
	var linie_x := tor.x - eigen * 14.0
	var ziel := tor - Vector2(eigen * 14.0, 0)
	var aufs_tor := ball.ist_frei() and signf(ball.vel.x) == float(eigen) and absf(ball.vel.x) > 40.0
	var y_ankunft := b.y
	if aufs_tor:
		var zeit := (linie_x - b.x) / ball.vel.x
		y_ankunft = b.y + ball.vel.y * maxf(zeit, 0.0)
		aufs_tor = absf(y_ankunft - tor.y) < Pitch.TOR_HALBE + 25.0
	if aufs_tor:
		# Schuss oder rollender Ball Richtung Tor: in die Bahn stellen
		ziel = Vector2(linie_x, clampf(y_ankunft, tor.y - Pitch.TOR_HALBE - 6.0, tor.y + Pitch.TOR_HALBE + 6.0))
		f.wunsch_sprint = true
	elif ball.besitzer and ball.besitzer.team_idx != t and not ball_geschuetzt() \
			and b.distance_to(tor) < 115.0 and f.position.distance_to(b) < 75.0:
		# Herauslaufen und dem Ballführer den Ball abnehmen
		ziel = b
		f.wunsch_sprint = true
		if f.position.distance_to(b) < 19.0 and f.kann_handeln() and f.tackling_cooldown <= 0.0:
			_torwart_greift_zu(f, ball.besitzer)
			return
	elif ball.ist_frei() and Pitch.im_strafraum(b, eigen):
		var gegner := _naechster(1 - t, b, false)
		if gegner == null or f.position.distance_to(b) < gegner.position.distance_to(b):
			ziel = b
			f.wunsch_sprint = true
		else:
			ziel = tor + (b - tor).normalized() * 34.0
	else:
		# Winkel verkürzen: je näher der Ball, desto weiter heraus
		var nah := clampf(1.0 - b.distance_to(tor) / 400.0, 0.0, 1.0)
		ziel = tor + (b - tor).normalized() * (20.0 + 30.0 * nah)
		ziel.y = clampf(ziel.y, tor.y - Pitch.TOR_HALBE * 0.9, tor.y + Pitch.TOR_HALBE * 0.9)
	_gehe_zu(f, ziel)


func _torwart_greift_zu(tw: Footballer, gegner: Footballer) -> void:
	tw.tackling_cooldown = 0.6
	var chance := clampf(0.5 + (tw.daten.wert("eins_gegen_eins") - gegner.daten.wert("dribbling")) * 0.03, 0.15, 0.85)
	if rng.randf() < chance:
		_ballannahme(tw)
		gegner.betaeubt = 0.3
		_meldung("%s schnappt sich den Ball" % tw.daten.nachname)
		return
	# Nicht gefangen, aber oft noch weggespitzelt. Der Torwart bleibt auf den Beinen.
	if rng.randf() < 0.5:
		ball.besitzer = null
		ball.letzter_kontakt = tw
		ball.vel = Vector2(richtung[tw.team_idx], rng.randf_range(-1.0, 1.0)).normalized() * 220.0
		gegner.betaeubt = 0.2
	var p := MatchRules.foul_chance(MatchRules.Tackling.GRAETSCHE, 0.0, false, tw.daten.wert("disziplin"), tw.daten.fitness) * 0.4
	if rng.randf() < p:
		_foul(tw, gegner, MatchRules.Tackling.GRAETSCHE, 0.0, true)


## KI-Spieler halten etwas Abstand zueinander, damit keine Klumpen entstehen.
func _trennen(t: int) -> void:
	var liste := aktive(t, false)
	for i in liste.size():
		var a: Footballer = liste[i]
		if a == kontrolliert or ball.besitzer == a:
			continue
		for j in liste.size():
			if i == j:
				continue
			var b: Footballer = liste[j]
			var d := a.position.distance_to(b.position)
			if d < 28.0 and d > 0.01:
				a.wunsch_richtung += (a.position - b.position) / d * (1.0 - d / 28.0) * 0.8
