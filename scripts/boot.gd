extends Control

var info: Label
## Boot and title screen. Run with `-- --smoke` to print a self-check and quit (used in CI).

func _ready() -> void:
	Game.new_run()
	var bg := TextureRect.new()
	bg.texture = Art.tex("MNU-01")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := Label.new()
	title.text = "VINLAND"
	title.add_theme_font_size_override("font_size", 120)
	title.position = Vector2(140, 200)
	add_child(title)
	info = Label.new()
	info.add_theme_font_size_override("font_size", 26)
	info.position = Vector2(146, 360)
	add_child(info)
	_refresh()
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke()

var save: Dictionary = {}

func _refresh() -> void:
	save = Game.latest_save()
	var cont := ("Start / Tab: continue  (%s)\n" % save.get("where", "saved game")) if not save.is_empty() else ""
	info.text = ("Production build  ·  slice art in place %d%%\n\n" % int(Art.coverage("Vertical slice") * 100)) + cont + \
		"A / Enter: new voyage: load the knarr at Eriksfjord\n" + \
		"Practice:  Y / F star ring   1 hand line   2 joint   3 storm bail   4 hunt   5 berry patch\n\n" + \
		"Difficulty:  ‹ %s ›   (D-pad or Z / C to change)\n" % Game.DIFFICULTY_NAMES[Game.settings.difficulty] + \
		{"forgiving": "Wide windows, steadier hands, clear prompts. Start here.",
		 "standard": "Tighter windows. The prompts stay on.",
		 "hard": "The original tuning: small windows, no prompts. Made for a gamepad."}[Game.settings.difficulty] + \
		"\n\nBack / P in play: pause and options." + \
		"\nKeyboard: WASD left stick · arrows right stick · Space right trigger · Shift left trigger · Enter A · Esc B · F Y · Q/E bumpers"

func _cycle(d: int) -> void:
	var i := Game.DIFFICULTIES.find(Game.settings.difficulty)
	Game.settings.difficulty = Game.DIFFICULTIES[clampi(i + d, 0, Game.DIFFICULTIES.size() - 1)]
	Game.save_settings()
	_refresh()

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_right_pad"):
		_cycle(1)
		return
	if e.is_action_pressed("ui_left_pad"):
		_cycle(-1)
		return
	if e.is_action_pressed("menu") and not save.is_empty():
		get_tree().change_scene_to_file(Game.load_game(save))
		return
	if e.is_action_pressed("commit"):
		Game.voyage = null
		Game.camp = null
		Game.loaded_stage = ""
		Game.loadout = {}
		get_tree().change_scene_to_file("res://scenes/loadout.tscn")
	elif e.is_action_pressed("alt"):
		get_tree().change_scene_to_file("res://scenes/star_ring.tscn")
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_1:
		get_tree().change_scene_to_file("res://scenes/hand_line.tscn")
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_2:
		get_tree().change_scene_to_file("res://scenes/joint.tscn")
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_3:
		get_tree().change_scene_to_file("res://scenes/storm_bail.tscn")
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_4:
		get_tree().change_scene_to_file("res://scenes/hunt.tscn")
	elif e is InputEventKey and e.pressed and e.physical_keycode == KEY_5:
		get_tree().change_scene_to_file("res://scenes/forage.tscn")

func _smoke() -> void:
	var ok := true
	ok = ok and Knobs.has("knarr_cargo_units")
	ok = ok and Art.manifest.size() > 200
	ok = ok and Art.tex("NAV-01") != null
	ok = ok and InputMap.has_action("rt") and InputMap.has_action("drop")
	print("SMOKE knobs=%d art=%d hold=%s/%s nav01=%s result=%s" % [
		62 if Knobs.has("fear_cap") else 0, Art.manifest.size(), Game.hold_load(), Game.hold_capacity(),
		Art.size_of("NAV-01"), "PASS" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)
