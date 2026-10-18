extends RefCounted
## Voyage rules tests and a balance sweep with bot captains.

static func legs_data() -> Dictionary:
	return JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())

static func make(seed: int) -> Voyage:
	var v := Voyage.new()
	v.setup(Knobs._v, legs_data(), seed)
	return v

static func run(t) -> void:
	var v := make(1)
	var p := v.default_provisions()
	t.check("voyage: default provisions match HoldCheck (13 days, 2 food, 3 drink, 2 fodder)",
		p.days == 13 and p.food == 2.0 and p.drink == 3.0 and p.fodder == 2.0, str(p))
	t.check("voyage: departure hold is full but legal (24.0 of 24)", is_equal_approx(v.hold_load(), 24.0), str(v.hold_load()))
	var total := 0.0
	for i in v.legs.size():
		total += v.leg_length(i)
	t.check("voyage: legs add up to the route distance", is_equal_approx(total, 1200.0), str(total))
	# drift: clean refunds, none walks
	var a := make(7); var b := make(7)
	a.start_day(); b.start_day()
	a.weather = "fair"; b.weather = "fair"
	for i in 4: a.sail_watch(); b.sail_watch()
	a.take_fix(RingFix.Result.CLEAN); b.take_fix(RingFix.Result.NONE)
	a.sail_watch(); a.sail_watch(); b.sail_watch(); b.sail_watch()
	var expect := 24.0 * float(a.leg().get("drift_mult", 1.0))
	t.check("voyage: a clean fix saves the full day's drift (24 nm, doubled on open water)", is_equal_approx(b.leg_left - a.leg_left, expect), "%.1f vs %.1f" % [b.leg_left - a.leg_left, expect])
	# rations: half ration halves food use
	var c := make(3); var d := make(3)
	c.ration = "full"; d.ration = "half"
	c.start_day(); d.start_day()
	for i in 6: c.sail_watch(); d.sail_watch()
	t.check("voyage: half rations use half the food", is_equal_approx((2.0 - d.food) * 2.0, 2.0 - c.food), "%.3f vs %.3f" % [2.0 - c.food, 2.0 - d.food])
	# season loss
	var e := make(5)
	e.day_of_year = 273
	e.start_day()
	for i in 6: e.sail_watch()
	t.check("voyage: still at sea in October is a loss", e.state == "lost", e.loss_reason)
	# fishing only on a coastal leg, once a day
	var f := make(9)
	f.start_day()
	var ev1 := f.fish(1.0); var ev2 := f.fish(1.0)
	t.check("voyage: fishing works once a day on a coastal leg", ev1.size() >= 1 and ev2.is_empty())
	balance(t)

## Plays 300 voyages per captain and prints the numbers the designer tunes against.
static func balance(t) -> void:
	var results := {}
	for policy in ["careful", "average", "average_nofix", "reckless"]:
		var arrived := 0; var days := 0; var deaths := 0; var lost_reasons := {}
		var m := {"animals": 0, "starve": 0, "hull": 0, "torn": 0, "food": 0.0}
		var runs := 300
		for s in runs:
			var v := make(1000 + s)
			var guard := 0
			while v.state == "sailing" and guard < 200:
				guard += 1
				v.start_day()
				_captain(v, policy)
				var today := v.day
				while v.state == "sailing" and v.day == today:
					if v.watch == Voyage.NIGHT_WATCH:
						_night(v, policy)
					if policy != "reckless" and v.is_coastal() and not v.fished_today and v.food_days() < 30 and v.watch == 0:
						v.fish()
						continue
					v.sail_watch()
			if v.state == "arrived":
				arrived += 1
				days += v.day
			else:
				lost_reasons[v.loss_reason] = lost_reasons.get(v.loss_reason, 0) + 1
			deaths += v.dead
			m.animals += v.animals_lost; m.starve += v.starving_days; m.hull += v.hull; m.torn += int(v.sail_torn)
			m.food += v.food_days()
			if s == 0:
				v.write_log("user://balance_%s_seed1000.csv" % policy)
		var rate := float(arrived) / runs
		var r := float(runs)
		print("INFO  balance %-8s arrived %3d%%  days %.1f  deaths %.2f  animals lost %.2f  starving days %.1f  hull %.2f  sail torn %d%%  food days left %.1f  losses %s" % [
			policy, roundi(rate * 100), float(days) / maxi(arrived, 1), deaths / r, m.animals / r, m.starve / r, m.hull / r,
			roundi(m.torn / r * 100), m.food / r, str(lost_reasons)])
		results[policy] = {"rate": rate, "days": float(days) / maxi(arrived, 1), "cost": (deaths + m.animals + m.starve) / r}
	t.check("balance: a careful captain arrives (>= 90%)", results.careful.rate >= 0.9, "%d%%" % roundi(results.careful.rate * 100))
	t.check("balance: recklessness costs more people, animals, or hunger than care", results.reckless.cost > results.careful.cost * 1.5,
		"%.2f vs %.2f" % [results.reckless.cost, results.careful.cost])
	t.check("balance: the same captain without fixes takes longer", results.average_nofix.days >= results.average.days + 0.5,
		"%.1f vs %.1f days" % [results.average_nofix.days, results.average.days])

static func _captain(v: Voyage, policy: String) -> void:
	var remaining := v.leg_left
	for i in range(v.leg_i + 1, v.legs.size()):
		remaining += v.leg_length(i)
	var days_needed := remaining / (v.n("good_day_s_sail") * 0.8)
	match policy:
		"careful":
			v.pace = "heave" if v.weather == "storm" else "easy"
			var ratio := v.food_days() / maxf(days_needed, 0.1)
			v.ration = "full" if ratio > 1.3 else ("half" if ratio > 0.7 else "bare")
			v.animal_ration = "full" if v.fodder > 0.3 else "half"
		"average", "average_nofix":
			v.pace = "heave" if v.weather == "storm" else ("crack" if v.weather == "fair" else "easy")
			v.ration = "full" if v.food_days() > days_needed else "half"
		"reckless":
			v.pace = "crack"
			v.ration = "full"

static func _night(v: Voyage, policy: String) -> void:
	var sky := v.ring_preset()
	if sky == "":
		return
	var roll := v.rng.randf()
	var good: float = {"careful": 0.6, "average": 0.4}.get(policy, 0.0)
	if policy == "reckless" or policy == "average_nofix":
		return
	var hard := 0.25 if sky in ["fog", "storm", "clouded"] else 0.0
	if roll < good - hard:
		v.take_fix(RingFix.Result.CLEAN)
	elif roll < 0.9 - hard:
		v.take_fix(RingFix.Result.PARTIAL)
	else:
		v.take_fix(RingFix.Result.NONE)
