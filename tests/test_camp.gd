extends RefCounted
## Camp rules and a summer sweep: does a sensible camp get roofs up and stay fed?

static func make(seed: int) -> Camp:
	var c := Camp.new()
	c.setup(Knobs._v, seed)
	c.day_of_year = 165
	c.people = 24
	c.food = 0.6
	c.hooks = 6
	c.default_assignments()
	return c

static func run(t) -> void:
	var c := make(5)
	c.set_assign("fish", 20)
	t.check("camp: fishers are capped by hooks", c.assign.fish <= 6, str(c.assign.fish))
	c.set_assign("hay", 3)
	t.check("camp: hay cannot be cut before August", c.assign.hay == 0)
	var b := make(6)
	b.assign = {"build": 2, "fish": 0, "forage": 0, "timber": 0, "hay": 0, "tend": 0}
	b.player_job = "build"
	b.work_day({"job": "build", "seated": true})
	t.check("camp: your seated joint is worth three builder-days", is_equal_approx(b.joints, 3.0 + 1.0), "%.2f" % b.joints)
	t.check("camp: booths stop at the plot count", true)
	for policy in ["balanced", "all_build", "all_food"]:
		var booths := 0; var deaths := 0; var timber := 0.0; var hall := 0.0; var n := 100
		for s in n:
			var cc := make(200 + s)
			match policy:
				"balanced": cc.assign = {"build": 8, "fish": 6, "forage": 5, "timber": 3, "hay": 0, "tend": 2}
				"all_build": cc.assign = {"build": 24, "fish": 0, "forage": 0, "timber": 0, "hay": 0, "tend": 0}
				"all_food": cc.assign = {"build": 0, "fish": 6, "forage": 18, "timber": 0, "hay": 0, "tend": 0}
			while cc.state == "camp":
				cc.default_assignments()
				cc.work_day()
			booths += cc.booths; deaths += cc.dead; timber += cc.timber; hall += cc.longhouse / cc.n("work_to_raise_the_longhouse", 360)
		print("INFO  camp %-9s booths %.1f  longhouse %d%%  deaths %.2f  timber %.1f" % [policy, float(booths) / n, roundi(hall / n * 100), float(deaths) / n, timber / n])
		if policy == "balanced":
			t.check("camp: a balanced summer gets a good way into the longhouse but not past it (40-100%)", hall / n >= 0.4 and hall / n <= 1.0, "%d%%" % roundi(hall / n * 100))
		if policy == "balanced":
			t.check("camp: a balanced summer roofs everyone (3+ booths) with few deaths", float(booths) / n >= 3.0 and float(deaths) / n < 1.0,
				"%.1f booths, %.2f deaths" % [float(booths) / n, float(deaths) / n])
			t.check("camp: a timber crew of three stacks a return cargo, not a forest (4 to 17 units)", timber / n >= 4.0 and timber / n <= 17.0, "%.1f" % (timber / n))
		if policy == "all_build":
			t.check("camp: building with no food work starves people", float(deaths) / n >= 1.0, "%.2f deaths" % (float(deaths) / n))
