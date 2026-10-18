extends RefCounted
## Can a first-time player pass each mini-game? Plays a novice model on keyboard and pad at each difficulty.

const TARGET := {"forgiving": 0.85, "standard": 0.6}
## Hunting is meant to fail often even for good hunters (the animal runs); targets are lower.
const HUNT_TARGET := {"forgiving": 0.6, "standard": 0.4}

static func run(t) -> void:
	var tree: SceneTree = t.get_tree()
	var table := {}
	var only: Array = []          # -- --games=sun,net,rack runs just those
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--games="):
			only = a.trim_prefix("--games=").split(",")
	for diff in ["forgiving", "standard", "hard"]:
		for kb in [true, false]:
			var dev := "keyboard" if kb else "pad"
			if only.is_empty() or "ring" in only:
				table["ring_%s_%s" % [diff, dev]] = await _ring(t, tree, diff, kb)
			if only.is_empty() or "line" in only:
				table["line_%s_%s" % [diff, dev]] = await _line(t, tree, diff, kb)
			if only.is_empty() or "joint" in only:
				table["joint_%s_%s" % [diff, dev]] = await _joint(t, tree, diff, kb)
			if only.is_empty() or "bail" in only:
				table["bail_%s_%s" % [diff, dev]] = await _bail(t, tree, diff, kb)
			if only.is_empty() or "hunt" in only:
				table["hunt_%s_%s" % [diff, dev]] = await _hunt(t, tree, diff, kb)
			if only.is_empty() or "forage" in only:
				table["forage_%s_%s" % [diff, dev]] = await _forage(t, tree, diff, kb)
			if only.is_empty() or "sun" in only:
				table["sun_%s_%s" % [diff, dev]] = await _sun(t, tree, diff, kb)
			if only.is_empty() or "net" in only:
				table["net_%s_%s" % [diff, dev]] = await _net(t, tree, diff, kb)
			if only.is_empty() or "rack" in only:
				table["rack_%s_%s" % [diff, dev]] = await _rack(t, tree, diff, kb)
	var games: Array = ["ring", "line", "joint", "bail", "hunt", "forage", "sun", "net", "rack"] if only.is_empty() else only
	for game in games:
		var row := "INFO  novice %-6s" % game
		for diff in ["forgiving", "standard", "hard"]:
			for dev in ["keyboard", "pad"]:
				row += "  %s/%s %3d%%" % [diff.substr(0, 4), dev.substr(0, 3), roundi(table["%s_%s_%s" % [game, diff, dev]] * 100)]
		print(row)
	for game in games:
		for diff in TARGET:
			for dev in ["keyboard", "pad"]:
				var v: float = table["%s_%s_%s" % [game, diff, dev]]
				var want: float = HUNT_TARGET[diff] if game == "hunt" else TARGET[diff]
				t.check("novice: %s on %s with %s passes %d%%+" % [game, diff, dev, roundi(want * 100)], v >= want, "%d%%" % roundi(v * 100))

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

static func _hunt(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/hunt.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(s % 2 == 1, 2500 + s)
		var nov := Novice.new(2500 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.hunt
		var g := 0
		while sc.result.is_empty() and g < 90 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if sc.result.get("kill", false):
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

## Forage passes when the basket holds a fair day's food (12+ person-days) without stripping the patch below 85%.
static func _forage(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/forage.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(2700 + s)
		var nov := Novice.new(2700 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.forage
		var g := 0
		while sc.result.is_empty() and g < 60 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if float(sc.result.get("person_days", 0.0)) >= 12.0 and float(sc.result.get("patch_health", 0.0)) >= 0.85:
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

## The sun board passes on a partial or clean reading; a third of noons have broken cloud.
static func _sun(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/sun_board.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(s % 3 == 2, 3100 + s)
		var nov := Novice.new(3100 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.sun
		var g := 0
		while sc.result.is_empty() and g < 50 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if int(sc.result.get("result", 0)) >= RingFix.Result.PARTIAL:
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

## The net passes when it comes up with any fish; a quarter of days are rainy (the school runs deep).
static func _net(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/net.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(s % 4 == 3, false, 3500 + s)
		var nov := Novice.new(3500 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.net
		var g := 0
		while sc.result.is_empty() and g < 60 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if not sc.result.get("empty", true):
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n

## The rack passes when the fish come through at least half cured and not spoiled.
static func _rack(t, tree: SceneTree, diff: String, kb: bool) -> float:
	var ok := 0; var n := 24
	for s in n:
		var sc: Node = load("res://scenes/smoke_rack.tscn").instantiate()
		sc.embedded = true
		t.add_child(sc)
		sc.difficulty = diff
		sc.start(3900 + s)
		var nov := Novice.new(3900 + s + (0 if kb else 50), kb)
		sc.bot_input = nov.rack
		var g := 0
		while sc.result.is_empty() and g < 50 * 60:
			sc._process(1.0 / 60.0)
			g += 1
		if float(sc.result.get("quality", 0.0)) >= 0.5 and not sc.result.get("spoiled", true):
			ok += 1
		sc.queue_free()
	await tree.process_frame
	return float(ok) / n
