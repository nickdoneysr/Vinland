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
	# whole-year sweeps
	var res := {}
	for policy in ["planner", "summer_only", "no_hay"]:
		var deaths := 0; var animals := 0; var ended := 0; var hall := 0; var n := 60
		for s in n:
			var cc := make(300 + s)
			var guard := 0
			while cc.state == "camp" and guard < 500:
				guard += 1
				plan(cc, policy)
				cc.work_day()
			deaths += cc.dead; animals += int(cc.history.animals_lost)
			if cc.state == "ended": ended += 1
			if cc.hall_done(): hall += 1
		res[policy] = {"deaths": float(deaths) / n, "animals": float(animals) / n, "ended": float(ended) / n}
		print("INFO  camp year %-11s reached spring %3d%%  deaths %.1f  animals lost %.1f  longhouse %d%%" % [policy, roundi(100.0 * ended / n), float(deaths) / n, float(animals) / n, roundi(100.0 * hall / n)])
	t.check("camp year: a planning camp reaches the second spring with few deaths (< 3)", res.planner.ended >= 0.95 and res.planner.deaths < 3.0, "%.1f deaths" % res.planner.deaths)
	t.check("camp year: a summer-only camp loses people over the winter (3+)", res.summer_only.deaths >= 3.0, "%.1f deaths" % res.summer_only.deaths)
	t.check("camp year: forgetting hay costs the herd", res.no_hay.animals >= 3.0 and res.planner.animals < 1.0, "%.1f vs %.1f" % [res.no_hay.animals, res.planner.animals])
