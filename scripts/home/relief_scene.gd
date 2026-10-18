extends Node2D
## Loading the relief at Eriksfjord, third spring (Backlog F30). LB/RB choose · D-pad change ·
## Y only what the household gives · A sail west · the silver pays for anything more.

var relief := Relief.new()
var home := Home.new()
var focus := 0
var refused := 0.0
var _font: Font
var autosave_off := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	home.from_dict(Knobs._v, Game.home)
	relief.setup(Knobs._v, home)

func _process(delta: float) -> void:
	refused = maxf(0.0, refused - delta)
	queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	var rows := Relief.ROWS.size()
	if e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down"):
		focus = (focus + 1) % rows
	elif e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up"):
		focus = (focus + rows - 1) % rows
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right"):
		relief.change(Relief.ROWS[focus], 1)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left"):
		relief.change(Relief.ROWS[focus], -1)
	elif e.is_action_pressed("alt"):
		relief.reset()
	elif e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		sail()

## The relief leaves Eriksfjord: a fresh outbound voyage carrying the relief's people and goods.
func sail() -> bool:
	if not relief.can_sail():
		refused = 1.5
		return false
	var legs_data: Dictionary = JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())
	var v := Voyage.new()
	v.setup(Knobs._v, legs_data)
	relief.apply_to(v)
	home.hires = home.hires              # spent silver stays recorded in the home dict
	var h := home.to_dict()
	h.relief_spent = relief.cost()
	Game.home = h
	Game.voyage = v
	Game.loaded_stage = "relief"
	if not autosave_off:
		Game.save_game("voyage")
	if is_inside_tree() and not get_tree().root.has_meta("no_scene_change"):
		get_tree().change_scene_to_file("res://scenes/voyage.tscn")
	return true

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	draw_rect(Rect2(0, 0, 1920, 1080), Color("9fb2bd"))
	draw_rect(Rect2(0, 640, 1920, 440), Color("51707e"))
	for hidx in relief.hulls():
		var hx := 1100.0 + hidx * 380.0
		draw_colored_polygon(PackedVector2Array([Vector2(hx, 900), Vector2(hx + 340, 900), Vector2(hx + 300, 950), Vector2(hx + 40, 950)]), Color("4a3828"))
	var r := Rect2(60, 40, 1800, 820)
	draw_rect(r, Color(0.1, 0.09, 0.07, 0.88))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 8)), Color("c9a55a"))
	draw_string(_font, Vector2(90, 96), "ERIKSFJORD, SPRING OF YEAR %d  ·  loading the relief" % (home.year + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
	draw_string(_font, Vector2(90, 136), "%d people in %d hull%s (%d units). The household gives food and drink for the crossing; silver buys the rest: %.1f marks in hand." % [
		relief.people(), relief.hulls(), "s" if relief.hulls() > 1 else "", int(relief.capacity()), relief.silver()], HORIZONTAL_ALIGNMENT_LEFT, 1740, 22, Color(ink, 0.85))
	for i in Relief.ROWS.size():
		var row: String = Relief.ROWS[i]
		var y := 210.0 + i * 62.0
		if i == focus:
			draw_rect(Rect2(80, y - 40, 1760, 54), Color("c9a55a", 0.22))
		draw_string(_font, Vector2(110, y), Relief.LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		draw_string(_font, Vector2(620, y), "‹ %d ›" % int(relief.c[row]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		var note := "%.1f marks each" % relief.price(row)
		if relief.free.has(row):
			note = "%d given; more at %.1f marks" % [int(relief.free[row]), relief.price(row)]
		if row in ["food", "drink", "fodder"]:
			var d := relief.days_of(row)
			note += "  ·  " + ("no animals to feed" if d >= 999.0 else "%d days" % floori(d))
		draw_string(_font, Vector2(780, y), note, HORIZONTAL_ALIGNMENT_LEFT, 1040, 22, Color(ink, 0.8))
	var over := relief.hold_load() > relief.capacity()
	draw_string(_font, Vector2(110, 700), "Hold %.1f of %d units   ·   cost %.1f of %.1f marks" % [relief.hold_load(), int(relief.capacity()), relief.cost(), relief.silver()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("e0735e") if over or relief.cost() > relief.silver() else ink)
	var w := relief.warnings()
	draw_string(_font, Vector2(110, 760), w[0] if not w.is_empty() else "Ready to sail west.", HORIZONTAL_ALIGNMENT_LEFT, 1700, 22,
		Color("ff8a6e") if refused > 0.0 else (Color("e0a35e") if not w.is_empty() else Color("9ec27a")))
	draw_string(_font, Vector2(110, 820), ("W/S or Q/E choose · Z/C change · F only what is given · Enter sail west" if kb else "LB/RB choose · D-pad change · Y only what is given · A sail west"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))
