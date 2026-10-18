class_name StormBail
extends RefCounted
## Rules for MG10 storm bail (Backlog F10). No sky tonight: find the leak, then bail in rhythm.
##   Check: LS left/right to look along the hull, A to stuff wool into the leaking seam.
##   Bail: RT on the beat. On-beat scoops build a rhythm that bails faster; off-beat scoops do little.
## Wave sets slop green water in; the rumble comes one beat early (the visual twin is the wave marker).

enum Phase { CHECK, BAIL, HELD, SWAMPED }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var phase := Phase.CHECK
var t := 0.0
var water := 0.15
var leak_spot := 0           # 0 bow, 1 midships, 2 stern
var look := 1
var plugged := false
var check_wait := 0.0
var beat_t := 0.0            # time to the next beat
var combo := 0
var next_set := 6.0
var waves_left := 0
var wave_t := 0.0
var peak := 0.0
var events: Array = []

func setup(cfg: Dictionary, seed: int = 0) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	water = float(c.start_water)
	leak_spot = rng.randi_range(0, 2)
	beat_t = float(c.beat_seconds)
	next_set = rng.randf_range(c.set_interval[0], c.set_interval[1])

## How far into the current beat cycle we are: 0 on the beat, 0.5 halfway to the next.
func beat_phase() -> float:
	return 1.0 - beat_t / float(c.beat_seconds)

## True when a wave arrives within the next beat: drives the early rumble and the wave marker.
func wave_coming() -> bool:
	return (waves_left > 0 and wave_t <= float(c.beat_seconds)) or (waves_left == 0 and next_set <= float(c.beat_seconds))

func step(dt: float, ls_x: float, a_pressed: bool, rt_pressed: bool) -> Array:
	events = []
	if phase >= Phase.HELD:
		return events
	t += dt
	var leak := float(c.leak_rate) * (float(c.plugged_leak_factor) if plugged else 1.0)
	match phase:
		Phase.CHECK:
			water += leak * dt
			check_wait = maxf(0.0, check_wait - dt)
			if check_wait <= 0.0:
				if ls_x > 0.5: look = mini(2, look + 1); check_wait = 0.25
				elif ls_x < -0.5: look = maxi(0, look - 1); check_wait = 0.25
			if a_pressed and check_wait <= 0.0:
				if look == leak_spot:
					plugged = true
					events.append("plugged")
					phase = Phase.BAIL
					t = 0.0
				else:
					events.append("dry_seam")
					check_wait = float(c.wrong_plug_seconds)
			if t > 8.0:                    # no time to look further: start bailing
				phase = Phase.BAIL
				t = 0.0
		Phase.BAIL:
			water += leak * dt
			beat_t -= dt
			if beat_t <= 0.0:
				beat_t += float(c.beat_seconds)
				events.append("beat")
			if rt_pressed:
				var off := minf(beat_phase(), 1.0 - beat_phase()) * float(c.beat_seconds)
				if off <= float(c.window_seconds):
					combo = mini(combo + 1, int(c.combo_max))
					water -= float(c.scoop) * (1.0 + combo * float(c.combo_bonus))
					events.append("scoop")
				else:
					combo = 0
					water -= float(c.offbeat_scoop)
					events.append("slop")
			# wave sets
			if waves_left == 0:
				next_set -= dt
				if next_set <= 0.0:
					waves_left = int(c.waves_per_set)
					wave_t = 0.0
			if waves_left > 0:
				wave_t -= dt
				if wave_t <= 0.0:
					water += float(c.wave_water)
					waves_left -= 1
					wave_t = float(c.wave_gap)
					events.append("wave")
					if waves_left == 0:
						next_set = rng.randf_range(c.set_interval[0], c.set_interval[1])
			if t >= float(c.session_seconds):
				phase = Phase.HELD
				events.append("held")
	water = clampf(water, 0.0, 1.2)
	peak = maxf(peak, water)
	if water >= 1.0 and phase < Phase.HELD:
		phase = Phase.SWAMPED
		events.append("swamped")
	return events

func held() -> bool:
	return phase == Phase.HELD
