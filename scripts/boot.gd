extends Control
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
	title.position = Vector2(140, 300)
	add_child(title)
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 26)
	info.position = Vector2(146, 460)
	info.text = "Preproduction build  ·  hold %s of %s units  ·  slice art in place %d%%\nPress A or Enter" % [
		Game.hold_load(), Game.hold_capacity(), int(Art.coverage("Vertical slice") * 100)]
	add_child(info)
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke()

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
