class_name MatchBall
extends Node2D
## Ball mit eigener, einfacher Physik (Bodenreibung, Höhe z für Lupfer/Schüsse).

const RADIUS := 5.0
const SCHWERKRAFT := 900.0
const BODEN_REIBUNG := 0.42     # Anteil Tempo, der pro Sekunde übrig bleibt
const LUFT_REIBUNG := 0.85

var vel := Vector2.ZERO
var z := 0.0
var vz := 0.0
var besitzer: Footballer = null
var letzter_kontakt: Footballer = null
var ist_schuss := false
var schuss_start := Vector2.ZERO
var ziel_spieler: Footballer = null   # für wen ein Pass gedacht ist


func step(delta: float) -> void:
	if besitzer != null:
		position = besitzer.position + besitzer.blick * (Footballer.RADIUS + 2.0)
		vel = besitzer.vel
		z = 0.0
		vz = 0.0
		ist_schuss = false
	else:
		position += vel * delta
		if z > 0.0 or vz > 0.0:
			vz -= SCHWERKRAFT * delta
			z += vz * delta
			vel *= pow(LUFT_REIBUNG, delta)
			if z <= 0.0:
				z = 0.0
				if vz < -90.0:
					vz = -vz * 0.38
					vel *= 0.8
				else:
					vz = 0.0
		else:
			vel *= pow(BODEN_REIBUNG, delta)
		if vel.length() < 140.0:
			ist_schuss = false
		if vel.length() < 4.0:
			vel = Vector2.ZERO
	queue_redraw()


func ist_frei() -> bool:
	return besitzer == null


func _draw() -> void:
	# Schatten am Boden, Ball um die Höhe nach oben versetzt
	draw_circle(Vector2(2, 2), RADIUS * 0.9, Color(0, 0, 0, 0.35))
	var hoehe := Vector2(0, -z * 0.6)
	var r := RADIUS * (1.0 + z / 120.0)
	draw_circle(hoehe, r, Color.WHITE)
	draw_arc(hoehe, r, 0, TAU, 16, Color(0.1, 0.1, 0.1), 1.2)
	draw_circle(hoehe + Vector2(-1.2, -1.2), r * 0.35, Color(0.15, 0.15, 0.15))
