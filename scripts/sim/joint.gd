class_name Joint
extends RefCounted
## Rules for MG7 the joint (Backlog F07). LS braces the timber, RS turns the peg to the hole,
## RT drives it: each pull of the trigger is one mallet blow, and how far you pull is how hard you hit.
## Hard blows seat the peg faster but load the grain; a mis-set peg or a slack brace loads it more.
## Rain lowers how much the grain can take. Too much load splits the log and the day is lost.

enum Phase { BRACE, SET, DRIVE, SEATED, SPLIT, TIMEOUT }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var rain := false
var phase := Phase.BRACE
var t := 0.0
var wobble := 0.0            # -1..1, the timber rocking on the trestle
var brace_held := 0.0
var hole_angle := 0.0        # degrees
var peg_angle := 0.0
var set_held := 0.0
var depth := 0.0             # 0..1 driven
var stress := 0.0            # grain load; split above the cap
var blows := 0
var _rt_peak := 0.0
var _rt_down := false
var _noise := FastNoiseLite.new()
var events: Array = []

func setup(cfg: Dictionary, seed: int = 0, is_rain: bool = false) -> void:
	c = cfg
	rain = is_rain
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	_noise.seed = rng.randi()
	_noise.frequency = 0.6
	hole_angle = rng.randf_range(-25.0, 25.0)
	peg_angle = hole_angle + rng.randf_range(20.0, 35.0) * (1.0 if rng.randf() < 0.5 else -1.0)

func cap() -> float:
	return float(c.stress_cap_rain if rain else c.stress_cap_dry)

func misalign() -> float:
	return absf(peg_angle - hole_angle)

func braced() -> bool:
	return absf(wobble) <= float(c.brace_tolerance)

func step(dt: float, ls_x: float, rs_x: float, rt: float) -> Array:
	events = []
	if phase >= Phase.SEATED:
		return events
	t += dt
	# The timber keeps rocking for the whole job; the left stick leans against it.
	wobble += (_noise.get_noise_1d(t * 1.7) * float(c.brace_drift) - ls_x * 1.6) * dt * 2.0
	wobble = clampf(wobble * (1.0 - dt * 0.15), -1.0, 1.0)
	stress = maxf(0.0, stress - float(c.stress_decay_per_second) * dt)
	match phase:
		Phase.BRACE:
			brace_held = brace_held + dt if braced() else maxf(0.0, brace_held - dt)
			if brace_held >= float(c.brace_seconds):
				phase = Phase.SET
				events.append("braced")
		Phase.SET:
			peg_angle += rs_x * 40.0 * dt
			set_held = set_held + dt if misalign() <= float(c.peg_tolerance_deg) else 0.0
			if set_held >= float(c.peg_seat_seconds):
				phase = Phase.DRIVE
				events.append("set")
		Phase.DRIVE:
			peg_angle += rs_x * 10.0 * dt      # small corrections still possible
			_blow_detect(rt)
	if phase < Phase.SEATED and t >= float(c.max_seconds):
		phase = Phase.TIMEOUT
		events.append("timeout")
	return events

func _blow_detect(rt: float) -> void:
	if rt > 0.15:
		_rt_down = true
		_rt_peak = maxf(_rt_peak, rt)
	elif _rt_down and rt < 0.1:
		_rt_down = false
		_blow(_rt_peak)
		_rt_peak = 0.0

func _blow(force: float) -> void:
	blows += 1
	var gain := float(c.depth_per_blow_at_full) * force
	var best_min := float(c.best_force[0])
	if force < best_min:
		gain *= pow(force / best_min, 2.0)      # light taps mostly bounce off
	depth += gain
	var load := float(c.stress_per_blow) * force
	var best_max := float(c.best_force[1])
	if force > best_max:
		load += (force - best_max) * float(c.stress_over_force) * 2.0
	load += misalign() * float(c.stress_misalign_per_deg) * force
	if not braced():
		load *= 1.8
	stress += load
	events.append("blow")
	if stress > cap():
		phase = Phase.SPLIT
		events.append("split")
	elif depth >= 1.0:
		depth = 1.0
		phase = Phase.SEATED
		events.append("seated")

## 0..1 how close the grain is to splitting: drives trigger resistance and the grain line's red.
func grain_load() -> float:
	return clampf(stress / cap(), 0.0, 1.0)

func succeeded() -> bool:
	return phase == Phase.SEATED
