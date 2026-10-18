extends Node2D
## MG1 Star ring (Backlog F03, F38). Gamepad grammar:
##   LS hold the ring against the ship's motion   RS fine-seat the Pole Star
##   RT raise the sight   LT lower the sight   A take the fix   B abort (partial at best)
## Debug keys: 1 clear, 2 clouded, 3 twilight, 4 fog, 5 storm swell, R new night.
## Draws procedurally until real art (SKY-07, NAV-01 ...) is saved at its listed path.

signal finished(result: Dictionary)
signal closed

var embedded := false   # true when the voyage opens the ring for one night

const K := 11.0                       # screen pixels per degree of altitude
const HORIZON_Y := 960.0
const CENTER := Vector2(960, 540)
const RING_R := 430.0
const BAR_OFFSET := 400.0             # bar sits this far below the ring centre
const WATCH_SECONDS := 75.0

const PRESETS := {
	"clear":    {"sea": 0.25, "cloud": 0.0,  "fog": false, "twilight": false, "label": "Clear night, easy swell"},
	"clouded":  {"sea": 0.35, "cloud": 0.75, "fog": false, "twilight": false, "label": "Clouded night"},
	"twilight": {"sea": 0.30, "cloud": 0.2,  "fog": false, "twilight": true,  "label": "Summer twilight"},
	"fog":      {"sea": 0.30, "cloud": 0.3,  "fog": true,  "twilight": false, "label": "Fog, false horizon"},
	"storm":    {"sea": 0.9,  "cloud": 0.45, "fog": false, "twilight": false, "label": "Heavy swell"},
}

var cond: Dictionary = PRESETS["clear"]
var preset_name := "clear"
var rule := RingFix.new()
var t := 0.0
var watch_left := WATCH_SECONDS
var ring_base := Vector2(960, HORIZON_Y - BAR_OFFSET)
var ring := ring_base
var reading := 55.0
var false_offset := 0.0
var clouds: Array = []
var guide: Array = []
var quality := 0.0
var outcome: Dictionary = {}
var _noise := FastNoiseLite.new()
var _pulse_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _font: Font
var autopilot := false          # test bot: steers like a skilled player (tests only)
var bot_input: Callable          # tests: a novice model returns [ls, rs, trig, commit]; replaces pad input
var cfg: Dictionary = {}
var difficulty := ""
var _vel := Vector2.ZERO
var autopilot_level_bias := 0.0  # degrees the bot mislevels by, to test grading

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.35
	new_night(preset_name)

func new_night(name: String) -> void:
	cfg = Game.tuning("ring", difficulty)
	rule.configure(cfg)
	preset_name = name
	cond = PRESETS[name]
	_rng.randomize()
	_noise.seed = _rng.randi()
	rule.reset(_rng.randf_range(58.5, 64.5))
	_vel = Vector2.ZERO
	t = 0.0
	watch_left = WATCH_SECONDS
	ring_base = Vector2(960 + _rng.randf_range(-120, 120), HORIZON_Y - BAR_OFFSET + _rng.randf_range(-60, 60))
	reading = _rng.randf_range(54.0, 68.0)
	false_offset = (_rng.randf_range(1.5, 3.0) * (1 if _rng.randf() < 0.5 else -1)) if cond.fog else 0.0
	outcome = {}
	clouds.clear()
	var n := int(cond.cloud * 16 * float(cfg.get("cloud_scale", 1.0)))
	for i in n:
		clouds.append({"p": Vector2(_rng.randf_range(-300, 2200), _rng.randf_range(-100, 760)),
			"r": _rng.randf_range(110, 260), "v": _rng.randf_range(18, 45)})
	guide.clear()
	# Guide marks around the Pole Star (deg offsets): the Plough's pointers and Cassiopeia.
	for o in [Vector2(-11, 25), Vector2(-14, 29), Vector2(-20, 31), Vector2(-25, 28), Vector2(-27, 22), Vector2(-21, 18), Vector2(-15, 18),
			Vector2(16, -24), Vector2(20, -26), Vector2(23, -22), Vector2(27, -25), Vector2(30, -21)]:
		guide.append(o)

# ---------------------------------------------------------------- motion
func pitch_deg() -> float:
	return (_noise.get_noise_1d(t * 0.6) * 1.6 + sin(t * 0.9) * 0.6) * cond.sea

func roll_rad() -> float:
	return deg_to_rad((_noise.get_noise_1d(t * 0.5 + 200.0) * 5.0 + sin(t * 0.7) * 2.0) * cond.sea)

## World (horizon frame) to screen: the ship rolls and pitches the whole sky.
func to_screen(p: Vector2) -> Vector2:
	var q := (p - CENTER).rotated(roll_rad()) + CENTER
	return q + Vector2(0, pitch_deg() * K)

func horizon_y_at(x: float) -> float:
	var a := to_screen(Vector2(x, HORIZON_Y))
	var b := to_screen(Vector2(x + 1, HORIZON_Y))
	# y on the rotated horizon line at screen x
	var slope := (b.y - a.y) / maxf(0.0001, b.x - a.x)
	return a.y + slope * (x - a.x)

func star_world() -> Vector2:
	return Vector2(960 + 40, HORIZON_Y - rule.true_lat * K)

func sway() -> Vector2:
	var s: float = (5.4 * cond.sea + 0.5) * K * float(cfg.get("sway_scale", 1.0))   # hand and ship motion, in degrees of sky
	return Vector2(_noise.get_noise_1d(t * 1.3 + 50.0), _noise.get_noise_1d(t * 1.1 + 90.0)) * s

# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	t += delta
	for c in clouds:
		c.p.x += c.v * delta
		if c.p.x - c.r > 2200:
			c.p.x = -300 - c.r
	if outcome.is_empty():
		_play(delta)
	queue_redraw()

func _play(delta: float) -> void:
	watch_left -= delta
	var ls: Vector2 = Controls.left_stick()
	var rs: Vector2 = Controls.right_stick()
	var trig := Input.get_action_strength("rt") - Input.get_action_strength("lt")
	var want_commit := Input.is_action_just_pressed("commit")
	if autopilot:
		var bot := _bot_inputs()
		ls = bot[0]; rs = bot[1]; trig = bot[2]
	elif bot_input.is_valid():
		var b: Array = bot_input.call(self)
		ls = b[0]; rs = b[1]; trig = b[2]; want_commit = b[3]
	# Eased movement: keys and flicks never jump the ring; the stick's speed builds over a moment.
	var speed := float(cfg.get("move_speed", 520.0))
	_vel = _vel.lerp(ls * speed, clampf(delta * (14.0 if autopilot else 7.0), 0.0, 1.0))
	ring_base += _vel * delta + Vector2(rs.x * 70.0, 0) * delta
	# Forgiving modes: the hands settle the bar toward the true horizon on their own.
	var assist := float(cfg.get("assist_level", 0.0))
	if assist > 0.0:
		var level_gap := horizon_y_at(ring_base.x) - (ring_base.y + BAR_OFFSET)
		ring_base.y += level_gap * assist * delta * 2.5
	ring_base = ring_base.clamp(Vector2(400, 300), Vector2(1520, 900))
	ring = ring_base + sway()
	reading += trig * 7.0 * delta
	reading -= rs.y * 1.2 * delta
	reading = clampf(reading, 50.0, 72.0)
	var bar_y := ring.y + BAR_OFFSET
	var sight := Vector2(ring.x, bar_y - reading * K)
	var star := to_screen(star_world())
	var visible := _star_visible(star)
	var aim_err := sight.distance_to(star) / K
	var level_err := (horizon_y_at(ring.x) - bar_y) / K
	var measured := (bar_y - star.y) / K
	quality = rule.step(delta, reading, level_err, aim_err, visible, measured)
	_haptics(delta)
	if want_commit:
		_finish(rule.commit())
	elif Input.is_action_just_pressed("drop"):
		_finish(rule.abort())
	elif watch_left <= 0.0:
		_finish(rule.commit() if rule.seat_held >= rule.seat_time else rule.abort())

## Test bot: levels the bar on the true horizon (plus a bias) and walks the sight onto the star,
## with stick values limited to -1..1 like a real pad.
func _bot_inputs() -> Array:
	var star := to_screen(star_world())
	var want_bar := horizon_y_at(ring.x) - autopilot_level_bias * K
	var bar_y := ring.y + BAR_OFFSET
	var ls := Vector2(clampf((star.x - ring.x) / 120.0, -1, 1), clampf((want_bar - bar_y) / 60.0, -1, 1))
	var want_reading := (bar_y - star.y) / K
	var d := want_reading - reading
	var trig := clampf(d * 0.8, -1, 1)
	var rs := Vector2(0, clampf(-d * 2.0, -1, 1)) if absf(d) < 0.6 else Vector2.ZERO
	return [ls, rs, trig]

func _star_visible(star: Vector2) -> bool:
	for c in clouds:
		if star.distance_to(c.p) < c.r * 0.82:
			return false
	return true

func _haptics(delta: float) -> void:
	_pulse_cd -= delta
	if quality > 0.05 and _pulse_cd <= 0.0:
		Controls.pulse(0.15 + quality * 0.25, quality * quality * 0.7, 0.06)
		_pulse_cd = lerpf(0.5, 0.12, quality)   # pulse sharpens as the star seats

func _finish(r: Dictionary) -> void:
	r.preset = preset_name
	r.time = WATCH_SECONDS - watch_left
	r.seat_held = rule.seat_held
	outcome = r
	_log(r)
	finished.emit(r)

func _log(r: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute("user://runlog")
	var path := "user://runlog/star_ring.csv"
	var fresh := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not fresh else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	if fresh:
		f.store_line("time_utc,preset,sea,cloud,fog,twilight,true_lat,estimate,error,result,seconds,seat_held")
	f.store_line("%s,%s,%.2f,%.2f,%s,%s,%.2f,%.2f,%.2f,%s,%.1f,%.2f" % [Time.get_datetime_string_from_system(true), r.preset,
		cond.sea, cond.cloud, cond.fog, cond.twilight, r.true_lat, r.estimate, r.error, RingFix.result_name(r.result), r.time, r.seat_held])

func _unhandled_input(e: InputEvent) -> void:
	if embedded:
		if not outcome.is_empty() and e.is_action_pressed("commit"):
			get_viewport().set_input_as_handled()
			closed.emit()
		return
	if e is InputEventKey and e.pressed and not e.echo:
		var map := {KEY_1: "clear", KEY_2: "clouded", KEY_3: "twilight", KEY_4: "fog", KEY_5: "storm"}
		if map.has(e.physical_keycode):
			new_night(map[e.physical_keycode])
		elif e.physical_keycode == KEY_R:
			new_night(preset_name)
	if not outcome.is_empty() and e.is_action_pressed("commit"):
		var names := PRESETS.keys()
		new_night(names[(names.find(preset_name) + 1) % names.size()])

# ---------------------------------------------------------------- drawing
func _draw() -> void:
	_draw_sky()
	_draw_ring()
	_draw_hud()

func _draw_sky() -> void:
	var tw: bool = cond.twilight
	var top := Color("141f2b") if not tw else Color("2a3550")
	var low := Color("22344a") if not tw else Color("8a6a55")
	for i in 24:
		var y0 := i * 45.0
		draw_rect(Rect2(0, y0, 1920, 46), top.lerp(low, float(i) / 23.0))
	# horizon and sea, rotated with the roll
	var a := to_screen(Vector2(-600, HORIZON_Y))
	var b := to_screen(Vector2(2520, HORIZON_Y))
	var sea := PackedVector2Array([a, b, to_screen(Vector2(2520, 2200)), to_screen(Vector2(-600, 2200))])
	draw_colored_polygon(sea, Color("0d1720"))
	var true_alpha := 0.18 if cond.fog else 0.9
	draw_line(a, b, Color(0.75, 0.82, 0.86, true_alpha), 2.0)
	if cond.fog:
		var fa := to_screen(Vector2(-600, HORIZON_Y - false_offset * K))
		var fb := to_screen(Vector2(2520, HORIZON_Y - false_offset * K))
		for w in [28.0, 14.0, 4.0]:
			draw_line(fa, fb, Color(0.86, 0.89, 0.89, 0.10 if w > 5 else 0.55), w)
	# stars
	var sa := 0.45 if tw else 1.0
	for o in guide:
		var g := to_screen(star_world() + o * K)
		draw_circle(g, 2.2, Color(1, 1, 0.95, sa * 0.8))
	var s := to_screen(star_world())
	var tw_flicker := 0.85 + 0.15 * sin(t * 7.0)
	draw_circle(s, 7.0, Color(1, 1, 0.9, 0.12 * sa))
	draw_circle(s, 3.4, Color(1, 1, 0.92, sa * tw_flicker))
	if Game.settings.difficulty != "hard" and _star_visible(s):
		draw_arc(s, 22, 0, TAU, 32, Color(0.91, 0.76, 0.35, 0.55), 2.0)
		draw_string(_font, s + Vector2(28, 6), "Pole Star", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.91, 0.76, 0.35, 0.8))
	# clouds and fog
	for c in clouds:
		for k in 4:
			draw_circle(c.p + Vector2(k * 18 - 27, sin(k) * 10), c.r * (1.0 - k * 0.12), Color(0.07, 0.09, 0.12, 0.42))
	if cond.fog:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.75, 0.78, 0.8, 0.16))

func _draw_ring() -> void:
	var wood := Color("8a6d4e")
	var dark := Color("4a3828")
	var gold := Color("c9a55a")
	# rim glow is the visual twin of the haptic pulse
	if quality > 0.0:
		draw_arc(ring, RING_R + 10, 0, TAU, 96, Color(gold, quality * 0.8), 6.0 + quality * 10.0)
	draw_arc(ring, RING_R, 0, TAU, 128, dark, 30.0)
	draw_arc(ring, RING_R, 0, TAU, 128, wood, 22.0)
	var bar_y := ring.y + BAR_OFFSET
	var half := sqrt(RING_R * RING_R - BAR_OFFSET * BAR_OFFSET)
	draw_line(Vector2(ring.x - half, bar_y), Vector2(ring.x + half, bar_y), wood, 10.0)
	# index arm with carved degree notches
	var top_y := bar_y - 72.0 * K
	draw_line(Vector2(ring.x, bar_y), Vector2(ring.x, maxf(top_y, ring.y - RING_R)), Color(wood, 0.8), 4.0)
	for d in range(50, 73):
		var y := bar_y - d * K
		if y < ring.y - RING_R:
			continue
		var len := 16.0 if d % 5 == 0 else 8.0
		draw_line(Vector2(ring.x - len, y), Vector2(ring.x + len, y), Color(dark, 0.9), 2.0)
		if d % 5 == 0:
			draw_string(_font, Vector2(ring.x + 22, y + 6), str(d), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.93, 0.89, 0.8, 0.8))
	var sight := Vector2(ring.x, bar_y - reading * K)
	draw_arc(sight, 14, 0, TAU, 32, Color("ede3cc"), 3.0)
	draw_circle(sight, 3.0, Color("9e3a2e"))
	# hands
	draw_rect(Rect2(ring.x - half - 70, bar_y - 30, 90, 120), Color("6b4a35"))
	draw_rect(Rect2(ring.x + half - 20, bar_y - 30, 90, 120), Color("6b4a35"))

func _draw_hud() -> void:
	var ink := Color("ede3cc")
	draw_string(_font, Vector2(40, 54), "STAR RING  ·  %s" % cond.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	var help := "WASD move the ring · Space raise the sight · Shift lower · arrows fine · Enter take the fix · Esc abort" if Controls.keyboard else "LS hold the ring   RS fine seat   RT raise   LT lower   A take the fix   B abort"
	if Game.settings.difficulty != "hard" and outcome.is_empty():
		var step := "1  Put the ring's bottom bar on the horizon line"
		var bar_y := ring.y + BAR_OFFSET
		if absf(horizon_y_at(ring.x) - bar_y) < 14.0:
			step = "2  Raise or lower the sight (the small circle) onto the bright Pole Star"
		if quality > 0.3:
			step = "3  Hold it there until the bar at the top right fills, then take the fix"
		if rule.seat_held >= rule.seat_time:
			step = "Seated. Take the fix now (%s)" % ("Enter" if Controls.keyboard else "A")
		draw_rect(Rect2(30, 990, 1120, 60), Color(0.08, 0.07, 0.06, 0.75))
		draw_string(_font, Vector2(50, 1030), step, HORIZONTAL_ALIGNMENT_LEFT, 1080, 26, Color("e8c35a"))
	draw_string(_font, Vector2(40, 90), help,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	if not embedded:
		draw_string(_font, Vector2(40, 122), "Keys: WASD / arrows / Space / Shift / Enter / Esc   ·   1-5 conditions   R new night",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.5))
	# the watch burning down: six notches
	for i in 6:
		var lit := watch_left > (5 - i) * WATCH_SECONDS / 6.0
		draw_rect(Rect2(1600 + i * 46, 40, 36, 14), Color(ink, 0.85 if lit else 0.15))
	var seat := clampf(rule.seat_held / rule.seat_time, 0, 1)
	draw_rect(Rect2(1600, 66, 266, 10), Color(ink, 0.15))
	draw_rect(Rect2(1600, 66, 266 * seat, 10), Color("c9a55a"))
	draw_string(_font, Vector2(1600, 100), "seat held" if seat >= 1.0 else "seating", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.6))
	if not outcome.is_empty():
		var r: int = outcome.result
		var line: String = ["No fix. The ship walks downwind.", "Partial fix. Drift halved.", "Clean fix. Drift refunded."][r]
		var col: Color = [Color("9e3a2e"), Color("c9a55a"), Color("6e8a4e")][r]
		draw_rect(Rect2(560, 430, 800, 220), Color(0.08, 0.07, 0.06, 0.88))
		draw_rect(Rect2(560, 430, 800, 8), col)
		draw_string(_font, Vector2(600, 500), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
		var detail := "Latitude by the ring: %.1f°   ·   true: %.1f°" % [outcome.estimate, outcome.true_lat] if not is_nan(outcome.estimate) else "The star never held in the sight."
		draw_string(_font, Vector2(600, 550), detail, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(ink, 0.8))
		draw_string(_font, Vector2(600, 610), "A: back to the ship" if embedded else "A: next night", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
