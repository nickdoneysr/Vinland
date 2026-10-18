extends Node
## The gamepad grammar from the MiniGames sheet, as Godot input actions (Backlog F08).
## Left stick gross, right stick fine, RT force, LT brace, LB/RB swap tool, A commit, B safe drop.
## Keyboard and mouse bindings are the fallback (Backlog F54), not the tuned target.

const DEADZONE := 0.18

## True when the last input came from the keyboard: digital keys get gentler handling (charged blows, eased sticks).
var keyboard := false

func _input(e: InputEvent) -> void:
	if e is InputEventKey:
		keyboard = true
	elif e is InputEventJoypadButton or (e is InputEventJoypadMotion and absf(e.axis_value) > 0.3):
		keyboard = false

func _ready() -> void:
	_axis("ls_left", JOY_AXIS_LEFT_X, -1.0, KEY_A)
	_axis("ls_right", JOY_AXIS_LEFT_X, 1.0, KEY_D)
	_axis("ls_up", JOY_AXIS_LEFT_Y, -1.0, KEY_W)
	_axis("ls_down", JOY_AXIS_LEFT_Y, 1.0, KEY_S)
	_axis("rs_left", JOY_AXIS_RIGHT_X, -1.0, KEY_LEFT)
	_axis("rs_right", JOY_AXIS_RIGHT_X, 1.0, KEY_RIGHT)
	_axis("rs_up", JOY_AXIS_RIGHT_Y, -1.0, KEY_UP)
	_axis("rs_down", JOY_AXIS_RIGHT_Y, 1.0, KEY_DOWN)
	_axis("rt", JOY_AXIS_TRIGGER_RIGHT, 1.0, KEY_SPACE)
	_axis("lt", JOY_AXIS_TRIGGER_LEFT, 1.0, KEY_SHIFT)
	_button("commit", JOY_BUTTON_A, KEY_ENTER)
	_button("drop", JOY_BUTTON_B, KEY_ESCAPE)
	_button("tool_next", JOY_BUTTON_RIGHT_SHOULDER, KEY_E)
	_button("tool_prev", JOY_BUTTON_LEFT_SHOULDER, KEY_Q)
	_button("menu", JOY_BUTTON_START, KEY_TAB)
	_button("alt", JOY_BUTTON_Y, KEY_F)          # secondary verb on voyage screens (fish)
	_button("ui_left_pad", JOY_BUTTON_DPAD_LEFT, KEY_Z)
	_button("ui_right_pad", JOY_BUTTON_DPAD_RIGHT, KEY_C)

func _axis(action: String, axis: JoyAxis, dir: float, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, DEADZONE)
	var j := InputEventJoypadMotion.new()
	j.axis = axis
	j.axis_value = dir
	InputMap.action_add_event(action, j)
	var k := InputEventKey.new()
	k.physical_keycode = key
	InputMap.action_add_event(action, k)

func _button(action: String, button: JoyButton, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var b := InputEventJoypadButton.new()
	b.button_index = button
	InputMap.action_add_event(action, b)
	var k := InputEventKey.new()
	k.physical_keycode = key
	InputMap.action_add_event(action, k)

func left_stick() -> Vector2:
	return Input.get_vector("ls_left", "ls_right", "ls_up", "ls_down")

func right_stick() -> Vector2:
	return Input.get_vector("rs_left", "rs_right", "rs_up", "rs_down")

## Vibration is the information channel; every call here must have a visual twin (Backlog F32).
func pulse(weak: float, strong: float, seconds: float) -> void:
	if Game.settings.get("haptics", true):
		for id in Input.get_connected_joypads():
			Input.start_joy_vibration(id, clampf(weak, 0, 1), clampf(strong, 0, 1), seconds)
