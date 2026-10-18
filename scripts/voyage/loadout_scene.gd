extends Node2D
## Eriksfjord loadout (Backlog F53) with the four outfits (F22) and their named crews (F23).
## LB/RB or W/S choose a row · D-pad or A/D change it · Y the outfit's own load · A sail · B back to the title.

const COLORS := {"people": Color("c9a55a"), "cattle": Color("8a6d4e"), "sheep": Color("d8cfb8"), "food": Color("9e7a3e"),
	"drink": Color("5f8a9a"), "fodder": Color("7a8a4e"), "cloth": Color("9e3a2e"), "iron": Color("7d8288"), "gear": Color("b0a080")}
const GAME_NAMES := {"ring": "star ring", "sun_board": "sun board", "joint": "joint", "forage": "berry patch", "hunt": "hunt", "hand_line": "hand line"}

var lo := Loadout.new()
var focus := 0                   # 0 is the outfit row, then Loadout.ROWS
var refused := 0.0               # flashes the overload warning when A is pressed on an overloaded hull
var _font: Font

func _ready() -> void:
	_font = ThemeDB.fallback_font
	lo.setup(Knobs._v, Game.outfit_table())
	if not Game.loadout.is_empty():
		lo.from_dict(Game.loadout)
	else:
		lo.set_outfit(str(Game.outfit_table().order[0]))

func _process(delta: float) -> void:
	refused = maxf(0.0, refused - delta)
	queue_redraw()

func _key(e: InputEvent, keys: Array) -> bool:
	return e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in keys

func rows() -> int:
	return Loadout.ROWS.size() + 1

## Step through the outfits.
func cycle_outfit(d: int) -> void:
	var order: Array = Game.outfit_table().order
	var i := order.find(lo.outfit)
	lo.set_outfit(order[(i + d + order.size()) % order.size()])

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down") or _key(e, [KEY_S]):
		focus = (focus + 1) % rows()
	elif e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up") or _key(e, [KEY_W]):
		focus = (focus + rows() - 1) % rows()
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right") or _key(e, [KEY_D]):
		_change(1)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left") or _key(e, [KEY_A]):
		_change(-1)
	elif e.is_action_pressed("alt"):
		lo.reset()
	elif e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		sail()
	elif e.is_action_pressed("drop"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file("res://scenes/boot.tscn")

func _change(d: int) -> void:
	if focus == 0:
		cycle_outfit(d)
	else:
		lo.change(Loadout.ROWS[focus - 1], d)
	Controls.pulse(0.1, 0.0, 0.03)

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
	var od := lo.outfit_data()
	# Eriksfjord at the quay
	draw_rect(Rect2(0, 0, 1920, 1080), Color("9fb2bd"))
	var hills := PackedVector2Array()
	for x in range(0, 1961, 40):
		hills.append(Vector2(x, 360 - 90 * sin(x * 0.0026 + 0.6) - 30 * sin(x * 0.011)))
	hills.append(Vector2(1960, 640)); hills.append(Vector2(0, 640))
	draw_colored_polygon(hills, Color("4d6a48"))
	draw_rect(Rect2(0, 640, 1920, 440), Color("51707e"))
	# the hold as a bar along the knarr
	var hx := 1060.0; var hw := 780.0; var hy := 840.0
	draw_colored_polygon(PackedVector2Array([Vector2(hx - 60, hy - 40), Vector2(hx + hw + 60, hy - 40), Vector2(hx + hw, hy + 70), Vector2(hx, hy + 70)]), Color("4a3828"))
	var cap := lo.capacity()
	var x := hx
	for r in Loadout.ROWS + ["gear"]:
		var units: float = lo.gear_units() if r == "gear" else lo.c[r] * lo.unit_cost(r)
		var w: float = units / cap * hw
		if w > 0.5:
			draw_rect(Rect2(x, hy - 30, minf(w, hx + hw + 40 - x), 60), COLORS[r])
			x += w
	draw_line(Vector2(hx + hw, hy - 60), Vector2(hx + hw, hy + 80), Color("e8c35a"), 4.0)
	draw_string(_font, Vector2(hx + hw - 90, hy - 70), "full", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("e8c35a"))
	var over := lo.hold_load() > cap
	draw_string(_font, Vector2(hx, hy + 120), "Hold %.1f of %d units%s" % [lo.hold_load(), int(cap), "  ·  OVERLOADED" if over else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color("e0735e") if over else ink)
	# the load panel
	var r0 := Rect2(60, 30, 1800, 690)
	draw_rect(r0, Color(0.1, 0.09, 0.07, 0.88))
	draw_rect(Rect2(r0.position, Vector2(r0.size.x, 8)), Color("c9a55a"))
	draw_string(_font, Vector2(90, 86), "ERIKSFJORD  ·  loading the knarr", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
	draw_string(_font, Vector2(90, 122), "The crossing is planned at %d days. Everything aboard competes for the same %d units of hull." % [lo.crossing_days(), int(cap)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.8))
	for i in rows():
		var y := 178.0 + i * 54.0
		if i == focus:
			draw_rect(Rect2(80, y - 36, 1760, 50), Color("c9a55a", 0.22))
		if i == 0:
			draw_string(_font, Vector2(136, y), "Outfit", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
			draw_string(_font, Vector2(560, y), "‹ %s ›" % od.get("name", "the plan's load"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
			draw_string(_font, Vector2(900, y), "Silver: %s  ·  %s" % [od.get("silver", "-"), od.get("feel", "")], HORIZONTAL_ALIGNMENT_LEFT, 920, 22, Color(ink, 0.85))
			continue
		var row: String = Loadout.ROWS[i - 1]
		draw_rect(Rect2(96, y - 22, 22, 22), COLORS[row])
		draw_string(_font, Vector2(136, y), Loadout.LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
		draw_string(_font, Vector2(560, y), "‹ %d ›" % lo.c[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
		var short: bool = row in ["food", "drink", "fodder"] and lo.days_of(row) < lo.crossing_days()
		draw_string(_font, Vector2(700, y), lo.readout(row), HORIZONTAL_ALIGNMENT_LEFT, 1120, 21, Color("e0a35e") if short else Color(ink, 0.8))
	var warn := lo.warnings()
	var wy := 696.0
	if warn.is_empty():
		draw_string(_font, Vector2(90, wy), "A sound load: stores for the crossing and the hold within her limit.", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("9ec27a"))
	else:
		draw_string(_font, Vector2(90, wy), warn[0] + ("   (+%d more)" % (warn.size() - 1) if warn.size() > 1 else ""), HORIZONTAL_ALIGNMENT_LEFT, 1740, 22,
			Color("ff8a6e") if refused > 0.0 else Color("e0a35e"))
	# the outfit card: strengths, the crew's leaders and roles, the kit, how the verbs feel
	if not od.is_empty():
		var c0 := Rect2(60, 740, 920, 236)
		draw_rect(c0, Color(0.1, 0.09, 0.07, 0.88))
		draw_string(_font, c0.position + Vector2(24, 40), str(od.name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
		draw_string(_font, c0.position + Vector2(24, 74), "Strength: " + str(od.strength), HORIZONTAL_ALIGNMENT_LEFT, 880, 20, ink)
		draw_string(_font, c0.position + Vector2(24, 102), "Weakness: " + str(od.weakness), HORIZONTAL_ALIGNMENT_LEFT, 880, 20, ink)
		var leads: Array = od.get("lead", []).map(func(l): return "%s (%s)" % [l[0], str(Crew.ROLE_NAMES[l[1]]).to_lower()])
		draw_string(_font, c0.position + Vector2(24, 130), "Led by " + " and ".join(leads), HORIZONTAL_ALIGNMENT_LEFT, 880, 20, ink)
		var g: Dictionary = od.get("gear", {})
		var kit := "%d hooks, %d net%s" % [int(g.get("hooks", 6)), int(g.get("nets", 1)), "" if int(g.get("nets", 1)) == 1 else "s"]
		if int(g.get("spare_sail", 0)) > 0:
			kit += ", a spare sail (1 unit)"
		draw_string(_font, c0.position + Vector2(24, 158), "Kit: " + kit, HORIZONTAL_ALIGNMENT_LEFT, 880, 20, Color(ink, 0.85))
		var eases: Array = []
		for gm in od.get("ease", {}):
			eases.append("%s %s" % [GAME_NAMES.get(gm, gm), "easier" if int(od.ease[gm]) < 0 else "harder"])
		draw_string(_font, c0.position + Vector2(24, 186), "Hands: " + (", ".join(eases) if not eases.is_empty() else "no mini-game easier or harder"), HORIZONTAL_ALIGNMENT_LEFT, 880, 20, Color(ink, 0.85))
		var roles: Dictionary = od.get("roles", {})
		var rl: Array = []
		for rk in Crew.KEY_ROLES:
			if int(roles.get(rk, 0)) > 0:
				rl.append(("%d %ss" % [int(roles[rk]), str(Crew.ROLE_NAMES[rk]).to_lower()]) if int(roles[rk]) > 1 else str(Crew.ROLE_NAMES[rk]).to_lower())
		draw_string(_font, c0.position + Vector2(24, 214), "Crew: " + ", ".join(rl) + ", the rest hands", HORIZONTAL_ALIGNMENT_LEFT, 880, 18, Color(ink, 0.7))
	var help := "W/S choose · A/D change · F the outfit's load · Enter sail · Esc back" if kb else "LB/RB choose · D-pad change · Y the outfit's load · A sail · B back"
	draw_rect(Rect2(60, 996, 920, 56), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(84, 1033), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
