extends RefCounted
## Plays the voyage screen from Eriksfjord to the end with a bot pressing A, using the ring's autopilot.

static func run(t) -> void:
	var tree: SceneTree = t.get_tree()
	for seed in [11, 12, 13]:
		var scene: Node = load("res://scenes/voyage.tscn").instantiate()
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
					var r: Node = scene.ring
					r.autopilot = true
					var guard := 0
					while r.outcome.is_empty() and guard < 5000:
						r._process(1.0 / 60.0)
						guard += 1
						if r.rule.seat_held >= RingFix.SEAT_TIME + 0.3 and r.outcome.is_empty():
							r._finish(r.rule.commit())
					rings += 1
					scene._close_ring()
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
	t.add_child(vs)
	var v: Voyage = vs.v
	var guard := 0
	while guard < 4000 and not (vs.mode == "card" and vs.cards.size() == 1 and vs.cards[0].get("kind", "") in ["end", "camp"]):
		guard += 1
		match vs.mode:
			"card": vs._unhandled_input(press)
			"sail": vs._try_watch()
			"ring":
				var r: Node = vs.ring
				r.autopilot = true
				while r.outcome.is_empty():
					r._process(1.0 / 60.0)
					if r.rule.seat_held >= RingFix.SEAT_TIME + 0.3 and r.outcome.is_empty():
						r._finish(r.rule.commit())
				vs._close_ring()
	Game.voyage = v
	vs.queue_free()
	await tree.process_frame
	var cs: Node = load("res://scenes/camp.tscn").instantiate()
	t.add_child(cs)
	var camp: Camp = cs.camp
	var played := 0
	guard = 0
	while guard < 3000 and camp.state == "camp" or (cs.mode == "card" and cs.cards.size() > 0 and cs.cards[0].get("kind", "") != "end"):
		guard += 1
		if guard > 3000:
			break
		match cs.mode:
			"card": cs._unhandled_input(press)
			"morning":
				camp.assign = {"build": 8, "fish": 5, "forage": 5, "timber": 3, "hay": 0, "tend": 1}
				camp.default_assignments()
				if played < 6:
					camp.player_job = "build" if played % 2 == 0 else "fish"
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
	t.check("slice: plays from Eriksfjord to autumn at the Strait", camp.state == "ended", "%s, %d people, %d booths, longhouse %d%%" % [camp.state, camp.people, camp.booths, roundi(camp.longhouse / 540.0 * 100)])
	t.check("slice: every G1 gate item is met by a played run", end_body.count("[x]") == 5, end_body.get_slice("\n", 1))
	cs.queue_free()
	await tree.process_frame
