extends Node2D
## MG5 Stalk and loose (Backlog F12). LS right walk · RT hurry · LB crouch · RB draw / lower · RS aim · A loose · B lower.
## When the caribou lifts its head and watches, freeze. The ear flick and the alarm meter are the visual twins
## of the heartbeat in the pad.

signal finished(result: Dictionary)
signal closed

const PX_PER_M := 10.0
const HUNTER_X := 380.0
const GROUND_Y := 860.0
const PX_PER_DEG := 34.0

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [move, fast, crouch_pressed, bow_pressed, aim_y, loose, lower]
var difficulty := ""
var rules := Hunt.new()
var result: Dictionary = {}
var t := 0.0
var _cfg: Dictionary
var _font: Font
var _beat_cd := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start(false)

func start(far: bool, seed: int = 0) -> void:
	_cfg = Game.tuning("hunt", difficulty)
	rules = Hunt.new()
	rules.setup(_cfg, seed, far)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	if result.is_empty():
		var move := maxf(0.0, Controls.left_stick().x)
		var fast := Input.get_action_strength("rt") > 0.5
		var crouch := Input.is_action_just_pressed("tool_prev")
		var bow := Input.is_action_just_pressed("tool_next")
		var aim_y := -Controls.right_stick().y
		var loose := Input.is_action_just_pressed("commit")
		var lower := Input.is_action_just_pressed("drop")
		var b: Array = []
		if autopilot:
			b = _bot()
		elif bot_input.is_valid():
			b = bot_input.call(self)
		if b.size() == 7:
			move = b[0]; fast = b[1]; crouch = b[2]; bow = b[3]; aim_y = b[4]; loose = b[5]; lower = b[6]
		for e in rules.step(delta, move, fast, crouch, bow, aim_y, loose, lower):
			match e:
				"kill": Controls.pulse(0.5, 0.5, 0.2)
				"fled", "miss", "wound": Controls.pulse(0.2, 0.6, 0.25)
		_heartbeat(delta)
		if rules.phase >= Hunt.Phase.KILL:
			result = {"kill": rules.succeeded(), "person_days": rules.meat_pd, "hide": 1 if rules.succeeded() else 0,
				"fear_tick": rules.fear_tick, "outcome": ["stalk", "drawn", "kill", "wound", "miss", "fled", "timeout"][rules.phase]}
			finished.emit(result)
	queue_redraw()

## Heartbeat in the pad while the animal is uneasy; faster as the alarm rises.
func _heartbeat(delta: float) -> void:
	_beat_cd -= delta
	if rules.alert > 0.3 and _beat_cd <= 0.0:
		Controls.pulse(0.0, 0.35 + rules.alert * 0.4, 0.07)
		_beat_cd = lerpf(0.9, 0.35, rules.alert)

## Expert bot: walks while it grazes, freezes while it watches, draws in the best range, holds the sight steady.
func _bot() -> Array:
	var r := rules
	if r.phase == Hunt.Phase.STALK:
		var close_enough := r.dist <= float(_cfg.best_range_m[1])
		var move := 0.0 if r.watching or close_enough else 1.0
		return [move, false, false, close_enough and r.in_range(), 0.0, false, false]
	var err := r.aim_error()
	var ready := r.draw_t >= float(_cfg.draw_seconds)
	return [0.0, false, false, false, clampf(-r.aim / 1.5, -1, 1), ready and absf(err) < r.vitals_window() * 0.3, false]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start(rules.far)
		return
	if not embedded and e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1: start(false)
			KEY_2: start(true)
			KEY_R: start(rules.far)

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	# meadow
	draw_rect(Rect2(0, 0, 1920, 560), Color("a9c4d0"))
	var hills := PackedVector2Array()
	for x in range(0, 1961, 40):
		hills.append(Vector2(x, 470 - 40 * sin(x * 0.004) - 18 * sin(x * 0.013)))
	hills.append(Vector2(1960, 600)); hills.append(Vector2(0, 600))
	draw_colored_polygon(hills, Color("2e4a36"))
	draw_rect(Rect2(0, 560, 1920, 520), Color("7a8a4e"))
	# range marks on the ground
	var rx := HUNTER_X + float(_cfg.range_m) * PX_PER_M
	draw_line(Vector2(rx, GROUND_Y - 10), Vector2(rx, GROUND_Y + 30), Color(ink, 0.5), 3.0)
	draw_string(_font, Vector2(rx - 40, GROUND_Y + 60), "bow range", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.6))
	# the caribou
	var cx := HUNTER_X + rules.dist * PX_PER_M
	var fled := rules.phase in [Hunt.Phase.FLED, Hunt.Phase.MISS, Hunt.Phase.WOUND]
	if fled:
		cx += t * 0.0
	var body := Color("8a7458")
	draw_rect(Rect2(cx - 70, GROUND_Y - 120, 140, 60), body)
	for lx in [-55.0, -35.0, 35.0, 55.0]:
		draw_line(Vector2(cx + lx, GROUND_Y - 60), Vector2(cx + lx, GROUND_Y), Color("5a4a36"), 7.0)
	var head := Vector2(cx - 88, GROUND_Y - 150) if rules.watching else Vector2(cx - 95, GROUND_Y - 70)
	draw_line(Vector2(cx - 60, GROUND_Y - 110), head, body, 16.0)
	draw_circle(head, 18, body)
	draw_line(head + Vector2(0, -14), head + Vector2(-20, -60), Color("d8cfb8"), 4.0)
	draw_line(head + Vector2(6, -14), head + Vector2(22, -58), Color("d8cfb8"), 4.0)
	if rules.watching:
		var flick := sin(t * 18.0) * 6.0
		draw_line(head + Vector2(10, -6), head + Vector2(26, -16 + flick), Color("e8c35a"), 5.0)   # the ear flick
	# vitals and aim when drawn
	if rules.phase == Hunt.Phase.DRAWN:
		var vit := Vector2(cx - 40, GROUND_Y - 95)
		var w := rules.vitals_window() * PX_PER_DEG
		draw_arc(vit, w * 0.6, 0, TAU, 32, Color("6e8a4e"), 3.0)
		draw_arc(vit, w * 1.4, 0, TAU, 40, Color("c9a55a", 0.6), 2.0)
		var sight := vit + Vector2(0, -rules.aim_error() * PX_PER_DEG)
		draw_line(sight - Vector2(18, 0), sight + Vector2(18, 0), Color("ede3cc"), 3.0)
		draw_line(sight - Vector2(0, 18), sight + Vector2(0, 18), Color("ede3cc"), 3.0)
	# the hunter
	var hy := GROUND_Y - (70.0 if rules.crouched else 120.0)
	draw_rect(Rect2(HUNTER_X - 20, hy, 40, GROUND_Y - hy), Color("3a2a1c"))
	draw_circle(Vector2(HUNTER_X, hy - 18), 16, Color("6b4a35"))
	if rules.phase == Hunt.Phase.DRAWN:
		draw_arc(Vector2(HUNTER_X + 30, hy + 20), 50, -1.2, 1.2, 16, Color("8a6d4e"), 5.0)
	# near grass hides the crouched hunter
	for x in range(0, 900, 24):
		var sway := sin(t * 2.0 + x * 0.1) * 8.0
		draw_line(Vector2(x, 1080), Vector2(x + sway, GROUND_Y - 40 - fmod(x * 7.0, 30.0)), Color("5a6a3a"), 5.0)
	# wind toward the animal: your scent drifting
	for i in 5:
		var wx := fmod(t * 120.0 + i * 300.0, 1600.0) + 200.0
		draw_line(Vector2(wx, 640 + i * 30), Vector2(wx + 60, 640 + i * 30), Color(1, 1, 1, 0.25), 2.0)
	# HUD
	draw_rect(Rect2(24, 20, 1000, 160), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "THE HUNT  ·  %s" % ("far grounds: more caribou, but the land is not ours" if rules.far else "near the camp"), HORIZONTAL_ALIGNMENT_LEFT, 960, 24, ink)
	var help := "D walk · Space hurry · Q crouch · E draw/lower · Up/Down aim · Enter loose · Esc lower" if kb else "LS walk · RT hurry · LB crouch · RB draw/lower · RS aim · A loose · B lower"
	draw_string(_font, Vector2(44, 96), help, HORIZONTAL_ALIGNMENT_LEFT, 960, 20, Color(ink, 0.75))
	draw_string(_font, Vector2(44, 134), "Distance %d m   ·   %s   ·   %ds of light" % [roundi(rules.dist), "crouched" if rules.crouched else "standing", maxi(0, ceili(float(_cfg.session_seconds) - rules.t))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.9))
	# alarm meter
	draw_rect(Rect2(1700, 40, 40, 260), Color(0.1, 0.09, 0.07, 0.85))
	draw_rect(Rect2(1700, 300 - 260 * rules.alert, 40, 260 * rules.alert), Color("9e3a2e") if rules.alert > 0.6 else Color("c9a55a"))
	draw_string(_font, Vector2(1680, 330), "alarm", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	if bool(_cfg.get("banner", false)) and result.is_empty():
		var tip := ""
		if rules.phase == Hunt.Phase.STALK:
			if rules.watching:
				tip = "Freeze! It is watching."
			elif rules.in_range():
				tip = "In range. %s to draw the bow." % ("E" if kb else "RB")
			else:
				tip = "It is grazing: creep closer (%s). Crouch (%s) if the alarm climbs." % ["D" if kb else "left stick", "Q" if kb else "LB"]
		elif rules.phase == Hunt.Phase.DRAWN:
			tip = "Hold the cross in the green ring (%s), then loose (%s)." % ["Up / Down" if kb else "right stick", "Enter" if kb else "A"]
		draw_rect(Rect2(560, 980, 1100, 64), Color(0.08, 0.07, 0.06, 0.8))
		draw_string(_font, Vector2(590, 1024), tip, HORIZONTAL_ALIGNMENT_LEFT, 1060, 28, Color("e8c35a") if rules.watching else ink)
	if not result.is_empty():
		var line: String = {"kill": "A clean kill. Meat for the camp and a hide.", "wound": "Wounded. It ran, and you could not follow.",
			"miss": "The arrow went wide. It is gone.", "fled": "It caught your scent and ran.", "timeout": "The light failed before you were close."}[result.outcome]
		draw_rect(Rect2(560, 420, 820, 200), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 820, 8), Color("6e8a4e") if result.kill else Color("9e3a2e"))
		draw_string(_font, Vector2(600, 490), line, HORIZONTAL_ALIGNMENT_LEFT, 760, 28, ink)
		var extra: String = "%d person-days of meat." % roundi(result.person_days) if result.kill else ""
		if result.fear_tick:
			extra += " Someone saw you ranging far. Fear rises."
		draw_string(_font, Vector2(600, 540), extra, HORIZONTAL_ALIGNMENT_LEFT, 760, 22, Color(ink, 0.85))
		draw_string(_font, Vector2(600, 590), "A: back" if embedded else "A: hunt again · 1 near · 2 far", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
