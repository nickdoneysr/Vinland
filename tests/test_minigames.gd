extends RefCounted
## Bot tests for the hand line and the joint.

static func cfg() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://data/minigames.json", FileAccess.READ).get_as_text())

static func run(t) -> void:
	_hand_line(t)
	if ResourceLoader.exists("res://scripts/sim/joint.gd"):
		_joint(t)

static func _hl_session(policy: String, seed: int, fog := false) -> HandLine:
	var h := HandLine.new()
	h.setup(cfg().hand_line, seed, 6)
	h.fog = fog
	var dt := 1.0 / 60.0
	var guard := 0
	while h.phase != HandLine.Phase.DONE and guard < 20000:
		guard += 1
		var stick := 0.0; var rt := false
		match policy:
			"skilled":
				if h.phase == HandLine.Phase.WAITING: stick = clampf((24.0 - h.depth) / 4.0, -1, 1)
				elif h.phase == HandLine.Phase.EASE: rt = h.rng.randf() < 0.2      # reacts within a few frames
				elif h.phase == HandLine.Phase.HOOKED: stick = -1.0 if h.tension < 0.8 else 0.6
			"eager":       # strikes at every twitch
				if h.phase == HandLine.Phase.WAITING: stick = clampf((24.0 - h.depth) / 4.0, -1, 1)
				elif h.phase in [HandLine.Phase.NIBBLE, HandLine.Phase.TUG1]: rt = true
				elif h.phase == HandLine.Phase.HOOKED: stick = -1.0
			"brute":       # good timing, always hauls flat out
				if h.phase == HandLine.Phase.WAITING: stick = clampf((24.0 - h.depth) / 4.0, -1, 1)
				elif h.phase == HandLine.Phase.EASE: rt = true
				elif h.phase == HandLine.Phase.HOOKED: stick = -1.0
			"shallow":     # fishes the top 8 m
				if h.phase == HandLine.Phase.WAITING: stick = clampf((8.0 - h.depth) / 4.0, -1, 1)
				elif h.phase == HandLine.Phase.EASE: rt = true
				elif h.phase == HandLine.Phase.HOOKED: stick = -1.0 if h.tension < 0.8 else 0.6
		h.step(dt, stick, rt, false)
	return h

static func _hand_line(t) -> void:
	var stats := {}
	for policy in ["skilled", "brute", "eager", "shallow"]:
		var pd := 0.0; var lost := 0; var n := 40
		for s in n:
			var h := _hl_session(policy, 500 + s)
			pd += h.person_days(); lost += h.hooks_lost
		stats[policy] = {"pd": pd / n, "lost": float(lost) / n}
		print("INFO  hand line %-8s %.1f person-days per watch, %.2f hooks lost" % [policy, pd / n, float(lost) / n])
	t.check("hand line: a skilled watch lands about a day's catch (12-26 person-days)", stats.skilled.pd >= 12.0 and stats.skilled.pd <= 26.0, "%.1f" % stats.skilled.pd)
	t.check("hand line: striking at nibbles catches almost nothing", stats.eager.pd < stats.skilled.pd * 0.25, "%.1f" % stats.eager.pd)
	t.check("hand line: hauling flat out loses more hooks", stats.brute.lost > stats.skilled.lost + 0.3, "%.2f vs %.2f" % [stats.brute.lost, stats.skilled.lost])
	t.check("hand line: shallow water gives smaller fish", stats.shallow.pd < stats.skilled.pd, "%.1f" % stats.shallow.pd)
	var h := HandLine.new()
	h.setup(cfg().hand_line, 3, 1)
	h.step(0.016, 0.0, false, true)
	t.check("hand line: cutting the line costs the last hook and ends the session", h.hooks == 0 and h.phase == HandLine.Phase.DONE)

static func _joint_run(policy: String, seed: int, rain: bool) -> Joint:
	var j := Joint.new()
	j.setup(cfg().joint, seed, rain)
	var dt := 1.0 / 60.0
	var cycle := 0.0
	while j.phase < Joint.Phase.SEATED:
		var ls := clampf(j.wobble * 3.0, -1, 1) if policy != "no_brace" else 0.0
		var rs := clampf((j.hole_angle - j.peg_angle) / 8.0, -1, 1)
		var rt := 0.0
		if j.phase == Joint.Phase.DRIVE:
			cycle += dt
			var force: float = {"steady": 0.65, "no_brace": 0.65, "hard": 1.0, "timid": 0.2}[policy]
			# one blow every 0.6 s; the steady hand waits if the grain is loaded
			var wait := policy == "steady" and j.grain_load() > 0.55
			rt = force if fmod(cycle, 0.6) < 0.25 and not wait else 0.0
		j.step(dt, ls, rs, rt)
	return j

static func _joint(t) -> void:
	var rates := {}
	for policy in ["steady", "hard", "timid", "no_brace"]:
		for rain in [false, true]:
			var ok := 0; var n := 60
			for s in n:
				if _joint_run(policy, 700 + s, rain).succeeded():
					ok += 1
			rates["%s_%s" % [policy, rain]] = float(ok) / n
			print("INFO  joint %-8s %-5s seats %3d%%" % [policy, "rain" if rain else "dry", roundi(100.0 * ok / n)])
	t.check("joint: a steady hand seats the peg in the dry (>= 90%)", rates.steady_false >= 0.9, "%d%%" % roundi(rates.steady_false * 100))
	t.check("joint: a steady hand still mostly seats it in rain (>= 70%)", rates.steady_true >= 0.7, "%d%%" % roundi(rates.steady_true * 100))
	t.check("joint: full-force blows split the log", rates.hard_false <= 0.2, "%d%%" % roundi(rates.hard_false * 100))
	t.check("joint: rain makes hard driving worse", rates.hard_true <= rates.hard_false)
	t.check("joint: timid taps run out of daylight", rates.timid_false <= 0.2, "%d%%" % roundi(rates.timid_false * 100))
	t.check("joint: driving without a brace splits more often", rates.no_brace_false < rates.steady_false, "%d%%" % roundi(rates.no_brace_false * 100))
