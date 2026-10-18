class_name HandLine
extends RefCounted
## Rules for MG3 hand-line fishing (Backlog F05). Pure: the scene feeds sticks and triggers in,
## draws what comes out, and pulses the pad on the events this returns.
##   LS down pays out line, LS up hauls · RT sets the hook (on the ease) · B cuts the line.
## A bite is two tugs then an ease; setting during the ease hooks the fish.

enum Phase { WAITING, NIBBLE, TUG1, GAP, TUG2, EASE, HOOKED, REBAIT, DONE }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var fog := false
var current := 0.3            # 0..1, adds false twitches

var time_left := 60.0
var depth := 0.0              # metres of line out
var phase := Phase.WAITING
var phase_t := 0.0            # time left in a timed phase
var wait_t := 0.0             # time until a fish finds the bait
var nibbles_left := 0
var fish := ""                # kind on the line or approaching
var fish_depth := 0.0         # how far the hooked fish still is from the boat
var tension := 0.0
var over_t := 0.0
var bait := true
var hooks := 6
var catch: Array = []         # [{kind, person_days}]
var hooks_lost := 0
var events: Array = []        # cleared every step: tug, nibble, twitch, hooked, spooked, stolen, snapped, landed, cut

func setup(cfg: Dictionary, seed: int = 0, hook_stock: int = 6) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	time_left = float(c.session_seconds)
	hooks = hook_stock
	_reset_wait()

func band_of(kind: String) -> Array:
	return c.fish_band[kind]

## Which fish swim at the hook's depth, weighted by how common they are. "" when none.
func _pick_kind() -> String:
	var mix: Dictionary = c.fish_mix
	var total := 0.0
	var here: Array = []
	for k in mix:
		if _kind_at_depth(k):
			here.append(k)
			total += float(mix[k])
	if here.is_empty():
		return ""
	var r := rng.randf() * total
	for k in here:
		r -= float(mix[k])
		if r <= 0.0:
			return k
	return here[-1]

func _kind_at_depth(kind: String) -> bool:
	var b: Array = band_of(kind)
	var tol := float(c.band_tolerance_m)
	return depth >= float(b[0]) - tol and depth <= float(b[1]) + tol

func _reset_wait() -> void:
	fish = ""
	wait_t = rng.randf_range(c.find_seconds[0], c.find_seconds[1])

## True when some fish swims where the hook hangs.
func in_band() -> bool:
	for k in c.fish_mix:
		if _kind_at_depth(k):
			return true
	return false

func step(dt: float, stick_y: float, rt_pressed: bool, cut: bool) -> Array:
	events = []
	if phase == Phase.DONE:
		return events
	time_left -= dt
	if hooks <= 0 and phase != Phase.HOOKED:
		phase = Phase.DONE
		return events
	if cut and phase != Phase.REBAIT:
		_lose_hook("cut")
		return events
	match phase:
		Phase.WAITING:
			depth = clampf(depth + stick_y * float(c.pay_speed_mps) * dt, 0.0, float(c.max_depth_m))
			if current > 0.0 and rng.randf() < current * dt * 0.8:
				events.append("twitch")     # the current, not a fish
			if bait and in_band():
				wait_t -= dt
				if wait_t <= 0.0:
					fish = _pick_kind()
					nibbles_left = rng.randi_range(int(c.nibbles[0]), int(c.nibbles[1]))
					_next_after_nibbles()
		Phase.NIBBLE, Phase.TUG1, Phase.GAP, Phase.TUG2, Phase.EASE:
			if rt_pressed and phase == Phase.NIBBLE and not bool(c.get("nibble_spooks", true)):
				rt_pressed = false          # forgiving: a strike at a nibble just misses, the fish stays
			if rt_pressed:
				if phase == Phase.EASE:
					phase = Phase.HOOKED
					phase_t = 0.0
					fish_depth = depth
					tension = 0.3
					events.append("hooked")
				else:
					events.append("spooked")   # struck at a nibble or mid-tug: the fish lets go
					if rng.randf() < 0.5:
						bait = false
						events.append("stolen")
					_after_miss()
				return events
			phase_t -= dt
			if phase_t <= 0.0:
				_advance_bite()
		Phase.HOOKED:
			_fight(dt, stick_y)
		Phase.REBAIT:
			phase_t -= dt
			if phase_t <= 0.0:
				bait = true
				phase = Phase.WAITING
				_reset_wait()
	if time_left <= 0.0 and phase != Phase.HOOKED:
		phase = Phase.DONE
	return events

func _next_after_nibbles() -> void:
	if nibbles_left > 0:
		nibbles_left -= 1
		phase = Phase.NIBBLE
		phase_t = float(c.nibble_seconds) + rng.randf_range(0.25, 0.6)
		events.append("nibble")
	else:
		phase = Phase.TUG1
		phase_t = float(c.tug_seconds)
		events.append("tug")

func _advance_bite() -> void:
	match phase:
		Phase.NIBBLE:
			_next_after_nibbles()
		Phase.TUG1:
			phase = Phase.GAP
			phase_t = float(c.tug_gap_seconds)
		Phase.GAP:
			phase = Phase.TUG2
			phase_t = float(c.tug_seconds)
			events.append("tug")
		Phase.TUG2:
			phase = Phase.EASE
			phase_t = float(c.ease_seconds_fog if fog else c.ease_seconds)
			events.append("ease")
		Phase.EASE:
			bait = false            # too slow: the bait is gone
			events.append("stolen")
			_after_miss()

func _after_miss() -> void:
	if not bait:
		phase = Phase.REBAIT
		phase_t = float(c.rebait_seconds)
	else:
		phase = Phase.WAITING
		_reset_wait()

## Hauling (stick up) brings the fish in but loads the line; surges spike the load.
func _fight(dt: float, stick_y: float) -> void:
	var strength := float(c.strength[fish])
	phase_t += dt
	var surge := strength * (0.55 + 0.45 * sin(phase_t * 2.3 + float(fish.length())) + (0.5 if fmod(phase_t, 3.7) < 0.5 else 0.0))
	var haul := maxf(0.0, -stick_y)
	var give := maxf(0.0, stick_y)
	var target := surge * 0.8 + haul * 0.55 - give * 0.7
	tension = lerpf(tension, clampf(target, 0.0, 1.6), clampf(dt * 6.0, 0.0, 1.0))
	fish_depth += (give * float(c.give_speed_mps) - haul * float(c.haul_speed_mps) * (1.0 - strength * 0.5)) * dt
	fish_depth += surge * 1.2 * dt                    # the fish pulls line back
	fish_depth = clampf(fish_depth, 0.0, float(c.max_depth_m) + 6.0)
	depth = fish_depth
	if tension > float(c.snap_tension):
		over_t += dt
		if over_t >= float(c.snap_hold_seconds):
			_lose_hook("snapped")
			return
	else:
		over_t = maxf(0.0, over_t - dt)
	if fish_depth <= 0.5:
		var r: Array = c.person_days[fish]
		var pd := rng.randf_range(float(r[0]), float(r[1]))
		catch.append({"kind": fish, "person_days": pd})
		events.append("landed")
		tension = 0.0
		over_t = 0.0
		phase_t = 0.0
		bait = false
		phase = Phase.REBAIT
		phase_t = float(c.rebait_seconds) * 0.5
		depth = 0.0

func _lose_hook(why: String) -> void:
	hooks -= 1
	hooks_lost += 1
	events.append(why)
	tension = 0.0
	over_t = 0.0
	bait = false
	depth = 0.0
	phase = Phase.REBAIT if hooks > 0 else Phase.DONE
	phase_t = float(c.rebait_seconds) * 1.5

func person_days() -> float:
	var s := 0.0
	for f in catch:
		s += f.person_days
	return s

## The line's visible twitch, 0..1: the visual twin of the tug haptics.
func line_signal() -> float:
	match phase:
		Phase.TUG1, Phase.TUG2: return 1.0
		Phase.NIBBLE: return 0.35
		Phase.EASE: return -0.6        # slack: the float rises
		Phase.HOOKED: return tension
	return 0.0
