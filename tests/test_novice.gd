extends RefCounted
## Can a first-time player pass each mini-game? Plays a novice model on keyboard and pad at each difficulty.

const TARGET := {"forgiving": 0.85, "standard": 0.6}

static func run(t) -> void:
	var tree: SceneTree = t.get_tree()
	var table := {}
	for diff in ["forgiving", "standard", "hard"]:
		for kb in [true, false]:
			var dev := "keyboard" if kb else "pad"
			table["ring_%s_%s" % [diff, dev]] = await _ring(t, tree, diff, kb)
			table["line_%s_%s" % [diff, dev]] = await _line(t, tree, diff, kb)
			table["joint_%s_%s" % [diff, dev]] = await _joint(t, tree, diff, kb)
			table["bail_%s_%s" % [diff, dev]] = await _bail(t, tree, diff, kb)
	for game in ["ring", "line", "joint", "bail"]:
		var row := "INFO  novice %-6s" % game
		for diff in ["forgiving", "standard", "hard"]:
			for dev in ["keyboard", "pad"]:
				row += "  %s/%s %3d%%" % [diff.substr(0, 4), dev.substr(0, 3), roundi(table["%s_%s_%s" % [game, diff, dev]] * 100)]
		print(row)
	for game in ["ring", "line", "joint", "bail"]:
		for diff in TARGET:
			for dev in ["keyboard", "pad"]:
				var v: float = table["%s_%s_%s" % [game, diff, dev]]
				t.check("novice: %s on %s with %s passes %d%%+" % [game, diff, dev, roundi(TARGET[diff] * 100)], v >= TARGET[diff], "%d%%" % roundi(v * 100))

static func _ring(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	var presets := ["clear", "clouded", "twilight", "fog"]
	for s in n:
		var sc: Node = load("res://scenes/star_ring.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.new_night(presets[s % presets.size()], 4100 + s)
		var nov := Novice.new(900 + s, kb)
		sc.bot_input = nov.ring
		var g := 0
		while sc.outcome.is_empty() and g < 75 * 60 + 10:
			sc._play(1.0 / 60.0); sc.t += 1.0 / 60.0
			g += 1
		if sc.outcome.get("result", 0) >= RingFix.Result.PARTIAL:
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

static func _line(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/hand_line.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(s % 4 == 3, 0.3, 1300 + s)
		var nov := Novice.new(1300 + s, kb)
		sc.bot_input = nov.hand_line
		var g := 0
		while sc.result.is_empty() and g < 80 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if float(sc.result.get("person_days", 0.0)) > 0.0:
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

static func _joint(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/joint.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.keyboard_charge = kb
		sc.start(s % 3 == 2, 1700 + s)
		var nov := Novice.new(1700 + s, kb)
		sc.bot_input = nov.joint
		var g := 0
		while sc.result.is_empty() and g < 60 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if sc.result.get("seated", false):
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

static func _bail(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/storm_bail.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(2100 + s)
		var nov := Novice.new(2100 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.bail
		var g := 0
		while sc.result.is_empty() and g < 60 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if sc.result.get("held", false):
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n
