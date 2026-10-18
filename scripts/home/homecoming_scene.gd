extends Node2D
## Eriksfjord homecoming (Backlog F25 appraisal and sale, F26 recruitment and a second hull).
## A steps through the pages; on the recruitment page LB/RB choose a row, D-pad changes it.

var PAGES := ["arrival", "appraisal", "recruit", "winter"]

var home := Home.new()
var page := 0
var rfocus := 0
var _font: Font
var autosave_off := false

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if Game.loaded_stage == "home" and not Game.home.is_empty():
		home.from_dict(Knobs._v, Game.home)
		Game.loaded_stage = ""
		page = PAGES.find("winter")
		return
	if Game.voyage != null and Game.camp != null:
		home.setup(Knobs._v, Game.voyage, Game.camp, Game.outfit_table().get(Game.voyage.outfit, {}), Game.home)
	if home.is_final():
		PAGES = ["arrival", "appraisal", "saga"]

func _unhandled_input(e: InputEvent) -> void:
	var pg: String = PAGES[page]
	if pg == "recruit":
		if e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down") or e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up"):
			rfocus = 1 - rfocus
			return
		var d := 0
		if e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right"):
			d = 1
		elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left"):
			d = -1
		if d != 0:
			if rfocus == 0:
				home.set_hull(d > 0)
			else:
				home.set_hires(home.hires + d)
			return
	if e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		advance()

## Next page. After recruitment the winter at home is saved; from the winter page the relief is loaded.
## A final homecoming ends in the saga and the score.
func advance() -> void:
	if PAGES[page] == "recruit":
		Game.home = home.to_dict()
		if not autosave_off:
			Game.save_game("home")
	if page < PAGES.size() - 1:
		page += 1
		if PAGES[page] == "saga":
			Game.home = home.to_dict()
			if not autosave_off:
				Game.clear_saves()
		return
	var next := "res://scenes/boot.tscn" if PAGES[page] == "saga" else "res://scenes/relief.tscn"
	if is_inside_tree() and not get_tree().root.has_meta("no_scene_change"):
		get_tree().change_scene_to_file(next)

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	# Eriksfjord in autumn: the farm, the fjord, the knarr drawn up
	draw_rect(Rect2(0, 0, 1920, 1080), Color("8d9ca6"))
	var hills := PackedVector2Array()
	for x in range(0, 1961, 40):
		hills.append(Vector2(x, 380 - 110 * sin(x * 0.0022 + 0.4) - 30 * sin(x * 0.012)))
	hills.append(Vector2(1960, 660)); hills.append(Vector2(0, 660))
	draw_colored_polygon(hills, Color("6f6a48"))
	draw_rect(Rect2(0, 660, 1920, 420), Color("4c6672"))
	draw_colored_polygon(PackedVector2Array([Vector2(1180, 990), Vector2(1700, 990), Vector2(1650, 1050), Vector2(1230, 1050)]), Color("4a3828"))
	for i in mini(home.timber, 17):
		draw_rect(Rect2(1250 + (i % 9) * 44, 958 - (i / 9) * 28, 40, 24), Color("8a6d4e"))
	var r := Rect2(240, 120, 1440, 760)
	draw_rect(r, Color(0.1, 0.09, 0.07, 0.9))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	var x0 := r.position.x + 50
	var y := r.position.y + 76
	match PAGES[page]:
		"arrival":
			draw_string(_font, Vector2(x0, y), "HOME AT ERIKSFJORD  ·  year %d  ·  cargo %d" % [home.year, home.cargoes], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
			var names: Array = home.crew.map(func(m): return str(m.name).split(" ")[0])
			var body := "%d came home: %s.\n\n%s\n\nIn the hold: %d units of timber and %d pelts." % [home.came_home, ", ".join(names),
				("%d wait at the Strait through another winter." % home.at_camp) if home.at_camp > 0 else "No one waits at the Strait. The booths stand empty.", home.timber, home.pelts]
			draw_multiline_string(_font, Vector2(x0, y + 60), body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 24, -1, Color(ink, 0.9))
		"appraisal":
			draw_string(_font, Vector2(x0, y), "THE APPRAISAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
			var why: String = {"prime": "Prime: seasoned, straight, mostly felled in winter when the sap was down.",
				"sound": "Sound: good building timber, some of it green.",
				"rough": "Rough: green summer wood that will check and twist as it dries."}[home.grade]
			var lines := [
				"%d units of timber, graded %s.  %s" % [home.timber, home.grade, why],
				"%d%% of the camp's timber was felled in winter.%s" % [roundi(home.winter_share * 100), "  The shipwright's kin chose the trees." if home.outfit == "shipwright_s_kin" else ""],
				"Timber:   %d units x %.1f marks x %.1f   =   %.1f marks of silver" % [home.timber, home.n("silver_per_timber_unit_sound_grade", 3), home.grade_multiplier(home.grade), home.timber_silver],
				"Pelts:    %d pelts x %.2f marks   =   %.1f marks" % [home.pelts, home.n("silver_per_pelt", 0.25), home.pelt_silver],
				"Silver the household had before:   %.1f marks" % home.silver_start,
				"",
				"In hand:   %.1f marks of silver" % home.silver()]
			draw_multiline_string(_font, Vector2(x0, y + 60), "\n".join(lines), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 24, -1, Color(ink, 0.9))
		"recruit":
			draw_string(_font, Vector2(x0, y), "THE STORY AND THE RELIEF", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
			draw_multiline_string(_font, Vector2(x0, y + 50), "The story told at the farms this winter:\n  " + "\n  ".join(home.story_lines) + "\nStory: %d points. %d come forward for the story alone%s." % [roundi(home.story), home.volunteers,
				("; there is room for %d" % home.volunteers_aboard()) if home.volunteers_aboard() < home.volunteers else ""],
				HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 22, -1, Color(ink, 0.9))
			var rows := [["A second hull (%d marks)" % roundi(home.hull_price()), "‹ %s ›" % ("buy her" if home.buy_hull else ("no" if home.can_buy_hull() else "no (not enough silver)"))],
				["Hire recruits (%d mark each)" % roundi(home.hire_price()), "‹ %d ›" % home.hires]]
			for i in rows.size():
				var ry := y + 330 + i * 60
				if i == rfocus:
					draw_rect(Rect2(x0 - 20, ry - 38, r.size.x - 60, 52), Color("c9a55a", 0.22))
				draw_string(_font, Vector2(x0, ry), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
				draw_string(_font, Vector2(x0 + 640, ry), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
			draw_string(_font, Vector2(x0, y + 480), "Silver left: %.1f marks   ·   the relief: %d of %d places in %d hull%s" % [home.left(), home.relief_party(), home.room(), home.hulls(), "s" if home.hulls() > 1 else ""],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
			draw_string(_font, Vector2(x0, y + 530), ("Q/E choose · Z/C change · Enter agree" if kb else "LB/RB choose · D-pad change · A agree"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))
		"winter":
			draw_string(_font, Vector2(x0, y), "WINTER AT ERIKSFJORD", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
			var body2 := "The silver is counted, the oaths are sworn. When the ice goes out, the relief sails west: %d people in %d hull%s, %.1f marks left for stores and stock.\n\n%s\n\nCargoes home so far: %d of two." % [
				home.relief_party(), home.hulls(), "s" if home.hulls() > 1 else "", home.left(),
				("%d people are wintering at the Strait without you. Whether they are alive in spring is the next question." % home.at_camp) if home.at_camp > 0 else "No one waits at the Strait.",
				home.cargoes]
			draw_multiline_string(_font, Vector2(x0, y + 60), body2, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 24, -1, Color(ink, 0.9))
			draw_string(_font, Vector2(x0, y + 400), "A: load the relief for the spring sailing.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 22, Color(ink, 0.7))
		"saga":
			var sc := home.score()
			draw_string(_font, Vector2(x0, y), str(sc.title).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color("e8c35a"))
			draw_multiline_string(_font, Vector2(x0, y + 50), str(sc.line), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 24, -1, ink)
			draw_multiline_string(_font, Vector2(x0, y + 170), "\n".join(sc.lines), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 24, -1, Color(ink, 0.9))
			draw_string(_font, Vector2(x0, y + 520), "Score: %d" % int(sc.total), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color("e8c35a"))
	if PAGES[page] != "recruit":
		draw_string(_font, Vector2(x0, r.end.y - 30), "A: continue" if page < PAGES.size() - 1 else ("A: back to the title" if PAGES[page] == "saga" else "A: load the relief"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
