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
		if keyboard:
			# Watches the wind-up and lets go, anticipating the rising meter by about half a reaction.
			var rate := 1.0 / float(n._cfg.get("charge_seconds", 0.8))
			if memo.get("pulling", false):
				if o.pull >= memo.aim - rate * delay * 0.5:
					memo.pulling = false
					memo.cd = 0.5
					memo.erase("aim")
				else:
					rt = 1.0
			elif memo.cd <= 0.0 and patient:
				memo.pulling = true
				rt = 1.0
		else:
			# A pad trigger is pulled to a depth by feel, held a moment, and released.
			memo.hold = memo.get("hold", 0.0)
			if memo.get("pulling", false):
				memo.hold += dt
				rt = memo.aim
				if memo.hold > 0.15:
					memo.pulling = false
					memo.cd = 0.5
					memo.hold = 0.0
					memo.erase("aim")
			elif memo.cd <= 0.0 and patient:
				memo.pulling = true
				rt = memo.aim
	return [ls, rs, rt]

# ------------------------------------------------------------------ storm bail
## Rhythm is predicted, not reacted to: presses land near the beat with some spread; finding the leak is seen late.
func bail(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var r: StormBail = n.rules
	var o := see(dt, {"phase": r.phase, "look": r.look, "leak": r.leak_spot, "wait": r.check_wait})
	if o.phase == StormBail.Phase.CHECK:
		var d: int = int(o.leak) - int(o.look)
		return [float(signi(d)), d == 0 and o.wait <= 0.0 and rng.randf() < 0.1, false]
	if not memo.has("offset"):
		memo.offset = rng.randf_range(-0.05, 0.05)       # each player's habit: a little early or late
	var c: float = float(n._cfg.beat_seconds)
	if not memo.has("next_press"):
		memo.k = 1
		memo.next_press = c + memo.offset + rng.randf_range(-0.09, 0.09)
	var press := false
	if r.t >= memo.next_press:
		press = true
		memo.k += 1
		memo.next_press = memo.k * c + memo.offset + rng.randf_range(-0.09, 0.09)
	return [0.0, false, press]

# ------------------------------------------------------------------ hunt
## Sees the head come up a reaction late, walks while it grazes, draws in range, steadies the sight and looses.
func hunt(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var r: Hunt = n.rules
	var o := see(dt, {"phase": r.phase, "watch": r.watching, "dist": r.dist, "alert": r.alert, "err": r.aim_error(),
		"aim": r.aim, "drawn": r.draw_t >= float(n._cfg.draw_seconds), "w": r.vitals_window(), "inr": r.in_range()})
	if o.phase == Hunt.Phase.STALK:
		var close: bool = o.inr and o.dist <= float(n._cfg.range_m) - 3.0
		var move := 0.0 if o.watch or close else 1.0
		var crouch := false
		if o.alert > 0.5 and not r.crouched:
			crouch = true                        # gets low when the alarm climbs
		elif o.alert < 0.3 and r.crouched:
			crouch = true                        # and stands again once it settles
		var bow: bool = close and o.inr and rng.randf() < 0.05
		return [move, false, crouch, bow, 0.0, false, false]
	var aim_y := stick(-o.err, 1.5, 0.3) * (0.6 if keyboard else 1.0)
	var loose: bool = o.drawn and absf(o.err) < o.w * 0.5 and rng.randf() < 0.08
	return [0.0, false, false, false, aim_y, loose, false]

# ------------------------------------------------------------------ forage
## Heads for a clump that looks ripe, holds the trigger, and lets go a reaction late once the ripe fruit is gone.
func forage(n: Node) -> Array:
	var dt := 1.0 / 60.0
	var f: Forage = n.rules
	var o := see(dt, {"cur": f.cursor, "near": f.nearest(), "ripe_near": (f.clumps[f.nearest()].ripe if f.nearest() >= 0 else 0.0)})
	if memo.get("target", -1) < 0 or f.clumps[memo.target].ripe <= 0.05 and o.ripe_near <= 0.0:
		var best := -1; var bd := 1e9
		for i in f.clumps.size():
			if f.clumps[i].ripe > 0.3:
				var d: float = f.cursor.distance_to(f.clumps[i].p)
				if d < bd:
					bd = d; best = i
		memo.target = best
	if memo.target < 0:
		return [Vector2.ZERO, false]
	var to: Vector2 = f.clumps[memo.target].p - o.cur
	var reach: float = maxf(float(n._cfg.pick_radius) * 0.6, float(n._cfg.get("magnet_radius", 0.0)) * 0.7)
	if to.length() > reach:
		var st := to.normalized()
		if keyboard:
			st = Vector2(signf(st.x) if absf(st.x) > 0.38 else 0.0, signf(st.y) if absf(st.y) > 0.38 else 0.0)
		return [st, false]
	return [Vector2.ZERO, o.ripe_near > 0.0 or rng.randf() < 0.5]
