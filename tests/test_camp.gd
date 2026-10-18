extends RefCounted
## Camp rules and whole-year sweeps: does a planning camp get through the first winter, and does a careless one not?

static func make(seed: int) -> Camp:
	var c := Camp.new()
	c.setup(Knobs._v, seed)
	c.day_of_year = 165
	c.people = 24
	c.food = 0.6
	c.hooks = 6
	c.default_assignments()
	return c

## Crew plans by season, the way a player would set them.
static func plan(c: Camp, policy: String) -> void:
	var s := c.season()
	var a := {}
	match policy:
		"planner":
			if s == "winter":
				a = {"build": 6, "fish": 6, "forage": 0, "dry": 0, "timber": 6, "hay": 0, "tend": 3}
				c.ration = "full" if c.food_days() > c.winter_days_left() * 0.8 else "half"
			elif c.job_open("hay"):
				a = {"build": 6, "fish": 6, "forage": 2, "dry": 3, "timber": 1, "hay": 4, "tend": 1}
				c.ration = "full"
			else:
				a = {"build": 8, "fish": 6, "forage": 3, "dry": 3, "timber": 2, "hay": 0, "tend": 1}
				c.ration = "full"
		"summer_only":     # what the slice taught: build, fish, forage; nothing put by
			a = {"build": 8, "fish": 6, "forage": 5, "dry": 0, "timber": 3, "hay": 0, "tend": 1}
			c.ration = "full"
		"no_hay":          # dries fish but forgets the herd
			if s == "winter":
				a = {"build": 6, "fish": 6, "forage": 0, "dry": 0, "timber": 6, "hay": 0, "tend": 3}
			else:
				a = {"build": 8, "fish": 6, "forage": 3, "dry": 3, "timber": 2, "hay": 0, "tend": 1}
			c.ration = "full"
	c.assign = a
	c.default_assignments()

static func run(t) -> void:
	var c := make(5)
	c.set_assign("fish", 20)
	t.check("camp: fishers are capped by hooks", c.assign.fish <= 6, str(c.assign.fish))
	c.set_assign("hay", 3)
	t.check("camp: hay cannot be cut before August", c.assign.hay == 0)
	var b := make(6)
	b.assign = {"build": 2, "fish": 0, "forage": 0, "dry": 0, "timber": 0, "hay": 0, "tend": 0}
	b.work_day({"job": "build", "seated": true})
	t.check("camp: your seated joint is worth three builder-days", is_equal_approx(b.joints, 3.0 + 1.0), "%.2f" % b.joints)
	var w := make(7)
	w.day_of_year = 310
	t.check("camp: winter closes foraging and the rack", w.is_winter() and not w.job_open("forage") and not w.job_open("dry"))
	w.day_of_year = 365
	w.work_day()
	t.check("camp: the calendar rolls into a new year", w.year == 2 and w.day_of_year == 1, "%d/%d" % [w.year, w.day_of_year])
	# rack: surplus fresh fish becomes stores
	var r := make(8)
	r.assign = {"build": 0, "fish": 0, "forage": 0, "dry": 2, "timber": 0, "hay": 0, "tend": 0}
	r.rain = false
	r.fresh = [[60.0, 0]]
	var before := r.food
	r.work_day()
	var dried_units: float = (r.food - before) * r.n("food_unit_feeds", 168)
	t.check("camp: the rack dries the surplus after the day's meals (2 dryers: 30 of 36 left, 90% kept)", is_equal_approx(snappedf(dried_units + 24.0 * 0.0, 0.1), 27.0), "%.1f person-days" % dried_units)
	# save round trip
	var sv := make(9)
	for i in 30: sv.work_day()
	var d: Dictionary = JSON.parse_string(JSON.stringify(sv.to_dict()))
	var back := Camp.new()
	back.from_dict(Knobs._v, d)
	var a1 := sv.work_day(); var a2 := back.work_day()
	t.check("camp: a saved camp continues exactly as the original", sv.food == back.food and sv.people == back.people and sv.day_of_year == back.day_of_year and sv.hay == back.hay,
		"%.4f vs %.4f" % [sv.food, back.food])
	# hunting: near and far grounds
	var near_meat := 0.0; var far_meat := 0.0; var far_fear := 0.0
	for sd in 20:
		var hn := make(400 + sd); var hf := make(400 + sd)
		hf.hunt_far = true
		for c2 in [hn, hf]:
			c2.assign = {"build": 0, "fish": 0, "hunt": 4, "forage": 0, "dry": 0, "timber": 0, "hay": 0, "tend": 0}
			for i in 20:
				c2.work_day()
		near_meat += hn.history.kills; far_meat += hf.history.kills; far_fear += hf.fear
	t.check("camp hunt: four hunters bring in caribou (about 5-6 kills in 20 days)", near_meat / 20.0 >= 3.0 and near_meat / 20.0 <= 9.0, "%.1f kills" % (near_meat / 20.0))
	t.check("camp hunt: the far grounds give more kills and raise fear", far_meat > near_meat and far_fear / 20.0 >= 1.5, "%.1f vs %.1f kills, fear %.1f" % [far_meat / 20.0, near_meat / 20.0, far_fear / 20.0])
	var fg := make(500)
	fg.assign = {"build": 0, "fish": 0, "hunt": 0, "forage": 2, "dry": 0, "timber": 0, "hay": 0, "tend": 0}
	fg.work_day({"job": "forage", "person_days": 10.0, "patch_health": 0.4})
	t.check("camp forage: stripping a patch thins foraging for the season", fg.patch_health < 0.8, "%.2f" % fg.patch_health)
	fg.day_of_year = 109
	fg.work_day()
	t.check("camp forage: the patches recover at the thaw", fg.patch_health == 1.0)
	_market(t)
	_work_games(t)
	# whole-year sweeps
	var res := {}
	for policy in ["planner", "summer_only", "no_hay"]:
		var deaths := 0; var animals := 0; var ended := 0; var hall := 0; var n := 60
		for s in n:
			var cc := make(300 + s)
			var guard := 0
			while cc.state == "camp" and not cc.second_spring and guard < 500:
				guard += 1
				plan(cc, policy)
				cc.work_day()
			deaths += cc.dead; animals += int(cc.history.animals_lost)
			if cc.second_spring: ended += 1
			if cc.hall_done(): hall += 1
		res[policy] = {"deaths": float(deaths) / n, "animals": float(animals) / n, "ended": float(ended) / n}
		print("INFO  camp year %-11s reached spring %3d%%  deaths %.1f  animals lost %.1f  longhouse %d%%" % [policy, roundi(100.0 * ended / n), float(deaths) / n, float(animals) / n, roundi(100.0 * hall / n)])
	t.check("camp year: a planning camp reaches the second spring with few deaths (< 3)", res.planner.ended >= 0.95 and res.planner.deaths < 3.0, "%.1f deaths" % res.planner.deaths)
	t.check("camp year: a summer-only camp loses people over the winter (3+)", res.summer_only.deaths >= 3.0, "%.1f deaths" % res.summer_only.deaths)
	t.check("camp year: forgetting hay costs the herd", res.no_hay.animals >= 3.0 and res.planner.animals < 1.0, "%.1f vs %.1f" % [res.no_hay.animals, res.planner.animals])

## A camp with visitors at the shore today.
static func market_camp(seed: int) -> Camp:
	var c := make(seed)
	c.day = 30
	c.cattle = 5
	c.cloth_strips = 20
	c.iron_blades = 5
	c.food = 2.0
	c.market_today = true
	c.market_pelts = 8
	return c

static func _market(t) -> void:
	# how often they come
	var seen := 0; var winter_seen := 0; var early := 0
	for s in 400:
		var c := make(700 + s)
		c.day = 30
		if c.roll_market(): seen += 1
		var w := make(700 + s); w.day = 200; w.day_of_year = 320
		if w.roll_market(): winter_seen += 1
		var e := make(700 + s); e.day = 3
		if e.roll_market(): early += 1
	t.check("market: visitors come now and then (about 6% of summer days)", seen >= 12 and seen <= 40, "%d of 400" % seen)
	t.check("market: no visitors in winter or in the first days", winter_seen == 0 and early == 0, "%d / %d" % [winter_seen, early])
	# a fair trade
	var m := market_camp(1)
	var r := m.do_trade(4, 20, true)
	t.check("market: 4 strips and 20 days of milk (value 6) buy 3 pelts at price 2", r.pelts == 3 and m.pelts == 3 and m.cloth_strips == 16, "%d pelts" % r.pelts)
	t.check("market: a trade earns goodwill", m.goodwill >= 1.0, "%.1f" % m.goodwill)
	# goodwill lowers the price and brings them more often
	var g := market_camp(2)
	g.goodwill = 6.0
	t.check("market: goodwill lowers the pelt price", g.pelt_price() < market_camp(2).pelt_price(), "%.2f" % g.pelt_price())
	# sending them away
	var sa := market_camp(3)
	sa.goodwill = 2.0
	sa.do_trade(0, 0, true)
	t.check("market: sending them away with nothing costs goodwill", sa.goodwill == 1.0)
	# the bull: penned or loose, with and without the byre
	var loose := 0; var penned := 0; var byre_loose := 0
	for s in 200:
		var a := market_camp(800 + s)
		a.do_trade(4, 0, false)
		loose += a.history.bull_loose
		var b := market_camp(800 + s)
		b.do_trade(4, 0, true)
		penned += b.history.bull_loose
		var c := market_camp(800 + s)
		c.byre = c.n("work_to_raise_the_byre", 160) + 1.0
		if c.byre_done():
			c.do_trade(4, 0, false)
			byre_loose += c.history.bull_loose
	t.check("market: an unpenned bull sometimes breaks loose (about 1 in 4)", loose >= 30 and loose <= 75, "%d of 200" % loose)
	t.check("market: a penned bull, or one in the byre, never does", penned == 0 and byre_loose == 0, "%d / %d" % [penned, byre_loose])
	var pd := market_camp(4)
	pd.do_trade(4, 0, true)
	var before_build: float = pd.assign.build
	pd.work_day()
	t.check("market: penning the bull keeps one of the crew from work that day", pd.penned_today == false and pd.assign.build == before_build, "build %d" % pd.assign.build)
	# weapons
	var ws := market_camp(5)
	ws.do_trade(4, 0, true)
	ws.weapon_request = true
	var wr := ws.answer_weapon_request(true)
	t.check("market: trading two blades brings 6 pelts and raises fear by 2", wr.pelts == 6 and ws.iron_blades == 3 and ws.fear == 2.0, "%d pelts, fear %.1f" % [wr.pelts, ws.fear])
	var rf := market_camp(6)
	rf.goodwill = 3.0
	rf.weapon_request = true
	rf.answer_weapon_request(false)
	t.check("market: refusing the blades costs a little goodwill and no fear", rf.goodwill == 2.5 and rf.fear == 0.0)
	# the fear cap
	var fc := market_camp(7)
	fc.fear = fc.n("fear_cap", 5)
	var any := false
	for i in 50:
		fc.day = 30 + i
		if fc.roll_market(): any = true
	t.check("market: at the fear cap no one comes to trade", not any and fc.trade_broken())
	var raids := 0
	for s in 50:
		var rc := market_camp(900 + s)
		rc.fear = rc.n("fear_cap", 5)
		for i in 28: rc.work_day()
		raids += rc.history.raids
	t.check("market: at the fear cap the camp is raided now and then", raids >= 15, "%d raids in 50 months" % raids)
	var calm := market_camp(10)
	calm.fear = 2.0
	for i in 14: calm.work_day()
	t.check("market: fear fades over quiet weeks", calm.fear == 1.0, "%.1f" % calm.fear)
	# save round trip keeps the market
	var sv := market_camp(11)
	sv.do_trade(4, 10, true)
	var back := Camp.new()
	back.from_dict(Knobs._v, JSON.parse_string(JSON.stringify(sv.to_dict())))
	t.check("market: goodwill, pelts, cloth and blades survive a save", back.goodwill == sv.goodwill and back.pelts == sv.pelts and back.cloth_strips == sv.cloth_strips and back.iron_blades == sv.iron_blades)

## The net and the smoke rack when you work them yourself.
static func _work_games(t) -> void:
	var c := make(1200)
	t.check("camp: fishing yourself plays the hand line, or the net when chosen", c.playable("fish") == "the hand line" and (func(): c.fish_net = true; return c.playable("fish") == "the net").call())
	c.nets = 0
	t.check("camp: no net, no net throw", c.playable("fish") == "the hand line")
	t.check("camp: drying yourself plays the smoke rack", c.playable("dry") == "the smoke rack")
	var stores := {}
	for kind in ["crew", "best", "poor", "spoiled"]:
		var r := make(1300)
		r.assign = {"build": 0, "fish": 0, "forage": 0, "dry": 2, "timber": 0, "hay": 0, "tend": 0}
		r.rain = false
		r.fresh = [[90.0, 0]]
		var before := r.food
		match kind:
			"crew": r.work_day()
			"best": r.work_day({"job": "dry", "quality": 1.0, "spoiled": false})
			"poor": r.work_day({"job": "dry", "quality": 0.4, "spoiled": false})
			"spoiled": r.work_day({"job": "dry", "quality": 0.1, "spoiled": true})
		stores[kind] = (r.food - before) * r.n("food_unit_feeds", 168)
	t.check("camp rack: your well-kept fire puts more into stores than a crew dryer", stores.best > stores.crew, "%.1f vs %.1f person-days" % [stores.best, stores.crew])
	t.check("camp rack: a poor fire keeps less, a spoiled rack loses your share", stores.poor < stores.best and stores.spoiled < stores.crew, "poor %.1f, spoiled %.1f" % [stores.poor, stores.spoiled])
	var sv := make(1400)
	sv.fish_net = true
	var back := Camp.new()
	back.from_dict(Knobs._v, JSON.parse_string(JSON.stringify(sv.to_dict())))
	t.check("camp: the line / net choice survives a save", back.fish_net and back.nets == sv.nets)
