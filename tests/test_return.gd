extends RefCounted
## The voyage home (F24), the appraisal and sale (F25), recruitment and the second hull (F26).

static func legs_data() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())

## A camp in its second June, everything in place for the voyage home.
static func ready_camp(seed: int, outfit := "merchant") -> Camp:
	var c: Camp = load("res://tests/test_outfits.gd").camp_for(outfit, seed)
	c.year = 2; c.day_of_year = 160; c.second_spring = true
	c.booths = 3; c.longhouse = 540.0; c.byre = 200.0; c.shed = 80.0
	c.timber = 20.0; c.timber_felled = 20.0; c.timber_winter = 9.0
	c.food = 3.0; c.pelts = 34; c.goodwill = 4.0
	return c

## Sail a voyage with the careful captain until it ends.
static func sail(v: Voyage) -> void:
	var TV = load("res://tests/test_voyage.gd")
	var guard := 0
	while v.state == "sailing" and guard < 200:
		guard += 1
		v.start_day()
		TV._captain(v, "careful")
		var today := v.day
		while v.state == "sailing" and v.day == today:
			if v.watch == Voyage.NIGHT_WATCH: TV._night(v, "careful")
			v.sail_watch()

static func run(t) -> void:
	# the return gate
	var fresh: Camp = load("res://tests/test_outfits.gd").camp_for("merchant", 300)
	var why := fresh.return_gate()
	t.check("return gate: closed in the first summer, with reasons", why.size() >= 3, str(why))
	var rc := ready_camp(301)
	t.check("return gate: open in the second June with a shed, a sound hull, timber and a crew", rc.return_gate().is_empty(), str(rc.return_gate()))
	rc.hull = 2
	t.check("return gate: a sprung hull keeps her ashore", not rc.return_gate().is_empty())
	var tim := rc.timber
	for i in 7: rc.work_day()
	t.check("return gate: the shipwright mends a level a week, using a little timber", rc.hull == 1 and rc.timber < tim + 1.0, "hull %d" % rc.hull)
	var bq := ready_camp(302)
	bq.shed = 0.0
	bq.assign = {"build": 8, "fish": 0, "hunt": 0, "forage": 0, "dry": 0, "timber": 0, "hay": 0, "tend": 0}
	for i in 12: bq.work_day()
	t.check("build queue: the boat shed follows the byre (80 builder-days)", bq.shed_done(), "%.0f" % bq.shed)
	var wf := ready_camp(303)
	wf.timber_felled = 0.0; wf.timber_winter = 0.0
	wf.day_of_year = 320; wf.year = 1
	wf.assign = {"build": 0, "fish": 0, "hunt": 0, "forage": 0, "dry": 0, "timber": 4, "hay": 0, "tend": 0}
	for i in 5: wf.work_day()
	t.check("timber: what is felled in winter is counted for the grade", wf.winter_share() > 0.99, "%.2f" % wf.winter_share())
	# loading the knarr
	var pc := ready_camp(304)
	var plan := ReturnPlan.new(); plan.setup(Knobs._v, pc)
	t.check("return load: the plan's load (10 sail, stores for 13 days, timber to fill) fits and can sail", plan.can_sail() and plan.c.sailors == 10 and plan.hold_load() <= 24.0 and plan.c.timber >= 4,
		"%.1f units, %d timber, %d bales" % [plan.hold_load(), plan.c.timber, plan.c.pelts])
	var sc: Array = plan.sailing_crew()
	t.check("return load: the skipper and a pilot sail; the healer and smith stay with the camp",
		sc.any(func(m): return m.role == "skipper") and sc.any(func(m): return m.role == "pilot") and not sc.any(func(m): return m.role in ["healer", "smith"]))
	plan.change("timber", 20)
	t.check("return load: too much timber overloads her", not plan.can_sail())
	plan.reset()
	plan.c.sailors = 8
	t.check("return load: fewer than ten cannot work her home", not plan.can_sail())
	plan.reset()
	var before := {"people": pc.people, "timber": pc.timber, "pelts": pc.pelts, "food": pc.food}
	var v := plan.launch(legs_data(), 77)
	t.check("return: sailing takes the crew and cargo out of the camp", v.people == 10 and pc.people == before.people - 10 and is_equal_approx(pc.timber, before.timber - v.timber) and pc.pelts == before.pelts - v.pelts \
		and v.crew.count() == 10 and pc.crew.count() == pc.people, "%d aboard, %d stay" % [v.people, pc.people])
	t.check("return: the legs run home, from the Strait to Eriksfjord", v.legs[0].id == "strait" and v.legs[-1].id == "eriksfjord" and v.homeward)
	var all_c := ready_camp(305)
	var p2 := ReturnPlan.new(); p2.setup(Knobs._v, all_c)
	p2.c.sailors = all_c.people
	p2.c.timber = 4; p2.c.pelts = 0
	t.check("return: everyone sailing warns that the camp is abandoned", p2.warnings().any(func(w): return "abandoned" in w))
	if p2.can_sail():
		p2.launch(legs_data(), 78)
	t.check("return: and leaves the camp empty", all_c.state == "abandoned" or not p2.can_sail())
	# the autumn bias
	var out_v: Voyage = load("res://tests/test_voyage.gd").make(5)
	var foul_out := 0; var foul_home := 0
	for card in out_v.deck: if card in ["fog", "low_cloud", "following_gale", "beam_sea", "storm"]: foul_out += 1
	var hv := ReturnPlan.new(); hv.setup(Knobs._v, ready_camp(306))
	var home_v := hv.launch(legs_data(), 79)
	home_v.leg_i = home_v.legs.find(home_v.legs.filter(func(l): return l.id == "eriksfjord")[0])
	home_v._new_deck()
	for card in home_v.deck: if card in ["fog", "low_cloud", "following_gale", "beam_sea", "storm"]: foul_home += 1
	t.check("return: autumn deals more foul weather than the outbound summer (same leg)", foul_home > foul_out, "%d vs %d foul cards" % [foul_home, foul_out])
	var jv := ReturnPlan.new(); jv.setup(Knobs._v, ready_camp(307))
	var jet := jv.launch(legs_data(), 80)
	var tb := jet.timber
	var thrown := false
	for i in 20:
		for e in jet.apply_bail(false):
			if e.type == "jettison": thrown = true
	t.check("return: a failed bail can send timber over the side", thrown and jet.timber < tb, "%d of %d left" % [jet.timber, tb])
	# the crossing home
	var arrived := 0; var timber_home := 0
	for s in 40:
		var rp := ReturnPlan.new(); rp.setup(Knobs._v, ready_camp(400 + s))
		var vv := rp.launch(legs_data(), 500 + s)
		sail(vv)
		if vv.state == "arrived":
			arrived += 1
			timber_home += vv.timber
	print("INFO  return crossing: arrived %d of 40, %.1f timber units home" % [arrived, float(timber_home) / maxi(arrived, 1)])
	t.check("return: a careful captain brings her home in autumn (32+ of 40)", arrived >= 32, "%d of 40" % arrived)
	# appraisal and sale
	var h := Home.new()
	h.k = Knobs._v
	t.check("appraisal: mostly winter-felled timber is prime, a little is sound, none is rough",
		h.timber_grade(0.6, false) == "prime" and h.timber_grade(0.3, false) == "sound" and h.timber_grade(0.05, false) == "rough")
	t.check("appraisal: the shipwright's kin lifts the grade a step", h.timber_grade(0.05, true) == "sound" and h.timber_grade(0.3, true) == "prime")
	var hc := ready_camp(310)
	var hp := ReturnPlan.new(); hp.setup(Knobs._v, hc)
	var hvv := hp.launch(legs_data(), 81)
	var home := Home.new()
	home.setup(Knobs._v, hvv, hc, Game.outfit_table().merchant)
	var expect: float = hvv.timber * 3.0 * 1.0 + hvv.pelts * 0.25 + 12.0
	t.check("sale: timber x price x grade, pelts, and the merchant's silver", is_equal_approx(home.silver(), expect) and home.grade == "sound", "%.1f marks (%s)" % [home.silver(), home.grade])
	t.check("story: the living, the buildings and the peace bring volunteers", home.story > 20.0 and home.volunteers >= 10, "%.0f points, %d volunteers" % [home.story, home.volunteers])
	home.set_hull(true)
	var could := home.buy_hull
	home.set_hires(100)
	t.check("recruitment: silver buys a second hull and hires up to the room aboard", (could == (expect >= 40.0)) and home.left() >= 0.0 and home.relief_party() <= home.room(), "%d hired, %.1f left, %d of %d places" % [home.hires, home.left(), home.relief_party(), home.room()])
	var one := Home.new(); one.from_dict(Knobs._v, home.to_dict()); one.buy_hull = false; one.hires = 0
	one.set_hires(100)
	t.check("recruitment: one hull carries thirty; silver cannot buy more places than that", one.relief_party() <= 30, "%d" % one.relief_party())
	var poor := Home.new(); poor.setup(Knobs._v, hvv, hc, Game.outfit_table().farm_household)
	poor.silver_start = 0.0; poor.timber_silver = 10.0; poor.pelt_silver = 0.0
	poor.set_hull(true)
	t.check("recruitment: no second hull without the silver", not poor.buy_hull)
	t.check("recruitment: the relief is those who came home, the volunteers and the hired", home.relief_party() == home.came_home + home.volunteers_aboard() + home.hires)
	var hd := Home.new(); hd.from_dict(Knobs._v, JSON.parse_string(JSON.stringify(home.to_dict())))
	t.check("recruitment: the winter at home survives a save", hd.hires == home.hires and hd.buy_hull == home.buy_hull and is_equal_approx(hd.silver(), home.silver()))
	# saves on the way home
	var sv := ReturnPlan.new(); sv.setup(Knobs._v, ready_camp(311))
	var sv_v := sv.launch(legs_data(), 82)
	for i in 3:
		sv_v.start_day()
		for w in 6: sv_v.sail_watch()
	var back := Voyage.new()
	back.from_dict(Knobs._v, legs_data(), JSON.parse_string(JSON.stringify(sv_v.to_dict())))
	t.check("return: a saved voyage home keeps its course, cargo and crew", back.homeward and back.legs[0].id == "strait" and back.timber == sv_v.timber and back.crew.count() == sv_v.crew.count() and is_equal_approx(back.leg_left, sv_v.leg_left))
	# the whole second summer with a planning player, from the camp to the farms at home
	var TC = load("res://tests/test_camp.gd")
	var opened := 0; var homecomings := 0; var silver := 0.0; var vols := 0
	for s in 12:
		var c: Camp = load("res://tests/test_outfits.gd").camp_for("merchant", 600 + s)
		c.food = 0.6
		var g := 0
		while c.state == "camp" and g < 700 and not (c.second_spring and c.return_gate().is_empty()):
			g += 1
			TC.plan(c, "planner")
			if c.second_spring and c.shed_done() == false:
				c.assign.build = maxi(int(c.assign.build), 6); c.default_assignments()
			c.work_day()
		if not c.return_gate().is_empty():
			continue
		opened += 1
		var p3 := ReturnPlan.new(); p3.setup(Knobs._v, c)
		var v3 := p3.launch(legs_data(), 700 + s)
		sail(v3)
		if v3.state == "arrived":
			homecomings += 1
			var h3 := Home.new(); h3.setup(Knobs._v, v3, c, Game.outfit_table().merchant)
			silver += h3.silver(); vols += h3.volunteers
	print("INFO  second summer: gate opened %d of 12, home %d, %.1f marks, %.1f volunteers on average" % [opened, homecomings, silver / maxi(homecomings, 1), float(vols) / maxi(homecomings, 1)])
	t.check("run: a planning camp opens the return gate in its second summer (11+ of 12)", opened >= 11, "%d of 12" % opened)
	t.check("run: most cargoes reach Eriksfjord and buy the relief (9+ of 12)", homecomings >= 9, "%d of 12" % homecomings)
	# scenes
	var root: Node = Engine.get_main_loop().root
	root.set_meta("no_scene_change", true)
	var cs: Node = load("res://scenes/camp.tscn").instantiate()
	cs.autosave_off = true
	Game.voyage = null; Game.loaded_stage = ""
	t.add_child(cs)
	cs.camp = ready_camp(320)
	cs.open_return()
	var ok_mode: bool = cs.mode == "return"
	var sailed: bool = cs.sail_home()
	t.check("camp scene: the knarr row opens the planner and sails her home", ok_mode and sailed and Game.voyage.homeward and Game.loaded_stage == "homeward")
	cs.queue_free()
	var vs: Node = load("res://scenes/voyage.tscn").instantiate()
	vs.autosave_off = true
	t.add_child(vs)
	t.check("voyage scene: picks up the voyage home", vs.v.homeward and vs.cards.size() > 0 and str(vs.cards[0].title).begins_with("Leaving the Strait"))
	vs.queue_free()
	var hs: Node = load("res://scenes/homecoming.tscn").instantiate()
	hs.autosave_off = true
	Game.camp = ready_camp(321)
	Game.voyage.timber = 12
	t.add_child(hs)
	for i in 3: hs.advance()
	t.check("homecoming scene: arrival, appraisal, recruitment, then the winter at home", hs.page == 3 and not Game.home.is_empty() and float(Game.home.timber_silver) > 0.0)
	hs.queue_free()
	root.remove_meta("no_scene_change")
	Game.voyage = null; Game.camp = null; Game.home = {}
