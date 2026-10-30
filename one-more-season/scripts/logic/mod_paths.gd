class_name ModPaths
extends RefCounted
## Ordner, die Spieler/Streamer selbst befüllen können.
## Im Editor: <Projekt>/mods/...  –  Im fertigen Spiel: <Spielordner>/mods/...


static func basis() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://mods")
	return OS.get_executable_path().get_base_dir().path_join("mods")


static func banden_ordner() -> String:
	return basis().path_join("banden")


static func daten_ordner() -> String:
	return basis().path_join("daten")


## Lädt eine JSON-Datei: zuerst die überschreibbare Version im Mod-Ordner,
## sonst die mitgelieferte Standardversion.
static func lade_json(dateiname: String, standard_pfad: String) -> Variant:
	var mod_pfad := daten_ordner().path_join(dateiname)
	for pfad in [mod_pfad, standard_pfad]:
		if FileAccess.file_exists(pfad):
			var text := FileAccess.get_file_as_string(pfad)
			var daten: Variant = JSON.parse_string(text)
			if daten != null:
				return daten
			push_warning("JSON fehlerhaft, ignoriert: %s" % pfad)
	return null


## Alle PNG/JPG-Bilder aus dem Banden-Ordner als Texturen.
static func lade_banden() -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	var ordner := banden_ordner()
	var dir := DirAccess.open(ordner)
	if dir == null:
		return out
	var dateien := dir.get_files()
	dateien.sort()
	for f in dateien:
		var ext := f.get_extension().to_lower()
		if ext not in ["png", "jpg", "jpeg", "webp"]:
			continue
		var img := Image.load_from_file(ordner.path_join(f))
		if img != null and not img.is_empty():
			out.append(ImageTexture.create_from_image(img))
	return out
