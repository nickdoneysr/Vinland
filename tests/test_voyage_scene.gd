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
					var last: bool = scene.cards.size() == 1 and scene.cards[0].get("kind", "") == "end"
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
