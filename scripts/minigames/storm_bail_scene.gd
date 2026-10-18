extends Node2D
## MG10 Storm bail (Backlog F10). First find the leak: LS left/right to look along the hull, A to stuff wool in.
## Then bail: RT on the beat (the swinging bucket marks it). Waves rumble one beat before they land;
## the wave marker is the visual twin of that rumble.

signal finished(result: Dictionary)
signal closed

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [ls_x, a_pressed, rt_pressed]
var difficulty := ""
var rules := StormBail.new()
var result: Dictionary = {}
var t := 0.0
var splash := 0.0
var _cfg: Dictionary
var _font: Font
var _rt_was := false
var _rumbled := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start()

func start(seed: int = 0) -> void:
	_cfg = Game.tuning("storm_bail", difficulty)
	rules = StormBail.new()
	rules.setup(_cfg, seed)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	splash = maxf(0.0, splash - delta * 2.0)
	if result.is_empty():
		var lx := Controls.left_stick().x
		var a := Input.is_action_just_pressed("commit")
		var rt_now := Input.get_action_strength("rt") > 0.5
		var rt := rt_now and not _rt_was
		_rt_was = rt_now
		if autopilot:
			var b := _bot()
			lx = b[0]; a = b[1]; rt = b[2]
		elif bot_input.is_valid():
			var b2: Array = bot_input.call(self)
			lx = b2[0]; a = b2[1]; rt = b2[2]
		for e in rules.step(delta, lx, a, rt):
			match e:
				"wave": splash = 1.0
				"scoop": Controls.pulse(0.25, 0.1, 0.06)
				"plugged": Controls.pulse(0.3, 0.3, 0.1)
				"swamped": Controls.pulse(1.0, 1.0, 0.4)
		var coming := rules.wave_coming()
		if coming and not _rumbled:
			Controls.pulse(0.1, 0.8, 0.3)       # the rumble arrives a beat before the wave
		_rumbled = coming
		if rules.phase >= StormBail.Phase.HELD:
			result = {"held": rules.held(), "peak": rules.peak, "plugged": rules.plugged}
			finished.emit(result)
	queue_redraw()

## Test bot: finds the leak, then scoops right on the beat.
func _bot() -> Array:
	if rules.phase == StormBail.Phase.CHECK:
		var d := rules.leak_spot - rules.look
		return [float(signi(d)), d == 0 and rules.check_wait <= 0.0, false]
	return [0.0, false, rules.beat_phase() < 0.05]

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
	# the hold seen from inside, looking aft
	draw_rect(Rect2(0, 0, 1920, 1080), Color("3a4650"))
	draw_colored_polygon(PackedVector2Array([Vector2(120, 180), Vector2(1800, 180), Vector2(1560, 1000), Vector2(360, 1000)]), Color("4a3828"))
	for i in 7:
		var y := 220.0 + i * 110.0
		var inset := 120.0 + i * 34.0
		draw_line(Vector2(inset, y), Vector2(1920 - inset, y), Color("6b4a35"), 6.0)
	for x in [520.0, 960.0, 1400.0]:
		draw_line(Vector2(x, 180), Vector2(x + (960 - x) * 0.25, 1000), Color("2a2119"), 10.0)
	# water rising in the bilge
	var wy := 1000.0 - rules.water * 760.0
	var pts := PackedVector2Array()
	for x in range(300, 1621, 40):
		pts.append(Vector2(x, minf(990.0, wy + sin(x * 0.02 + t * 3.0) * (6.0 + splash * 20.0))))
	pts.append(Vector2(1620, 1000)); pts.append(Vector2(300, 1000))
	draw_colored_polygon(pts, Color(0.18, 0.29, 0.34, 0.85))
	# the full line
	draw_line(Vector2(300, 240), Vector2(1620, 240), Color("9e3a2e", 0.7), 4.0)
	draw_string(_font, Vector2(1640, 248), "swamped", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("9e3a2e"))
	# seams: the leaking one drips (until plugged)
	var spots := [Vector2(460, 600), Vector2(960, 640), Vector2(1460, 600)]
	for i in 3:
		var p: Vector2 = spots[i]
		var looking := rules.phase == StormBail.Phase.CHECK and rules.look == i
		if looking:
			draw_arc(p, 70, 0, TAU, 40, Color("e8c35a"), 5.0)
		if i == rules.leak_spot and not rules.plugged:
			for k in 4:
				var dy := fmod(t * 300.0 + k * 40.0, 160.0)
				draw_circle(p + Vector2(0, dy), 6, Color(0.7, 0.85, 0.9, 0.9))
		if i == rules.leak_spot and rules.plugged:
			draw_rect(Rect2(p - Vector2(30, 8), Vector2(60, 16)), Color("ede3cc"))
	# the beat: a swinging bucket metronome
	var bp := rules.beat_phase()
	var swing := sin(bp * TAU) * 0.6
	var pivot := Vector2(960, 1010)
	var bucket := pivot + Vector2(sin(swing) * 140, -cos(swing) * 140) * Vector2(1, -1)
	draw_line(pivot, bucket, Color("8a6d4e"), 6.0)
	var on_beat := minf(bp, 1.0 - bp) * float(_cfg.beat_seconds) <= float(_cfg.window_seconds)
	draw_rect(Rect2(bucket - Vector2(30, 24), Vector2(60, 48)), Color("e8c35a") if on_beat else Color("6b4a35"))
	# wave marker: the visual twin of the early rumble
	if rules.wave_coming():
		draw_rect(Rect2(1640, 420, 240, 90), Color(0.1, 0.09, 0.07, 0.85))
		draw_string(_font, Vector2(1660, 478), "WAVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("e8c35a"))
	if splash > 0.0:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.85, 0.9, 0.95, splash * 0.2))
	# HUD
	draw_rect(Rect2(24, 20, 960, 150), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "STORM  ·  no sky tonight", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var step := ""
	if rules.phase == StormBail.Phase.CHECK:
		step = "1  Find the leak: look along the hull (%s) for the drip, then stuff it with wool (%s)" % ["A / D" if kb else "left stick", "Enter" if kb else "A"]
	elif rules.phase == StormBail.Phase.BAIL:
		step = "2  Bail on the beat: %s each time the bucket swings gold. Keep the water under the red line" % ("Space" if kb else "RT")
	elif rules.held():
		step = "The hull holds. Dawn comes up grey."
	else:
		step = "Swamped."
	draw_string(_font, Vector2(44, 100), step, HORIZONTAL_ALIGNMENT_LEFT, 920, 22, Color("e8c35a") if Game.settings.difficulty != "hard" else ink)
	draw_string(_font, Vector2(44, 150), "Water %d%%   ·   rhythm %d   ·   %ds to dawn" % [roundi(rules.water * 100), rules.combo, maxi(0, ceili(float(_cfg.session_seconds) - (rules.t if rules.phase == StormBail.Phase.BAIL else 0.0)))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	if not result.is_empty():
		draw_rect(Rect2(560, 420, 800, 200), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 800, 8), Color("6e8a4e") if result.held else Color("9e3a2e"))
		draw_string(_font, Vector2(600, 490), "The hull holds through the storm." if result.held else "She swamped. Something was lost.", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		draw_string(_font, Vector2(600, 570), "A: back" if embedded else "A: another storm   ·   R restart", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
