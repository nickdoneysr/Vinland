extends Node2D
## MG7 The joint (Backlog F07). LS brace the timber · RS turn the peg to the hole · RT drive (pull = one blow).
## The grain line turns red as the load builds (the visual twin of the trigger's resistance).
## Debug keys when standalone: 1 dry, 2 rain, R new timber.

signal finished(result: Dictionary)
signal closed

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: a novice model returns [ls, rs, rt]
var difficulty := ""
var keyboard_charge := false     # tests can force the keyboard model
var _charge := 0.0               # keyboard: holding the drive key winds up the blow
var _pull := 0.0                 # what the gauge shows: current pull or wind-up
var _last_force := -1.0
var rules := Joint.new()
var _cfg: Dictionary
var _font: Font
var t := 0.0
var strike := 0.0
var result: Dictionary = {}
var _bot_cycle := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_cfg = Game.tuning("joint", difficulty)
	if not embedded:
		start(false)

func start(rain: bool, seed: int = 0) -> void:
	_cfg = Game.tuning("joint", difficulty)
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
		# Keyboard: a key is all or nothing, so holding it winds the blow up (charge_seconds to full) and
		# letting go strikes at the wound-up force. A pad trigger strikes at how far it was pulled.
		if (Controls.keyboard or keyboard_charge) and not autopilot and not bot_input.is_valid():
			if rt > 0.5:
				_charge = minf(1.0, _charge + delta / float(_cfg.get("charge_seconds", 0.8)))
				rt = maxf(0.16, _charge)
			else:
				_charge = 0.0
				rt = 0.0
		if bot_input.is_valid():
			var b: Array = bot_input.call(self)
			ls = b[0]; rs = b[1]; rt = b[2]
			if keyboard_charge:
				if rt > 0.5:
					_charge = minf(1.0, _charge + delta / float(_cfg.get("charge_seconds", 0.8)))
					rt = maxf(0.16, _charge)
				else:
					_charge = 0.0
					rt = 0.0
		_pull = rt
		if autopilot:
			ls = clampf(rules.wobble * 3.0, -1, 1)
			rs = clampf((rules.hole_angle - rules.peg_angle) / 8.0, -1, 1)
			_bot_cycle += delta
			rt = 0.65 if rules.phase == Joint.Phase.DRIVE and fmod(_bot_cycle, 0.6) < 0.25 and rules.grain_load() < 0.55 else 0.0
		for e in rules.step(delta, ls, rs, rt):
			match e:
				"blow":
					strike = 1.0
					_last_force = rules._last_force
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
	var kb := Controls.keyboard
	var step_text := {Joint.Phase.BRACE: "1  Brace the timber (%s) against its rocking until the brace meter is green" % ("A / D" if kb else "left stick"),
		Joint.Phase.SET: "2  Turn the peg (%s) to line up with the hole's mark" % ("left / right arrows" if kb else "right stick"),
		Joint.Phase.DRIVE: "3  Drive it: %s. Too hard splits the log; keep the brace green" % ("hold Space and let go in the green" if kb else "pull RT into the green and release"),
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
	if rules.phase == Joint.Phase.DRIVE:
		_force_gauge(Vector2(1780, 40))
	if not result.is_empty():
		draw_rect(Rect2(560, 820, 800, 180), Color(0.08, 0.07, 0.06, 0.9))
		draw_rect(Rect2(560, 820, 800, 8), Color("6e8a4e") if result.seated else Color("9e3a2e"))
		var line := "Seated in %d blows. The day counts." % result.blows if result.seated else ("Split log. The day is lost." if rules.phase == Joint.Phase.SPLIT else "Not home before dark. The day is lost.")
		draw_string(_font, Vector2(600, 890), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
		draw_string(_font, Vector2(600, 950), "A: back" if embedded else "A: next timber", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))

## The blow gauge: how hard the next blow will land, with the band that drives with the grain.
func _force_gauge(at: Vector2) -> void:
	var ink := Color("ede3cc")
	var h := 220.0
	var best: Array = _cfg.best_force
	draw_rect(Rect2(at, Vector2(56, h)), Color(0.1, 0.09, 0.07, 0.82))
	var lo := float(best[0]); var hi := float(best[1])
	draw_rect(Rect2(at + Vector2(0, h - h * hi), Vector2(56, h * (hi - lo))), Color("6e8a4e", 0.55))
	draw_rect(Rect2(at + Vector2(0, 0), Vector2(56, h - h * hi)), Color("9e3a2e", 0.35))
	draw_rect(Rect2(at + Vector2(8, h - h * _pull), Vector2(40, h * _pull)), Color("e8c35a"))
	if _last_force >= 0.0:
		var y := at.y + h - h * _last_force
		draw_line(Vector2(at.x - 6, y), Vector2(at.x + 62, y), ink, 3.0)
	draw_string(_font, at + Vector2(-14, h + 30), "blow", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ink)
	var tip := "Hold Space, let go in the green" if Controls.keyboard else "Pull RT into the green, release"
	draw_string(_font, Vector2(1180, 330), tip, HORIZONTAL_ALIGNMENT_LEFT, 700, 22, ink)

func _meter(at: Vector2, label: String, v: float, ok: bool) -> void:
	draw_rect(Rect2(at, Vector2(40, 220)), Color(0.1, 0.09, 0.07, 0.82))
	draw_rect(Rect2(at + Vector2(0, 220 - 220 * v), Vector2(40, 220 * v)), Color("6e8a4e") if ok else Color("c9a55a"))
	draw_string(_font, at + Vector2(-8, 250), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ede3cc"))
