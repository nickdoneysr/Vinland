extends Node2D
## MG3 Hand line (Backlog F05). LS down pays out, LS up hauls · RT sets the hook on the ease · B cuts the line.
## A bite is two tugs then an ease: the pad tugs twice, then goes slack. On screen the line jerks twice,
## then bows slack (the visual twin for players with vibration off).
## Debug keys when standalone: 1 clear water, 2 fog, 3 strong current, R new session.

signal finished(result: Dictionary)
signal closed

const SURFACE_Y := 260.0
const PX_PER_M := 26.0
const HOOK_X := 980.0

var embedded := false
var hook_stock := 6
var autopilot := false
var bot_input: Callable          # tests: a novice model returns [stick, rt_held, cut]
var difficulty := ""
var rules := HandLine.new()
var t := 0.0
var result: Dictionary = {}
var flash := 0.0
var flash_text := ""
var _rt_was := false
var _font: Font
var _cfg: Dictionary
var _bot_cd := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_cfg = Game.tuning("hand_line", difficulty)
	if not embedded:
		start(false, 0.3)

func start(fog: bool, current: float, seed: int = 0) -> void:
	_cfg = Game.tuning("hand_line", difficulty)
	rules = HandLine.new()
	rules.setup(_cfg, seed, hook_stock)
	rules.fog = fog
	rules.current = current
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	flash = maxf(0.0, flash - delta)
	if result.is_empty():
		var stick := Controls.left_stick().y
		var rt := Input.get_action_strength("rt") > 0.5
		var cut := Input.is_action_just_pressed("drop")
		if autopilot:
			var b := _bot()
			stick = b[0]; rt = b[1]; cut = false
		elif bot_input.is_valid():
			var b2: Array = bot_input.call(self)
			stick = b2[0]; rt = b2[1]; cut = b2[2]
		var pressed := rt and not _rt_was
		_rt_was = rt
		for e in rules.step(delta, stick, pressed, cut):
			_on_event(e)
		if rules.phase == HandLine.Phase.DONE:
			result = {"person_days": rules.person_days(), "hooks_lost": rules.hooks_lost, "catch": rules.catch}
			finished.emit(result)
	queue_redraw()

func _on_event(e: String) -> void:
	match e:
		"tug": Controls.pulse(0.9, 0.2, 0.16)          # left-heavy tug
		"nibble": Controls.pulse(0.3, 0.0, 0.08)
		"twitch": Controls.pulse(0.15, 0.0, 0.05)
		"hooked": _say("Hooked!"); Controls.pulse(0.6, 0.6, 0.2)
		"spooked": _say("Struck too soon. It let go.")
		"stolen": _say("Bait stolen.")
		"snapped": _say("The line parted. Hook lost."); Controls.pulse(1.0, 1.0, 0.25)
		"landed": _say("Landed: %s" % rules.catch[-1].kind)
		"cut": _say("Line cut. Hook lost, hands safe.")

func _say(s: String) -> void:
	flash_text = s
	flash = 1.6

## Test bot: drops to cod depth, strikes on the ease, hauls while the line is under the snap point.
func _bot() -> Array:
	var stick := 0.0
	var rt := false
	match rules.phase:
		HandLine.Phase.WAITING:
			stick = clampf((24.0 - rules.depth) / 4.0, -1, 1)
		HandLine.Phase.EASE:
			rt = true
		HandLine.Phase.HOOKED:
			stick = -1.0 if rules.tension < 0.8 else 0.6
	return [stick, rt]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start(rules.fog, rules.current)
		return
	if embedded:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1: start(false, 0.3)
			KEY_2: start(true, 0.3)
			KEY_3: start(false, 1.0)
			KEY_R: start(rules.fog, rules.current)

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var ink := Color("ede3cc")
	# sky and gunwale
	draw_rect(Rect2(0, 0, 1920, SURFACE_Y), Color("a9b9c0") if not rules.fog else Color("d6dcdc"))
	# water gradient
	for i in 20:
		var y0 := SURFACE_Y + i * 41.0
		draw_rect(Rect2(0, y0, 1920, 42), Color("3d6a72").lerp(Color("0d1a20"), i / 19.0))
	var bottom := SURFACE_Y + float(_cfg.max_depth_m) * PX_PER_M
	draw_rect(Rect2(0, bottom, 1920, 1080 - bottom), Color("2a2a22"))
	for x in range(0, 1920, 70):
		var h := 60.0 + 40.0 * sin(x * 0.03)
		var sway := sin(t * 0.8 + x) * 14.0
		draw_line(Vector2(x, bottom), Vector2(x + sway, bottom - h), Color("2e4a36"), 5.0)
	# depth marks
	for m in range(5, int(_cfg.max_depth_m) + 1, 5):
		var y := SURFACE_Y + m * PX_PER_M
		draw_line(Vector2(40, y), Vector2(70, y), Color(ink, 0.35), 2.0)
		draw_string(_font, Vector2(80, y + 7), "%d m" % m, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.45))
	# surface line
	draw_line(Vector2(0, SURFACE_Y), Vector2(1920, SURFACE_Y), Color(0.9, 0.95, 0.95, 0.6), 3.0)
	# line and hook
	var sig := rules.line_signal()
	var jerk := 0.0
	if sig >= 1.0:
		jerk = 18.0
	elif sig > 0.2 and rules.phase != HandLine.Phase.HOOKED:
		jerk = 6.0
	var drift := sin(t * 1.3) * 18.0 * rules.current
	var hook := Vector2(HOOK_X + drift, SURFACE_Y + rules.depth * PX_PER_M - jerk)
	var hand := Vector2(900, 210 - jerk * 0.5)
	if sig < 0.0:
		var mid := (hand + hook) / 2.0 + Vector2(60, 0)           # the ease: line bows slack
		draw_polyline(PackedVector2Array([hand, mid, hook]), Color("ede3cc"), 2.0)
	else:
		draw_line(hand, hook, Color("ede3cc"), 2.0 + (rules.tension * 3.0 if rules.phase == HandLine.Phase.HOOKED else 0.0))
	draw_circle(hook, 6, Color("8a8a80"))
	if rules.bait and rules.phase != HandLine.Phase.HOOKED:
		draw_circle(hook + Vector2(0, 8), 7, Color("c98a6a"))
	# fish: approaching during the bite, on the hook when hooked (hidden in fog until hooked)
	var show_fish := rules.fish != "" and rules.phase in [HandLine.Phase.NIBBLE, HandLine.Phase.TUG1, HandLine.Phase.GAP, HandLine.Phase.TUG2, HandLine.Phase.EASE, HandLine.Phase.HOOKED]
	if show_fish and (not rules.fog or rules.phase == HandLine.Phase.HOOKED):
		var size := {"cod": 1.0, "char": 0.7, "halibut": 1.6}.get(rules.fish, 1.0) as float
		var fpos := hook + Vector2(70 * size, 10)
		var col := {"cod": Color("8a8a6a"), "char": Color("b07a5a"), "halibut": Color("6a6252")}.get(rules.fish, Color.GRAY) as Color
		draw_set_transform(fpos, sin(t * 9.0) * 0.12, Vector2(size, size * (0.6 if rules.fish == "halibut" else 1.0)))
		draw_colored_polygon(PackedVector2Array([Vector2(-70, 0), Vector2(-30, -22), Vector2(40, -16), Vector2(70, 0), Vector2(40, 16), Vector2(-30, 22)]), col)
		draw_colored_polygon(PackedVector2Array([Vector2(70, 0), Vector2(100, -20), Vector2(100, 20)]), col)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if rules.fog:
		draw_rect(Rect2(0, SURFACE_Y, 1920, 1080 - SURFACE_Y), Color(0.75, 0.8, 0.8, 0.28))
	# gunwale and hands
	draw_rect(Rect2(600, 196, 520, 40), Color("4a3828"))
	draw_rect(Rect2(860, 190 - jerk * 0.5, 80, 50), Color("6b4a35"))
	# HUD
	draw_rect(Rect2(24, 20, 760, 140), Color(0.1, 0.09, 0.07, 0.8))
	draw_string(_font, Vector2(44, 60), "HAND LINE  ·  %s" % ("fog" if rules.fog else ("strong current" if rules.current > 0.6 else "clear water")), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	draw_string(_font, Vector2(44, 96), "LS down pay out · LS up haul · RT set on the ease · B cut the line", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	draw_string(_font, Vector2(44, 132), "Hooks %d   ·   catch %d (%.0f person-days)   ·   %ds left   ·   line out %.0f m" % [
		rules.hooks, rules.catch.size(), rules.person_days(), maxi(0, ceili(rules.time_left)), rules.depth], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.9))
	if not embedded:
		draw_string(_font, Vector2(44, 190), "Keys: W/S line · Space set · Esc cut · 1 clear · 2 fog · 3 current · R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink, 0.55))
	if rules.phase == HandLine.Phase.HOOKED:
		var tx := 1500.0
		draw_rect(Rect2(tx, 40, 40, 300), Color(0.1, 0.09, 0.07, 0.8))
		var h := clampf(rules.tension / 1.4, 0, 1) * 300.0
		draw_rect(Rect2(tx, 340 - h, 40, h), Color("c9a55a") if rules.tension < 1.0 else Color("9e3a2e"))
		var snap_y := 340.0 - 300.0 / 1.4
		draw_line(Vector2(tx - 10, snap_y), Vector2(tx + 50, snap_y), Color("9e3a2e"), 3.0)
		draw_string(_font, Vector2(tx - 30, 380), "line strain", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	if bool(_cfg.get("bite_banner", false)) and result.is_empty():
		var banner := ""
		var bcol := ink
		match rules.phase:
			HandLine.Phase.NIBBLE: banner = "nibble... wait"
			HandLine.Phase.TUG1, HandLine.Phase.GAP: banner = "TUG"
			HandLine.Phase.TUG2: banner = "TUG TUG"
			HandLine.Phase.EASE:
				banner = "NOW!  pull RT"
				bcol = Color("e8c35a")
			HandLine.Phase.HOOKED:
				banner = "Haul (LS up) · ease off (LS down) when the strain goes red"
		if banner != "":
			draw_rect(Rect2(1080, 400, 760, 90), Color(0.08, 0.07, 0.06, 0.8))
			draw_string(_font, Vector2(1110, 460), banner, HORIZONTAL_ALIGNMENT_LEFT, 720, 40 if rules.phase != HandLine.Phase.HOOKED else 24, bcol)
		elif rules.phase == HandLine.Phase.WAITING and rules.bait:
			var hint := "Let out line (LS down) to the deep water: cod are 20-30 m down" if rules.depth < 16.0 else "Wait for the bite..."
			draw_rect(Rect2(1080, 400, 760, 70), Color(0.08, 0.07, 0.06, 0.6))
			draw_string(_font, Vector2(1110, 446), hint, HORIZONTAL_ALIGNMENT_LEFT, 720, 22, Color(ink, 0.85))
	if flash > 0.0:
		draw_string(_font, Vector2(1100, 210), flash_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(ink, minf(1.0, flash)))
	if not result.is_empty():
		draw_rect(Rect2(560, 420, 800, 220), Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(Rect2(560, 420, 800, 8), Color("6e8a4e") if result.person_days > 0 else Color("9e3a2e"))
		var kinds := {}
		for f in result.catch:
			kinds[f.kind] = kinds.get(f.kind, 0) + 1
		var parts: Array = []
		for k2 in kinds:
			parts.append("%d %s" % [kinds[k2], k2])
		draw_string(_font, Vector2(600, 490), "The watch is over: %s." % (", ".join(parts) if parts.size() > 0 else "nothing"), HORIZONTAL_ALIGNMENT_LEFT, 720, 30, ink)
		draw_string(_font, Vector2(600, 540), "%.0f person-days of fresh fish · %d hooks lost" % [result.person_days, result.hooks_lost], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(ink, 0.85))
		draw_string(_font, Vector2(600, 600), "A: back" if embedded else "A: fish again", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
