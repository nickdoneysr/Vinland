extends RefCounted
## F30: the full three-summer run, outfit to score, with no debug commands.

static func legs_data() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())

## Play camp days the way a planning player would until the return gate opens (or the camp fails).
static func plan_until_gate(c: Camp) -> void:
	var g := 0
	while c.state == "camp" and g < 900 and not (c.second_spring and c.return_gate().is_empty()):
		g += 1
		c.auto_plan()
		if c.second_spring and not c.shed_done():
			c.assign.build = maxi(int(c.assign.build), 6); c.default_assignments()
		if c.roll_market():
			c.do_trade(mini(c.cloth_strips, 4), mini(c.milk_to_spare(), 20), not c.byre_done())
			if c.weapon_request: c.answer_weapon_request(false)
		c.work_day()

## One whole run with expert-ish choices; returns the final homecoming (or {} if the run ended early) and what happened.
static func whole_run(outfit: String, seed: int) -> Dictionary:
	var TR = load("res://tests/test_return.gd")
	var v: Voyage = load("res://tests/test_outfits.gd").voyage_for(outfit, seed)
	TR.sail(v)
	if v.state != "arrived":
		return {"end": "lost at sea outbound"}
	var c := Camp.new()
	c.from_voyage(v)
	plan_until_gate(c)
	if not c.return_gate().is_empty():
		return {"end": "no return (%s)" % c.state}
	var p := ReturnPlan.new(); p.setup(Knobs._v, c)
	var hv := p.launch(legs_data(), seed + 1)
	TR.sail(hv)
	if hv.state != "arrived":
		return {"end": "lost at sea homeward"}
	var h := Home.new()
	h.setup(Knobs._v, hv, c, Game.outfit_table()[outfit])
	h.set_hull(true)
	h.set_hires(100)
	var rl := Relief.new(); rl.setup(Knobs._v, h)
	# buy some stock and stores with what is left
	while rl.cost() + rl.price("food") <= rl.silver() and rl.hold_load() + 1.0 <= rl.capacity() and rl.c.food < rl.free.food + 6:
		rl.change("food", 1)
	var rv := Voyage.new()
	rv.setup(Knobs._v, legs_data(), seed + 2)
	rl.apply_to(rv)
	var hd := h.to_dict(); hd.relief_spent = rl.cost()
	TR.sail(rv)
	if rv.state != "arrived":
		return {"end": "relief lost at sea"}
	var rep := c.reunite(rv)
	plan_until_gate(c)
	if not c.return_gate().is_empty():
		return {"end": "no second return (%s, year %d day %d)" % [c.state, c.year, c.day_of_year]}
	var p2 := ReturnPlan.new(); p2.setup(Knobs._v, c)
	var hv2 := p2.launch(legs_data(), seed + 3)
	TR.sail(hv2)
	if hv2.state != "arrived":
		return {"end": "lost at sea, second cargo"}
	var h2 := Home.new()
	h2.setup(Knobs._v, hv2, c, Game.outfit_table()[outfit], hd)
	return {"end": "home", "home": h2, "score": h2.score(), "rep": rep, "relief_people": rv.people}

static func run(t) -> void:
	# the camp alone
	var c: Camp = load("res://tests/test_return.gd").ready_camp(900)
	c.people = 14
	c.crew.sync_to(14, c.rng)
	c.auto_plan()
	var busy := 0
	for j in c.assign: busy += int(c.assign[j])
	t.check("auto plan: everyone fit has work", busy == c.people - c.sick.size(), "%d of %d" % [busy, c.people])
	var lines := c.catch_up(3, 160)
	t.check("catch-up: fourteen left at the camp live through a winter on their own", c.state == "camp" and c.people >= 10 and c.year == 3, "%d alive, %s" % [c.people, c.state])
	t.check("catch-up: tells the winter (snow, thaw)", lines.any(func(l): return "First snow" in l) and lines.any(func(l): return "thaw" in l))
	var herd: Camp = load("res://tests/test_return.gd").ready_camp(910, "farm_household")
	herd.people = 12; herd.crew.sync_to(12, herd.rng); herd.hay = 0.0
	var animals := herd.cattle + herd.sheep
	herd.catch_up(3, 160)
	t.check("catch-up: twelve left alone put up enough hay to winter the farm household's herd", herd.cattle + herd.sheep == animals and herd.history.animals_lost == 0,
		"%d of %d animals" % [herd.cattle + herd.sheep, animals])
	var st: Camp = load("res://tests/test_outfits.gd").camp_for("merchant", 901)
	st.year = 3; st.day_of_year = 304
	st.work_day()
	t.check("ending: a camp whose ship never sailed home is stranded at the third winter", st.state == "stranded")
	# the relief
	var TR = load("res://tests/test_return.gd")
	var rc: Camp = TR.ready_camp(902)
	var p := ReturnPlan.new(); p.setup(Knobs._v, rc)
	var hv := p.launch(legs_data(), 903)
	TR.sail(hv)
	var h := Home.new(); h.setup(Knobs._v, hv, rc, Game.outfit_table().merchant)
	h.set_hull(true); h.set_hires(6)
	var rl := Relief.new(); rl.setup(Knobs._v, h)
	t.check("relief: two hulls carry 48 units; the household feeds the crossing for free", rl.capacity() == 48.0 and rl.cost() == 0.0 and rl.warnings().is_empty(), "%s" % str(rl.warnings()))
	rl.change("cattle", 3); rl.change("sheep", 4); rl.change("fodder", 2)
	t.check("relief: stock and fodder cost silver", is_equal_approx(rl.cost(), 3 * 3.0 + 4 * 0.5 + 2 * 0.5), "%.1f marks" % rl.cost())
	rl.change("cattle", 30)
	t.check("relief: more than the silver will buy cannot sail", not rl.can_sail())
	rl.reset()
	var rv := Voyage.new(); rv.setup(Knobs._v, legs_data(), 904)
	rl.apply_to(rv)
	var names := {}
	for m in rv.crew.members: names[m.name] = true
	t.check("relief: the voyage carries the party, named, with the second hull's room", rv.relief and rv.hulls == 2 and rv.people == h.relief_party() and rv.crew.count() == rv.people \
		and names.size() == rv.crew.members.size() and rv.hold_capacity() == 48.0 and rv.year == 3, "%d people, %d names" % [rv.people, names.size()])
	TR.sail(rv)
	var before := rc.people
	var rep := rc.reunite(rv)
	t.check("reunion: the camp lives out its months, then the relief joins it", rc.relief_came and rc.knarr_here and rc.people == int(rep.alive_after) + rv.people and rc.crew.count() == rc.people,
		"%d waited, %d met the relief, %d came" % [before, rep.alive_after, rv.people])
	t.check("reunion: the return gate opens again for the second cargo", rc.year == 3 and (rc.return_gate().is_empty() or rc.timber < 4.0), str(rc.return_gate()))
	var ab: Camp = TR.ready_camp(905)
	ab.state = "abandoned"; ab.people = 0; ab.crew.members.clear()
	var rv2 := Voyage.new(); rv2.setup(Knobs._v, legs_data(), 906)
	rl.apply_to(rv2)
	rv2.day_of_year = 190
	ab.reunite(rv2)
	t.check("reunion: a relief resettles an empty camp", ab.state == "camp" and ab.people == rv2.people)
	# scores
	var full := Score.compute(Knobs._v, {"timber": 34, "cargoes": 2, "relief": true, "camp_alive": 40, "home_alive": 10, "goodwill": 5, "dead": 3})
	var rich := Score.compute(Knobs._v, {"timber": 34, "cargoes": 2, "relief": true, "camp_alive": 0, "home_alive": 50, "goodwill": 5, "dead": 3})
	var stranded := Score.compute(Knobs._v, {"timber": 0, "cargoes": 0, "relief": false, "camp_alive": 20, "home_alive": 0, "goodwill": 2, "dead": 4})
	t.check("score: two cargoes, a relief and a living camp is the full saga", full.full and full.title == "The full saga", str(full.total))
	t.check("score: everyone home and rich is allowed, and scored below a living camp", not rich.full and rich.title == "Home and rich" and rich.total < full.total and "never" not in str(rich.line),
		"%d vs %d" % [rich.total, full.total])
	t.check("score: a camp that never sent a ship scores lowest of the three", stranded.total < rich.total and stranded.title == "A camp without a ship", str(stranded.total))
	# the whole run, outfit to score
	for outfit in Game.outfit_table().order:
		var fulls := 0; var homes := 0; var total := 0; var ends := {}
		for s in 8:
			var r := whole_run(outfit, 20000 + s * 10)
			ends[r.end] = ends.get(r.end, 0) + 1
			if r.end == "home":
				homes += 1
				total += int(r.score.total)
				if r.score.full: fulls += 1
		print("INFO  full run %-16s home %d of 8, full saga %d, average score %d, ends %s" % [Game.outfit_table()[outfit].name, homes, fulls, total / maxi(homes, 1), str(ends)])
		t.check("full run: a %s run goes outfit to score with no debug commands (6+ of 8 full sagas)" % Game.outfit_table()[outfit].name, fulls >= 6, "%d of 8, ends %s" % [fulls, str(ends)])
	# scenes: the final homecoming, the relief screen, the relief voyage, the reunion
	var root: Node = Engine.get_main_loop().root
	root.set_meta("no_scene_change", true)
	Game.home = h.to_dict()
	var rs: Node = load("res://scenes/relief.tscn").instantiate()
	rs.autosave_off = true
	t.add_child(rs)
	var sailed: bool = rs.sail()
	t.check("relief scene: loads the relief and sails west", sailed and Game.voyage.relief and Game.loaded_stage == "relief")
	rs.queue_free()
	var vs: Node = load("res://scenes/voyage.tscn").instantiate()
	vs.autosave_off = true
	t.add_child(vs)
	t.check("voyage scene: picks up the relief", vs.v.relief and str(vs.cards[0].title).begins_with("The relief sails"))
	vs.queue_free()
	Game.camp = TR.ready_camp(907)
	Game.voyage.day_of_year = 185
	Game.loaded_stage = "reunion"
	var cs: Node = load("res://scenes/camp.tscn").instantiate()
	cs.autosave_off = true
	t.add_child(cs)
	t.check("camp scene: the reunion card tells what the camp did alone", str(cs.cards[0].title).begins_with("The camp again") and cs.camp.relief_came)
	cs.queue_free()
	var r2 := whole_run("merchant", 31000)
	if r2.end == "home":
		Game.home = (r2.home as Home).to_dict()
		Game.home.cargoes = 1
		var hs: Node = load("res://scenes/homecoming.tscn").instantiate()
		hs.autosave_off = true
		Game.loaded_stage = ""
		var home2 := Home.new(); home2.from_dict(Knobs._v, Game.home)
		t.check("homecoming: the second cargo ends the run in the saga", (r2.home as Home).is_final() and (r2.home as Home).cargoes == 2)
		hs.free()
	root.remove_meta("no_scene_change")
	Game.voyage = null; Game.camp = null; Game.home = {}
