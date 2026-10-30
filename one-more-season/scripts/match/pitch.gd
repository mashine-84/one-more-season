class_name Pitch
extends Node2D
## Spielfeld: Geometrie (statisch) und Darstellung inkl. Werbebanden.

const FELD := Rect2(116, 104, 920, 480)
const TOR_HALBE := 62.0
const TOR_TIEFE := 26.0
const TOR_HOEHE := 38.0
const STRAFRAUM_TIEFE := 115.0
const STRAFRAUM_HALBE := 115.0
const ELFMETER_ABSTAND := 82.0
const BANDE_HOEHE := 26.0
const BANDE_ABSTAND := 8.0

## Fiktive Platzhalter-Werbung, falls mods/banden leer ist.
const PLATZHALTER_WERBUNG := [
	["DEICHBRÄU", Color("#b03a2e"), Color.WHITE],
	["Möwen-Versicherung", Color("#1f618d"), Color.WHITE],
	["Kutter & Co.", Color("#f4d03f"), Color("#1c2833")],
	["NORDLICHT ENERGIE", Color("#117864"), Color.WHITE],
	["Fischbrötchen Hein", Color("#fdfefe"), Color("#154360")],
	["Salzwind Reisen", Color("#6c3483"), Color.WHITE],
]

var banden_texturen: Array[Texture2D] = []


static func mitte() -> Vector2:
	return FELD.get_center()


## seite: -1 = linkes Tor, +1 = rechtes Tor
static func tor_mitte(seite: int) -> Vector2:
	var x := FELD.position.x if seite < 0 else FELD.end.x
	return Vector2(x, FELD.get_center().y)


static func im_strafraum(pos: Vector2, seite: int) -> bool:
	var tor := tor_mitte(seite)
	if absf(pos.y - tor.y) > STRAFRAUM_HALBE:
		return false
	return absf(pos.x - tor.x) <= STRAFRAUM_TIEFE and signf(pos.x - tor.x) != float(seite)


static func elfmeterpunkt(seite: int) -> Vector2:
	return tor_mitte(seite) - Vector2(ELFMETER_ABSTAND * seite, 0)


func _ready() -> void:
	banden_texturen = ModPaths.lade_banden()
	z_index = -10


func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Umgebung
	draw_rect(Rect2(0, 60, 1152, 588), Color("#2d5a27"))
	# Rasen mit Streifen
	var streifen := 10
	var w := FELD.size.x / streifen
	for i in streifen:
		var c := Color("#3d8b37") if i % 2 == 0 else Color("#367d31")
		draw_rect(Rect2(FELD.position.x + i * w, FELD.position.y, w, FELD.size.y), c)
	var linie := Color(1, 1, 1, 0.85)
	draw_rect(FELD, linie, false, 2.0)
	var m := FELD.get_center()
	draw_line(Vector2(m.x, FELD.position.y), Vector2(m.x, FELD.end.y), linie, 2.0)
	draw_arc(m, 60, 0, TAU, 48, linie, 2.0)
	draw_circle(m, 3, linie)
	for seite in [-1, 1]:
		var tor := tor_mitte(seite)
		var sr := Rect2(
			Vector2(tor.x if seite < 0 else tor.x - STRAFRAUM_TIEFE, tor.y - STRAFRAUM_HALBE),
			Vector2(STRAFRAUM_TIEFE, STRAFRAUM_HALBE * 2))
		draw_rect(sr, linie, false, 2.0)
		draw_circle(elfmeterpunkt(seite), 3, linie)
		# Tor mit Netz
		var tor_rect := Rect2(
			Vector2(tor.x if seite > 0 else tor.x - TOR_TIEFE, tor.y - TOR_HALBE),
			Vector2(TOR_TIEFE, TOR_HALBE * 2))
		draw_rect(tor_rect, Color(1, 1, 1, 0.12))
		for i in range(1, 6):
			var x := tor_rect.position.x + tor_rect.size.x * i / 6.0
			draw_line(Vector2(x, tor_rect.position.y), Vector2(x, tor_rect.end.y), Color(1, 1, 1, 0.25), 1.0)
		for i in range(1, 10):
			var y := tor_rect.position.y + tor_rect.size.y * i / 10.0
			draw_line(Vector2(tor_rect.position.x, y), Vector2(tor_rect.end.x, y), Color(1, 1, 1, 0.25), 1.0)
		draw_rect(tor_rect, Color.WHITE, false, 3.0)
		draw_circle(Vector2(tor.x, tor.y - TOR_HALBE), 4, Color.WHITE)
		draw_circle(Vector2(tor.x, tor.y + TOR_HALBE), 4, Color.WHITE)
	# Werbebanden oben und unten
	var oben := Rect2(FELD.position.x - 40, FELD.position.y - BANDE_ABSTAND - BANDE_HOEHE, FELD.size.x + 80, BANDE_HOEHE)
	var unten := Rect2(FELD.position.x - 40, FELD.end.y + BANDE_ABSTAND, FELD.size.x + 80, BANDE_HOEHE)
	_zeichne_bande(oben, 0, font)
	_zeichne_bande(unten, 3, font)


func _zeichne_bande(bereich: Rect2, versatz: int, font: Font) -> void:
	var feld_breite := 170.0
	var anzahl := int(ceil(bereich.size.x / feld_breite))
	var breite := bereich.size.x / anzahl
	for i in anzahl:
		var r := Rect2(bereich.position.x + i * breite, bereich.position.y, breite - 2, bereich.size.y)
		if not banden_texturen.is_empty():
			var tex := banden_texturen[(i + versatz) % banden_texturen.size()]
			draw_texture_rect(tex, r, false)
		else:
			var w: Array = PLATZHALTER_WERBUNG[(i + versatz) % PLATZHALTER_WERBUNG.size()]
			draw_rect(r, w[1])
			var groesse := 13
			var text_breite := font.get_string_size(w[0], HORIZONTAL_ALIGNMENT_LEFT, -1, groesse).x
			var pos := Vector2(r.position.x + (r.size.x - text_breite) / 2.0, r.position.y + r.size.y / 2.0 + 5)
			draw_string(font, pos, w[0], HORIZONTAL_ALIGNMENT_LEFT, -1, groesse, w[2])
		draw_rect(r, Color(0, 0, 0, 0.35), false, 1.0)
