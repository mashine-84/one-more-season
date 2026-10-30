extends Node
## Legt die Steuerung beim Start an (Controller zuerst, Tastatur als Alternative).
## So bleibt project.godot schlank und die Belegung steht an einer Stelle.

const AKTIONEN := {
	# Aktion: [Tasten, Controller-Buttons]
	"om_pass": [[KEY_K, KEY_SPACE], [JOY_BUTTON_A]],
	"om_schuss": [[KEY_J], [JOY_BUTTON_B]],
	"om_steil": [[KEY_L], [JOY_BUTTON_X]],
	"om_lupfer": [[KEY_I], [JOY_BUTTON_Y]],
	"om_taktik": [[KEY_Q], [JOY_BUTTON_LEFT_SHOULDER]],
	"om_pause": [[KEY_ESCAPE, KEY_ENTER], [JOY_BUTTON_START]],
}


func _ready() -> void:
	for aktion: String in AKTIONEN:
		var belegung: Array = AKTIONEN[aktion]
		_neue_aktion(aktion)
		for key: int in belegung[0]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(aktion, ev)
		for btn: int in belegung[1]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			InputMap.action_add_event(aktion, jb)

	# Sprint: Shift oder rechter Trigger
	_neue_aktion("om_sprint")
	var shift := InputEventKey.new()
	shift.physical_keycode = KEY_SHIFT
	InputMap.action_add_event("om_sprint", shift)
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("om_sprint", rt)

	# Bewegung: WASD, Pfeiltasten, linker Stick
	_bewegung("om_links", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_bewegung("om_rechts", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_bewegung("om_hoch", [KEY_W, KEY_UP], JOY_AXIS_LEFT_Y, -1.0)
	_bewegung("om_runter", [KEY_S, KEY_DOWN], JOY_AXIS_LEFT_Y, 1.0)


func _neue_aktion(aktion: String) -> void:
	if InputMap.has_action(aktion):
		InputMap.action_erase_events(aktion)
	else:
		InputMap.add_action(aktion, 0.25)


func _bewegung(aktion: String, keys: Array, achse: JoyAxis, richtung: float) -> void:
	_neue_aktion(aktion)
	for key: int in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(aktion, ev)
	var jm := InputEventJoypadMotion.new()
	jm.axis = achse
	jm.axis_value = richtung
	InputMap.action_add_event(aktion, jm)
