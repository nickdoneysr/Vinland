extends RefCounted
## Eriksfjord loadout (F53): the plan's load fills the hull exactly; every change trades against something.

static func make() -> Loadout:
	var lo := Loadout.new()
	lo.setup(Knobs._v)
	return lo

## Sail a careful captain with this load; returns the voyage at its end.
static func sail(c: Dictionary, seed: int) -> Voyage:
	var TV = load("res://tests/test_voyage.gd")
	var v: Voyage = TV.make(seed)
	var lo := make()
	lo.c = c.duplicate()
	lo.apply_to(v)
	var guard := 0
	while v.state == "sailing" and guard < 200:
		guard += 1
		v.start_day()
		TV._captain(v, "careful")
		var today := v.day
		while v.state == "sailing" and v.day == today:
			if v.watch == Voyage.NIGHT_WATCH:
				TV._night(v, "careful")
			v.sail_watch()
	return v

static func run(t) -> void:
	var lo := make()
	t.check("loadout: the plan's HoldCheck load fills the 24-unit hull exactly", lo.hold_load() == 24.0 and lo.can_sail(), "%.1f" % lo.hold_load())
	t.check("loadout: the plan's load has stores for the 13-day crossing", lo.warnings().is_empty() and lo.crossing_days() == 13, str(lo.warnings()))
	lo.change("people", 1)
	t.check("loadout: one more person overloads her and she will not sail", not lo.can_sail() and str(lo.warnings()[0]).begins_with("Overloaded"))
	lo.change("sheep", -1)
	t.check("loadout: leaving a sheep behind makes room for a person", lo.can_sail(), "%.1f" % lo.hold_load())
	lo.change("people", 20)
	t.check("loadout: the party is capped at 40", lo.c.people == 40)
	lo.reset()
	lo.change("food", -1)
	t.check("loadout: cutting food warns that it will not last the crossing", lo.warnings().size() == 1 and str(lo.warnings()[0]).begins_with("Food"), str(lo.warnings()))
	lo.reset()
	lo.change("cattle", -2); lo.change("sheep", -6)
	t.check("loadout: with no animals aboard fodder never runs short", lo.days_of("fodder") >= 999.0)
	# apply to a voyage and carry the trade goods into the camp
	var v: Voyage = load("res://tests/test_voyage.gd").make(42)
	var lc := make()
	lc.c.cloth = 2; lc.c.iron = 0
	lc.apply_to(v)
	t.check("loadout: the voyage sails with the chosen load", v.trade == 2 and v.cloth_units == 2 and v.iron_units == 0 and v.hold_load() == 24.0, "%.1f" % v.hold_load())
	var c := Camp.new()
	c.from_voyage(v)
	t.check("loadout: two units of cloth and no iron reach the camp as 40 strips and no blades", c.cloth_strips == 40 and c.iron_blades == 0, "%d / %d" % [c.cloth_strips, c.iron_blades])
	# a short-stocked load costs on the water
	var plan_load := make().c
	var lean: Dictionary = plan_load.duplicate()
	lean.food = 1; lean.drink = 2; lean.people = 24; lean.cattle = 3; lean.sheep = 8   # trade stores for animals
	var hunger_plan := 0.0; var hunger_lean := 0.0; var arrive_plan := 0; var arrive_lean := 0
	for s in 60:
		var a := sail(plan_load, 2000 + s)
		var b := sail(lean, 2000 + s)
		hunger_plan += a.starving_days + a.dead; hunger_lean += b.starving_days + b.dead
		arrive_plan += int(a.state == "arrived"); arrive_lean += int(b.state == "arrived")
	print("INFO  loadout plan load: arrived %d/60, hunger %.1f   lean stores: arrived %d/60, hunger %.1f" % [arrive_plan, hunger_plan / 60.0, arrive_lean, hunger_lean / 60.0])
	t.check("loadout: trading stores for animals means more hungry days at sea", hunger_lean > hunger_plan + 1.0, "%.1f vs %.1f" % [hunger_lean / 60.0, hunger_plan / 60.0])
	# the scene: A on an overloaded hull is refused; on a sound load it hands the load to the voyage
	var sc: Node = load("res://scenes/loadout.tscn").instantiate()
	sc._ready()
	sc.lo.change("people", 3)
	var refused: bool = not sc.sail()
	sc.lo.set_outfit("")
	sc.lo.change("cloth", 1); sc.lo.change("food", -1)
	Engine.get_main_loop().root.set_meta("no_scene_change", true)
	var ok: bool = sc.sail()
	Engine.get_main_loop().root.remove_meta("no_scene_change")
	t.check("loadout scene: an overloaded hull will not sail; a sound one hands its load to the voyage", refused and ok and Game.loadout.cloth == 2 and Game.loadout.food == 1)
	Game.loadout = {}
	sc.free()
