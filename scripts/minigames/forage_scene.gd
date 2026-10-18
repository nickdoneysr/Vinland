extends Node2D
## MG6 Patch reading (Backlog F13). LS walk the hand over the patch · RT hold to pick.
## Each pick ticks in the pad; a harsh buzz means you are stripping the plant (the clump turns brown on screen).

signal finished(result: Dictionary)
signal closed

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [stick: Vector2, picking: bool]
var difficulty := ""
var rules := Forage.new()
var result: Dictionary = {}
var t := 0.0
var _cfg: Dictionary
var _font: Font
var _tick := 0.0
var season_health := 1.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start()

func start(seed: int = 0, health: float = 1.0) -> void:
	_cfg = Game.tuning("forage", difficulty)
	season_health = health
	rules = Forage.new()
	rules.setup(_cfg, seed, health)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	_tick -= delta
	if result.is_empty():
		var stick := Controls.left_stick()
		var picking := Input.get_action_strength("rt") > 0.5
		if autopilot:
			var b := _bot()
			stick = b[0]; picking = b[1]
		elif bot_input.is_valid():
			var b2: Array = bot_input.call(self)
			stick = b2[0]; picking = b2[1]
		var evs := rules.step(delta, stick, picking)
		if _tick <= 0.0:
			if "greedy" in evs:
				Controls.pulse(0.7, 0.9, 0.08)
				_tick = 0.12
			elif "take" in evs:
				Controls.pulse(0.15, 0.0, 0.04)
				_tick = 0.25
		if rules.done:
			result = {"person_days": rules.basket, "patch_health": rules.patch_health(), "stripped": rules.stripped}
			finished.emit(result)
	queue_redraw()

## Expert bot: goes to the richest clump in reach, picks only ripe fruit.
func _bot() -> Array:
	var best := -1
	var score := -1.0
	for i in rules.clumps.size():
		var cl: Dictionary = rules.clumps[i]
		if cl.ripe <= 0.05:
			continue
		var s: float = cl.ripe / (1.0 + rules.cursor.distance_to(cl.p) / 300.0)
		if s > score:
			score = s; best = i
	if best < 0:
		return [Vector2.ZERO, false]
	var to: Vector2 = rules.clumps[best].p - rules.cursor
	if to.length() > float(_cfg.pick_radius) * 0.5:
		return [to.normalized() * clampf(to.length() / 120.0, 0.25, 1.0), false]
	return [Vector2.ZERO, rules.ripe_in_reach() >= 0]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start()
		return
	if not embedded and e is InputEventKey and e.pressed and e.physical_keycode == KEY_R:
		start()

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	draw_rect(Rect2(0, 0, 1920, 1080), Color("4f6040"))
	draw_rect(Forage.AREA.grow(40), Color("5e7048"))
	for cl in rules.clumps:
		var p: Vector2 = cl.p
		var leaf := Color("6e8a4e").lerp(Color("7a5a3a"), cl.strip)
		draw_circle(p, 46, leaf)
		var n_ripe := ceili(cl.ripe * 3.0)
		var n_green := ceili(cl.unripe * 2.0)
		for k in n_ripe:
			var a := k * 2.4
			draw_circle(p + Vector2(cos(a), sin(a)) * (12 + k * 2), 7, Color("3f4d8a"))
		for k in n_green:
			var a2 := k * 2.4 + 1.2
			draw_circle(p + Vector2(cos(a2), sin(a2)) * (18 + k * 2), 5, Color("9ab060"))
	var near := rules.nearest()
	if near >= 0:
		draw_arc(rules.clumps[near].p, float(_cfg.pick_radius), 0, TAU, 40, Color("e8c35a", 0.6), 2.0)
	# the hand
	draw_circle(rules.cursor, 22, Color("c49a76"))
	draw_arc(rules.cursor, 22, 0, TAU, 24, Color("3a2a1c"), 3.0)
	# basket
	var fill := rules.basket / float(_cfg.basket_pd)
	draw_rect(Rect2(1700, 600, 160, 300), Color(0.1, 0.09, 0.07, 0.85))
	draw_rect(Rect2(1700, 900 - 300 * fill, 160, 300 * fill), Color("3f4d8a"))
	draw_string(_font, Vector2(1700, 940), "basket", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, ink)
	# HUD
	draw_rect(Rect2(24, 20, 1100, 150), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "FORAGING  ·  blueberries and partridgeberries", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	draw_string(_font, Vector2(44, 96), ("WASD move the hand · hold Space to pick" if kb else "LS move the hand · hold RT to pick"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	draw_string(_font, Vector2(44, 134), "Picked %d person-days   ·   patch health %d%%   ·   %ds left" % [roundi(rules.basket), roundi(rules.patch_health() * 100), maxi(0, ceili(float(_cfg.session_seconds) - rules.t))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.9))
	if bool(_cfg.get("banner", false)) and result.is_empty():
		var tip := "Pick the dark ripe berries. When a clump has none left, let go: pulling on stripped plants ruins the patch."
		if near >= 0 and rules.clumps[near].ripe <= 0.0:
			tip = "No ripe fruit left here. Let go and move on."
		draw_rect(Rect2(300, 990, 1320, 64), Color(0.08, 0.07, 0.06, 0.8))
		draw_string(_font, Vector2(320, 1032), tip, HORIZONTAL_ALIGNMENT_LEFT, 1280, 24, Color("e8c35a") if near >= 0 and rules.clumps[near].ripe <= 0.0 else ink)
	if not result.is_empty():
		draw_rect(Rect2(560, 420, 820, 200), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 820, 8), Color("6e8a4e") if result.patch_health > 0.8 else Color("c9a55a"))
		draw_string(_font, Vector2(600, 490), "%d person-days in the basket." % roundi(result.person_days), HORIZONTAL_ALIGNMENT_LEFT, 760, 28, ink)
		var note := "The patch is left in good heart." if result.patch_health > 0.9 else ("The patch is thinned; it will give less this season." if result.patch_health > 0.6 else "You stripped the patch. It will give little until next year.")
		draw_string(_font, Vector2(600, 540), note, HORIZONTAL_ALIGNMENT_LEFT, 760, 22, Color(ink, 0.85))
		draw_string(_font, Vector2(600, 590), "A: back" if embedded else "A: another patch", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
