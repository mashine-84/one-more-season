class_name MatchRules
extends RefCounted
## Alle Formeln, die Stats in Spielverhalten übersetzen. Reine Funktionen,
## damit sie ohne Grafik getestet und gebalanced werden können.

enum Tackling { STEHEND, GRAETSCHE }
enum Karte { KEINE, GELB, ROT }
enum Verletzung { KEINE, LEICHT, MITTEL, SCHWER }

const SPERRE_GELB_ROT := 1
const SPERRE_ROT := 2
const GELB_FUER_SPERRE := 3


## Laufgeschwindigkeit in Pixel/Sekunde.
static func laufgeschwindigkeit(tempo: float) -> float:
	return 105.0 + tempo * 5.5


## Fitnessverlust pro Sekunde Echtzeit (Match = 2 × 4 Minuten).
static func fitness_verlust(ausdauer: float, sprint: bool) -> float:
	var basis := 0.035 * (21.0 - ausdauer) / 10.5
	return basis * (3.2 if sprint else 1.0)


## Winkelfehler beim Pass in Grad.
static func pass_streuung(passen: float) -> float:
	return (21.0 - passen) * 0.75


## Winkelfehler beim Schuss in Grad (kleinerer Zielkegel bei hohem Schuss).
static func schuss_streuung(schuss: float, kraft: float) -> float:
	return (21.0 - schuss) * 0.8 * (0.7 + kraft * 0.6)


static func schussgeschwindigkeit(schuss: float, kraft: float) -> float:
	return (380.0 + kraft * 520.0) * (0.75 + schuss * 0.0125)


## Chance, dass ein stehendes Tackling den Ball gewinnt.
static func tackling_erfolg(zweikampf: float, dribbling: float) -> float:
	return clampf(0.42 + (zweikampf - dribbling) * 0.035, 0.12, 0.88)


## Foulwahrscheinlichkeit = Tackling-Art × Winkel × Timing × Disziplin × Fitness.
## von_hinten: 0 (von vorne) bis 1 (genau von hinten).
static func foul_chance(art: Tackling, von_hinten: float, zu_spaet: bool,
		disziplin: float, fitness: float) -> float:
	var basis := 0.035 if art == Tackling.STEHEND else 0.12
	var winkel := 1.0 + 2.0 * clampf(von_hinten, 0.0, 1.0)
	var timing := 1.8 if zu_spaet else 1.0
	var disz := (21.0 - disziplin) / 10.5
	var fit := 1.0 + maxf(0.0, 60.0 - fitness) / 40.0
	return clampf(basis * winkel * timing * disz * fit, 0.0, 0.95)


## Welche Karte gibt es für ein Foul?
static func karte_fuer_foul(rng: RandomNumberGenerator, art: Tackling,
		von_hinten: float, notbremse: bool, disziplin: float) -> Karte:
	if notbremse:
		return Karte.ROT
	var disz := (21.0 - disziplin) / 10.5
	var art_f := 1.0 if art == Tackling.GRAETSCHE else 0.0
	var p_rot := (0.002 + 0.02 * art_f * von_hinten) * disz
	var p_gelb := (0.05 + 0.12 * art_f + 0.18 * von_hinten) * disz
	var r := rng.randf()
	if r < p_rot:
		return Karte.ROT
	if r < p_rot + p_gelb:
		return Karte.GELB
	return Karte.KEINE


static func verletzungs_chance(art: Tackling, von_hinten: float,
		anfaelligkeit: float) -> float:
	var art_f := 1.0 if art == Tackling.GRAETSCHE else 0.0
	return clampf((0.035 + 0.07 * art_f + 0.06 * von_hinten) * anfaelligkeit, 0.0, 0.6)


## Liefert {"stufe": Verletzung, "spiele": int}.
static func wuerfle_verletzung(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	if r < 0.6:
		return {"stufe": Verletzung.LEICHT, "spiele": 0}
	if r < 0.9:
		return {"stufe": Verletzung.MITTEL, "spiele": rng.randi_range(1, 2)}
	return {"stufe": Verletzung.SCHWER, "spiele": rng.randi_range(3, 6)}


## Chance des Torwarts, einen Schuss zu halten.
static func parade_chance(reflexe: float, eins_gegen_eins: float,
		ball_tempo: float, entfernung_schuetze: float) -> float:
	var tw := (reflexe * 0.7 + eins_gegen_eins * 0.3)
	var schwer := clampf((ball_tempo - 300.0) / 700.0, 0.0, 1.0)
	var nah := clampf(1.0 - entfernung_schuetze / 350.0, 0.0, 1.0)
	return clampf(0.75 + tw * 0.02 - schwer * 0.15 - nah * 0.06, 0.1, 0.95)


## Anzahl Sperrspiele nach einem Match für einen Spieler.
## gelb_im_spiel: Gelbe in diesem Spiel, rot: direkte Rote, gelb_rot: Gelb-Rot.
static func sperre_nach_spiel(p: PlayerData, gelb_im_spiel: int, rot: bool, gelb_rot: bool) -> int:
	var sperre := 0
	if rot:
		sperre += SPERRE_ROT
	elif gelb_rot:
		sperre += SPERRE_GELB_ROT
	elif gelb_im_spiel > 0:
		p.gelbe_karten_saison += gelb_im_spiel
		if p.gelbe_karten_saison >= GELB_FUER_SPERRE:
			p.gelbe_karten_saison -= GELB_FUER_SPERRE
			sperre += 1
	return sperre
