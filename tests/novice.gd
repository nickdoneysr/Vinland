class_name Novice
extends RefCounted
## A first-time player, for difficulty tests: sees the game a reaction-time late, aims imperfectly,
## and on keyboard can only press keys fully or not at all. Expert bots prove a game is winnable;
## this model asks whether a new player can win it.

var rng := RandomNumberGenerator.new()
var keyboard := true
var delay := 0.25            # seconds behind the game
var history: Array = []      # [time, observation]
var t := 0.0
var memo := {}

func _init(seed: int, on_keyboard: bool) -> void:
	rng.seed = seed
	keyboard = on_keyboard
	delay = rng.randf_range(0.18, 0.34)

## Store what the game shows now and return what the player perceives (delay seconds ago).
func see(dt: float, obs: Dictionary) -> Dictionary:
	t += dt
	history.append([t, obs])
	while history.size() > 2 and history[1][0] <= t - delay:
		history.pop_front()
	return history[0][1]

## Turn an error into a stick value the way this player would.
func stick(err: float, scale: float, deadband: float) -> float:
	if absf(err) < deadband:
		return 0.0
	if keyboard:
		return signf(err)
	return clampf(err / scale + rng.randf_range(-0.15, 0.15), -1.0, 1.0)

# ------------------------------------------------------------------ star ring
func ring(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var star: Vector2 = n.to_screen(n.star_world())
	var bar_y: float = n.ring.y + n.BAR_OFFSET
	var horizon: float = n.horizon_y_at(n.ring.x)
	if n.cond.fog:
		if not memo.has("fooled"):
			memo.fooled = rng.randf() < 0.4         # some novices level on the bright false line
		if memo.fooled:
			horizon -= n.false_offset * n.K
	var o := see(dt, {"star": star, "ring": n.ring, "bar": bar_y, "hz": horizon, "reading": n.reading,
		"seat": n.rule.seat_held, "seat_time": n.rule.seat_time, "vis": n._star_visible(star)})
	var ls := Vector2(stick(o.star.x - o.ring.x, 160.0, 14.0), stick(o.hz - o.bar, 90.0, 8.0))
	var want: float = (o.bar - o.star.y) / n.K
	var trig := stick(want - o.reading, 2.0, 0.4)
	var commit := false
	if o.seat >= o.seat_time:
		memo.ready_t = memo.get("ready_t", t)
		commit = t - memo.ready_t > 0.35          # notices the bar is full, then presses A
	return [ls, Vector2.ZERO, trig, commit]

# ------------------------------------------------------------------ hand line
func hand_line(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var r: HandLine = n.rules
	var o := see(dt, {"phase": r.phase, "depth": r.depth, "tension": r.tension})
	var s := 0.0
	var rt := false
	match o.phase:
		HandLine.Phase.WAITING:
			s = stick(24.0 - o.depth, 4.0, 1.5)
		HandLine.Phase.NIBBLE:
			rt = rng.randf() < 0.01                  # now and then strikes too soon
		HandLine.Phase.EASE:
			rt = true
		HandLine.Phase.HOOKED:
			s = -1.0 if o.tension < 0.75 else (1.0 if keyboard else 0.6)
	return [s, rt, false]

# ------------------------------------------------------------------ joint
func joint(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var j: Joint = n.rules
	var o := see(dt, {"wobble": j.wobble, "peg": j.peg_angle, "hole": j.hole_angle, "phase": j.phase,
		"pull": n._pull, "load": j.grain_load(), "best": n._cfg.best_force})
	var ls := stick(o.wobble, 0.3, 0.06)
	var rs := stick(o.hole - o.peg, 10.0, 2.5)
	var rt := 0.0
	if o.phase == Joint.Phase.DRIVE:
		memo.cd = memo.get("cd", 0.0) - dt
		if not memo.has("aim"):
			var lo := float(o.best[0]); var hi := float(o.best[1])
			memo.aim = clampf((lo + hi) / 2.0 + rng.randf_range(-0.14, 0.14), 0.2, 1.0)
		var patient: bool = o.load < 0.6
		if memo.get("pulling", false):
			if o.pull >= memo.aim:
				memo.pulling = false               # lets go (the release itself lands a reaction late)
				memo.cd = 0.5
				memo.erase("aim")
			else:
				rt = 1.0 if keyboard else minf(1.0, o.pull + 0.25)
		elif memo.cd <= 0.0 and patient:
			memo.pulling = true
			rt = 1.0 if keyboard else 0.25
	return [ls, rs, rt]
