class_name NetThrow
extends RefCounted
## Rules for MG4 the net (Backlog F14). From the boat in the shallows: RS aims the throw over the water,
## A casts, the net sinks, and both triggers draw it closed. Close it as it reaches the school's depth
## with the school under it. The school runs deeper in rain; in fog it shows only once it is near the boat.
## An empty throw spends the day.

enum Phase { AIM, FLIGHT, SINK, HAULED, DONE }

var c: Dictionary
var rng := RandomNumberGenerator.new()
var phase := Phase.AIM
var t := 0.0
var phase_t := 0.0
var aim := Vector2(960, 640)
var net_at := Vector2.ZERO
var net_depth := 0.0       # 0 surface .. 1 bottom
var school := Vector2.ZERO
var school_v := Vector2.ZERO
var school_r := 70.0
var school_depth := 0.45
var school_pd := 0.0       # what the whole school is worth if every fish is taken
var throws_left := 1
var catch_pd := 0.0
var last_overlap := 0.0
var last_depth_q := 0.0
var throws := 0
var rain := false
var fog := false
const WATER := Rect2(240, 300, 1440, 560)
const BOAT := Vector2(960, 930)

func setup(cfg: Dictionary, max_pd: float, throws_allowed: int, seed: int = 0, is_rain: bool = false, is_fog: bool = false) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	rain = is_rain
	fog = is_fog
	throws_left = throws_allowed + int(c.get("extra_throws", 0))
	school_pd = max_pd * rng.randf_range(0.75, 1.0)
	school_depth = float(c.rain_depth) if rain else float(c.school_depth)
	_new_school()

func _new_school() -> void:
	school_r = rng.randf_range(c.school_r[0], c.school_r[1])
	var left := rng.randf() < 0.5
	school = Vector2(WATER.position.x + 40 if left else WATER.end.x - 40, rng.randf_range(WATER.position.y + 80, WATER.end.y - 80))
	var sp := rng.randf_range(c.school_speed[0], c.school_speed[1])
	school_v = Vector2(sp if left else -sp, rng.randf_range(-0.3, 0.3) * sp)

## Can the player see the school now? In fog only once it is close to the boat.
func school_seen() -> bool:
	return not fog or school.distance_to(BOAT) <= float(c.fog_radius)

## Share of the school under the net, 0..1 (circle overlap, area-weighted).
func overlap() -> float:
	if phase != Phase.SINK and phase != Phase.HAULED:
		return 0.0
	var d := net_at.distance_to(school)
	var R := float(c.net_radius)
	var r := school_r
	if d >= R + r:
		return 0.0
	if d <= absf(R - r):
		return 1.0 if r <= R else (R * R) / (r * r)
	var a1 := r * r * acos(clampf((d * d + r * r - R * R) / (2.0 * d * r), -1.0, 1.0))
	var a2 := R * R * acos(clampf((d * d + R * R - r * r) / (2.0 * d * R), -1.0, 1.0))
	var a3 := 0.5 * sqrt(maxf(0.0, (-d + r + R) * (d + r - R) * (d - r + R) * (d + r + R)))
	return clampf((a1 + a2 - a3) / (PI * r * r), 0.0, 1.0)

func depth_quality() -> float:
	return clampf(1.0 - absf(net_depth - school_depth) / float(c.depth_tol), 0.0, 1.0)

func step(dt: float, rs: Vector2, cast: bool, close_l: float, close_r: float) -> Array:
	var ev: Array = []
	if phase == Phase.DONE:
		return ev
	t += dt
	phase_t += dt
	# the school swims, turning back at the edges of the shallows
	school += school_v * dt
	if school.x < WATER.position.x + school_r or school.x > WATER.end.x - school_r:
		school_v.x = -school_v.x
	if school.y < WATER.position.y + school_r or school.y > WATER.end.y - school_r:
		school_v.y = -school_v.y
	school = school.clamp(WATER.position + Vector2(school_r, school_r), WATER.end - Vector2(school_r, school_r))
	match phase:
		Phase.AIM:
			aim += rs * float(c.aim_speed) * dt
			aim = aim.clamp(WATER.position, WATER.end)
			var off := aim - BOAT
			if off.length() > float(c.max_range):
				aim = BOAT + off.normalized() * float(c.max_range)
			if cast:
				phase = Phase.FLIGHT
				phase_t = 0.0
				net_at = aim
				throws += 1
				throws_left -= 1
				ev.append("cast")
		Phase.FLIGHT:
			if phase_t >= float(c.flight_time):
				phase = Phase.SINK
				phase_t = 0.0
				net_depth = 0.0
				ev.append("splash")
		Phase.SINK:
			net_depth = minf(1.0, net_depth + float(c.sink_rate) * dt)
			if close_l > 0.5 and close_r > 0.5:
				_haul(ev)
			elif net_depth >= 1.0:
				last_overlap = 0.0
				last_depth_q = 0.0
				ev.append("bottom")
				_after_empty(ev)
		Phase.HAULED:
			pass
	if phase in [Phase.AIM] and t >= float(c.session_seconds):
		phase = Phase.DONE
		ev.append("done")
	return ev

func _haul(ev: Array) -> void:
	last_overlap = overlap()
	last_depth_q = depth_quality()
	var got := school_pd * last_overlap * last_depth_q
	if got < 1.0:
		ev.append("empty")
		_after_empty(ev)
		return
	catch_pd = got
	phase = Phase.DONE
	ev.append("catch")
	ev.append("done")

func _after_empty(ev: Array) -> void:
	if throws_left > 0:
		phase = Phase.AIM
		phase_t = 0.0
		ev.append("again")
	else:
		phase = Phase.DONE
		ev.append("done")
