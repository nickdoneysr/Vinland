extends RefCounted
## Save and continue (F50): round trips through the real files, rotation, and a voyage that replays identically.

static func run(t) -> void:
	var legs: Dictionary = JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())
	Game.clear_saves()
	var v := Voyage.new()
	v.setup(Knobs._v, legs, 4242)
	for d in 3:
		v.start_day()
		for w in 6:
			v.sail_watch()
	v.start_day()
	v.sail_watch()
	Game.voyage = v
	Game.camp = null
	t.check("save: writing a voyage save succeeds", Game.save_game("voyage"))
	for i in 3:
		Game.save_game("voyage")
	t.check("save: three rolling slots and no temp file left",
		FileAccess.file_exists("user://save/autosave_0.json") and FileAccess.file_exists("user://save/autosave_2.json")
		and not FileAccess.file_exists("user://save/autosave_3.json") and not FileAccess.file_exists("user://save/autosave.tmp"))
	var d := Game.latest_save()
	var scene_path := Game.load_game(d)
	var w: Voyage = Game.voyage
	t.check("save: loading a voyage save opens the voyage", scene_path.ends_with("voyage.tscn") and w != v)
	for i in 12:
		v.sail_watch(); w.sail_watch()
	t.check("save: a loaded voyage sails on exactly as the original", is_equal_approx(v.leg_left, w.leg_left) and is_equal_approx(v.food, w.food) and v.day == w.day and v.weather == w.weather and v.deck == w.deck,
		"%.2f vs %.2f nm" % [v.leg_left, w.leg_left])
	# a corrupt newest slot falls back to the next
	var f := FileAccess.open("user://save/autosave_0.json", FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	t.check("save: a broken newest save falls back to the one before", not Game.latest_save().is_empty())
	# camp
	var c := Camp.new()
	c.setup(Knobs._v, 77)
	c.day_of_year = 200
	for i in 20:
		c.work_day()
	Game.camp = c
	Game.save_game("camp")
	var path2 := Game.load_game(Game.latest_save())
	t.check("save: loading a camp save opens the camp at the same day", path2.ends_with("camp.tscn") and Game.camp.day_of_year == c.day_of_year and Game.camp.food == c.food)
	Game.clear_saves()
	Game.voyage = null
	Game.camp = null
	Game.loaded_stage = ""
