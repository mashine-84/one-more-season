class_name Footballer
extends Node2D
## Ein Spieler auf dem Platz. Bewegung wird vom Match gesteuert (step),
## die Werte kommen aus PlayerData.

const RADIUS := 11.0

var daten: PlayerData
var team_idx: int = 0
var ist_torwart := false
var slot: int = 0                    # Position in der Formation (0–4), TW = -1
var farbe := Color.WHITE
var farbe_hell := Color.WHITE

var vel := Vector2.ZERO
var blick := Vector2.RIGHT
var wunsch_richtung := Vector2.ZERO  # vom Menschen oder der KI gesetzt
var wunsch_sprint := false
var wunsch_tempo := 1.0              # 0–1 Anteil der Höchstgeschwindigkeit

var kontrolliert := false            # vom Menschen gesteuert
var betaeubt := 0.0                  # nach misslungenem Tackling / Grätsche
var graetsche_zeit := 0.0
var graetsche_richtung := Vector2.ZERO
var graetsche_ball_beruehrt := false
var graetsche_getroffen: Array[Footballer] = []
var schuss_sperre := 0.0             # kurz nach eigenem Schuss/Pass nicht sofort wieder annehmen
var tackling_cooldown := 0.0
var platzverweis := false
var ausgewechselt := false
var leicht_verletzt := false
var gelb_im_spiel := 0
var pressing_zeit := 0.0             # vom Mitspieler angefordertes Pressing
var halte_zeit := 0.0                # Torwart hält den Ball


func ist_aktiv() -> bool:
	return not platzverweis and not ausgewechselt and visible


func kann_handeln() -> bool:
	return ist_aktiv() and betaeubt <= 0.0 and graetsche_zeit <= 0.0


func hoechstgeschwindigkeit() -> float:
	var v := MatchRules.laufgeschwindigkeit(daten.wert("tempo"))
	if leicht_verletzt:
		v *= 0.85
	return v


func step(delta: float) -> void:
	betaeubt = maxf(0.0, betaeubt - delta)
	schuss_sperre = maxf(0.0, schuss_sperre - delta)
	tackling_cooldown = maxf(0.0, tackling_cooldown - delta)
	pressing_zeit = maxf(0.0, pressing_zeit - delta)

	if graetsche_zeit > 0.0:
		graetsche_zeit -= delta
		var t := clampf(graetsche_zeit / 0.45, 0.0, 1.0)
		vel = graetsche_richtung * (130.0 + 260.0 * t)
		if graetsche_zeit <= 0.0:
			betaeubt = 0.55
			vel = Vector2.ZERO
	elif betaeubt > 0.0:
		vel = vel.move_toward(Vector2.ZERO, 900.0 * delta)
	else:
		var max_v := hoechstgeschwindigkeit() * wunsch_tempo
		var sprint := wunsch_sprint and daten.fitness > 15.0 and wunsch_richtung.length() > 0.1
		if sprint:
			max_v *= 1.32
		var ziel := wunsch_richtung.limit_length(1.0) * max_v
		var beschl := 950.0 if ziel.length() > vel.length() else 1300.0
		vel = vel.move_toward(ziel, beschl * delta)
		daten.fitness = maxf(0.0, daten.fitness - MatchRules.fitness_verlust(daten.wert("ausdauer"), sprint) * delta)
	if vel.length() > 5.0:
		blick = vel.normalized()
	position += vel * delta
	# Spieler dürfen etwas über die Linien hinaus, aber nicht in die Banden
	var feld := Pitch.FELD.grow(18.0)
	position = position.clamp(feld.position, feld.end)
	queue_redraw()


func starte_graetsche(richtung: Vector2) -> void:
	graetsche_richtung = richtung.normalized() if richtung.length() > 0.1 else blick
	graetsche_zeit = 0.45
	graetsche_ball_beruehrt = false
	graetsche_getroffen.clear()
	tackling_cooldown = 1.2


func _draw() -> void:
	if not ist_aktiv():
		return
	var font := ThemeDB.fallback_font
	draw_circle(Vector2(2, 3), RADIUS, Color(0, 0, 0, 0.3))
	if graetsche_zeit > 0.0:
		# liegend: in Laufrichtung gestreckt
		var a := graetsche_richtung.angle()
		draw_set_transform(Vector2.ZERO, a, Vector2(1.6, 0.75))
		draw_circle(Vector2.ZERO, RADIUS, farbe)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	else:
		var koerper := farbe
		if ist_torwart:
			koerper = farbe_hell
		if betaeubt > 0.0:
			koerper = koerper.darkened(0.35)
		draw_circle(Vector2.ZERO, RADIUS, koerper)
		draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 20, Color(0, 0, 0, 0.6), 1.5)
		draw_line(blick * (RADIUS - 1), blick * (RADIUS + 4), Color(1, 1, 1, 0.9), 2.5)
	var nr := str(daten.rueckennummer)
	var nr_breite := font.get_string_size(nr, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(-nr_breite / 2.0, 4.5), nr, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.BLACK if ist_torwart else Color.WHITE)
	if kontrolliert:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, -27), Vector2(6, -27), Vector2(0, -19)]), Color("#f7dc6f"))
		var name_text := daten.nachname
		var nb := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(font, Vector2(-nb / 2.0, -31), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		# Fitnessbalken
		draw_rect(Rect2(-12, 14, 24, 3), Color(0, 0, 0, 0.5))
		var fit_farbe := Color("#58d68d") if daten.fitness > 60 else (Color("#f4d03f") if daten.fitness > 35 else Color("#e74c3c"))
		draw_rect(Rect2(-12, 14, 24.0 * daten.fitness / 100.0, 3), fit_farbe)
	if leicht_verletzt:
		draw_string(font, Vector2(RADIUS, -RADIUS), "+", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#e74c3c"))
