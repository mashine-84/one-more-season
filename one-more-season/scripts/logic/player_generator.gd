class_name PlayerGenerator
extends RefCounted
## Erzeugt zufällige Spieler und Teams. Namen kommen aus data/namen.json
## (überschreibbar über mods/daten/namen.json).

const STANDARD_NAMEN := "res://data/namen.json"
const FELD_TRAITS: Array[String] = [
	"Kopfballstark", "Heißsporn", "Führungsspieler", "Glasknochen", "Joker",
]

var rng: RandomNumberGenerator
var _namen: Dictionary = {}
var _naechste_id: int = 1


func _init(seed_wert: int = -1) -> void:
	rng = RandomNumberGenerator.new()
	if seed_wert >= 0:
		rng.seed = seed_wert
	else:
		rng.randomize()
	var daten: Variant = ModPaths.lade_json("namen.json", STANDARD_NAMEN)
	if daten is Dictionary:
		_namen = daten
	if not _namen.has("vornamen") or (_namen["vornamen"] as Array).is_empty():
		_namen["vornamen"] = ["Max"]
	if not _namen.has("nachnamen") or (_namen["nachnamen"] as Array).is_empty():
		_namen["nachnamen"] = ["Muster"]
	if not _namen.has("vereine"):
		_namen["vereine"] = []


func vereine() -> Array:
	return _namen["vereine"]


func _wert(mitte: float) -> int:
	return clampi(roundi(rng.randfn(mitte, 2.3)), 1, 20)


func erzeuge_spieler(rolle: PlayerData.Rolle, staerke: float) -> PlayerData:
	var p := PlayerData.new()
	p.id = _naechste_id
	_naechste_id += 1
	var vn: Array = _namen["vornamen"]
	var nn: Array = _namen["nachnamen"]
	p.vorname = str(vn[rng.randi() % vn.size()])
	p.nachname = str(nn[rng.randi() % nn.size()])
	p.alter = rng.randi_range(18, 34)
	p.rolle = rolle
	var liste := PlayerData.TW_ATTRIBUTE if rolle == PlayerData.Rolle.TORWART else PlayerData.FELD_ATTRIBUTE
	for a in liste:
		p.attribute[a] = _wert(staerke)
	p.verletzungsanfaelligkeit = clampf(rng.randfn(1.0, 0.2), 0.5, 1.5)
	p.form = rng.randi_range(-1, 1)
	if rolle == PlayerData.Rolle.FELDSPIELER and rng.randf() < 0.3:
		p.traits.append(FELD_TRAITS[rng.randi() % FELD_TRAITS.size()])
	if p.hat_trait("Glasknochen"):
		p.verletzungsanfaelligkeit = 1.5
	if p.hat_trait("Heißsporn"):
		p.attribute["disziplin"] = clampi(int(p.attribute["disziplin"]) - 4, 1, 20)
		p.attribute["zweikampf"] = clampi(int(p.attribute["zweikampf"]) + 2, 1, 20)
	return p


## Kader: 2 Torhüter + 9 Feldspieler (11 gesamt, maximal 12 erlaubt).
func erzeuge_team(verein: Dictionary, staerke: float) -> TeamData:
	var t := TeamData.new()
	t.name = str(verein.get("name", "Unbenannt"))
	t.kurz = str(verein.get("kurz", "UNB"))
	t.farbe = Color.from_string(str(verein.get("farbe", "#888888")), Color.GRAY)
	t.farbe_hell = t.farbe.lightened(0.45)
	var nummer := 1
	for i in 2:
		var tw := erzeuge_spieler(PlayerData.Rolle.TORWART, staerke)
		tw.rueckennummer = 1 if i == 0 else 12
		t.kader.append(tw)
	for i in 9:
		nummer += 1
		var fs := erzeuge_spieler(PlayerData.Rolle.FELDSPIELER, staerke)
		fs.rueckennummer = nummer
		t.kader.append(fs)
	return t
