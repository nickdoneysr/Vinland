extends Node2D
## Eriksfjord loadout (Backlog F53). Choose what goes into the 24-unit hold before sailing.
## LB/RB or W/S choose a row · D-pad or A/D change it · Y reset to the plan's load · A sail · B back to the title.

const COLORS := {"people": Color("c9a55a"), "cattle": Color("8a6d4e"), "sheep": Color("d8cfb8"), "food": Color("9e7a3e"),
	"drink": Color("5f8a9a"), "fodder": Color("7a8a4e"), "cloth": Color("9e3a2e"), "iron": Color("7d8288")}

var lo := Loadout.new()
var focus := 0
var refused := 0.0       # flashes the overload warning when A is pressed on an overloaded hull
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	lo.setup(Knobs._v)
	if not Game.loadout.is_empty():
		lo.c = Game.loadout.duplicate()

func _process(delta: float) -> void:
	refused = maxf(0.0, refused - delta)
	queue_redraw()

func _key(e: InputEvent, keys: Array) -> bool:
	return e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in keys

func _unhandled_input(e: InputEvent) -> void:
	var rows := Loadout.ROWS.size()
	if e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down") or _key(e, [KEY_S]):
		focus = (focus + 1) % rows
	elif e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up") or _key(e, [KEY_W]):
		focus = (focus + rows - 1) % rows
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right") or _key(e, [KEY_D]):
		lo.change(Loadout.ROWS[focus], 1)
		Controls.pulse(0.1, 0.0, 0.03)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left") or _key(e, [KEY_A]):
		lo.change(Loadout.ROWS[focus], -1)
		Controls.pulse(0.1, 0.0, 0.03)
	elif e.is_action_pressed("alt"):
		lo.reset()
	elif e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		sail()
	elif e.is_action_pressed("drop"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/boot.tscn")

## Leave Eriksfjord with this load (refused while the hull is overloaded).
func sail() -> bool:
	if not lo.can_sail():
		refused = 1.5
		Controls.pulse(0.3, 0.6, 0.2)
		return false
	Game.loadout = lo.to_dict()
	Game.voyage = null
	Game.camp = null
	Game.loaded_stage = ""
	if is_inside_tree() and not get_tree().root.has_meta("no_scene_change"):
		get_tree().change_scene_to_file("res://scenes/voyage.tscn")
	return true

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	# Eriksfjord at the quay: grey fjord, green slopes, the knarr alongside
	draw_rect(Rect2(0, 0, 1920, 1080), Color("9fb2bd"))
	var hills := PackedVector2Array()
	for x in range(0, 1961, 40):
		hills.append(Vector2(x, 360 - 90 * sin(x * 0.0026 + 0.6) - 30 * sin(x * 0.011)))
	hills.append(Vector2(1960, 640)); hills.append(Vector2(0, 640))
	draw_colored_polygon(hills, Color("4d6a48"))
	draw_rect(Rect2(0, 640, 1920, 440), Color("51707e"))
	# the hold as a bar along the knarr: each kind of cargo stacked in its colour
	var hx := 1060.0; var hw := 780.0; var hy := 820.0
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 60, hy - 40), Vector2(hx + hw + 60, hy - 40), Vector2(hx + hw, hy + 70), Vector2(hx, hy + 70)]), Color("4a3828"))
	var cap := lo.capacity()
	var x := hx
	for r in Loadout.ROWS:
		var w: float = lo.c[r] * lo.unit_cost(r) / cap * hw
		if w > 0.5:
			draw_rect(Rect2(x, hy - 30, minf(w, hx + hw + 40 - x), 60), COLORS[r])
			x += w
	draw_line(Vector2(hx + hw, hy - 60), Vector2(hx + hw, hy + 80), Color("e8c35a"), 4.0)
	draw_string(_font, Vector2(hx + hw - 90, hy - 70), "full", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e8c35a"))
	var over := lo.hold_load() > cap
	draw_string(_font, Vector2(hx, hy + 120), "Hold %.1f of %d units%s" % [lo.hold_load(), int(cap), "  ·  OVERLOADED" if over else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("e0735e") if over else ink)
	# panel
	var r0 := Rect2(60, 40, 1800, 680)
	draw_rect(r0, Color(0.1, 0.09, 0.07, 0.88))
	draw_rect(Rect2(r0.position, Vector2(r0.size.x, 8)), Color("c9a55a"))
	draw_string(_font, Vector2(90, 100), "ERIKSFJORD  ·  loading the knarr", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, ink)
	draw_string(_font, Vector2(90, 140), "The crossing is planned at %d days. Everything aboard competes for the same %d units of hull." % [lo.crossing_days(), int(cap)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.8))
	for i in Loadout.ROWS.size():
		var row: String = Loadout.ROWS[i]
		var y := 200.0 + i * 58.0
		if i == focus:
			draw_rect(Rect2(80, y - 38, 1760, 52), Color("c9a55a", 0.22))
		draw_rect(Rect2(96, y - 24, 22, 22), COLORS[row])
		draw_string(_font, Vector2(136, y), Loadout.LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		draw_string(_font, Vector2(720, y), "‹ %d ›" % lo.c[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		var short: bool = row in ["food", "drink", "fodder"] and lo.days_of(row) < lo.crossing_days()
		draw_string(_font, Vector2(860, y), lo.readout(row), HORIZONTAL_ALIGNMENT_LEFT, 960, 22, Color("e0a35e") if short else Color(ink, 0.8))
	var warn := lo.warnings()
	var wy := 680.0
	if warn.is_empty():
		draw_string(_font, Vector2(90, wy), "A sound load: stores for the crossing and the hold within her limit.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("9ec27a"))
	else:
		draw_string(_font, Vector2(90, wy), warn[0] + ("   (+%d more)" % (warn.size() - 1) if warn.size() > 1 else ""), HORIZONTAL_ALIGNMENT_LEFT, 1740, 22,
			Color("ff8a6e") if refused > 0.0 else Color("e0a35e"))
	var help := "W/S choose · A/D change · F the plan's load · Enter sail · Esc back" if kb else "LB/RB choose · D-pad change · Y the plan's load · A sail · B back"
	draw_rect(Rect2(60, 990, 900, 56), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(84, 1027), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
