class_name SmokeRack
extends RefCounted
## Rules for MG9 the smoke rack fire (Backlog F15). RS left/right moves the hide screen that steers the
## smoke column; gusts shove it off the rack. RS up feeds the fire, down damps it with green wood.
## Keep the smoke under the fish and the heat in the band: too cool and nothing cures, too hot and the
## fish case-hardens (a crust outside, rot within). White smoke cures; black smoke is too hot.

var c: Dictionary
var rng := RandomNumberGenerator.new()
var t := 0.0
var column := 0.0          # smoke column offset from under the rack, px
var col_v := 0.0
var wind := 0.0            # -1 .. 1, gusting
var wind_target := 0.0
var gust_t := 0.0
var heat := 0.5            # 0 .. 1
var fuel := 0.5            # what the fire is being given, 0 .. 1
var cure := 0.0            # 0 .. 1
var hardening := 0.0       # 0 .. 1
var done := false
var under := false
var in_band := false

func setup(cfg: Dictionary, seed: int = 0) -> void:
	c = cfg
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	heat = rng.randf_range(0.3, 0.5)
	fuel = heat
	gust_t = rng.randf_range(c.gust_every[0], c.gust_every[1])

func band() -> Array:
	return c.band

func step(dt: float, steer: float, feed: float) -> Array:
	var ev: Array = []
	if done:
		return ev
	t += dt
	# gusts
	gust_t -= dt
	if gust_t <= 0.0:
		wind_target = rng.randf_range(-1.0, 1.0) * float(c.wind_max)
		gust_t = rng.randf_range(c.gust_every[0], c.gust_every[1])
		ev.append("gust")
	wind = move_toward(wind, wind_target, dt * 1.5)
	# the column: shoved by the wind, steered by the screen, settling back slowly on its own
	var accel := wind * float(c.shove) + steer * float(c.steer) - column * 0.6 - col_v * float(c.damping)
	col_v += accel * dt
	column = clampf(column + col_v * dt, -400.0, 400.0)
	# the fire answers what it is fed, a little late
	fuel = clampf(fuel + feed * dt * 0.8, 0.0, 1.0)
	heat = clampf(heat + (fuel - heat) * float(c.heat_rate) * dt - float(c.heat_cool) * dt, 0.0, 1.0)
	under = absf(column) <= float(c.rack_half)
	in_band = heat >= float(c.band[0]) and heat <= float(c.band[1])
	if under:
		if in_band:
			cure += float(c.cure_rate) * dt
		elif heat < float(c.band[0]) and heat > float(c.band[0]) - 0.15:
			cure += float(c.cure_rate) * 0.3 * dt
	if heat > float(c.hard_above):
		var before := hardening
		hardening = minf(1.0, hardening + float(c.harden_rate) * dt * (1.0 if under else 0.4))
		if int(before * 10) != int(hardening * 10):
			ev.append("harden")
	if cure >= 1.0 or t >= float(c.session_seconds):
		cure = minf(cure, 1.0)
		done = true
		ev.append("done")
	return ev

## How well the rack came through, 0..1.
func quality() -> float:
	return clampf(cure * (1.0 - hardening), 0.0, 1.0)

func spoiled() -> bool:
	return quality() < float(c.spoil_q)
