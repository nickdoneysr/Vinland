extends Node
## Headless tests. Run: godot --headless --path . res://tests/test_runner.tscn
## Prints one line per check and exits non-zero on any failure.

var fails := 0

func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1

func _ready() -> void:
	# Watchdog: a script error must never leave the run hanging.
	get_tree().create_timer(900.0).timeout.connect(func(): print("RESULT FAIL (watchdog timeout)"); get_tree().quit(2))
	_rules()
	await _bot_nights()
	load("res://tests/test_voyage.gd").run(self)
	await load("res://tests/test_voyage_scene.gd").run(self)
	load("res://tests/test_minigames.gd").run(self)
	load("res://tests/test_camp.gd").run(self)
	load("res://tests/test_save.gd").run(self)
	load("res://tests/test_loadout.gd").run(self)
	load("res://tests/test_options.gd").run(self)
	load("res://tests/test_outfits.gd").run(self)
	await load("res://tests/test_work_games.gd").run(self)
	load("res://tests/test_work_games.gd").voyage(self)
	await load("res://tests/test_voyage_scene.gd").run_slice(self)
	print("RESULT %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)

func _feed(r: RingFix, reading: float, seconds: float) -> void:
	var dt := 1.0 / 60.0
	for i in int(seconds / dt):
		r.step(dt, reading, 0.0, 0.1, true)

func _rules() -> void:
	var r := RingFix.new()
	r.reset(61.0); _feed(r, 61.2, 2.0)
	check("ring: reading within 0.5 deg is clean", r.commit().result == RingFix.Result.CLEAN)
	r.reset(61.0); _feed(r, 62.0, 2.0)
	check("ring: 1 deg off is partial", r.commit().result == RingFix.Result.PARTIAL)
	r.reset(61.0); _feed(r, 63.0, 2.0)
	check("ring: 2 deg off is no fix", r.commit().result == RingFix.Result.NONE)
	r.reset(61.0); _feed(r, 61.0, 0.5)
	check("ring: commit before the seat holds is no fix", r.commit().result == RingFix.Result.NONE)
	r.reset(61.0); _feed(r, 61.0, 2.0)
	check("ring: abort caps a clean reading at partial", r.abort().result == RingFix.Result.PARTIAL)
	r.reset(61.0)
	for i in 120: r.step(1.0 / 60.0, 61.0, 0.0, 0.1, false)
	check("ring: a clouded star never seats", r.commit().result == RingFix.Result.NONE)
	check("drift: clean refunds, partial halves, none walks",
		RingFix.drift_multiplier(2) == 0.0 and RingFix.drift_multiplier(1) == 0.5 and RingFix.drift_multiplier(0) == 1.0)

## Plays nights with a bot to prove each condition is winnable and that mislevelling is punished.
func _bot_nights() -> void:
	var scene: PackedScene = load("res://scenes/star_ring.tscn")
	for spec in [["clear", 0.0, RingFix.Result.CLEAN], ["storm", 0.0, -1], ["twilight", 0.0, RingFix.Result.CLEAN],
			["clear", 1.0, RingFix.Result.PARTIAL], ["fog", 2.2, RingFix.Result.NONE]]:
		var n = scene.instantiate()
		add_child(n)
		check("star ring scene loads", n.has_method("new_night"))
		if not n.has_method("new_night"):
			return
		n.difficulty = "hard"
		n.new_night(spec[0])
		n.autopilot = true
		n.autopilot_level_bias = spec[1]
		var out := {}
		n.finished.connect(func(r): out.merge(r))
		var elapsed := 0.0
		while out.is_empty() and elapsed < 75.0:
			n._process(1.0 / 60.0)
			elapsed += 1.0 / 60.0
			if n.rule.seat_held >= RingFix.SEAT_TIME + 0.6 and out.is_empty():
				n._finish(n.rule.commit())
		var res: int = out.get("result", -9)
		var ok: bool = res == spec[2] if spec[2] >= 0 else res >= RingFix.Result.PARTIAL
		check("bot night: %s, mislevel %.1f deg -> %s" % [spec[0], spec[1], RingFix.result_name(res) if res >= 0 else "timeout"], ok,
			"err=%.2f t=%.1fs" % [out.get("error", NAN), elapsed])
		n.queue_free()
		await get_tree().process_frame
