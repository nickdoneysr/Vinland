extends RefCounted
## Economy tuning pass (Backlog F55): whole three-summer runs played by three player models, logged per run.
## planner: plans the camp by season and sizes hay to the herd, careful captain, sails the day the gate opens.
## average: the same plan with uneven hands (jobs off by one or two), three haymakers whatever the herd,
##          little drying, average captain, sails home some weeks late, buys nothing extra for the relief.
## careless: summer-only camp (no hay, no rack), reckless captain, sails home late.

const CAPTAIN := {"planner": "careful", "planner_hop": "careful", "average": "average", "careless": "reckless"}

static func legs_data() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())

static func sail(v: Voyage, policy: String) -> void:
	var TV = load("res://tests/test_voyage.gd")
	var cap: String = CAPTAIN[policy]
	var guard := 0
	while v.state == "sailing" and guard < 200:
		guard += 1
		v.start_day()
		TV._captain(v, cap)
		var today := v.day
		while v.state == "sailing" and v.day == today:
			if v.watch == Voyage.NIGHT_WATCH: TV._night(v, cap)
			if cap != "reckless" and v.is_coastal() and not v.fished_today and v.food_days() < 20 and v.watch == 0:
				v.fish()
				continue
			v.sail_watch()

## One camp day as the model would play it.
static func camp_day(c: Camp, policy: String, rng: RandomNumberGenerator) -> void:
	match policy:
		"planner", "planner_hop":
			c.auto_plan()
			if c.second_spring and not c.shed_done():
				c.assign.build = maxi(int(c.assign.build), 6); c.default_assignments()
		"average":
			c.auto_plan()
			if c.day % 7 == 0 or not c.has_meta("noise"):
				var noise := {}
				for j in ["build", "fish", "forage", "dry", "timber", "tend"]:
					noise[j] = rng.randi_range(-2, 1)
				c.set_meta("noise", noise)
			var nz: Dictionary = c.get_meta("noise")
			for j in nz:
				c.assign[j] = maxi(0, int(c.assign[j]) + int(nz[j]))
			if c.job_open("hay"):
				c.assign.hay = 3
			c.assign.dry = maxi(0, int(c.assign.dry) - 2)
			c.ration = "full"
			c.default_assignments()
			if c.second_spring and not c.shed_done():
				c.assign.build = maxi(int(c.assign.build), 4); c.default_assignments()
		"careless":
			var people := c.people - c.sick.size()
			c.assign = {"build": people * 8 / 23, "fish": 6, "hunt": 0, "forage": people * 5 / 23, "dry": 0, "timber": people * 3 / 23, "hay": 0, "tend": 0}
			c.ration = "full"
			c.default_assignments()
			var spare := c.idle()
			if spare > 0:
				c.assign.build = int(c.assign.build) + spare
				c.default_assignments()
	if c.roll_market():
		c.do_trade(mini(c.cloth_strips, 4), mini(c.milk_to_spare(), 20), policy != "careless" and not c.byre_done())
		if c.weapon_request: c.answer_weapon_request(policy == "careless")
	c.work_day()

## Play the camp until the model sails home (or the camp ends). Returns false when no voyage home happens.
static func camp_until_sail(c: Camp, policy: String, rng: RandomNumberGenerator) -> bool:
	var delay := 0 if policy.begins_with("planner") else (rng.randi_range(10, 50) if policy == "average" else rng.randi_range(30, 90))
	var waited := 0
	var g := 0
	while c.state == "camp" and g < 1100:
		g += 1
		if policy == "planner_hop" and c.hop_gate(10).is_empty():
			c.start_hop(10)
		if c.second_spring and c.return_gate().is_empty():
			if waited >= delay or c.late_in_the_year():
				return true
			waited += 1
		camp_day(c, policy, rng)
	return false

static func whole_run(outfit: String, policy: String, seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed
	var row := {"outfit": outfit, "policy": policy, "seed": seed, "end": "", "score": 0, "title": "", "dead": 0, "timber": 0, "cargoes": 0,
		"winter1_food_days": -1.0, "animals_lost": 0, "home_day": 0, "silver": 0.0}
	var v: Voyage = load("res://tests/test_outfits.gd").voyage_for(outfit, seed)
	sail(v, policy)
	if v.state != "arrived":
		row.end = "lost outbound"; row.dead = v.dead; return row
	var c := Camp.new()
	c.from_voyage(v)
	var ok := camp_until_sail(c, policy, rng)
	row.animals_lost = int(c.history.animals_lost)
	if not ok:
		row.end = "camp " + c.state; row.dead = c.dead; row.title = c.state; return row
	var p := ReturnPlan.new(); p.setup(Knobs._v, c)
	var hv := p.launch(legs_data(), seed + 1)
	row.home_day = hv.day_of_year
	sail(hv, policy)
	if hv.state != "arrived":
		row.end = "lost homeward"; row.dead = c.dead + hv.dead; return row
	var h := Home.new()
	h.setup(Knobs._v, hv, c, Game.outfit_table()[outfit])
	row.silver = h.silver()
	h.set_hull(policy != "careless")
	h.set_hires(100 if policy.begins_with("planner") else (h.max_hires() / 2 if policy == "average" else 0))
	var rl := Relief.new(); rl.setup(Knobs._v, h)
	if policy.begins_with("planner"):
		while rl.cost() + 3.0 <= rl.silver() and rl.hold_load() + 2.0 <= rl.capacity() and rl.c.cattle < 3:
			rl.change("cattle", 1); rl.change("fodder", 1)
		while rl.cost() + 1.0 <= rl.silver() and rl.hold_load() + 1.0 <= rl.capacity() and rl.c.food < rl.free.food + 4:
			rl.change("food", 1)
	var rv := Voyage.new()
	rv.setup(Knobs._v, legs_data(), seed + 2)
	rl.apply_to(rv)
	var hd := h.to_dict(); hd.relief_spent = rl.cost()
	sail(rv, policy)
	if rv.state != "arrived":
		row.end = "relief lost"; row.dead = c.dead + hv.dead + rv.dead
		var sc0 := Score.compute(Knobs._v, {"timber": hv.timber, "cargo_value": h.cargo_value, "cargoes": 1, "relief": false, "camp_alive": 0, "home_alive": hv.people, "goodwill": 0, "dead": row.dead})
		row.score = sc0.total; row.title = sc0.title; row.cargoes = 1; row.timber = hv.timber
		return row
	c.reunite(rv)
	var ok2 := camp_until_sail(c, policy, rng)
	if not ok2:
		row.end = "no second cargo (%s)" % c.state; row.dead = c.dead + h.sea_dead
		var sc1 := Score.compute(Knobs._v, {"timber": h.timber_total, "cargo_value": h.cargo_value, "cargoes": 1, "relief": true, "camp_alive": c.people if c.state == "camp" else 0, "home_alive": 0, "goodwill": c.goodwill, "dead": row.dead})
		row.score = sc1.total; row.title = sc1.title; row.cargoes = 1; row.timber = h.timber_total
		return row
	var p2 := ReturnPlan.new(); p2.setup(Knobs._v, c)
	var hv2 := p2.launch(legs_data(), seed + 3)
	sail(hv2, policy)
	if hv2.state != "arrived":
		row.end = "lost with the second cargo"; row.dead = c.dead + h.sea_dead + hv2.dead
		var sc2 := Score.compute(Knobs._v, {"timber": h.timber_total, "cargo_value": h.cargo_value, "cargoes": 1, "relief": true, "camp_alive": c.people, "home_alive": 0, "goodwill": c.goodwill, "dead": row.dead})
		row.score = sc2.total; row.title = sc2.title; row.cargoes = 1; row.timber = h.timber_total
		return row
	var h2 := Home.new()
	h2.setup(Knobs._v, hv2, c, Game.outfit_table()[outfit], hd)
	var sc := h2.score()
	row.end = "home"; row.score = sc.total; row.title = sc.title; row.dead = h2.dead; row.timber = h2.timber_total; row.cargoes = 2
	row.animals_lost += int(c.history.animals_lost)
	return row

## Run the sweep, print a summary per policy and outfit, write every run to user://balance/fullrun.csv. Returns summaries.
static func sweep(n: int) -> Dictionary:
	var rows: Array = []
	var out := {}
	for policy in ["planner", "average", "careless"]:
		for outfit in Game.outfit_table().order:
			for s in n:
				rows.append(whole_run(outfit, policy, 50000 + s * 13))
	for policy in ["planner", "average", "careless"]:
		var pr: Array = rows.filter(func(r): return r.policy == policy)
		var full := pr.filter(func(r): return r.title == "The full saga").size()
		var titles := {}
		var score := 0; var dead := 0
		for r in pr:
			var key: String = r.title if r.title != "" else r.end
			titles[key] = titles.get(key, 0) + 1
			score += int(r.score); dead += int(r.dead)
		out[policy] = {"full": float(full) / pr.size(), "score": float(score) / pr.size(), "dead": float(dead) / pr.size(), "titles": titles}
		print("INFO  balance %-9s full saga %3d%%  score %5.0f  deaths %4.1f  %s" % [policy, roundi(100.0 * full / pr.size()), float(score) / pr.size(), float(dead) / pr.size(), str(titles)])
	DirAccess.make_dir_recursive_absolute("user://balance")
	var f := FileAccess.open("user://balance/fullrun.csv", FileAccess.WRITE)
	f.store_line("outfit,policy,seed,end,title,score,cargoes,timber,dead,animals_lost,home_day,silver")
	for r in rows:
		f.store_line("%s,%s,%d,%s,%s,%d,%d,%d,%d,%d,%d,%.1f" % [r.outfit, r.policy, r.seed, r.end, r.title, r.score, r.cargoes, r.timber, r.dead, r.animals_lost, r.home_day, r.silver])
	f.close()
	return out
