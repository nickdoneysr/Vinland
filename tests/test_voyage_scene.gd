extends RefCounted
## Plays the voyage screen from Eriksfjord to the end with a bot pressing A, using the ring's autopilot.

## Plays whichever mini-game the voyage opened (star ring, storm bail, or hand line) with its expert bot.
static func drive_child(scene: Node) -> void:
	if scene.line != null:
		var l: Node = scene.line
		l.autopilot = true
		var g := 0
		while l.result.is_empty() and g < 20000:
			l._process(1.0 / 60.0); g += 1
		scene._close_line()
		return
	var r: Node = scene.ring
	r.autopilot = true
	var guard := 0
	if r is Node2D and "rules" in r and r.rules is SunBoard:
		while r.result.is_empty() and guard < 20000:
			r._process(1.0 / 60.0); guard += 1
		scene._close_sun()
		return
	if r is Node2D and "rules" in r and r.rules is StormBail:
		while r.result.is_empty() and guard < 20000:
			r._process(1.0 / 60.0); guard += 1
		scene._close_bail()
		return
	while r.outcome.is_empty() and guard < 5000:
		r._process(1.0 / 60.0)
		guard += 1
		if r.rule.seat_held >= r.rule.seat_time + 0.3 and r.outcome.is_empty():
			r._finish(r.rule.commit())
	scene._close_ring()

static func run(t) -> void:
	var tree: SceneTree = t.get_tree()
	for seed in [11, 12, 13]:
		var scene: Node = load("res://scenes/voyage.tscn").instantiate()
		scene.autosave_off = true
		t.add_child(scene)
		var v: Voyage = scene.v
		var press := InputEventAction.new()
		press.action = "commit"; press.pressed = true
		var steps := 0; var rings := 0; var cards := 0
		while steps < 4000:
			steps += 1
			match scene.mode:
				"card":
					var last: bool = scene.cards.size() == 1 and scene.cards[0].get("kind", "") in ["end", "camp"]
					if last:
						break
					cards += 1
					scene._unhandled_input(press)
				"sail":
					if v.is_coastal() and not v.fished_today and v.watch == 0 and v.food_days() < 12:
						var ev := v.fish()
						scene._handle_events(ev.slice(1))
					scene._try_watch()
				"ring":
					drive_child(scene)
					rings += 1
		t.check("voyage screen: seed %d plays to an ending" % seed, v.state != "sailing",
			"%s day %d, %d people, %d rings, %d cards, %d steps" % [v.state, v.day, v.people, rings, cards, steps])
		scene.queue_free()
		await tree.process_frame

## The whole vertical slice: voyage, then the camp with your own joints and fishing, to the G1 checklist.
static func run_slice(t) -> void:
	var tree: SceneTree = t.get_tree()
	var press := InputEventAction.new()
	press.action = "commit"; press.pressed = true
	var vs: Node = load("res://scenes/voyage.tscn").instantiate()
	vs.autosave_off = true
	t.add_child(vs)
	var v: Voyage = vs.v
	var guard := 0
	while guard < 4000 and not (vs.mode == "card" and vs.cards.size() == 1 and vs.cards[0].get("kind", "") in ["end", "camp"]):
		guard += 1
		match vs.mode:
			"card": vs._unhandled_input(press)
			"sail": vs._try_watch()
			"ring":
				drive_child(vs)
	Game.voyage = v
	vs.queue_free()
	await tree.process_frame
	var cs: Node = load("res://scenes/camp.tscn").instantiate()
	cs.autosave_off = true
	t.add_child(cs)
	var camp: Camp = cs.camp
	var played := 0
	guard = 0
	while guard < 3000 and camp.state == "camp" and not (cs.mode == "card" and cs.cards.size() > 0 and cs.cards[0].get("kind", "") == "spring"):
		guard += 1
		if guard > 3000:
			break
		match cs.mode:
			"card": cs._unhandled_input(press)
			"morning":
				camp.assign = {"build": 7, "fish": 5, "hunt": 2, "forage": 3, "dry": 2, "timber": 2, "hay": 2 if camp.job_open("hay") else 0, "tend": 1}
				camp.default_assignments()
				if played < 8:
					camp.player_job = ["build", "fish", "hunt", "forage"][played % 4]
					played += 1
					cs._start_day()
				else:
					cs._work_week()
			"minigame":
				var ch: Node = cs.child
				ch.autopilot = true
				var g2 := 0
				while ch.result.is_empty() and g2 < 20000:
					ch._process(1.0 / 60.0)
					g2 += 1
				cs._close_minigame()
	var end_body: String = cs.cards[0].body if cs.cards.size() > 0 else ""
	t.check("slice: plays from Eriksfjord through the first winter to the second spring", camp.second_spring and camp.state == "camp", "%s, %d people, %d booths, longhouse %d%%" % [camp.state, camp.people, camp.booths, roundi(camp.longhouse / 540.0 * 100)])
	t.check("slice: every G1 gate item is met by a played run", end_body.count("[x]") == 5, end_body.get_slice("\n", 1))
	cs.queue_free()
	await tree.process_frame
