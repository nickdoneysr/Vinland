extends Node2D
## The camp at the Strait (Backlog F06). Morning: share the crew between jobs and choose your own job.
## Controls: LS up/down or LB/RB pick a job · D-pad or LS left/right change its crew · Y work this job yourself
##           A start the day (you play the joint or the hand line) · Start/Tab let the crew work a week without you
## Draws procedurally until the camp art (CMP-*, ANI-*) is saved at its listed paths.

const JOINT_SCENE := preload("res://scenes/joint.tscn")
const LINE_SCENE := preload("res://scenes/hand_line.tscn")
const HUNT_SCENE := preload("res://scenes/hunt.tscn")
const FORAGE_SCENE := preload("res://scenes/forage.tscn")
const NET_SCENE := preload("res://scenes/net.tscn")
const RACK_SCENE := preload("res://scenes/smoke_rack.tscn")

var camp := Camp.new()
var voyage: Voyage = null
var mode := "morning"          # morning | market | return | hop | minigame | card
var hop_count := 10
var plan: ReturnPlan = null    # the voyage home being loaded (F24)
var rfocus := 0
var market_done := false       # today's market has been met (or there was none)
var offer := {"cloth": 0, "milk": 0, "pen": true}
var mfocus := 0
var after_cards := ""          # what to do when the cards are dismissed: "" or "work"
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
	add_to_group("camp_screen")
	voyage = Game.voyage
	if Game.loaded_stage == "reunion" and Game.camp != null and voyage != null:
		camp = Game.camp
		Game.loaded_stage = ""
		var rep := camp.reunite(voyage)
		var story := ""
		if str(rep.state_before) != "camp":
			story = "The booths stand empty. %s The relief takes up the camp again." % ("Everyone had sailed home." if str(rep.state_before) == "abandoned" else "No one survived the winter; the cairns above the shore say so.")
		else:
			story = "%d were waiting at the camp; %d came through to meet the relief%s." % [rep.alive_before, rep.alive_after,
				(" (%d died while you were away)" % rep.dead_while_away) if rep.dead_while_away > 0 else ""]
		var tail: Array = rep.lines.slice(maxi(0, rep.lines.size() - 7))
		_card("The camp again, %s, year %d" % [camp.date_text(), camp.year], story + "\n" + "\n".join(tail) + "\n" + _stores_line() + \
			"\nThe knarr is here. A second cargo of timber home before the autumn closes the full arc.")
		_autosave()
		return
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
	if not market_done:
		market_done = true
		if camp.roll_market():
			offer = {"cloth": mini(camp.cloth_strips, 4), "milk": mini(camp.milk_to_spare(), 20), "pen": not camp.byre_done()}
			mfocus = 0
			mode = "market"
			return
	_start_work()

func _start_work() -> void:
	camp.default_assignments()
	var job := camp.player_job
	if job == "dry" and camp.rain:
		job = ""                     # no fire on the rack in the rain
	if job != "" and int(camp.assign[job]) > 0:
		mode = "minigame"
		match job:
			"build":
				child = JOINT_SCENE.instantiate()
				child.embedded = true
				add_child(child)
				child.start(camp.rain)
			"fish":
				if camp.playable("fish") == "the net":
					child = NET_SCENE.instantiate()
					child.embedded = true
					add_child(child)
					child.start(camp.rain, false)
				else:
					child = LINE_SCENE.instantiate()
					child.embedded = true
					child.hook_stock = camp.hooks
					add_child(child)
					child.start(false, 0.3)
			"dry":
				child = RACK_SCENE.instantiate()
				child.embedded = true
				add_child(child)
				child.start()
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
		"dry": _finish_day({"job": "dry", "quality": float(r.get("quality", 0.0)), "spoiled": bool(r.get("spoiled", false))})

func _finish_day(player: Dictionary) -> void:
	market_done = false
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
		if camp.roll_market():
			var auto := camp.do_trade(mini(camp.cloth_strips, 4), mini(camp.milk_to_spare(), 20), not camp.byre_done())
			for l in auto.lines:
				lines.append("%s: %s" % [camp.date_text(), l])
			if camp.weapon_request:
				for l in camp.answer_weapon_request(false).lines:
					lines.append("%s: %s" % [camp.date_text(), l])
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
	if camp.second_spring and not camp.history.get("spring_card", false):
		camp.history.spring_card = true
		_spring_card()
	if camp.state == "camp":
		return
	if not _logged:
		_logged = true
		DirAccess.make_dir_recursive_absolute("user://runlog")
		camp.write_log("user://runlog/camp_%s.csv" % Time.get_datetime_string_from_system(true).replace(":", "-"))
	if camp.state == "lost":
		_card("The camp is lost", camp.end_reason, "end")
		return
	if camp.state == "stranded":
		var h := Home.new()
		h.k = Knobs._v
		var prev: Dictionary = Game.home
		var sc := Score.compute(Knobs._v, {"timber": int(prev.get("timber_total", 0)), "cargo_value": float(prev.get("cargo_value", 0.0)), "cargoes": int(prev.get("cargoes", 0)), "relief": camp.relief_came,
			"camp_alive": camp.people, "home_alive": 0, "goodwill": camp.goodwill, "dead": camp.dead})
		_card(str(sc.title), camp.end_reason + "\n" + str(sc.line) + "\n" + "\n".join(sc.lines) + "\nScore: %d" % int(sc.total), "end")
		return

## The first winter is behind them: the G1 checklist, and what the second summer asks.
func _spring_card() -> void:
	var v := voyage
	var fixes := 0 if v == null else int(v.fixes[2])
	var hold_changed: bool = v != null and (v.food < v.default_provisions().food or v.hooks < int(v.n("hooks_carried", 6)) or v.fixes[2] > 0)
	var check := func(ok: bool) -> String: return "[x]" if ok else "[ ]"
	var gate := "Vertical slice gate (G1):\n%s One sea leg   %s A clean fix (%d)   %s A fish on the hand line (%d watches)   %s A seated joint (%d)   %s A hold that changed because of them" % [
		check.call(v != null and v.state == "arrived"), check.call(fixes > 0), fixes, check.call(camp.history.fish_watches > 0), camp.history.fish_watches,
		check.call(camp.history.joints_seated > 0), camp.history.joints_seated, check.call(hold_changed)]
	_card("Spring at the Strait, year two",
		"The camp came through its first winter. %d people at the camp (%d lost since Eriksfjord), %d cattle and %d sheep.\n%d booths, the longhouse %s, the byre %s. %.1f units of timber stacked for the return. %d person-days of fish went onto the rack.\n%s\n" % [
		camp.people, camp.dead, camp.cattle, camp.sheep, camp.booths, "finished" if camp.hall_done() else "%d%% raised" % roundi(camp.longhouse / camp.n("work_to_raise_the_longhouse", 540) * 100.0),
		"finished" if camp.byre_done() else "unfinished", camp.timber, roundi(camp.history.dried_pd), gate] + \
		"\nFrom 1 June the knarr can sail home with timber: raise the boat shed, mend the hull, stack at least %d units, then Y on the knarr row." % int(camp.n("timber_units_to_open_a_return", 4)), "spring")

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
				focus = clampi(focus + (1 if s.y > 0 else -1), 0, Camp.JOBS.size())
			else:
				_change(1 if s.x > 0 else -1)
	queue_redraw()

func _change(d: int) -> void:
	if focus >= Camp.JOBS.size():
		return
	var job: String = Camp.JOBS[focus]
	camp.set_assign(job, int(camp.assign[job]) + d)

func _unhandled_input(e: InputEvent) -> void:
	if mode == "minigame":
		return
	if mode == "market":
		_market_input(e)
		return
	if mode == "return":
		_return_input(e)
		return
	if mode == "hop":
		_hop_input(e)
		return
	if mode == "card" and not cards.is_empty() and cards[0].get("kind", "") == "weapon":
		if e.is_action_pressed("commit") or e.is_action_pressed("alt"):
			get_viewport().set_input_as_handled()
			cards.pop_front()
			var res := camp.answer_weapon_request(e.is_action_pressed("alt"))
			_card("The blades", "\n".join(res.lines), "to_work")
		return
	if mode == "card":
		if e.is_action_pressed("commit"):
			get_viewport().set_input_as_handled()
			var c: Dictionary = cards.pop_front()
			if c.get("kind", "") == "to_work":
				if cards.is_empty():
					_start_work()
				return
			if c.get("kind", "") == "end":
				get_tree().change_scene_to_file("res://scenes/boot.tscn")
				return
			if cards.is_empty():
				mode = "morning"
		return
	if e.is_action_pressed("tool_next"):
		focus = (focus + 1) % (Camp.JOBS.size() + 1)
	elif e.is_action_pressed("tool_prev"):
		focus = (focus + Camp.JOBS.size()) % (Camp.JOBS.size() + 1)
	elif e.is_action_pressed("ui_right_pad"):
		_change(1)
	elif e.is_action_pressed("ui_left_pad"):
		_change(-1)
	elif e.is_action_pressed("alt") and focus >= Camp.JOBS.size():
		open_return()
	elif e.is_action_pressed("drop") and focus >= Camp.JOBS.size():
		open_hop()
	elif e.is_action_pressed("alt"):
		var job: String = Camp.JOBS[focus]
		if Camp.PLAYABLE.has(job):
			camp.player_job = "" if camp.player_job == job else job
	elif e.is_action_pressed("drop") and focus < Camp.JOBS.size() and Camp.JOBS[focus] == "fish" and camp.nets > 0:
		camp.fish_net = not camp.fish_net
	elif e.is_action_pressed("drop") and focus < Camp.JOBS.size() and Camp.JOBS[focus] == "hunt":
		camp.hunt_far = not camp.hunt_far
	elif e.is_action_pressed("menu"):
		_work_week()
	elif e.is_action_pressed("commit"):
		_start_day()

# ------------------------------------------------------------------ the voyage home (F24)
## Y on the knarr row: plan the voyage home if the return gate is open, or say what still stands in the way.
func open_return() -> void:
	var why := camp.return_gate()
	if not why.is_empty():
		_card("The knarr is not ready", "\n".join(why))
		return
	plan = ReturnPlan.new()
	plan.setup(Knobs._v, camp)
	rfocus = 0
	mode = "return"

## B on the knarr row: plan a push south to Hóp (F27).
func open_hop() -> void:
	hop_count = int(camp.n("hop_smallest_party", 10))
	var why := camp.hop_gate(hop_count)
	if not why.is_empty():
		_card("No voyage to Hóp now", "\n".join(why))
		return
	mode = "hop"

func _hop_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right"):
		hop_count = mini(hop_count + 1, camp.people - 4)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left"):
		hop_count = maxi(int(camp.n("hop_smallest_party", 10)), hop_count - 1)
	elif e.is_action_pressed("drop"):
		get_viewport().set_input_as_handled()
		mode = "morning"
	elif e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if camp.start_hop(hop_count):
			_card("South to Hóp", "%d sail south in the knarr. They will be gone about %d days; the camp works on without them.\nThe knarr cannot sail home until she is back." % [hop_count, int(camp.n("hop_days_away", 30))])
			_autosave()
		else:
			mode = "morning"

func _draw_hop() -> void:
	var ink := Color("ede3cc")
	var r := Rect2(420, 260, 1080, 470)
	draw_rect(r, Color("2a2119"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	draw_string(_font, r.position + Vector2(40, 64), "THE PUSH SOUTH TO HÓP", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	var p := hop_count
	var body := "South along the coast to Hóp, where the saga says the vines grow wild, wheat sows itself and the rivers are full of salmon. About %d days away.\n\nThey should bring back about %.1f units of vines and grapes (worth %d marks a unit at home, twice the timber), self-sown wheat and dried salmon.\nMany people live at Hóp: fear may rise (less with goodwill). The shoals may strain the hull. The knarr is gone while they are." % [
		int(camp.n("hop_days_away", 30)), p * camp.n("hop_vines_and_grapes_per_person", 0.25), int(camp.n("silver_per_unit_of_vines", 6))]
	draw_multiline_string(_font, r.position + Vector2(40, 110), body, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 21, -1, Color(ink, 0.9))
	draw_string(_font, r.position + Vector2(40, 360), "Party:  ‹ %d ›   (%d stay at the camp)" % [p, camp.people - p], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
	var names: Array = camp.hop_party(p).map(func(m): return str(m.name).split(" ")[0])
	draw_string(_font, r.position + Vector2(40, 400), "Sailing: " + ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 18, Color(ink, 0.7))
	draw_string(_font, r.position + Vector2(40, 446), ("Z/C party size · Enter sail south · Esc not now" if Controls.keyboard else "D-pad party size · A sail south · B not now"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))

func _return_input(e: InputEvent) -> void:
	var rows := ReturnPlan.ROWS.size()
	if e.is_action_pressed("tool_next") or e.is_action_pressed("ui_down"):
		rfocus = (rfocus + 1) % rows
	elif e.is_action_pressed("tool_prev") or e.is_action_pressed("ui_up"):
		rfocus = (rfocus + rows - 1) % rows
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_right"):
		plan.change(ReturnPlan.ROWS[rfocus], 1)
	elif e.is_action_pressed("ui_left_pad") or e.is_action_pressed("ui_left"):
		plan.change(ReturnPlan.ROWS[rfocus], -1)
	elif e.is_action_pressed("alt"):
		plan.reset()
	elif e.is_action_pressed("drop"):
		get_viewport().set_input_as_handled()
		plan = null
		mode = "morning"
	elif e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		sail_home()

## Launch the voyage home: the stayers keep the camp; the voyage scene takes the knarr out.
func sail_home() -> bool:
	if plan == null or not plan.can_sail():
		return false
	var legs_data: Dictionary = JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())
	var v := plan.launch(legs_data)
	Game.voyage = v
	Game.camp = camp
	Game.loaded_stage = "homeward"
	plan = null
	mode = "sailed"
	if not autosave_off:
		Game.save_game("voyage")
	if is_inside_tree() and not get_tree().root.has_meta("no_scene_change"):
		get_tree().change_scene_to_file("res://scenes/voyage.tscn")
	return true

func _draw_return() -> void:
	var ink := Color("ede3cc")
	var r := Rect2(300, 200, 1320, 660)
	draw_rect(r, Color("2a2119"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	draw_string(_font, r.position + Vector2(40, 64), "THE VOYAGE HOME  ·  loading the knarr at the Strait", HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	draw_string(_font, r.position + Vector2(40, 102), "%s. The crossing is planned at %d days; autumn brings fog and gales. Whoever stays winters the camp." % [camp.date_text(), plan.crossing_days()],
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 20, Color(ink, 0.8))
	for i in ReturnPlan.ROWS.size():
		var row: String = ReturnPlan.ROWS[i]
		var y := r.position.y + 170 + i * 58
		if i == rfocus:
			draw_rect(Rect2(r.position.x + 24, y - 38, r.size.x - 48, 52), Color("c9a55a", 0.22))
		draw_string(_font, Vector2(r.position.x + 50, y), ReturnPlan.LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
		draw_string(_font, Vector2(r.position.x + 480, y), "‹ %d ›" % int(plan.c[row]), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ink)
		draw_string(_font, Vector2(r.position.x + 620, y), plan.readout(row), HORIZONTAL_ALIGNMENT_LEFT, 660, 20, Color(ink, 0.8))
	var names: Array = plan.sailing_crew().map(func(m): return str(m.name).split(" ")[0] + ("" if m.role == "hand" else " (" + str(Crew.ROLE_NAMES[m.role]).to_lower() + ")"))
	draw_multiline_string(_font, r.position + Vector2(50, 470), "Sailing: " + ", ".join(names), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 100, 18, -1, Color(ink, 0.75))
	var over := plan.hold_load() > plan.capacity()
	draw_string(_font, r.position + Vector2(50, 560), "Hold %.1f of %d units" % [plan.hold_load(), int(plan.capacity())], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e0735e") if over else ink)
	var w := plan.warnings()
	draw_string(_font, r.position + Vector2(400, 560), w[0] if not w.is_empty() else "Ready to sail.", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 450, 20, Color("e0a35e") if not w.is_empty() else Color("9ec27a"))
	var kb := Controls.keyboard
	draw_string(_font, r.position + Vector2(50, 626), ("Q/E choose · Z/C change · F the plan's load · Enter sail · Esc not yet" if kb else "LB/RB choose · D-pad change · Y the plan's load · A sail · B not yet"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))

func _market_input(e: InputEvent) -> void:
	var rows := 3 if not camp.byre_done() else 2
	if e.is_action_pressed("tool_next") or (e is InputEventKey and e.pressed and e.physical_keycode == KEY_S):
		mfocus = (mfocus + 1) % rows
	elif e.is_action_pressed("tool_prev") or (e is InputEventKey and e.pressed and e.physical_keycode == KEY_W):
		mfocus = (mfocus + rows - 1) % rows
	elif e.is_action_pressed("ui_right_pad") or e.is_action_pressed("ui_left_pad"):
		var d := 1 if e.is_action_pressed("ui_right_pad") else -1
		match mfocus:
			0: offer.cloth = clampi(offer.cloth + d, 0, camp.cloth_strips)
			1: offer.milk = clampi(offer.milk + d * 5, 0, camp.milk_to_spare())
			2: offer.pen = not offer.pen
	elif e.is_action_pressed("commit") or e.is_action_pressed("drop"):
		get_viewport().set_input_as_handled()
		var send_away := e.is_action_pressed("drop")
		var res := camp.do_trade(0 if send_away else offer.cloth, 0 if send_away else offer.milk, offer.pen)
		var weapon := camp.weapon_request and not send_away and camp.market_today == true
		_card("Market at the shore", "\n".join(res.lines) + "\nGoodwill %d of %d · fear %d of %d · %d pelts in the store." % [
			int(camp.goodwill), int(camp.n("goodwill_cap", 10)), int(camp.fear), int(camp.n("fear_cap", 5)), camp.pelts], "" if weapon else "to_work")
		if weapon:
			_card("They ask for iron", "One of the visitors points at the iron blades in the trade chest and holds up a bundle of furs, then another.\nKarlsefni forbade the sale of weapons. A: refuse   Y: trade two blades", "weapon")

# ------------------------------------------------------------------ drawing
func _draw() -> void:
	if mode == "minigame":
		return
	_draw_world()
	_draw_board()
	if mode == "market":
		_draw_market()
	if mode == "return":
		_draw_return()
	if mode == "hop":
		_draw_hop()
	if mode == "card":
		_draw_card()

func _draw_market() -> void:
	var ink := Color("ede3cc")
	# neutral placeholder visitors and their boats at the shore (art waits on the cultural review, F59)
	for i in 3:
		draw_colored_polygon(PackedVector2Array([Vector2(1700 + i * 60, 700 + i * 40), Vector2(1800 + i * 60, 700 + i * 40), Vector2(1780 + i * 60, 716 + i * 40), Vector2(1720 + i * 60, 716 + i * 40)]), Color("6b5a44"))
	for i in camp.market_pelts:
		draw_rect(Rect2(1560 + (i % 4) * 34, 760 + (i / 4) * 60, 18, 50), Color("8a8a8a"))
	var r := Rect2(360, 230, 1160, 560)
	draw_rect(r, Color("2a2119"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 10)), Color("c9a55a"))
	draw_string(_font, r.position + Vector2(40, 70), "Visitors at the shore", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, ink)
	draw_multiline_string(_font, r.position + Vector2(40, 116), "Skin boats came in on the morning tide. They have brought %d pelts and look at the cattle and the red cloth.\nThe price today is %.1f trade value a pelt (goodwill lowers it). A strip of cloth is worth 1; ten person-days of milk are worth 1." % [camp.market_pelts, camp.pelt_price()],
		HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 80, 22, -1, Color(ink, 0.85))
	var rows := [["Red cloth strips", "‹ %d ›  of %d" % [offer.cloth, camp.cloth_strips]], ["Milk (person-days)", "‹ %d ›  of %d" % [offer.milk, camp.milk_to_spare()]]]
	if not camp.byre_done():
		rows.append(["Pen the bull (one of the crew stays with him)", "‹ %s ›" % ("yes" if offer.pen else "no")])
	for i in rows.size():
		var y := r.position.y + 270 + i * 64
		if i == mfocus:
			draw_rect(Rect2(r.position.x + 30, y - 40, r.size.x - 60, 56), Color("c9a55a", 0.25))
		draw_string(_font, Vector2(r.position.x + 50, y), rows[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		draw_string(_font, Vector2(r.position.x + 760, y), rows[i][1], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
	var got := camp.pelts_for(offer.cloth, offer.milk)
	draw_string(_font, Vector2(r.position.x + 50, r.position.y + 480), "This offer buys %d of their %d pelts." % [got, camp.market_pelts], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color("e8c35a"))
	var kb := Controls.keyboard
	draw_string(_font, Vector2(r.position.x + 50, r.position.y + 530), ("Q/E or W/S choose · Z/C change · Enter trade · Esc send them away" if kb else "LB/RB choose · D-pad change · A trade · B send them away"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.7))

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
	draw_rect(Rect2(24, 20, 800, 120), panel)
	draw_rect(Rect2(24, 140, 800, 60), panel)
	draw_rect(Rect2(24, 200, 800, 66), panel)
	draw_multiline_string(_font, Vector2(44, 224), "Crew: " + camp.crew.roles_line(), HORIZONTAL_ALIGNMENT_LEFT, 770, 17, -1, Color(ink, 0.75))
	var wx := ("snow" if camp.is_winter() else "rain") if camp.rain else "fair"
	draw_string(_font, Vector2(44, 62), "%s, year %d  ·  %s  ·  %s" % [camp.date_text(), camp.year, camp.season(), wx], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, ink)
	draw_string(_font, Vector2(44, 100), "%d people, %d sick · %d of %d under a roof · cattle %d, sheep %d" % [camp.people, camp.sick.size(), camp.sheltered_total(), camp.people, camp.cattle, camp.sheep],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.85))
	var food_col := ink if camp.is_winter() or camp.food_days() >= camp.winter_days_left() else Color("e8c35a")
	draw_string(_font, Vector2(44, 132), "Food %.0f days · hay %.0f days · winter %d days" % [camp.food_days(), minf(camp.hay_days(), 999.0), camp.winter_days_left()], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, food_col)
	draw_string(_font, Vector2(44, 168), "Building %s · timber %.1f · hides %d · pelts %d · goodwill %d · fear %d/%d%s" % [camp.building_target(), camp.timber, camp.hides, camp.pelts, int(camp.goodwill), int(camp.fear), int(camp.n("fear_cap", 5)), " · trade broken" if camp.trade_broken() else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.75))
	# job board
	var bx := 1340.0; var by := 20.0
	draw_rect(Rect2(bx, by, 556, 650), panel)
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
		elif job == "fish" and camp.nets > 0:
			label = "Fish: %s" % ("the net" if camp.fish_net else "hand lines")
		draw_string(_font, Vector2(bx + 24, y), label, HORIZONTAL_ALIGNMENT_LEFT, 370, 24 if open else 20, Color(ink, 1.0 if open else 0.4))
		draw_string(_font, Vector2(bx + 400, y), "‹ %d ›" % int(camp.assign[job]), HORIZONTAL_ALIGNMENT_LEFT, -1, 26, ink)
		if camp.player_job == job:
			draw_string(_font, Vector2(bx + 480, y), "you", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("c9a55a"))
	var ky := by + 92 + Camp.JOBS.size() * 56
	if focus == Camp.JOBS.size() and mode == "morning":
		draw_rect(Rect2(bx + 10, ky - 34, 536, 50), Color("c9a55a", 0.25))
	var gate := camp.return_gate()
	var kl := "The knarr: " + ("ready to sail home (Y)" if gate.is_empty() else "not ready (Y: why)")
	if not camp.hop.is_empty():
		kl = "The knarr: at Hóp, back in %d days" % int(camp.hop.days_left)
	elif camp.hop_gate().is_empty():
		kl += " · B: Hóp"
	draw_string(_font, Vector2(bx + 24, ky), kl, HORIZONTAL_ALIGNMENT_LEFT, 520, 22, Color("9ec27a") if gate.is_empty() else Color(ink, 0.7))
	draw_string(_font, Vector2(bx + 20, by + 608), "Y: work this job yourself", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.65))
	draw_string(_font, Vector2(bx + 20, by + 634), "B: fish with line or net · hunt near or far", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(ink, 0.65))
	if mode == "morning":
		var you := "A: start the day" + (" (you play %s)" % camp.playable(camp.player_job) if camp.player_job != "" and int(camp.assign[camp.player_job]) > 0 else "")
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
	draw_string(_font, r.position + Vector2(40, r.size.y - 30), {"end": "A: back to the title", "weapon": "A: refuse   ·   Y: trade two blades"}.get(c.get("kind", ""), "A: continue"), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
