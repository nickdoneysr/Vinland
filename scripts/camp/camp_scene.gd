extends Node2D
## The camp at the Strait (Backlog F06). Morning: share the crew between jobs and choose your own job.
## Controls: LS up/down or LB/RB pick a job · D-pad or LS left/right change its crew · Y work this job yourself
##           A start the day (you play the joint or the hand line) · Start/Tab let the crew work a week without you
## Draws procedurally until the camp art (CMP-*, ANI-*) is saved at its listed paths.

const JOINT_SCENE := preload("res://scenes/joint.tscn")
const LINE_SCENE := preload("res://scenes/hand_line.tscn")
const HUNT_SCENE := preload("res://scenes/hunt.tscn")
const FORAGE_SCENE := preload("res://scenes/forage.tscn")

var camp := Camp.new()
var voyage: Voyage = null
var mode := "morning"          # morning | minigame | card
var cards: Array = []
var focus := 0
var child: Node = null
var t := 0.0
var _font: Font
var _stick_ready := true
var _logged := false
var autosave_off := false        # tests turn this off

func _ready() -> void:
	_font = ThemeDB.fallback_font
	voyage = Game.voyage
	if Game.loaded_stage == "camp" and Game.camp != null:
		camp = Game.camp
		Game.loaded_stage = ""
		_card("Continuing at the Strait", "%s, year %d, %s.\n%s" % [camp.date_text(), camp.year, camp.season(), _stores_line()])
		return
	if voyage != null:
		camp.from_voyage(voyage)
	else:
		camp.setup(Knobs._v)
		camp.day_of_year = 165
		camp.food = 1.0
		camp.default_assignments()
	Game.camp = camp
	_card("The Strait, %s" % camp.date_text(),
		"The knarr is drawn up on the shingle. %d people come ashore with %.1f units of food in the stores and %d hooks.\nEach morning, share out the crew and pick the job you will work yourself. Roofs first: the booths shelter eight each.\nThe first snow comes about 1 November. Dry fish on the rack and cut hay in August, or the winter will take people and animals." % [camp.people, camp.food, camp.hooks])

func _card(title: String, body: String, kind: String = "") -> void:
	cards.append({"title": title, "body": body, "kind": kind})
	mode = "card"

# ------------------------------------------------------------------ the day
func _start_day() -> void:
	camp.default_assignments()
	var job := camp.player_job
	if job != "" and int(camp.assign[job]) > 0:
		mode = "minigame"
		match job:
			"build":
				child = JOINT_SCENE.instantiate()
				child.embedded = true
				add_child(child)
				child.start(camp.rain)
			"fish":
				child = LINE_SCENE.instantiate()
				child.embedded = true
				child.hook_stock = camp.hooks
				add_child(child)
				child.start(false, 0.3)
			"hunt":
				child = HUNT_SCENE.instantiate()
				child.embedded = true
				add_child(child)
				child.start(camp.hunt_far)
			"forage":
				child = FORAGE_SCENE.instantiate()
				child.embedded = true
				add_child(child)
				child.start(0, camp.patch_health)
		child.closed.connect(_close_minigame)
	else:
		_finish_day({})

func _close_minigame() -> void:
	var r: Dictionary = child.result
	var job := camp.player_job
	child.queue_free()
	child = null
	match job:
		"build": _finish_day({"job": "build", "seated": bool(r.get("seated", false))})
		"fish": _finish_day({"job": "fish", "person_days": float(r.get("person_days", 0.0)), "hooks_lost": int(r.get("hooks_lost", 0))})
		"hunt": _finish_day({"job": "hunt", "kill": bool(r.get("kill", false)), "person_days": float(r.get("person_days", 0.0)), "fear_tick": bool(r.get("fear_tick", false))})
		"forage": _finish_day({"job": "forage", "person_days": float(r.get("person_days", 0.0)), "patch_health": float(r.get("patch_health", 1.0))})

func _finish_day(player: Dictionary) -> void:
	var tally := camp.work_day(player)
	var head := "Evening, %s  ·  %s%s" % [tally.date, tally.season, ("  ·  snow" if tally.season == "winter" else "  ·  rain") if tally.rain else ""]
	var body := "\n".join(tally.lines) if tally.lines.size() > 0 else "A quiet day."
	body += "\n" + _stores_line()
	_card(head, body)
	_autosave()
	_check_end()

func _work_week() -> void:
	var lines: Array = []
	var start := camp.date_text()
	for i in 7:
		if camp.state != "camp":
			break
		var tally := camp.work_day({})
		for l in tally.lines:
			if l.begins_with("A booth") or l.begins_with("The longhouse") or l.begins_with("The byre") or l.begins_with("First snow") or l.begins_with("The thaw") \
					or l.begins_with("Autumn") or "died" in l or "starved" in l or "fell sick" in l or "empty" in l or l.begins_with("No hay"):
				lines.append("%s: %s" % [tally.date, l])
	if lines.size() > 9:
		lines = lines.slice(lines.size() - 9)
	lines.append(_stores_line() + " Building: %s." % camp.building_target())
	_card("A week of work, %s to %s" % [start, camp.date_text()], "\n".join(lines))
	_autosave()
	_check_end()

## Day-level autosave in camp (Release: Save). A finished or lost camp clears its saves.
func _autosave() -> void:
	if autosave_off:
		return
	if camp.state == "camp":
		Game.save_game("camp")
	else:
		Game.clear_saves()

func _stores_line() -> String:
	var s := "Stores: %.0f days of food" % camp.food_days()
	if not camp.is_winter():
		s += " (winter is %d days long)" % camp.winter_days_left()
	s += ". Hay: %.0f days for the herd. %d of %d under a roof." % [minf(camp.hay_days(), 999.0), camp.sheltered_total(), camp.people]
	return s

func _check_end() -> void:
	if camp.state == "camp":
		return
	if not _logged:
		_logged = true
		DirAccess.make_dir_recursive_absolute("user://runlog")
		camp.write_log("user://runlog/camp_%s.csv" % Time.get_datetime_string_from_system(true).replace(":", "-"))
	if camp.state == "lost":
		_card("The camp is lost", camp.end_reason, "end")
		return
	var v := voyage
	var fixes := 0 if v == null else int(v.fixes[2])
	var hold_changed: bool = v != null and (v.food < v.default_provisions().food or v.hooks < int(v.n("hooks_carried", 6)) or v.fixes[2] > 0)
	var check := func(ok: bool) -> String: return "[x]" if ok else "[ ]"
	var gate := "Vertical slice gate (G1):\n%s One sea leg   %s A clean fix (%d)   %s A fish on the hand line (%d watches)   %s A seated joint (%d)   %s A hold that changed because of them" % [
		check.call(v != null and v.state == "arrived"), check.call(fixes > 0), fixes, check.call(camp.history.fish_watches > 0), camp.history.fish_watches,
		check.call(camp.history.joints_seated > 0), camp.history.joints_seated, check.call(hold_changed)]
	_card("Spring at the Strait, year two",
		"The camp came through its first winter. %d people at the camp (%d lost since Eriksfjord), %d cattle and %d sheep.\n%d booths, the longhouse %s, the byre %s. %.1f units of timber stacked for the return. %d person-days of fish went onto the rack.\n%s\nThe market, the second summer, and the voyage home come next." % [
		camp.people, camp.dead, camp.cattle, camp.sheep, camp.booths, "finished" if camp.hall_done() else "%d%% raised" % roundi(camp.longhouse / camp.n("work_to_raise_the_longhouse", 540) * 100.0),
		"finished" if camp.byre_done() else "unfinished", camp.timber, roundi(camp.history.dried_pd), gate], "end")

# ------------------------------------------------------------------ input
func _process(delta: float) -> void:
	t += delta
	if mode == "morning":
		var s := Controls.left_stick()
		if s.length() < 0.3:
			_stick_ready = true
		elif _stick_ready:
			_stick_ready = false
			if absf(s.y) > absf(s.x):
				focus = clampi(focus + (1 if s.y > 0 else -1), 0, Camp.JOBS.size() - 1)
			else:
				_change(1 if s.x > 0 else -1)
	queue_redraw()

func _change(d: int) -> void:
	var job: String = Camp.JOBS[focus]
	camp.set_assign(job, int(camp.assign[job]) + d)

func _unhandled_input(e: InputEvent) -> void:
	if mode == "minigame":
		return
	if mode == "card":
		if e.is_action_pressed("commit"):
			get_viewport().set_input_as_handled()
			var c: Dictionary = cards.pop_front()
			if c.get("kind", "") == "end":
				get_tree().change_scene_to_file("res://scenes/boot.tscn")
				return
			if cards.is_empty():
				mode = "morning"
		return
	if e.is_action_pressed("tool_next"):
		focus = (focus + 1) % Camp.JOBS.size()
	elif e.is_action_pressed("tool_prev"):
		focus = (focus + Camp.JOBS.size() - 1) % Camp.JOBS.size()
	elif e.is_action_pressed("ui_right_pad"):
		_change(1)
	elif e.is_action_pressed("ui_left_pad"):
		_change(-1)
	elif e.is_action_pressed("alt"):
		var job: String = Camp.JOBS[focus]
		if Camp.PLAYABLE.has(job):
			camp.player_job = "" if camp.player_job == job else job
	elif e.is_action_pressed("drop") and Camp.JOBS[focus] == "hunt":
		camp.hunt_far = not camp.hunt_far
	elif e.is_action_pressed("menu"):
		_work_week()
	elif e.is_action_pressed("commit"):
		_start_day()

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if mode == "minigame":
		return
	_draw_world()
	_draw_board()
	if mode == "card":
		_draw_card()

func _draw_world() -> void:
	var winter := camp.is_winter()
	var sky := Color("a9c4d0") if not camp.rain else Color("7d8a90")
	if camp.season() == "autumn":
		sky = sky.lerp(Color("c9a77a"), 0.25)
	if winter:
		sky = Color("c8d2d6") if not camp.rain else Color("9aa4a8")
	draw_rect(Rect2(0, 0, 1920, 540), sky)
	var hills := PackedVector2Array()
	for x in range(0, 1961, 40):
		hills.append(Vector2(x, 420 - 50 * sin(x * 0.003) - 20 * sin(x * 0.011)))
	hills.append(Vector2(1960, 560)); hills.append(Vector2(0, 560))
	draw_colored_polygon(hills, Color("2e4a36"))
	var grass := Color("6e8a4e")
	if camp.season() == "autumn":
		grass = Color("9a9a52")
	if winter:
		grass = Color("e8ecec")
	elif camp.season() == "spring":
		grass = Color("8a8a5a")
	draw_rect(Rect2(0, 520, 1920, 560), grass)
	# brook, shore and sea on the right
	draw_line(Vector2(786, 520), Vector2(806, 1080), Color("5c7c8a"), 22.0)
	draw_colored_polygon(PackedVector2Array([Vector2(1500, 520), Vector2(1920, 520), Vector2(1920, 1080), Vector2(1700, 1080)]), Color("bdb39a"))
	draw_colored_polygon(PackedVector2Array([Vector2(1640, 520), Vector2(1920, 520), Vector2(1920, 1080), Vector2(1840, 1080)]), Color("2f4a57"))
	# the knarr drawn up on the shingle
	draw_colored_polygon(PackedVector2Array([Vector2(1520, 880), Vector2(1600, 940), Vector2(1800, 940), Vector2(1860, 860), Vector2(1800, 900), Vector2(1580, 900)]), Color("4a3828"))
	# booths at their plots
	var plots := int(camp.n("booth_plots_at_the_camp", 3))
	for i in plots:
		var x := 820.0 + i * 190.0
		var y := 700.0
		if i < camp.booths:
			draw_rect(Rect2(x, y - 70, 150, 70), Color("6b5a44"))
			draw_colored_polygon(PackedVector2Array([Vector2(x - 10, y - 70), Vector2(x + 75, y - 120), Vector2(x + 160, y - 70)]), Color("7a8a5a"))
		elif i == camp.booths:
			var p := camp.joints / camp.n("work_to_raise_a_booth", 16)
			draw_rect(Rect2(x, y - 70 * p, 150, 70 * p), Color("6b5a44", 0.8))
			for px in [x, x + 75, x + 150]:
				draw_line(Vector2(px, y), Vector2(px, y - 100), Color("4a3828"), 6.0)
		else:
			draw_rect(Rect2(x, y - 6, 150, 6), Color("4a3828", 0.5))
	# the byre beside the booths
	var byre_p := camp.byre / camp.n("work_to_raise_the_byre", 160)
	if byre_p > 0.0:
		draw_rect(Rect2(1180, 820 - 70 * byre_p, 200, 70 * byre_p), Color("5a4a36"))
		if byre_p >= 1.0:
			draw_colored_polygon(PackedVector2Array([Vector2(1170, 750), Vector2(1280, 712), Vector2(1390, 750)]), Color("7a8a5a") if not winter else Color("f0f2f2"))
	# the longhouse rises behind
	var hall := camp.longhouse / camp.n("work_to_raise_the_longhouse", 540)
	draw_rect(Rect2(300, 640, 460, 6), Color("4a3828"))
	if hall > 0:
		draw_rect(Rect2(300, 640 - 110 * minf(hall, 0.7) / 0.7, 460, 110 * minf(hall, 0.7) / 0.7), Color("5a4a36"))
	if hall > 0.7:
		var rp := (hall - 0.7) / 0.3
		draw_colored_polygon(PackedVector2Array([Vector2(290, 530), Vector2(290 + 240 * rp, 530 - 60 * rp), Vector2(770 - 240 * rp, 530 - 60 * rp), Vector2(770, 530)]), Color("6e8a4e"))
	# the smoke rack
	draw_line(Vector2(140, 720), Vector2(140, 640), Color("4a3828"), 6.0)
	draw_line(Vector2(240, 720), Vector2(240, 640), Color("4a3828"), 6.0)
	draw_line(Vector2(130, 645), Vector2(250, 645), Color("4a3828"), 6.0)
	if int(camp.assign.get("dry", 0)) > 0 and not camp.rain:
		for i in 4:
			draw_rect(Rect2(150 + i * 24, 650, 10, 30), Color("c9a55a"))
		draw_circle(Vector2(190 + sin(t) * 6, 610 - fmod(t * 30.0, 60.0)), 14, Color(0.85, 0.85, 0.85, 0.4))
	# timber stack and hay
	for i in mini(int(camp.timber), 12):
		draw_rect(Rect2(1380 + (i % 4) * 30, 900 - (i / 4) * 22, 26, 18), Color("8a6d4e"))
	for i in mini(int(camp.hay), 6):
		draw_circle(Vector2(1180 + i * 46, 980), 22, Color("c9b060"))
	# animals and people
	for i in camp.cattle:
		draw_rect(Rect2(420 + i * 70, 820 + sin(t + i) * 2, 56, 30), Color("8a6d4e") if i > 0 else Color("3a2a1c"))
	for i in camp.sheep:
		draw_circle(Vector2(560 + i * 34, 880 + sin(t * 1.3 + i) * 2), 12, Color("e0d8c4"))
	var spots := {"build": Vector2(900, 760), "fish": Vector2(1640, 860), "forage": Vector2(300, 860), "timber": Vector2(80, 600), "hay": Vector2(1100, 940), "tend": Vector2(1000, 640), "dry": Vector2(130, 740), "hunt": Vector2(40, 820)}
	for job in Camp.JOBS:
		var c: int = int(camp.assign[job])
		for i in c:
			var p: Vector2 = spots[job] + Vector2((i % 6) * 18, (i / 6) * 26)
			draw_rect(Rect2(p, Vector2(10, 22)), Color("2a2119") if job != camp.player_job or i > 0 else Color("c9a55a"))
	if camp.rain and winter:
		for i in 120:
			var sx := fmod(i * 97.0 + t * 60.0 + sin(t + i) * 30.0, 1920.0)
			var sy := fmod(i * 53.0 + t * 140.0, 1080.0)
			draw_circle(Vector2(sx, sy), 3.0, Color(1, 1, 1, 0.8))
	elif camp.rain:
		for i in 70:
			var rx := fmod(i * 97.0 + t * 700.0, 1920.0)
			var ry := fmod(i * 53.0 + t * 1200.0, 1080.0)
			draw_line(Vector2(rx, ry), Vector2(rx - 8, ry + 30), Color(0.85, 0.88, 0.9, 0.3), 1.5)

func _draw_board() -> void:
	var ink := Color("ede3cc")
	var panel := Color(0.1, 0.09, 0.07, 0.86)
	draw_rect(Rect2(24, 20, 640, 120), panel)
	draw_rect(Rect2(24, 140, 640, 60), panel)
	var wx := ("snow" if camp.is_winter() else "rain") if camp.rain else "fair"
	draw_string(_font, Vector2(44, 62), "%s, year %d  ·  %s  ·  %s" % [camp.date_text(), camp.year, camp.season(), wx], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	draw_string(_font, Vector2(44, 100), "%d people, %d sick · %d of %d under a roof · cattle %d, sheep %d" % [camp.people, camp.sick.size(), camp.sheltered_total(), camp.people, camp.cattle, camp.sheep],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	var food_col := ink if camp.is_winter() or camp.food_days() >= camp.winter_days_left() else Color("e8c35a")
	draw_string(_font, Vector2(44, 132), "Food %.0f days · hay %.0f days · winter %d days" % [camp.food_days(), minf(camp.hay_days(), 999.0), camp.winter_days_left()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, food_col)
	draw_string(_font, Vector2(44, 168), "Building %s · timber %.1f · hooks %d · hides %d · fear %d/%d%s" % [camp.building_target(), camp.timber, camp.hooks, camp.hides, int(camp.fear), int(camp.n("fear_cap", 5)), "" if camp.is_winter() else " · %d days to snow" % camp.days_to_snow()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	# job board
	var bx := 1340.0; var by := 20.0
	draw_rect(Rect2(bx, by, 556, 590), panel)
	draw_string(_font, Vector2(bx + 20, by + 42), "MORNING  ·  %d idle" % camp.idle(), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	for i in Camp.JOBS.size():
		var job: String = Camp.JOBS[i]
		var y := by + 92 + i * 56
		var open := camp.job_open(job)
		if i == focus and mode == "morning":
			draw_rect(Rect2(bx + 10, y - 34, 536, 50), Color("c9a55a", 0.25))
		var label: String = Camp.JOB_NAMES[job] + ("" if open else "  " + camp.job_note(job))
		if job == "build":
			label = "Build: " + camp.build_short()
		elif job == "hunt":
			label = "Hunt: %s grounds" % ("far" if camp.hunt_far else "near")
		draw_string(_font, Vector2(bx + 24, y), label, HORIZONTAL_ALIGNMENT_LEFT, 370, 24 if open else 20, Color(ink, 1.0 if open else 0.4))
		draw_string(_font, Vector2(bx + 400, y), "‹ %d ›" % int(camp.assign[job]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		if camp.player_job == job:
			draw_string(_font, Vector2(bx + 480, y), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("c9a55a"))
	draw_string(_font, Vector2(bx + 20, by + 560), "Y: work this job yourself · B on Hunt: near / far", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.65))
	if mode == "morning":
		var you := "A: start the day" + (" (you play %s)" % Camp.PLAYABLE[camp.player_job] if camp.player_job != "" and int(camp.assign[camp.player_job]) > 0 else "")
		draw_rect(Rect2(560, 1000, 980, 56), panel)
		draw_string(_font, Vector2(580, 1038), you + "      Start/Tab: let the crew work a week", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)

func _draw_card() -> void:
	if cards.is_empty():
		return
	var c: Dictionary = cards[0]
	var ink := Color("ede3cc")
	draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 0.35))
	var r := Rect2(410, 250, 1100, 520)
	draw_rect(r, Color("2a2119"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	draw_rect(r, Color("8a6d4e"), false, 4.0)
	draw_string(_font, r.position + Vector2(40, 74), c.title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 34, ink)
	draw_multiline_string(_font, r.position + Vector2(40, 130), c.body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 24, -1, Color(ink, 0.88))
	draw_string(_font, r.position + Vector2(40, r.size.y - 30), "A: continue" if c.get("kind", "") != "end" else "A: back to the title", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
