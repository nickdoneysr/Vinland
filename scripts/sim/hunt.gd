class_name Hunt
extends RefCounted
## Rules for MG5 stalk and loose (Backlog F12).
##   LS left/right walk · RT hurry (louder) · LB crouch (quieter, slower) · RB draw or lower the bow
##   RS up/down aim · A loose · B lower the bow
## The caribou grazes, then lifts its head and watches. Movement while it watches alarms it fast: freeze.
## The wind carries your scent toward it all the time, so the stalk cannot take forever.
## In range, draw (you cannot walk with the bow drawn), hold the sight on the vitals, and loose.

enum Phase { STALK, DRAWN, KILL, WOUND, MISS, FLED, TIMEOUT }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var far := false
var phase := Phase.STALK
var t := 0.0
var dist := 120.0
var watching := false
var cycle_t := 4.0
var alert := 0.0
var crouched := false
var draw_t := 0.0
var drawn_for := 0.0
var aim := 0.0                # degrees above (+) or below (-) the vitals, before sway
var sway := 0.0
var meat_pd := 0.0
var fear_tick := false
var events: Array = []
var _sway_noise := FastNoiseLite.new()

func setup(cfg: Dictionary, seed: int = 0, ground_far: bool = false) -> void:
	c = cfg
	far = ground_far
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	_sway_noise.seed = rng.randi()
	_sway_noise.frequency = 0.9
	dist = rng.randf_range(c.start_distance_m[0], c.start_distance_m[1]) * (0.85 if far else 1.0)
	cycle_t = rng.randf_range(c.graze_seconds[0], c.graze_seconds[1])
	aim = rng.randf_range(-3.0, 3.0)

func in_range() -> bool:
	return dist <= float(c.range_m)

## Total aim error right now, in degrees, including the hands' sway.
func aim_error() -> float:
	return aim + sway

## Vitals window at this distance (wider close in, narrower at the edge of range).
func vitals_window() -> float:
	var near := float(c.best_range_m[0]); var outer := float(c.range_m)
	var k := clampf((dist - near) / maxf(1.0, outer - near), 0.0, 1.0)
	return lerpf(float(c.vitals_deg[0]), float(c.vitals_deg[1]), k)

func step(dt: float, move: float, fast: bool, crouch_pressed: bool, bow_pressed: bool, aim_y: float, loose: bool, lower: bool) -> Array:
	events = []
	if phase >= Phase.KILL:
		return events
	t += dt
	# the animal's rhythm: graze, then lift the head and watch
	cycle_t -= dt
	if cycle_t <= 0.0:
		watching = not watching
		var r: Array = c.watch_seconds if watching else c.graze_seconds
		cycle_t = rng.randf_range(r[0], r[1])
		events.append("watch" if watching else "graze")
	var noise := 0.0
	match phase:
		Phase.STALK:
			if crouch_pressed:
				crouched = not crouched
			var speed := float(c.walk_mps) * clampf(move, 0.0, 1.0)
			if speed > 0.0:
				if crouched:
					speed *= float(c.crouch_mult)
					noise = float(c.noise_crouch)
				elif fast:
					speed *= float(c.fast_mult)
					noise = float(c.noise_fast)
				else:
					noise = float(c.noise_walk)
				noise *= clampf(move, 0.0, 1.0)
			dist = maxf(8.0, dist - speed * dt)
			if bow_pressed and in_range():
				phase = Phase.DRAWN
				draw_t = 0.0
				drawn_for = 0.0
				events.append("draw")
		Phase.DRAWN:
			draw_t += dt
			noise = 0.15 if draw_t < float(c.draw_seconds) else 0.0
			if draw_t >= float(c.draw_seconds):
				drawn_for += dt
				aim += aim_y * float(c.aim_speed_deg) * dt
				var amp := float(c.sway_deg)
				if drawn_for > float(c.sway_growth_after):
					amp += (drawn_for - float(c.sway_growth_after)) * float(c.sway_growth)
				sway = _sway_noise.get_noise_1d(t * 3.0) * amp * 2.0
				if loose:
					_loose()
					return events
			if lower or bow_pressed:
				phase = Phase.STALK
				sway = 0.0
				events.append("lower")
	# alarm: noise matters most while it watches; scent always creeps in
	var gain := float(c.alert_watch) if watching else float(c.alert_graze)
	alert += noise * gain * dt + float(c.scent_per_second) * dt
	if noise <= 0.01:
		alert -= float(c.alert_decay) * dt * (0.3 if watching else 1.0)
	alert = clampf(alert, 0.0, 1.0)
	if alert >= 1.0:
		phase = Phase.FLED
		events.append("fled")
		_range_far()
	elif t >= float(c.session_seconds):
		phase = Phase.TIMEOUT
		events.append("timeout")
	return events

func _loose() -> void:
	var err := absf(aim_error())
	var w := vitals_window()
	if err <= w * 0.6:
		phase = Phase.KILL
		meat_pd = rng.randf_range(c.person_days[0], c.person_days[1])
		events.append("kill")
	elif err <= w * 1.4:
		phase = Phase.WOUND
		events.append("wound")
		_range_far()
	else:
		phase = Phase.MISS
		events.append("miss")
	if phase != Phase.KILL:
		alert = 1.0

## Following a frightened or wounded animal far from camp can be seen as a threat (Systems: Goodwill / fear).
func _range_far() -> void:
	if far and rng.randf() < float(c.far_fear_tick):
		fear_tick = true
		events.append("fear_tick")

func succeeded() -> bool:
	return phase == Phase.KILL
