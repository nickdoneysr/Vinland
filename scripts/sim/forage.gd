class_name Forage
extends RefCounted
## Rules for MG6 patch reading (Backlog F13). LS walk the hand over the patch · RT hold to pick.
## Ripe berries are worth a full measure; once a clump's ripe fruit is gone, holding on strips the plant:
## green fruit worth little, and damage that thins the patch for the rest of the season.

var c: Dictionary
var rng := RandomNumberGenerator.new()
var t := 0.0
var cursor := Vector2(960, 600)
var clumps: Array = []        # {p: Vector2, ripe, unripe, strip}
var basket := 0.0             # person-days picked
var stripped := 0.0           # total strip damage dealt
var vel := Vector2.ZERO
var events: Array = []
var done := false
const AREA := Rect2(300, 240, 1320, 720)

func setup(cfg: Dictionary, seed: int = 0, season_health: float = 1.0) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	for i in int(c.clumps):
		var p := Vector2(rng.randf_range(AREA.position.x, AREA.end.x), rng.randf_range(AREA.position.y, AREA.end.y))
		clumps.append({"p": p, "ripe": rng.randf_range(c.ripe_per_clump[0], c.ripe_per_clump[1]) * season_health,
			"unripe": rng.randf_range(c.unripe_per_clump[0], c.unripe_per_clump[1]), "strip": 0.0})

func nearest(radius: float = -1.0) -> int:
	var best := -1
	var bd := (float(c.pick_radius) if radius < 0.0 else radius)
	for i in clumps.size():
		var d: float = cursor.distance_to(clumps[i].p)
		if d <= bd:
			bd = d
			best = i
	return best

## The richest clump in reach that still has ripe fruit, or -1.
func ripe_in_reach() -> int:
	var best := -1
	var most := 0.0
	for i in clumps.size():
		if cursor.distance_to(clumps[i].p) <= float(c.pick_radius) and clumps[i].ripe > most:
			most = clumps[i].ripe
			best = i
	return best

func step(dt: float, stick: Vector2, picking: bool) -> Array:
	events = []
	if done:
		return events
	t += dt
	# eased hand: speed builds over a moment, so a key press does not fling it past the clump
	vel = vel.lerp(stick * float(c.cursor_speed), clampf(dt * 8.0, 0.0, 1.0))
	cursor = (cursor + vel * dt).clamp(AREA.position, AREA.end)
	# Easier settings: holding pick near a ripe clump glides the hand onto it.
	var mag := float(c.get("magnet_radius", 0.0))
	if picking and mag > 0.0 and ripe_in_reach() < 0:
		var best := -1
		var bd := mag
		for k in clumps.size():
			var d: float = cursor.distance_to(clumps[k].p)
			if clumps[k].ripe > 0.05 and d < bd:
				bd = d
				best = k
		if best >= 0:
			cursor = cursor.move_toward(clumps[best].p, 420.0 * dt)
			vel = Vector2.ZERO
	if picking:
		var i := ripe_in_reach()
		if i < 0:
			i = nearest()
		if i >= 0:
			var cl: Dictionary = clumps[i]
			var take := float(c.take_rate) * dt
			if cl.ripe > 0.0:
				var got := minf(take, cl.ripe)
				cl.ripe -= got
				basket += got * float(c.ripe_value_pd)
				events.append("take")
			else:
				# greedy: the ripe fruit is gone and the hand keeps pulling
				var got2 := minf(take, cl.unripe)
				cl.unripe -= got2
				basket += got2 * float(c.unripe_value_pd)
				var s := float(c.strip_rate) * dt
				cl.strip = minf(1.0, cl.strip + s)
				stripped += s
				events.append("greedy")
	if basket >= float(c.basket_pd) or t >= float(c.session_seconds):
		basket = minf(basket, float(c.basket_pd))
		done = true
		events.append("done")
	return events

## How much of the patch is left for the rest of the season, 0..1.
func patch_health() -> float:
	var s := 0.0
	for cl in clumps:
		s += cl.strip
	return clampf(1.0 - s / maxf(1.0, clumps.size()), 0.0, 1.0)

func ripe_left() -> float:
	var s := 0.0
	for cl in clumps:
		s += cl.ripe
	return s
