class_name PlayerData
extends RefCounted
## Reine Spielerdaten ohne Darstellung. Werte 1–20 wie im Fußball Manager.

enum Rolle { TORWART, FELDSPIELER }

const FELD_ATTRIBUTE: Array[String] = [
	"tempo", "ausdauer", "passen", "schuss",
	"dribbling", "zweikampf", "stellungsspiel", "disziplin",
]
const TW_ATTRIBUTE: Array[String] = [
	"reflexe", "strafraum", "abwurf", "eins_gegen_eins",
	"tempo", "ausdauer", "passen", "disziplin",
]

var id: int = 0
var vorname: String = ""
var nachname: String = ""
var alter: int = 24
var rolle: Rolle = Rolle.FELDSPIELER
var rueckennummer: int = 0
var attribute: Dictionary = {}

## Zustandswerte
var fitness: float = 100.0          # 0–100 %
var form: int = 0                   # −3 bis +3
var moral: int = 0                  # −3 bis +3
var verletzungsanfaelligkeit: float = 1.0  # versteckt, 0.5–1.5
var traits: Array[String] = []

## Saisonwerte
var gelbe_karten_saison: int = 0
var sperre_spiele: int = 0
var verletzung_spiele: int = 0


func voller_name() -> String:
	return "%s %s" % [vorname, nachname]


func ist_torwart() -> bool:
	return rolle == Rolle.TORWART


func ist_verfuegbar() -> bool:
	return sperre_spiele <= 0 and verletzung_spiele <= 0


## Grundwert ohne Form/Fitness.
func basiswert(name: String) -> int:
	return int(attribute.get(name, 10))


## Effektiver Wert im Match: Form addiert, unter 60 % Fitness sinkt alles.
func wert(name: String) -> float:
	var v := float(basiswert(name) + form)
	if fitness < 60.0:
		v *= 1.0 - (60.0 - fitness) / 100.0
	return clampf(v, 1.0, 20.0)


## Gesamtstärke für Aufstellung und Anzeige.
func staerke() -> float:
	var liste := TW_ATTRIBUTE if ist_torwart() else FELD_ATTRIBUTE
	var summe := 0.0
	for a in liste:
		if a == "disziplin":
			continue
		summe += basiswert(a)
	return summe / float(liste.size() - 1)


func hat_trait(t: String) -> bool:
	return traits.has(t)
