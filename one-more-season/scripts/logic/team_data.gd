class_name TeamData
extends RefCounted
## Verein mit Kader. Kennt keine Darstellung.

var name: String = ""
var kurz: String = ""
var farbe: Color = Color.WHITE
var farbe_hell: Color = Color.WHITE
var kader: Array[PlayerData] = []
var formation: String = "2-2-1"
var spielstil: String = SpielStil.STANDARD_ID   ## wie die KI dieses Teams spielt


func verfuegbare() -> Array[PlayerData]:
	var out: Array[PlayerData] = []
	for p in kader:
		if p.ist_verfuegbar():
			out.append(p)
	return out


## Wählt 1 Torwart + 5 Feldspieler + bis zu 5 Ersatzspieler nach Stärke.
## Sind zu wenige Feldspieler fit, rückt notfalls ein Torwart ins Feld.
func auto_aufstellung() -> Dictionary:
	var fit := verfuegbare()
	fit.sort_custom(func(a: PlayerData, b: PlayerData) -> bool: return a.staerke() > b.staerke())
	var tw: PlayerData = null
	var feld: Array[PlayerData] = []
	var rest: Array[PlayerData] = []
	for p in fit:
		if p.ist_torwart() and tw == null:
			tw = p
		elif not p.ist_torwart() and feld.size() < 5:
			feld.append(p)
		else:
			rest.append(p)
	# Notlösungen, falls Spieler fehlen
	while feld.size() < 5 and not rest.is_empty():
		feld.append(rest.pop_front())
	if tw == null and not rest.is_empty():
		tw = rest.pop_front()
	var bank: Array[PlayerData] = []
	for p in rest:
		if bank.size() < 5:
			bank.append(p)
	return {"tw": tw, "feld": feld, "bank": bank}
