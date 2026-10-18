extends RefCounted
## Outfits (F22) and named crew roles (F23).

static func lo_for(id: String) -> Loadout:
	var lo := Loadout.new()
	lo.setup(Knobs._v, Game.outfit_table())
	lo.set_outfit(id)
	return lo

static func voyage_for(id: String, seed: int) -> Voyage:
	var v: Voyage = load("res://tests/test_voyage.gd").make(seed)
	lo_for(id).apply_to(v)
	return v

static func camp_for(id: String, seed: int) -> Camp:
	var c := Camp.new()
	c.from_voyage(voyage_for(id, seed))
	c.day_of_year = 165
	c.default_assignments()
	return c

static func run(t) -> void:
	var table := Game.outfit_table()
	var order: Array = table.order
	t.check("outfits: four outfits", order.size() == 4)
	for id in order:
		var lo := lo_for(id)
		t.check("outfits: %s starts with a legal hold and stores for the crossing" % table[id].name, lo.can_sail() and lo.warnings().is_empty(), "%.1f units %s" % [lo.hold_load(), str(lo.warnings())])
	t.check("outfits: the farm household carries the most animals, the merchant the most trade", lo_for("farm_household").c.cattle == 3 and lo_for("merchant").c.cloth + lo_for("merchant").c.iron == 4)
	t.check("outfits: the shipwright's kin carries a spare sail in the hold", lo_for("shipwright_s_kin").gear_units() == 1.0)
	# crews
	var women_in_roles := 0
	for id in order:
		var v := voyage_for(id, 100)
		var cr: Crew = v.crew
		var keys_ok := true
		for r in Crew.KEY_ROLES:
			if not cr.has_role(r): keys_ok = false
		t.check("crew: %s has a named crew the size of the party, with every key role" % table[id].name, cr.count() == v.people and keys_ok, "%d of %d" % [cr.count(), v.people])
		var lead: String = table[id].lead[0][0]
		t.check("crew: %s is led by %s" % [table[id].name, lead], cr.members.any(func(m): return m.name == lead))
		for m in cr.members:
			if m.female and m.role != "hand": women_in_roles += 1
		var women := cr.members.filter(func(m): return m.female).size()
		t.check("crew: %s has women in the company (about two in five)" % table[id].name, women >= v.people * 0.3, "%d of %d" % [women, v.people])
	t.check("crew: women hold key roles, not just passage", women_in_roles >= 8, "%d role-holders" % women_in_roles)
	var cr2 := voyage_for("merchant", 101).crew
	var rng := RandomNumberGenerator.new(); rng.seed = 5
	var names := cr2.lose(3, rng)
	t.check("crew: losses are named and the roster shrinks", names.size() == 3 and cr2.count() == 19, str(names))
	var sm := Crew.new()
	sm.build({"roles": {"skipper": 1, "pilot": 1}}, 8, rng)
	t.check("crew: a small party keeps its skipper and pilot", sm.count() == 8 and sm.has_role("skipper") and sm.has_role("pilot"))
	t.check("crew: a skipper or pilot and enough hands can sail home", sm.can_sail_home(8) and not sm.can_sail_home(9))
	# mini-game ease follows the outfit and the pilot
	var keep_v = Game.voyage; var keep_c = Game.camp; var keep_d: String = Game.settings.difficulty
	Game.camp = null
	Game.settings.difficulty = "standard"
	Game.voyage = voyage_for("hunter_boat", 102)
	t.check("ease: the hunter-boat reads the star ring one step easier", Game.tuning("ring") == Game.tuning("ring", "forgiving"))
	t.check("ease: and seats a joint one step harder", Game.tuning("joint") == Game.tuning("joint", "hard"))
	Game.voyage = voyage_for("merchant", 103)
	t.check("ease: a merchant's ring is the chosen difficulty", Game.tuning("ring") == Game.tuning("ring", "standard"))
	for m in Game.voyage.crew.members:
		if m.role == "pilot": m.alive = false
	t.check("ease: with the pilot dead the sky is one step harder", Game.tuning("ring") == Game.tuning("ring", "hard") and Game.tuning("sun_board") == Game.tuning("sun_board", "hard"))
	Game.voyage = keep_v; Game.camp = keep_c; Game.settings.difficulty = keep_d
	# voyage effects
	var a := voyage_for("merchant", 110); var b := voyage_for("merchant", 110)
	for m in b.crew.members:
		if m.role == "skipper": m.alive = false
	for vv in [a, b]:
		vv.start_day(); vv.weather = "fair"; vv.pace = "easy"
	var la := a.leg_left; var lb := b.leg_left
	a.sail_watch(); b.sail_watch()
	t.check("roles: without a skipper she makes less way", (lb - b.leg_left) < (la - a.leg_left) * 0.95, "%.1f vs %.1f nm" % [lb - b.leg_left, la - a.leg_left])
	var sk := voyage_for("shipwright_s_kin", 111); var mc := voyage_for("merchant", 111); var nw := voyage_for("merchant", 111)
	for m in nw.crew.members:
		if m.role == "shipwright": m.alive = false
	for vv in [sk, mc, nw]:
		vv.hull = 2
		vv.leg_left = 1.0
		vv._advance(2.0, [])
	t.check("roles: the shipwright's kin mends two levels at a landfall, others one, none without a shipwright", sk.hull == 0 and mc.hull == 1 and nw.hull == 2, "%d / %d / %d" % [sk.hull, mc.hull, nw.hull])
	var ss := voyage_for("shipwright_s_kin", 112)
	ss.start_day(); ss.weather = "following_gale"; ss.pace = "crack"; ss.sail_strain = 0.99
	var evs := ss.sail_watch()
	t.check("roles: the spare sail goes up when the old one splits", not ss.sail_torn and ss.spare_sail == 0 and evs.any(func(e): return e.type == "spare_sail"))
	var heal := voyage_for("merchant", 113)
	t.check("roles: a healer aboard shortens sickness by a day", heal.sick_days() == 4)
	for m in heal.crew.members:
		if m.role == "healer": m.alive = false
	t.check("roles: without one it runs its course", heal.sick_days() == 5)
	var fm := lo_for("farm_household")
	t.check("outfits: the farm household's fodder goes further", fm.days_of("fodder") > 20.0, "%.1f days" % fm.days_of("fodder"))
	var dv := voyage_for("merchant", 114)
	dv.sick = [3, 3, 3, 3, 3, 3]
	dv.food = 0.0; dv.fresh_fish = []
	var named := false
	for i in 30:
		dv.start_day()
		for e in dv.end_day():
			if e.type == "death" and not e.get("names", []).is_empty(): named = true
		if dv.state != "sailing": break
	t.check("crew: deaths at sea are named, and the roster matches the head count", named and dv.crew.count() == dv.people, "%d / %d" % [dv.crew.count(), dv.people])
	# camp effects
	var farm := camp_for("farm_household", 120); var merch := camp_for("merchant", 120)
	t.check("outfits: the farm household's byre needs less work", farm.byre_need() < merch.byre_need(), "%.0f vs %.0f builder-days" % [farm.byre_need(), merch.byre_need()])
	t.check("outfits: the farm household gets more milk from a cow", farm.milk_per_cow() > merch.milk_per_cow(), "%.2f vs %.2f" % [farm.milk_per_cow(), merch.milk_per_cow()])
	t.check("outfits: the merchant pays less for a pelt", merch.pelt_price() < camp_for("hunter_boat", 120).pelt_price(), "%.2f" % merch.pelt_price())
	var hb := camp_for("hunter_boat", 121)
	hb.market_today = true; hb.market_pelts = 8
	hb.do_trade(4, 0, true)
	t.check("outfits: the hunter-boat earns less goodwill from a trade", hb.goodwill < 1.0, "%.2f" % hb.goodwill)
	var tim := {}
	for id in ["shipwright_s_kin", "merchant"]:
		var c := camp_for(id, 122)
		c.assign = {"build": 0, "fish": 0, "hunt": 0, "forage": 0, "dry": 0, "timber": 4, "hay": 0, "tend": 0}
		for i in 10: c.work_day()
		tim[id] = c.timber
	t.check("outfits: the shipwright's kin fells more timber", tim.shipwright_s_kin > tim.merchant, "%.2f vs %.2f" % [tim.shipwright_s_kin, tim.merchant])
	var smith := camp_for("merchant", 123)
	smith.hooks = 2
	var blades := smith.iron_blades
	for i in 7: smith.work_day()
	t.check("roles: the smith beats trade iron into hooks when they run short", smith.hooks >= 6 and smith.iron_blades == blades - 1, "%d hooks, %d blades" % [smith.hooks, smith.iron_blades])
	var nos := camp_for("merchant", 124)
	nos.hooks = 2
	for m in nos.crew.members:
		if m.role == "smith": m.alive = false
	for i in 7: nos.work_day()
	t.check("roles: with no smith, no new hooks", nos.hooks <= 2)
	var sv := camp_for("hunter_boat", 125)
	var back := Camp.new()
	back.from_dict(Knobs._v, JSON.parse_string(JSON.stringify(sv.to_dict())))
	t.check("crew: the named crew and the outfit survive a save", back.outfit == "hunter_boat" and back.crew.count() == sv.crew.count() and back.crew.members[0].name == sv.crew.members[0].name)
	# every outfit can cross with a careful captain
	for id in order:
		var arrived := 0
		for s in 40:
			var v := voyage_for(id, 8000 + s)
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
			if v.state == "arrived": arrived += 1
		t.check("outfits: a careful %s crossing arrives (36+ of 40)" % table[id].name, arrived >= 36, "%d of 40" % arrived)
	# every outfit's camp gets through the first winter with a planning player
	var TC = load("res://tests/test_camp.gd")
	for id in order:
		var deaths := 0; var animals := 0; var ended := 0; var n := 20
		for s in n:
			var c := camp_for(id, 8500 + s)
			c.food = 0.6
			var guard := 0
			while c.state == "camp" and not c.second_spring and guard < 500:
				guard += 1
				TC.plan(c, "planner")
				if id == "farm_household" and c.job_open("hay"):
					c.assign.hay = 5; c.assign.build = maxi(0, int(c.assign.build) - 1)   # a bigger herd wants one more haymaker
					c.default_assignments()
				c.work_day()
			deaths += c.dead; animals += int(c.history.animals_lost)
			if c.second_spring: ended += 1
		print("INFO  outfit year %-16s spring %3d%%  deaths %.1f  animals lost %.1f" % [table[id].name, roundi(100.0 * ended / n), float(deaths) / n, float(animals) / n])
		t.check("outfits: a planning %s camp reaches the second spring with few deaths (< 3) and its herd (< 1 lost)" % table[id].name, ended >= n - 1 and float(deaths) / n < 3.0 and float(animals) / n < 1.0, "%.1f deaths, %.1f animals" % [float(deaths) / n, float(animals) / n])
	# the loadout screen steps through the outfits
	var sc: Node = load("res://scenes/loadout.tscn").instantiate()
	sc._ready()
	var seen := {}
	for i in 4:
		seen[sc.lo.outfit] = true
		sc.cycle_outfit(1)
	t.check("loadout scene: steps through all four outfits", seen.size() == 4)
	sc.free()
