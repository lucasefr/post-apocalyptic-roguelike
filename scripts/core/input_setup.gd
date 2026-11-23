extends RefCounted
## Registers the input actions in code (physical keys, so WASD works on any
## keyboard layout). Edit here to remap controls.

const ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"attack": [KEY_SPACE],
	"inspect": [KEY_SHIFT],
	"cancel": [KEY_ESCAPE],
	"restart": [KEY_R],
	"slot_1": [KEY_1, KEY_KP_1],
	"slot_2": [KEY_2, KEY_KP_2],
	"slot_3": [KEY_3, KEY_KP_3],
	"slot_4": [KEY_4, KEY_KP_4],
}


static func ensure_actions() -> void:
	for action in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
