extends Node2D
## MG4 The net (Backlog F14). RS aims the throw · A casts · both triggers draw it closed as it reaches the
## school. Weight builds in both triggers as the school comes under the net; its visual twin is the
## water darkening and the surface boiling over the school.

signal finished(result: Dictionary)
signal closed

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [rs: Vector2, cast: bool, lt: float, rt: float]
var difficulty := ""
var rules := NetThrow.new()
var result: Dictionary = {}
var t := 0.0
var _cfg: Dictionary
var _font: Font
var _beat := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start(false, false)

func start(rain: bool, fog: bool, seed: int = 0) -> void:
	_cfg = Game.tuning("net", difficulty)
	rules = NetThrow.new()
	rules.setup(_cfg, Knobs.num("net_most_a_throw_can_land", 48), int(Knobs.num("net_throws_per_day", 1)), seed, rain, fog)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	_beat -= delta
	if result.is_empty():
		var rs := Controls.right_stick()
		var cast := Input.is_action_just_pressed("commit")
		var lt := Input.get_action_strength("lt")
		var rt := Input.get_action_strength("rt")
		var b: Array = []
		if autopilot:
			b = _bot()
		elif bot_input.is_valid():
			b = bot_input.call(self)
		if b.size() == 4:
			rs = b[0]; cast = b[1]; lt = b[2]; rt = b[3]
		var evs := rules.step(delta, rs, cast, lt, rt)
		if rules.phase == NetThrow.Phase.SINK and _beat <= 0.0:
			var w := rules.overlap()
			if w > 0.05:
				Controls.pulse(w * 0.6, w * 0.6, 0.08)    # weight in the triggers as the school comes under
			_beat = 0.15
		if "catch" in evs:
			Controls.pulse(0.6, 0.6, 0.3)
		elif "empty" in evs or "bottom" in evs:
			Controls.pulse(0.1, 0.4, 0.2)
		if rules.phase == NetThrow.Phase.DONE:
			result = {"person_days": rules.catch_pd, "empty": rules.catch_pd <= 0.0, "throws": rules.throws}
			finished.emit(result)
	queue_redraw()

## Expert bot: leads the school by the flight and the sink, casts, and closes at the school's depth.
func _bot() -> Array:
	var r := rules
	if r.phase == NetThrow.Phase.AIM:
		var lead: float = float(_cfg.flight_time) + r.school_depth / float(_cfg.sink_rate)
		var want: Vector2 = r.school + r.school_v * lead
		var to: Vector2 = want - r.aim
		return [to.normalized() * clampf(to.length() / 60.0, 0.0, 1.0), to.length() < 14.0, 0.0, 0.0]
	if r.phase == NetThrow.Phase.SINK and r.net_depth >= r.school_depth - 0.01:
		return [Vector2.ZERO, false, 1.0, 1.0]
	return [Vector2.ZERO, false, 0.0, 0.0]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start(rules.rain, rules.fog)
		return
	if not embedded and e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_1: start(false, false)
			KEY_2: start(true, false)
			KEY_3: start(false, true)

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	var r := rules
	# shore, shallows and the boat
	draw_rect(Rect2(0, 0, 1920, 1080), Color("51707e") if not r.rain else Color("46606c"))
	draw_rect(Rect2(0, 0, 1920, 230), Color("4d6a48"))
	draw_rect(Rect2(0, 230, 1920, 24), Color("b9ae8f"))      # the shingle
	if r.rain:
		for k in 60:
			var x := fmod(k * 137.0 + t * 400.0, 1920.0)
			var y := fmod(k * 89.0 + t * 900.0, 1080.0)
			draw_line(Vector2(x, y), Vector2(x - 6, y + 22), Color(1, 1, 1, 0.25), 1.5)
	# the school: dark water and a boiling surface (the visual twin of the trigger weight)
	if r.school_seen():
		var a := 0.45 if r.rain else 0.7
		draw_circle(r.school, r.school_r, Color(0.12, 0.2, 0.24, a))
		for k in 7:
			var p: Vector2 = r.school + Vector2(cos(t * 3.0 + k * 0.9), sin(t * 2.3 + k * 1.7)) * r.school_r * 0.6
			draw_arc(p, 8 + 4 * sin(t * 6.0 + k), 0, TAU, 12, Color(1, 1, 1, a * 0.6), 2.0)
	if r.fog:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.85, 0.87, 0.88, 0.55))
		draw_circle(NetThrow.BOAT, float(_cfg.fog_radius), Color(0.85, 0.87, 0.88, 0.0))
	# the boat
	draw_colored_polygon(PackedVector2Array([NetThrow.BOAT + Vector2(-110, -20), NetThrow.BOAT + Vector2(110, -20), NetThrow.BOAT + Vector2(80, 30), NetThrow.BOAT + Vector2(-80, 30)]), Color("4a3828"))
	draw_circle(NetThrow.BOAT + Vector2(0, -40), 18, Color("6b4a35"))
	var R := float(_cfg.net_radius)
	match r.phase:
		NetThrow.Phase.AIM:
			draw_arc(r.aim, R, 0, TAU, 48, Color(ink, 0.8), 3.0)
			draw_line(r.aim - Vector2(14, 0), r.aim + Vector2(14, 0), ink, 2.0)
			draw_line(r.aim - Vector2(0, 14), r.aim + Vector2(0, 14), ink, 2.0)
			draw_line(NetThrow.BOAT + Vector2(0, -40), r.aim, Color(ink, 0.25), 2.0)
		NetThrow.Phase.FLIGHT:
			var f := clampf(r.phase_t / float(_cfg.flight_time), 0.0, 1.0)
			var p := NetThrow.BOAT.lerp(r.net_at, f) - Vector2(0, sin(f * PI) * 200)
			draw_arc(p, R * (0.3 + 0.7 * f), 0, TAU, 32, ink, 3.0)
		NetThrow.Phase.SINK, NetThrow.Phase.HAULED:
			var fade := 1.0 - r.net_depth * 0.6
			draw_arc(r.net_at, R, 0, TAU, 48, Color(ink, fade), 3.0)
			for k in 12:
				var a2 := k * TAU / 12.0
				draw_line(r.net_at, r.net_at + Vector2(cos(a2), sin(a2)) * R, Color(ink, fade * 0.4), 1.0)
	# depth gauge: net sinking, the school's depth band
	draw_rect(Rect2(1760, 320, 50, 520), Color(0.1, 0.09, 0.07, 0.85))
	if bool(_cfg.get("banner", false)) or r.school_seen():
		var tol := float(_cfg.depth_tol) * 0.5
		draw_rect(Rect2(1760, 320 + 520 * (r.school_depth - tol), 50, 520 * tol * 2.0), Color(0.45, 0.72, 0.8, 0.85))
	if r.phase == NetThrow.Phase.SINK:
		draw_rect(Rect2(1750, 320 + 520 * r.net_depth - 4, 70, 8), Color("e8c35a"))
	draw_string(_font, Vector2(1740, 870), "depth", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	# HUD
	draw_rect(Rect2(24, 20, 1060, 150), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "THE NET  ·  %s" % ("rain: the school runs deep" if r.rain else ("fog" if r.fog else "the shallows")), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var help := "Arrows aim · Enter cast · hold Space + Shift to close" if kb else "RS aim · A cast · both triggers close"
	draw_string(_font, Vector2(44, 98), help, HORIZONTAL_ALIGNMENT_LEFT, 1020, 20, Color(ink, 0.75))
	draw_string(_font, Vector2(44, 140), "Throws left %d   ·   %ds of slack water" % [r.throws_left, maxi(0, ceili(float(_cfg.session_seconds) - r.t))], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	if bool(_cfg.get("banner", false)) and result.is_empty():
		var tip := ""
		match r.phase:
			NetThrow.Phase.AIM:
				tip = "Aim ahead of the dark water (%s), then cast (%s)." % ["arrows" if kb else "right stick", "Enter" if kb else "A"] if r.school_seen() else "Fog: watch for the school near the boat."
			NetThrow.Phase.FLIGHT:
				tip = "The net is in the air..."
			NetThrow.Phase.SINK:
				tip = "Close it (%s) as the gold mark reaches the blue band." % ("Space + Shift" if kb else "both triggers")
		draw_rect(Rect2(460, 980, 1100, 64), Color(0.08, 0.07, 0.06, 0.8))
		draw_string(_font, Vector2(490, 1024), tip, HORIZONTAL_ALIGNMENT_LEFT, 1060, 26, ink)
	if not result.is_empty():
		var line := "An empty net. The day is spent." if result.empty else "The net comes up heavy: %d person-days of fish." % roundi(result.person_days)
		draw_rect(Rect2(560, 420, 820, 180), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 820, 8), Color("9e3a2e") if result.empty else Color("6e8a4e"))
		draw_string(_font, Vector2(600, 490), line, HORIZONTAL_ALIGNMENT_LEFT, 760, 26, ink)
		draw_string(_font, Vector2(600, 560), "A: back" if embedded else "A: again · 1 clear · 2 rain · 3 fog", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
