extends RefCounted
## Sun board (MG2), net (MG4) and smoke rack (MG9): rules and expert bots on Hard.

static func run(t) -> void:
	var tree: SceneTree = t.get_tree()
	var hard_sun: Dictionary = Game.tuning("sun_board", "hard")
	# sun board rules
	var s := SunBoard.new(); s.setup(hard_sun, 11)
	s.step(0.1, 0, 0, false, false, true)
	t.check("sun board: giving up is no reading", s.result == RingFix.Result.NONE)
	s = SunBoard.new(); s.setup(hard_sun, 12)
	for i in 600:
		s.disk = s.sun_az + s.yaw()          # hold the noon line exactly
		s.peg = s.ideal_peg() / (1.0 + s.pitch())
		s.step(1.0 / 60.0, 0, 0, true, false, false)
		if s.seat_held > 0.5: break
	s.step(1.0 / 60.0, 0, 0, true, true, false)
	t.check("sun board: a reading taken before it steadies is snatched (partial)", s.result == RingFix.Result.PARTIAL and s.snatched)
	var cl := SunBoard.new(); cl.setup(hard_sun, 13, true)
	var hidden := false
	for i in 60 * 30:
		cl.step(1.0 / 60.0, 0, 0, false, false, false)
		if not cl.sun_visible: hidden = true
	t.check("sun board: broken cloud hides the sun now and then", hidden)
	var braced := SunBoard.new(); braced.setup(hard_sun, 14)
	var loose_swing := 0.0; var held_swing := 0.0
	for i in 300:
		braced.t = i / 60.0
		braced.brace = 0.0; loose_swing = maxf(loose_swing, absf(braced.yaw() - float(hard_sun.wander_deg) * sin(braced.t * float(hard_sun.wander_speed))))
		braced.brace = 1.0; held_swing = maxf(held_swing, absf(braced.yaw() - float(hard_sun.wander_deg) * sin(braced.t * float(hard_sun.wander_speed))))
	t.check("sun board: holding RT damps the roll's swing of the shadow", held_swing < loose_swing * 0.4, "%.1f vs %.1f deg" % [held_swing, loose_swing])
	var clean := 0
	for i in 20:
		var sc: Node = load("res://scenes/sun_board.tscn").instantiate()
		sc.embedded = true; t.add_child(sc); sc.difficulty = "hard"; sc.start(i % 3 == 2, 5100 + i); sc.autopilot = true
		var g := 0
		while sc.result.is_empty() and g < 50 * 60:
			sc._process(1.0 / 60.0); g += 1
		if int(sc.result.get("result", -1)) == RingFix.Result.CLEAN: clean += 1
		sc.queue_free()
	await tree.process_frame
	t.check("sun board: the expert bot takes clean readings on Hard (18+ of 20)", clean >= 18, "%d of 20" % clean)
	# net rules
	var hard_net: Dictionary = Game.tuning("net", "hard")
	var nt := NetThrow.new(); nt.setup(hard_net, 48.0, 1, 21)
	nt.aim = nt.school
	nt.step(1.0 / 60.0, Vector2.ZERO, true, 0, 0)
	for i in 60: nt.step(1.0 / 60.0, Vector2.ZERO, false, 0, 0)
	nt.step(1.0 / 60.0, Vector2.ZERO, false, 1, 1)          # closes at the surface
	t.check("net: closing at the surface comes up empty and spends the day", nt.phase == NetThrow.Phase.DONE and nt.catch_pd == 0.0)
	var dry := NetThrow.new(); dry.setup(hard_net, 48.0, 1, 22, false)
	var wet := NetThrow.new(); wet.setup(hard_net, 48.0, 1, 22, true)
	t.check("net: in rain the school runs deeper", wet.school_depth > dry.school_depth)
	var fg := NetThrow.new(); fg.setup(hard_net, 48.0, 1, 23, false, true)
	fg.school = Vector2(400, 400)
	t.check("net: in fog the school is hidden until it nears the boat", not fg.school_seen())
	var two := NetThrow.new(); two.setup(Game.tuning("net", "forgiving"), 48.0, 1, 24)
	t.check("net: Forgiving allows a second throw", two.throws_left == 2)
	var caught := 0; var total := 0.0
	for i in 20:
		var sc: Node = load("res://scenes/net.tscn").instantiate()
		sc.embedded = true; t.add_child(sc); sc.difficulty = "hard"; sc.start(i % 4 == 3, false, 5500 + i); sc.autopilot = true
		var g := 0
		while sc.result.is_empty() and g < 60 * 60:
			sc._process(1.0 / 60.0); g += 1
		if not sc.result.get("empty", true): caught += 1
		total += float(sc.result.get("person_days", 0.0))
		sc.queue_free()
	await tree.process_frame
	t.check("net: the expert bot lands fish on Hard (17+ of 20) and a good throw feeds the camp", caught >= 17 and total / 20.0 >= 24.0, "%d of 20, %.1f person-days" % [caught, total / 20.0])
	# smoke rack rules
	var hard_rack: Dictionary = Game.tuning("smoke_rack", "hard")
	var hot := SmokeRack.new(); hot.setup(hard_rack, 31)
	while not hot.done:
		hot.step(1.0 / 60.0, -hot.column / 50.0, 1.0)
	t.check("smoke rack: a fire fed hard case-hardens the fish and spoils the rack", hot.hardening > 0.6 and hot.spoiled(), "hardened %.2f" % hot.hardening)
	var cold := SmokeRack.new(); cold.setup(hard_rack, 32)
	while not cold.done:
		cold.step(1.0 / 60.0, -cold.column / 50.0, -1.0)
	t.check("smoke rack: a fire let die cures nothing", cold.cure < 0.2, "%.2f" % cold.cure)
	var good := 0
	for i in 20:
		var sc: Node = load("res://scenes/smoke_rack.tscn").instantiate()
		sc.embedded = true; t.add_child(sc); sc.difficulty = "hard"; sc.start(5900 + i); sc.autopilot = true
		var g := 0
		while sc.result.is_empty() and g < 50 * 60:
			sc._process(1.0 / 60.0); g += 1
		if float(sc.result.get("quality", 0.0)) >= 0.8: good += 1
		sc.queue_free()
	await tree.process_frame
	t.check("smoke rack: the expert bot cures the rack on Hard (18+ of 20 at 80%+)", good >= 18, "%d of 20" % good)

## The noon sun fix at sea: sunny days only, and the day's drift uses the better of sun and stars.
static func voyage(t) -> void:
	var TV = load("res://tests/test_voyage.gd")
	var sunny := 0; var overcast_sun := 0; var days := 0
	for s in 40:
		var v: Voyage = TV.make(7000 + s)
		v.start_day()
		days += 1
		if v.sun_noon: sunny += 1
		if v.sun_noon and v.weather in ["fog", "storm", "following_gale", "beam_sea"]: overcast_sun += 1
	t.check("voyage sun: some days have a noon sun; overcast and storm days never do", sunny > 0 and overcast_sun == 0, "%d of %d days sunny" % [sunny, days])
	var a: Voyage = TV.make(7100); var b: Voyage = TV.make(7100)
	for v in [a, b]:
		v.start_day()
		v.weather = "fair"
	a.take_sun_fix(RingFix.Result.CLEAN)
	a.take_fix(RingFix.Result.NONE)
	b.take_fix(RingFix.Result.NONE)
	t.check("voyage sun: a clean noon reading wins back the day's drift even with no star fix", a.best_fix() == RingFix.Result.CLEAN and b.best_fix() == RingFix.Result.NONE)
	var leg_a := a.leg_left; var leg_b := b.leg_left
	a.end_day(); b.end_day()
	t.check("voyage sun: the sun-fixed ship walks no distance downwind", a.leg_left - leg_a < b.leg_left - leg_b, "%.1f vs %.1f nm" % [a.leg_left - leg_a, b.leg_left - leg_b])
	var d: Dictionary = JSON.parse_string(JSON.stringify(a.to_dict()))
	var back := Voyage.new()
	back.from_dict(Knobs._v, TV.legs_data(), d)
	t.check("voyage sun: the noon reading survives a save", back.sun_today == a.sun_today and back.sun_fixes == a.sun_fixes)
