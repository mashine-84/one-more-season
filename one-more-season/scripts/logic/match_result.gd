class_name MatchResult
extends RefCounted
## Ergebnis und Statistik eines Spiels. Wird später an Liga und Tabelle übergeben.

var heim: TeamData
var gast: TeamData
var tore: Array[int] = [0, 0]
var schuesse: Array[int] = [0, 0]
var fouls: Array[int] = [0, 0]
var ereignisse: Array[Dictionary] = []   # {"minute", "team", "typ", "spieler", "text"}

## Pro Spieler-ID: {"gelb": int, "rot": bool, "gelb_rot": bool, "verletzung_spiele": int}
var spieler_status: Dictionary = {}


func status(p: PlayerData) -> Dictionary:
	if not spieler_status.has(p.id):
		spieler_status[p.id] = {"gelb": 0, "rot": false, "gelb_rot": false, "verletzung_spiele": 0}
	return spieler_status[p.id]


func ereignis(minute: int, team: int, typ: String, spieler: PlayerData, text: String) -> void:
	ereignisse.append({
		"minute": minute, "team": team, "typ": typ,
		"spieler": spieler.voller_name() if spieler else "", "text": text,
	})


## Schreibt Sperren und Verletzungen dauerhaft in die Spielerdaten.
## Gibt eine Liste lesbarer Folgen zurück.
func anwenden() -> Array[String]:
	var folgen: Array[String] = []
	for team in [heim, gast]:
		for p: PlayerData in team.kader:
			# Laufende Sperren/Verletzungen zählen ein Spiel herunter
			if p.sperre_spiele > 0:
				p.sperre_spiele -= 1
			if p.verletzung_spiele > 0:
				p.verletzung_spiele -= 1
			if not spieler_status.has(p.id):
				continue
			var s: Dictionary = spieler_status[p.id]
			var sperre := MatchRules.sperre_nach_spiel(p, s["gelb"], s["rot"], s["gelb_rot"])
			if sperre > 0:
				p.sperre_spiele += sperre
				folgen.append("%s (%s): %d Spiel(e) gesperrt" % [p.voller_name(), team.kurz, sperre])
			if s["verletzung_spiele"] > 0:
				p.verletzung_spiele = maxi(p.verletzung_spiele, s["verletzung_spiele"])
				folgen.append("%s (%s): %d Spieltag(e) verletzt" % [p.voller_name(), team.kurz, s["verletzung_spiele"]])
	return folgen
