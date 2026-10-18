extends Node2D
## MG2 Sun board (Backlog F04). LS turns the disk · RS up/down sets the peg · RT holds the bowl steady ·
## A takes the reading · B gives up. A low hum in the pad when the shadow tip crosses the curve;
## its visual twin is the tip's glint and the curve lighting gold.

signal finished(result: Dictionary)
signal closed

const CENTER := Vector2(960, 590)
const R_PX := 330.0

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [turn, peg_move, hold, take, abort]
var difficulty := ""
var rules := SunBoard.new()
var result: Dictionary = {}
var t := 0.0
var _cfg: Dictionary
var _font: Font
var _was_on := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start(false)

func start(partly_cloudy: bool, seed: int = 0) -> void:
	_cfg = Game.tuning("sun_board", difficulty)
	rules = SunBoard.new()
	rules.setup(_cfg, seed, partly_cloudy)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	if result.is_empty():
		var turn := Controls.left_stick().x
		var peg_move := -Controls.right_stick().y
		var hold := Input.get_action_strength("rt") > 0.5
		var take := Input.is_action_just_pressed("commit")
		var abort := Input.is_action_just_pressed("drop")
		var b: Array = []
		if autopilot:
			b = _bot()
		elif bot_input.is_valid():
			b = bot_input.call(self)
		if b.size() == 5:
			turn = b[0]; peg_move = b[1]; hold = b[2]; take = b[3]; abort = b[4]
		var evs := rules.step(delta, turn, peg_move, hold, take, abort)
		var on := absf(rules.len_err()) <= float(_cfg.len_tol) and rules.sun_visible
		if on and not _was_on:
			Controls.pulse(0.0, 0.3, 0.12)           # the hum as the tip crosses the curve
		_was_on = on
		if "steady" in evs:
			Controls.pulse(0.3, 0.0, 0.1)
		if rules.phase == SunBoard.Phase.DONE:
			result = {"result": rules.result, "snatched": rules.snatched}
			finished.emit(result)
	queue_redraw()

## Expert bot: turns the disk onto the noon line, sets the peg, braces, and takes the reading once steady.
func _bot() -> Array:
	var r := rules
	var turn := clampf(r.dir_err() / 2.5, -1.0, 1.0)
	var pm := clampf((-r.len_err()) / 0.03, -1.0, 1.0)
	return [turn, pm, true, r.seat_held >= float(_cfg.seat_time) + 0.05, false]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start(rules.cloudy)
		return
	if not embedded and e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1: start(false)
			KEY_2: start(true)

func _v(deg: float) -> Vector2:
	return Vector2(sin(deg_to_rad(deg)), -cos(deg_to_rad(deg)))

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	var r := rules
	# the deck around the bowl, lit by noon sun (dimmer under cloud)
	var light := 1.0 if r.sun_visible else 0.7
	draw_rect(Rect2(0, 0, 1920, 1080), Color("6b4a35") * Color(light, light, light))
	for i in 12:
		draw_line(Vector2(0, 90 * i + 40), Vector2(1920, 90 * i + 40), Color("4a3828"), 4.0)
	var c := CENTER + Vector2(0, r.pitch() * 40.0)
	# the bowl of water
	draw_circle(c, R_PX + 60, Color("3a2a1c"))
	draw_circle(c, R_PX + 40, Color("5f8a9a"))
	# the disk, turned by the player
	draw_circle(c, R_PX, Color("c9a26a"))
	draw_arc(c, R_PX, 0, TAU, 72, Color("8a6d4e"), 6.0)
	for k in 32:
		var a := k * 360.0 / 32.0 + r.disk
		var inner := 0.9 if k % 4 == 0 else 0.95
		draw_line(c + _v(a) * R_PX * inner, c + _v(a) * R_PX, Color("6b4a35"), 3.0)
	# the noon line and the north mark
	draw_line(c, c + _v(r.disk) * R_PX * 0.98, Color("6b4a35"), 4.0)
	var nm := c + _v(r.disk) * (R_PX - 30)
	draw_colored_polygon(PackedVector2Array([nm + _v(r.disk) * 20, nm + _v(r.disk + 90) * 12, nm + _v(r.disk - 90) * 12]), Color("9e3a2e"))
	# the home curve, cut around the noon line
	var on: bool = r.on_mark()
	var curve_col := Color("e8c35a") if absf(r.len_err()) <= float(_cfg.len_tol) and r.sun_visible else Color("5a3f2a")
	var pts := PackedVector2Array()
	for k in 41:
		var a := r.disk - 45.0 + k * 90.0 / 40.0
		pts.append(c + _v(a) * SunBoard.CURVE * R_PX * (1.0 + 0.00012 * pow(a - r.disk, 2)))
	draw_polyline(pts, curve_col, 5.0)
	# the shadow of the peg
	if r.sun_visible:
		var dir := r.disk + r.shadow_dir()
		var tip := c + _v(dir) * r.shadow_len() * R_PX
		draw_line(c, tip, Color(0.15, 0.1, 0.06, 0.75), 12.0)
		if absf(r.len_err()) <= float(_cfg.len_tol):
			draw_circle(tip, 12, Color("fff2b0"))            # the glint: visual twin of the hum
	# the gnomon peg, its height shown by its size
	draw_circle(c, 10 + r.peg * 18, Color("3a2a1c"))
	draw_circle(c, 6 + r.peg * 10, Color("8a6d4e"))
	if not r.sun_visible:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.6, 0.65, 0.7, 0.35))
	# HUD
	draw_rect(Rect2(24, 20, 1060, 150), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "SUN BOARD  ·  noon", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var help := "A/D turn the disk · Up/Down the peg · Space steady · Enter take the reading · Esc give up" if kb else "LS turn the disk · RS up/down the peg · RT steady · A take the reading · B give up"
	draw_string(_font, Vector2(44, 98), help, HORIZONTAL_ALIGNMENT_LEFT, 1020, 20, Color(ink, 0.75))
	draw_string(_font, Vector2(44, 140), "%s   ·   %ds of noon left" % ["steadied" if r.brace > 0.8 else "rolling", maxi(0, ceili(float(_cfg.session_seconds) - r.t))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	# steadiness bar: visual twin of the steady pulse
	draw_rect(Rect2(1700, 40, 40, 260), Color(0.1, 0.09, 0.07, 0.85))
	var f := clampf(r.seat_held / float(_cfg.seat_time), 0.0, 1.0)
	draw_rect(Rect2(1700, 300 - 260 * f, 40, 260 * f), Color("6e8a4e") if f >= 1.0 else Color("c9a55a"))
	draw_string(_font, Vector2(1676, 330), "steady", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	if bool(_cfg.get("banner", false)) and result.is_empty():
		var tip_text := ""
		if not r.sun_visible:
			tip_text = "Cloud over the sun. Wait for the gap."
		elif absf(r.dir_err()) > float(_cfg.dir_tol):
			tip_text = "Turn the disk (%s): lay the shadow along the line to the red mark." % ("A / D" if kb else "left stick")
		elif absf(r.len_err()) > float(_cfg.len_tol):
			tip_text = "%s the peg (%s) until the shadow tip meets the curve." % ["Lower" if r.len_err() > 0 else "Raise", "Up / Down" if kb else "right stick"]
		elif r.brace < 0.8:
			tip_text = "Hold %s to steady the bowl through the roll." % ("Space" if kb else "RT")
		elif f < 1.0:
			tip_text = "Hold it there..."
		else:
			tip_text = "Steady. Take the reading (%s)." % ("Enter" if kb else "A")
		draw_rect(Rect2(460, 980, 1100, 64), Color(0.08, 0.07, 0.06, 0.8))
		draw_string(_font, Vector2(490, 1024), tip_text, HORIZONTAL_ALIGNMENT_LEFT, 1060, 26, Color("e8c35a") if on else ink)
	if not result.is_empty():
		var line: String = ["No reading. The error carries from yesterday.", "A snatched shadow: half the drift is saved.", "A clean noon reading. The day's drift is won back."][result.result]
		draw_rect(Rect2(560, 420, 820, 180), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 820, 8), [Color("9e3a2e"), Color("c9a55a"), Color("6e8a4e")][result.result])
		draw_string(_font, Vector2(600, 490), line, HORIZONTAL_ALIGNMENT_LEFT, 760, 26, ink)
		draw_string(_font, Vector2(600, 560), "A: back" if embedded else "A: another noon · 1 clear · 2 broken cloud", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
