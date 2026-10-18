extends Node2D
## MG7 The joint (Backlog F07). LS brace the timber · RS turn the peg to the hole · RT drive (pull = one blow).
## The grain line turns red as the load builds (the visual twin of the trigger's resistance).
## Debug keys when standalone: 1 dry, 2 rain, R new timber.

signal finished(result: Dictionary)
signal closed

var embedded := false
var autopilot := false
var rules := Joint.new()
var _cfg: Dictionary
var _font: Font
var t := 0.0
var strike := 0.0
var result: Dictionary = {}
var _bot_cycle := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_cfg = JSON.parse_string(FileAccess.open("res://data/minigames.json", FileAccess.READ).get_as_text()).joint
	if not embedded:
		start(false)

func start(rain: bool, seed: int = 0) -> void:
	rules = Joint.new()
	rules.setup(_cfg, seed, rain)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	strike = maxf(0.0, strike - delta * 5.0)
	if result.is_empty():
		var ls := Controls.left_stick().x
		var rs := Controls.right_stick().x
		var rt := Input.get_action_strength("rt")
		if autopilot:
			ls = clampf(rules.wobble * 3.0, -1, 1)
			rs = clampf((rules.hole_angle - rules.peg_angle) / 8.0, -1, 1)
			_bot_cycle += delta
			rt = 0.65 if rules.phase == Joint.Phase.DRIVE and fmod(_bot_cycle, 0.6) < 0.25 and rules.grain_load() < 0.55 else 0.0
		for e in rules.step(delta, ls, rs, rt):
			match e:
				"blow":
					strike = 1.0
					Controls.pulse(0.3 + rules.grain_load() * 0.5, 0.2 + rules.grain_load() * 0.8, 0.1)
				"split": Controls.pulse(1.0, 1.0, 0.35)
				"seated": Controls.pulse(0.4, 0.4, 0.15)
		if rules.phase >= Joint.Phase.SEATED:
			result = {"seated": rules.succeeded(), "phase": rules.phase, "blows": rules.blows, "seconds": rules.t}
			finished.emit(result)
	queue_redraw()

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start(rules.rain)
		return
	if embedded:
		return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1: start(false)
			KEY_2: start(true)
			KEY_R: start(rules.rain)

func _draw() -> void:
	var ink := Color("ede3cc")
	# background: workbench in the camp
	draw_rect(Rect2(0, 0, 1920, 1080), Color("6e8a4e") if not rules.rain else Color("4f6048"))
	draw_rect(Rect2(0, 0, 1920, 420), Color("a9c4d0") if not rules.rain else Color("7d8a90"))
	draw_rect(Rect2(300, 700, 60, 300), Color("4a3828"))
	draw_rect(Rect2(1560, 700, 60, 300), Color("4a3828"))
	# the timber rocks with the wobble
	var center := Vector2(960, 640)
	var rot := rules.wobble * 0.06
	draw_set_transform(center, rot, Vector2.ONE)
	var wood := Color("b08a5e") if not rules.rain else Color("8a6a46")
	draw_rect(Rect2(-700, -80, 1400, 160), wood)
	var load := rules.grain_load()
	var grain := Color("6b4a35").lerp(Color("c0392b"), load)
	for i in 7:
		var y := -60.0 + i * 20.0
		var pts := PackedVector2Array()
		for x in range(-700, 701, 50):
			pts.append(Vector2(x, y + sin(x * 0.01 + i) * 6.0))
		draw_polyline(pts, grain, 2.0 + load * 3.0)
	if rules.phase == Joint.Phase.SPLIT:
		draw_line(Vector2(-700, 0), Vector2(700, 8), Color("1c1915"), 10.0)
	# mortise hole and its angle mark
	var hole_dir := Vector2.UP.rotated(deg_to_rad(rules.hole_angle))
	draw_circle(Vector2(0, -80), 34, Color("2a1f17"))
	draw_line(Vector2(0, -80), Vector2(0, -80) + hole_dir * 120, Color(ink, 0.35), 3.0)
	# peg sinks with depth
	var sink := rules.depth * 200.0
	var peg_dir := Vector2.UP.rotated(deg_to_rad(rules.peg_angle))
	var peg_base := Vector2(0, -80) + peg_dir * (-sink + 0.0)
	var peg_top := peg_base + peg_dir * 240.0
	var aligned := rules.misalign() <= float(_cfg.peg_tolerance_deg)
	draw_line(peg_base, peg_top, Color("d8c09a") if aligned else Color("c9a55a"), 40.0)
	# mallet
	var mallet_y := -340.0 - (1.0 - strike) * 120.0 - sink
	draw_rect(Rect2(-90, mallet_y, 180, 90), Color("5a3e2b"))
	draw_line(Vector2(80, mallet_y + 45), Vector2(320, mallet_y + 140), Color("6b4a35"), 16.0)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if rules.rain:
		for i in 80:
			var rx := fmod(i * 97.0 + t * 700.0, 1920.0)
			var ry := fmod(i * 53.0 + t * 1200.0, 1080.0)
			draw_line(Vector2(rx, ry), Vector2(rx - 8, ry + 30), Color(0.85, 0.88, 0.9, 0.3), 1.5)
	# HUD
	draw_rect(Rect2(24, 20, 900, 150), Color(0.1, 0.09, 0.07, 0.82))
	var step_text := {Joint.Phase.BRACE: "1  Brace the timber with the left stick until it stops rocking",
		Joint.Phase.SET: "2  Turn the peg to the hole with the right stick",
		Joint.Phase.DRIVE: "3  Drive it: pull RT for each blow. A half pull drives with the grain; a full pull can split it",
		Joint.Phase.SEATED: "The joint is seated.", Joint.Phase.SPLIT: "The log split along the grain.", Joint.Phase.TIMEOUT: "The light is gone and the peg is not home."}
	draw_string(_font, Vector2(44, 60), "THE JOINT  ·  %s" % ("rain: the grain takes less" if rules.rain else "dry"), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	draw_string(_font, Vector2(44, 98), step_text[rules.phase], HORIZONTAL_ALIGNMENT_LEFT, 860, 21, Color(ink, 0.9))
	draw_string(_font, Vector2(44, 150), "Blows %d   ·   peg home %d%%   ·   %ds of light left" % [rules.blows, roundi(rules.depth * 100), maxi(0, ceili(float(_cfg.max_seconds) - rules.t))],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	if not embedded:
		draw_string(_font, Vector2(44, 200), "Keys: A/D brace · arrows turn peg · Space drive · 1 dry · 2 rain · R new timber", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(ink, 0.6))
	# meters: brace, alignment, grain
	_meter(Vector2(1520, 40), "brace", 1.0 - clampf(absf(rules.wobble) / 0.6, 0, 1), rules.braced())
	_meter(Vector2(1600, 40), "peg", 1.0 - clampf(rules.misalign() / 30.0, 0, 1), aligned)
	_meter(Vector2(1680, 40), "grain", 1.0 - load, load < 0.6)
	if not result.is_empty():
		draw_rect(Rect2(560, 820, 800, 180), Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(Rect2(560, 820, 800, 8), Color("6e8a4e") if result.seated else Color("9e3a2e"))
		var line := "Seated in %d blows. The day counts." % result.blows if result.seated else ("Split log. The day is lost." if rules.phase == Joint.Phase.SPLIT else "Not home before dark. The day is lost.")
		draw_string(_font, Vector2(600, 890), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		draw_string(_font, Vector2(600, 950), "A: back" if embedded else "A: next timber", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))

func _meter(at: Vector2, label: String, v: float, ok: bool) -> void:
	draw_rect(Rect2(at, Vector2(40, 220)), Color(0.1, 0.09, 0.07, 0.82))
	draw_rect(Rect2(at + Vector2(0, 220 - 220 * v), Vector2(40, 220 * v)), Color("6e8a4e") if ok else Color("c9a55a"))
	draw_string(_font, at + Vector2(-8, 250), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ede3cc"))
