extends Node2D
## The outbound voyage, playable (Backlog F02 with F01, F09, F35, F37, F38, F39).
## Controls: A sail a watch (hold A to keep sailing) · Y fish (coastal legs, costs a watch)
##           LB/RB choose a selector · D-pad or left stick left/right change it
## At the night watch the star ring opens; a storm night has no sky.
## Draws procedurally until real art is saved at the asset list's paths.

const RING_SCENE := preload("res://scenes/star_ring.tscn")
const LINE_SCENE := preload("res://scenes/hand_line.tscn")
const BAIL_SCENE := preload("res://scenes/storm_bail.tscn")
const SELECTORS := ["pace", "ration", "animal_ration"]
const SEL_NAMES := {"pace": "Pace", "ration": "Rations", "animal_ration": "Animals"}
const SEL_VALUES := {"pace": ["crack", "easy", "heave"], "ration": ["full", "half", "bare"], "animal_ration": ["full", "half", "none"]}
const VALUE_NAMES := {"crack": "Crack on", "easy": "Easy", "heave": "Heave to", "full": "Full", "half": "Half", "bare": "Bare bones", "none": "None"}
const KIND_COLORS := {"people": Color("ede3cc"), "cattle": Color("8a6d4e"), "sheep": Color("d8cfb8"), "food": Color("c9a55a"),
	"drink": Color("5c7c8a"), "fodder": Color("6e8a4e"), "trade": Color("9e3a2e"), "timber": Color("4a3828")}

var v := Voyage.new()
var mode := "card"               # card | sail | ring | end
var cards: Array = []            # queue of {title, body, kind}
var focus := 0
var t := 0.0
var auto_cd := 0.0
var scroll := 0.0
var ring: Node = null
var line: Node = null
var _font: Font
var _stick_ready := true
var _logged := false
var autosave_off := false        # tests turn this off

func _ready() -> void:
	_font = ThemeDB.fallback_font
	var legs_data: Dictionary = JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())
	var seed := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			seed = int(a.trim_prefix("--seed="))
	if Game.loaded_stage == "voyage" and Game.voyage != null:
		v = Game.voyage
		Game.loaded_stage = ""
		_card("Continuing the voyage", "%s, day %d. %s\n%s" % [v.date_text(), v.day + 1, v.weather_info().name, _leg_line()])
		return
	v.setup(Knobs._v, legs_data, seed)
	Game.voyage = v
	Game.camp = null
	_card("Eriksfjord, %s" % v.date_text(),
		"The knarr is loaded to the gunwales: %d people, %d cattle, %d sheep, %d food, %d drink, %d fodder, %d trade goods.\nThe hold is %.1f of %d units. Leave after the ice; be ashore before October." % [
		v.people, v.cattle, v.sheep, int(v.food), int(v.drink), int(v.fodder), v.trade, v.hold_load(), int(v.hold_capacity())], "start")
	_begin_day()

# ------------------------------------------------------------------ flow
func _begin_day() -> void:
	var e := v.start_day()
	var info: Dictionary = e.info
	_card("Day %d  ·  %s  ·  %s" % [v.day + 1, v.date_text(), info.name], "%s\n%s" % [info.line, _leg_line()], "weather")

func _leg_line() -> String:
	return "%s: %d nm to the next landfall." % [v.leg().name, maxi(0, roundi(v.leg_left))]

func _card(title: String, body: String, kind: String = "") -> void:
	cards.append({"title": title, "body": body, "kind": kind})
	mode = "card"

func _handle_events(evs: Array) -> void:
	for e in evs:
		match e.type:
			"landfall": _card("Landfall", "The coast of %s is behind us." % e.leg, "landfall")
			"new_leg": _card("Next leg: %s" % e.leg, "%d nm to go on this leg." % roundi(e.nm))
			"repair": _card("Repairs ashore", "A day's work on the strakes. The hull is %s." % _hull_word())
			"sail_torn": _card("The sail has torn", "Cracking on in heavy weather split the wool. We make less way until it is mended.")
			"strake": _card("A strake has sprung", "Water is coming in. The hull is %s." % _hull_word())
			"cask_breach": _card("A cask is breached", "Water floods across the deck and is lost. Sour whey would have kept.")
			"spoiled": _card("Fish spoiled", "%d person-days of fresh fish went bad. Dry it on fair days or eat it fast." % roundi(e.person_days))
			"starving": _card("The food is gone", "No stores left. Sickness spreads among the hungry.")
			"thirst": _card("The water is gone", "Without drink the crew sickens fast.")
			"sick": _card("Sickness", "%d more of the crew are sick and cannot stand a watch." % e.count)
			"death": _card("A death aboard", "%d lost. They are given to the sea with what words we have." % e.count)
			"bail_held": _card("The storm passes", "You kept her afloat through the night. No fix, but the hull is whole.")
			"overboard": _card("Man overboard", "A wave took one of the crew over the side. %s" % ("They were lost in the dark." if e.lost else "We got a line to them and hauled them back."))
			"animal_died": _card("An animal died", "With no fodder, a %s died. Starve the bull, lose the trade good." % ("head of cattle" if e.kind == "cattle" else "sheep"))
			"drift":
				pass
			"arrived": _end(true)
			"lost": _end(false, e.reason)
			"day_end":
				if v.state == "sailing":
					_begin_day()

func _end(won: bool, reason: String = "") -> void:
	if not _logged:
		_logged = true
		DirAccess.make_dir_recursive_absolute("user://runlog")
		v.write_log("user://runlog/voyage_%s.csv" % Time.get_datetime_string_from_system(true).replace(":", "-"))
	var summary := "Day %d, %s. %d people aboard (%d lost), %d cattle, %d sheep. %d nm sailed, %d nm of it lost to drift. Fixes: %d clean, %d partial, %d none." % [
		v.day, v.date_text(), v.people, v.dead, v.cattle, v.sheep, roundi(v.sailed_nm), roundi(v.drift_nm_total), v.fixes[2], v.fixes[1], v.fixes[0]]
	if won:
		_card("Landfall at the Strait", "The camp site at last: a grassy terrace, a brook, a shingle shore.\n" + summary, "camp")
	else:
		_card("The voyage is lost", reason + "\n" + summary, "end")

func _night() -> void:
	var sky := v.ring_preset()
	if sky == "":
		_open_bail()
		return
	mode = "ring"
	ring = RING_SCENE.instantiate()
	ring.embedded = true
	add_child(ring)
	ring.new_night(sky)
	ring.finished.connect(func(r): _handle_events(v.take_fix(r.result)))
	ring.closed.connect(_close_ring)

func _open_bail() -> void:
	mode = "ring"
	var b := BAIL_SCENE.instantiate()
	b.embedded = true
	add_child(b)
	b.start()
	ring = b                      # reuse the child slot; the tests drive it like any mini-game
	b.closed.connect(_close_bail)

func _close_bail() -> void:
	var r: Dictionary = ring.result
	ring.queue_free()
	ring = null
	mode = "sail"
	v.take_fix(RingFix.Result.NONE)          # no sky, no fix
	_handle_events(v.apply_bail(bool(r.get("held", false))))
	if mode == "sail":
		_sail_one()

func _close_ring() -> void:
	ring.queue_free()
	ring = null
	mode = "sail"
	if v.fix_today < 0:
		v.take_fix(RingFix.Result.NONE)
	_sail_one()

func _sail_one() -> void:
	if v.state != "sailing":
		return
	_handle_events(v.sail_watch())
	if v.state == "sailing" and not autosave_off:
		Game.save_game("voyage")    # watch-level autosave at sea (Release: Save)
	if mode != "card" and mode != "end":
		mode = "sail"

# ------------------------------------------------------------------ input
func _process(delta: float) -> void:
	t += delta
	scroll += delta * 60.0 * (0.3 if v.pace == "heave" else (1.4 if v.pace == "crack" else 1.0))
	if mode == "sail":
		_selectors_stick()
		auto_cd -= delta
		if Input.is_action_pressed("commit") and auto_cd <= 0.0:
			auto_cd = 0.45
			_try_watch()
	queue_redraw()

func _try_watch() -> void:
	if v.watch == Voyage.NIGHT_WATCH and v.fix_today == -1:
		_night()
	else:
		_sail_one()

func _unhandled_input(e: InputEvent) -> void:
	if mode == "ring":
		return
	if mode == "card":
		if e.is_action_pressed("commit"):
			get_viewport().set_input_as_handled()
			var c: Dictionary = cards.pop_front()
			auto_cd = 0.35
			if c.get("kind", "") == "end":
				get_tree().change_scene_to_file("res://scenes/boot.tscn")
				return
			if c.get("kind", "") == "camp":
				get_tree().change_scene_to_file("res://scenes/camp.tscn")
				return
			if cards.is_empty():
				mode = "sail"
		return
	if mode == "sail":
		if e.is_action_pressed("tool_next"):
			focus = (focus + 1) % SELECTORS.size()
		elif e.is_action_pressed("tool_prev"):
			focus = (focus + SELECTORS.size() - 1) % SELECTORS.size()
		elif e.is_action_pressed("ui_right_pad"):
			_change(1)
		elif e.is_action_pressed("ui_left_pad"):
			_change(-1)
		elif e.is_action_pressed("alt"):
			if not v.can_fish():
				var why := "Open water: no bottom for a hand line here."
				if v.hooks <= 0:
					why = "No hooks left. The smith at the camp can make more."
				elif v.is_coastal():
					why = "Fishing is once a day, on a coastal leg, before the day's last watch."
				_card("No fishing now", why)
			else:
				_open_line()

func _open_line() -> void:
	mode = "ring"          # any child mini-game pauses the voyage the same way
	line = LINE_SCENE.instantiate()
	line.embedded = true
	line.hook_stock = v.hooks
	add_child(line)
	line.start(v.weather == "fog", 0.8 if v.weather in ["beam_sea", "following_gale"] else 0.3)
	line.closed.connect(_close_line)

func _close_line() -> void:
	var r: Dictionary = line.result
	line.queue_free()
	line = null
	mode = "sail"
	var evs := v.fish(1.0, float(r.get("person_days", 0.0)), int(r.get("hooks_lost", 0)))
	if not evs.is_empty():
		_card("Fishing", "A watch at anchor on the hand lines: %d person-days of fresh fish. It spoils in three days. %d hooks left." % [roundi(evs[0].person_days), v.hooks])
		_handle_events(evs.slice(1))

func _selectors_stick() -> void:
	var x := Controls.left_stick().x
	if absf(x) < 0.3:
		_stick_ready = true
	elif _stick_ready:
		_stick_ready = false
		_change(1 if x > 0 else -1)

func _change(dir: int) -> void:
	var key: String = SELECTORS[focus]
	var vals: Array = SEL_VALUES[key]
	var i := vals.find(v.get(key))
	v.set(key, vals[clampi(i + dir, 0, vals.size() - 1)])

func _hull_word() -> String:
	return ["sound", "strained", "sprung", "holed"][clampi(v.hull, 0, 3)]

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if mode == "ring":
		return
	_draw_world()
	_draw_hud()
	if mode == "card" or mode == "end":
		_draw_card()

func _sky_colors() -> Array:
	var night := v.watch >= Voyage.NIGHT_WATCH
	var w := v.weather
	var top := Color("a9c4d0"); var low := Color("dce3e3")
	if w in ["fog"]:
		top = Color("c9d0d0"); low = Color("e4e8e6")
	elif w in ["low_cloud", "beam_sea", "following_gale"]:
		top = Color("6f8794"); low = Color("a9b6ba")
	elif w == "storm":
		top = Color("3a4650"); low = Color("6b767c")
	if night:
		top = top.darkened(0.75); low = low.darkened(0.55)
	return [top, low]

func _draw_world() -> void:
	var c := _sky_colors()
	for i in 14:
		draw_rect(Rect2(0, i * 45.0, 1920, 46), c[0].lerp(c[1], i / 13.0))
	var hy := 620.0
	# coast on coastal legs
	if v.is_coastal():
		var tint: Color = {"eriksfjord": Color("5b6e52"), "helluland": Color("7c8186"), "markland": Color("2e4a36"),
			"furdustrandir": Color("b9ad8c"), "strait": Color("6e8a4e")}.get(v.leg().id, Color("556655"))
		var pts := PackedVector2Array()
		for x in range(0, 1960, 40):
			var h := maxf(8.0, 46.0 + 30.0 * sin((x + scroll * 0.3) * 0.004) + 18.0 * sin((x + scroll * 0.3) * 0.013))
			pts.append(Vector2(x, hy - h))
		pts.append(Vector2(1960, hy)); pts.append(Vector2(0, hy))
		draw_colored_polygon(pts, tint.lerp(c[1], 0.45))
	# sea bands
	var sea := Color("2f4a57") if v.weather != "storm" else Color("26343c")
	draw_rect(Rect2(0, hy, 1920, 460), sea)
	var amp: float = {"calm": 2.0, "fair": 6.0, "fog": 4.0, "low_cloud": 7.0, "drift_ice": 4.0, "following_gale": 14.0, "beam_sea": 16.0, "storm": 24.0}.get(v.weather, 6.0)
	for band in 6:
		var y0 := hy + 30 + band * 70
		var pts2 := PackedVector2Array()
		for x in range(0, 1961, 30):
			pts2.append(Vector2(x, y0 + sin((x + scroll * (1 + band * 0.4)) * 0.01 + band) * amp * (0.5 + band * 0.25)))
		draw_polyline(pts2, Color(0.86, 0.89, 0.89, 0.12 + band * 0.04), 2.0)
	if v.weather == "drift_ice":
		for i in 6:
			var x := fmod(i * 360.0 - scroll * 1.2, 2200.0) + 2000.0
			x = fmod(x, 2200.0) - 140.0
			draw_rect(Rect2(x, hy + 40 + (i % 3) * 90, 140 - (i % 2) * 50, 14), Color("e8eef0"))
	_draw_ship(Vector2(760, 760 + sin(t * 1.3) * amp * 0.6))
	if v.weather == "fog":
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.88, 0.9, 0.9, 0.35))
	if v.weather in ["storm", "beam_sea", "low_cloud"]:
		for i in 70:
			var rx := fmod(i * 97.0 + t * 900.0, 1920.0)
			var ry := fmod(i * 53.0 + t * 1400.0, 1080.0)
			draw_line(Vector2(rx, ry), Vector2(rx - 12, ry + 34), Color(0.85, 0.88, 0.9, 0.25), 1.5)

func _draw_ship(at: Vector2) -> void:
	var tilt := sin(t * 1.1) * (0.06 if v.weather in ["storm", "beam_sea"] else 0.02)
	draw_set_transform(at, tilt, Vector2.ONE)
	var hull := PackedVector2Array([Vector2(-640, -70), Vector2(-560, 30), Vector2(-300, 70), Vector2(300, 70), Vector2(560, 30),
		Vector2(660, -90), Vector2(560, -10), Vector2(-540, -10)])
	draw_colored_polygon(hull, Color("4a3828"))
	for i in 4:
		draw_line(Vector2(-560 + i * 10, 0 + i * 12), Vector2(560 - i * 10, 0 + i * 12), Color("8a6d4e"), 3.0)
	# cargo heap follows the hold
	var fill := clampf(v.hold_load() / v.hold_capacity(), 0, 1.2)
	draw_rect(Rect2(-260, -10 - 60 * fill, 520, 60 * fill), Color("6b5a44"))
	# crew
	for i in mini(v.people, 10):
		draw_rect(Rect2(-420 + i * 80, -60, 16, 50), Color(0.12, 0.1, 0.08) if i >= v.people - v.sick.size() else Color(0.2, 0.17, 0.13))
	# mast and sail
	draw_line(Vector2(0, -10), Vector2(0, -620), Color("6b4a35"), 10.0)
	var sail_h: float = {"crack": 420.0, "easy": 300.0, "heave": 40.0}[v.pace]
	draw_line(Vector2(-300, -600), Vector2(300, -600), Color("6b4a35"), 8.0)
	for s in 6:
		var col := Color("9e3a2e") if s % 2 == 0 else Color("ede3cc")
		draw_rect(Rect2(-290 + s * 97, -598, 97, sail_h), col if not v.sail_torn or s != 3 else Color(col, 0.35))
	# steering oar
	draw_line(Vector2(-560, -40), Vector2(-600, 80), Color("6b4a35"), 8.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

func _draw_hud() -> void:
	var ink := Color("ede3cc")
	var panel := Color(0.11, 0.1, 0.08, 0.78)
	# top-left: date, day, watch notches
	draw_rect(Rect2(24, 20, 560, 120), panel)
	draw_string(_font, Vector2(44, 62), "%s  ·  day %d" % [v.date_text(), v.day + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	for i in Voyage.WATCHES_PER_DAY:
		var lit := i < v.watch
		var night := i >= Voyage.NIGHT_WATCH
		draw_rect(Rect2(44 + i * 52, 80, 44, 16), Color(ink, 0.9 if lit else 0.2) if not night else Color(Color("5c7c8a"), 0.9 if lit else 0.3))
	draw_string(_font, Vector2(370, 96), "%s" % v.weather_info().name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	draw_string(_font, Vector2(44, 128), _leg_line(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.8))
	# top-right: season dial
	var dc := Vector2(1790, 110)
	draw_circle(dc, 82, panel)
	var start := deg_to_rad(-90.0)
	var span := TAU * 0.85
	var d0 := Knobs.num("departure_day_of_year", 145)
	var d1 := Knobs.num("last_safe_day_at_sea", 273)
	draw_arc(dc, 66, start, start + span, 48, Color(ink, 0.35), 10.0)
	draw_arc(dc, 66, start + span, start + span + TAU * 0.12, 16, Color("9e3a2e"), 10.0)
	var frac := clampf((v.day_of_year - d0) / (d1 - d0), 0, 1.15)
	var ang := start + span * frac
	draw_line(dc, dc + Vector2(cos(ang), sin(ang)) * 70, Color("c9a55a"), 5.0)
	draw_rect(Rect2(dc + Vector2(-210, 88), Vector2(300, 34)), panel)
	draw_string(_font, dc + Vector2(-200, 112), "%d days to October" % maxi(0, int(d1 - v.day_of_year + 1)), HORIZONTAL_ALIGNMENT_RIGHT, 280, 20, ink)
	# bottom: hold tally stick
	var sx := 360.0; var sy := 958.0
	draw_rect(Rect2(sx - 20, sy - 30, 1240, 100), panel)
	var kinds := [["people", v.people * Knobs.num("cargo_units_per_person", 0.4)], ["cattle", v.cattle * Knobs.num("cargo_units_per_head_of_cattle", 1.5)],
		["sheep", v.sheep * Knobs.num("cargo_units_per_sheep_or_goat", 0.4)], ["food", ceilf(v.food)], ["drink", ceilf(v.drink)],
		["fodder", ceilf(v.fodder)], ["trade", float(v.trade)], ["timber", float(v.timber)]]
	var notch := 0.0
	var cap := v.hold_capacity()
	for kd in kinds:
		var units: float = kd[1]
		var x0 := sx + notch / cap * 1200.0
		var w := units / cap * 1200.0
		if w > 0.5:
			draw_rect(Rect2(x0, sy, w - 2, 26), KIND_COLORS[kd[0]])
			if w > 50:
				draw_string(_font, Vector2(x0 + 4, sy + 52), kd[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink, 0.8))
		notch += units
	for i in int(cap) + 1:
		draw_line(Vector2(sx + i * 50, sy - 6), Vector2(sx + i * 50, sy + 32), Color(0, 0, 0, 0.5), 2.0)
	draw_string(_font, Vector2(sx, sy - 8), "Hold %.1f / %d   ·   food %.0f days   ·   drink %.0f days" % [v.hold_load(), int(cap), v.food_days(), v.drink_days()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	# bottom-left: ship and crew
	draw_rect(Rect2(24, 860, 300, 196), panel)
	draw_string(_font, Vector2(40, 900), "Hull: %s" % _hull_word(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(_font, Vector2(40, 932), "Sail: %s" % ("torn" if v.sail_torn else "whole"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(_font, Vector2(40, 964), "Crew: %d (%d sick)" % [v.people, v.sick.size()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(_font, Vector2(40, 996), "Morale: %d" % roundi(v.morale), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	draw_string(_font, Vector2(40, 1028), "Cattle %d · sheep %d" % [v.cattle, v.sheep], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	# right: selectors
	draw_rect(Rect2(1610, 700, 290, 356), panel)
	for i in SELECTORS.size():
		var key: String = SELECTORS[i]
		var y := 740.0 + i * 92
		var f := i == focus and mode == "sail"
		if f:
			draw_rect(Rect2(1620, y - 30, 270, 80), Color("c9a55a", 0.25))
		draw_string(_font, Vector2(1636, y), SEL_NAMES[key], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))
		draw_string(_font, Vector2(1636, y + 34), "‹ %s ›" % VALUE_NAMES[v.get(key)], HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	draw_string(_font, Vector2(1622, 1030), "LB/RB choose · D-pad change", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink, 0.6))
	if mode == "sail":
		var prompt := "A: take the star ring" if v.watch == Voyage.NIGHT_WATCH and v.fix_today == -1 else "A: sail a watch (hold to keep sailing)"
		if v.can_fish():
			prompt += "    Y: fish (%d hooks)" % v.hooks
		draw_string(_font, Vector2(620, 900), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)

func _draw_card() -> void:
	if cards.is_empty():
		return
	var c: Dictionary = cards[0]
	var ink := Color("ede3cc")
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 0.35))
	var r := Rect2(460, 300, 1000, 380)
	draw_rect(r, Color("2a2119"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	draw_rect(r, Color("8a6d4e"), false, 4.0)
	draw_string(_font, r.position + Vector2(40, 74), c.title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 34, ink)
	draw_multiline_string(_font, r.position + Vector2(40, 130), c.body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 24, -1, Color(ink, 0.88))
	draw_string(_font, r.position + Vector2(40, r.size.y - 30), {"end": "A: back to the title", "camp": "A: go ashore"}.get(c.get("kind", ""), "A: continue"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
	if cards.size() > 1:
		draw_string(_font, r.position + Vector2(r.size.x - 140, r.size.y - 30), "+%d more" % (cards.size() - 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.5))
