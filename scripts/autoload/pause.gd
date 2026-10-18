extends CanvasLayer
## Pause and options (Backlog F51). Back / P anywhere in play: resume, difficulty, vibration, prompts,
## save and quit to the title. The tree pauses underneath; this layer keeps running.

const ROWS := ["resume", "difficulty", "vibration", "prompts", "quit"]

var open := false
var focus := 0
var _view: Control
var _font: Font

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.visible = false
	_view.draw.connect(_draw_menu)
	add_child(_view)

## Where the run stands: "voyage", "camp", or "" on the title, the loadout and practice screens.
func stage() -> String:
	if get_tree().get_first_node_in_group("camp_screen") != null and Game.camp != null:
		return "camp"
	if get_tree().get_first_node_in_group("voyage_screen") != null and Game.voyage != null:
		return "voyage"
	return ""

func can_pause() -> bool:
	var s := get_tree().current_scene
	return s != null and s.scene_file_path != "res://scenes/boot.tscn"

func show_menu() -> void:
	open = true
	focus = 0
	get_tree().paused = true
	_view.visible = true
	_view.queue_redraw()

func hide_menu() -> void:
	open = false
	get_tree().paused = false
	_view.visible = false
	Game.save_settings()

func _key(e: InputEvent, keys: Array) -> bool:
	return e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in keys

func _unhandled_input(e: InputEvent) -> void:
	if not open:
		if e.is_action_pressed("pause") and can_pause():
			get_viewport().set_input_as_handled()
			show_menu()
		return
	get_viewport().set_input_as_handled()
	if e.is_action_pressed("pause") or e.is_action_pressed("drop"):
		hide_menu()
	elif e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down") or _key(e, [KEY_S]):
		focus = (focus + 1) % ROWS.size()
	elif e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up") or _key(e, [KEY_W]):
		focus = (focus + ROWS.size() - 1) % ROWS.size()
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right") or _key(e, [KEY_D]):
		change(ROWS[focus], 1)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left") or _key(e, [KEY_A]):
		change(ROWS[focus], -1)
	elif e.is_action_pressed("commit"):
		match ROWS[focus]:
			"resume": hide_menu()
			"quit": save_and_quit()
			_: change(ROWS[focus], 1)
	_view.queue_redraw()

func change(row: String, d: int) -> void:
	match row:
		"difficulty":
			var i := Game.DIFFICULTIES.find(Game.settings.difficulty)
			Game.settings.difficulty = Game.DIFFICULTIES[clampi(i + d, 0, Game.DIFFICULTIES.size() - 1)]
		"vibration":
			Game.settings.haptics = not Game.settings.haptics
			Controls.pulse(0.3, 0.3, 0.15)
		"prompts":
			var i := Game.PROMPTS.find(str(Game.settings.prompts))
			Game.settings.prompts = Game.PROMPTS[(i + d + Game.PROMPTS.size()) % Game.PROMPTS.size()]

## Save the run where it stands (voyage or camp) and go back to the title.
func save_and_quit() -> bool:
	var st := stage()
	var saved := true
	if st != "":
		saved = Game.save_game(st)
	hide_menu()
	get_tree().change_scene_to_file("res://scenes/boot.tscn")
	return saved

func value(row: String) -> String:
	match row:
		"difficulty": return Game.DIFFICULTY_NAMES[Game.settings.difficulty]
		"vibration": return "on" if Game.settings.haptics else "off"
		"prompts": return {"auto": "auto (off on Hard)", "on": "always", "off": "never"}[str(Game.settings.prompts)]
	return ""

func _draw_menu() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	_view.draw_rect(Rect2(0, 0, 1920, 1080), Color(0.05, 0.05, 0.05, 0.6))
	var r := Rect2(560, 220, 800, 620)
	_view.draw_rect(r, Color("2a2119"))
	_view.draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	_view.draw_string(_font, r.position + Vector2(40, 76), "PAUSED", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, ink)
	var labels := {"resume": "Resume", "difficulty": "Difficulty", "vibration": "Vibration", "prompts": "On-screen prompts",
		"quit": "Save and quit to the title" if stage() != "" else "Quit to the title"}
	for i in ROWS.size():
		var row: String = ROWS[i]
		var y := r.position.y + 170 + i * 70
		if i == focus:
			_view.draw_rect(Rect2(r.position.x + 24, y - 42, r.size.x - 48, 60), Color("c9a55a", 0.25))
		_view.draw_string(_font, Vector2(r.position.x + 50, y), labels[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
		if value(row) != "":
			_view.draw_string(_font, Vector2(r.position.x + 440, y), "‹ %s ›" % value(row), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	var note := "A new difficulty applies from the next mini-game. Vibration always has a visual twin on screen."
	_view.draw_multiline_string(_font, r.position + Vector2(40, 540), note, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 20, -1, Color(ink, 0.7))
	var help := "W/S choose · A/D change · Enter select · P or Esc resume" if kb else "LB/RB choose · D-pad change · A select · Back or B resume"
	_view.draw_string(_font, r.position + Vector2(40, 600), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))
