class_name SpielStil
extends RefCounted
## Wie eine KI-Mannschaft spielt. Die Werte kommen aus data/spielstile.json
## (überschreibbar über mods/daten/spielstile.json).

enum Drittel { ABWEHR, MITTELFELD, ANGRIFF }

const STANDARD_PFAD := "res://data/spielstile.json"
const STANDARD_ID := "ausgeglichen"
const DRITTEL_NAMEN := ["abwehr", "mittelfeld", "angriff"]

var id := STANDARD_ID
var name := "Ausgeglichen"
var beschreibung := ""
## je Drittel: {"fluegel": Gewicht, "zentrum": Gewicht}
var zonen: Array[Dictionary] = [
	{"fluegel": 1.0, "zentrum": 1.0}, {"fluegel": 1.0, "zentrum": 1.0}, {"fluegel": 1.0, "zentrum": 1.0},
]
var hoch_pass: Array[float] = [0.15, 0.15, 0.1]   # Anteil hoher Bälle je Drittel des Passgebers
var lang_pass: Array[float] = [0.0, 0.0, 0.0]     # Vorliebe für weite Pässe je Drittel
var pass_rate := 1.0          # wie schnell abgespielt wird
var dribbel_neigung := 0.5    # 0 = spielt sofort ab, 1 = dribbelt gern
var flanken_rate := 0.25      # Flanken pro Sekunde auf dem Flügel im Angriffsdrittel
var schuss_distanz := 1.0     # Faktor für die Entfernung, ab der geschossen wird
var breite := 1.0             # Formation: 1 = normal, >1 breiter
var hoehe := 0.0              # Formation: Verschiebung nach vorne (Anteil Feldlänge)
var pressing := 1.0           # Faktor für Zweikampfhäufigkeit
var langer_ball_aus_abwehr := false

static var _cache: Dictionary = {}


## Anteil 0–1, wie stark dieses Drittel die Flügel (true) bzw. das Zentrum (false) bevorzugt.
func zonen_anteil(drittel: int, fluegel: bool) -> float:
	var z: Dictionary = zonen[clampi(drittel, 0, 2)]
	var f := float(z.get("fluegel", 1.0))
	var m := float(z.get("zentrum", 1.0))
	if f + m <= 0.0:
		return 0.5
	return (f if fluegel else m) / (f + m)


func hoch_anteil(drittel: int) -> float:
	return hoch_pass[clampi(drittel, 0, 2)]


func lang_anteil(drittel: int) -> float:
	return lang_pass[clampi(drittel, 0, 2)]


static func drittel_aus_fortschritt(fortschritt: float) -> int:
	if fortschritt < 1.0 / 3.0:
		return Drittel.ABWEHR
	if fortschritt < 2.0 / 3.0:
		return Drittel.MITTELFELD
	return Drittel.ANGRIFF


static func alle() -> Dictionary:
	if _cache.is_empty():
		var daten: Variant = ModPaths.lade_json("spielstile.json", STANDARD_PFAD)
		if daten is Dictionary and daten.has("stile"):
			for d: Variant in daten["stile"]:
				if d is Dictionary:
					var s := aus_dict(d)
					_cache[s.id] = s
		if not _cache.has(STANDARD_ID):
			_cache[STANDARD_ID] = SpielStil.new()
	return _cache


static func ids() -> Array:
	return alle().keys()


static func hole(stil_id: String) -> SpielStil:
	var a := alle()
	return a.get(stil_id, a[STANDARD_ID])


static func aus_dict(d: Dictionary) -> SpielStil:
	var s := SpielStil.new()
	s.id = str(d.get("id", STANDARD_ID))
	s.name = str(d.get("name", s.id))
	s.beschreibung = str(d.get("beschreibung", ""))
	var z: Variant = d.get("zonen", {})
	if z is Dictionary:
		for i in 3:
			var eintrag: Variant = (z as Dictionary).get(DRITTEL_NAMEN[i], null)
			if eintrag is Dictionary:
				s.zonen[i] = {
					"fluegel": float(eintrag.get("fluegel", 1.0)),
					"zentrum": float(eintrag.get("zentrum", 1.0)),
				}
	s.hoch_pass = _drei(d.get("hoch_pass", null), s.hoch_pass)
	s.lang_pass = _drei(d.get("lang_pass", null), s.lang_pass)
	s.pass_rate = float(d.get("pass_rate", s.pass_rate))
	s.dribbel_neigung = float(d.get("dribbel_neigung", s.dribbel_neigung))
	s.flanken_rate = float(d.get("flanken_rate", s.flanken_rate))
	s.schuss_distanz = float(d.get("schuss_distanz", s.schuss_distanz))
	s.breite = float(d.get("breite", s.breite))
	s.hoehe = float(d.get("hoehe", s.hoehe))
	s.pressing = float(d.get("pressing", s.pressing))
	s.langer_ball_aus_abwehr = bool(d.get("langer_ball_aus_abwehr", false))
	return s


static func _drei(wert: Variant, standard: Array[float]) -> Array[float]:
	var out: Array[float] = standard.duplicate()
	if wert is Array and (wert as Array).size() >= 3:
		for i in 3:
			out[i] = clampf(float(wert[i]), 0.0, 1.0)
	return out
