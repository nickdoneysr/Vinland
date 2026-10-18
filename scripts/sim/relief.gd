class_name Relief
extends RefCounted
## Loading the relief at Eriksfjord in the third spring (Backlog F30). The household feeds the crossing;
## silver buys more stores, stock and trade goods. One hull holds 24 units, two hold 48.

const ROWS := ["food", "drink", "fodder", "cattle", "sheep", "cloth", "iron"]
const LABELS := {"food": "Food (units)", "drink": "Drink (units)", "fodder": "Fodder (units)", "cattle": "Cattle", "sheep": "Sheep and goats",
	"cloth": "Red cloth (trade units)", "iron": "Iron blades (trade units)"}
const PRICE_KEYS := {"food": "relief_price_food_unit", "drink": "relief_price_drink_unit", "fodder": "relief_price_fodder_unit",
	"cattle": "relief_price_head_of_cattle", "sheep": "relief_price_sheep_or_goat", "cloth": "relief_price_trade_unit", "iron": "relief_price_trade_unit"}

var k: Dictionary
var home: Home
var c := {}
var free := {}     # what the household gives for the crossing

func setup(knobs: Dictionary, h: Home) -> void:
	k = knobs
	home = h
	var d := crossing_days()
	free = {"food": ceili(people() * d / n("food_unit_feeds", 168)), "drink": ceili(people() * d / n("drink_unit_covers", 120))}
	reset()

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

func crossing_days() -> int:
	return ceili(n("outbound_route_distance", 1200) / n("good_day_s_sail", 120) * n("weather_and_lost_day_factor", 1.3))

func people() -> int:
	return home.relief_party()

func hulls() -> int:
	return home.hulls()

func capacity() -> float:
	return n("knarr_cargo_units", 24) * hulls()

## The household's crossing stores and nothing bought.
func reset() -> void:
	c = {"food": free.food, "drink": free.drink, "fodder": 0, "cattle": 0, "sheep": 0, "cloth": 0, "iron": 0}

func price(row: String) -> float:
	return n(PRICE_KEYS[row], 1)

func cost() -> float:
	var t := 0.0
	for r in ROWS:
		t += maxi(0, int(c[r]) - int(free.get(r, 0))) * price(r)
	return t

func silver() -> float:
	return home.left()

func change(row: String, d: int) -> void:
	c[row] = clampi(int(c[row]) + d, 0, 30)

func unit_cost(row: String) -> float:
	match row:
		"cattle": return n("cargo_units_per_head_of_cattle", 1.5)
		"sheep": return n("cargo_units_per_sheep_or_goat", 0.4)
	return 1.0

func hold_load() -> float:
	var u := people() * n("cargo_units_per_person", 0.4)
	for r in ROWS:
		u += int(c[r]) * unit_cost(r)
	return snappedf(u, 0.1)

func days_of(row: String) -> float:
	match row:
		"food": return c.food * n("food_unit_feeds", 168) / maxf(1.0, people())
		"drink": return c.drink * n("drink_unit_covers", 120) / maxf(1.0, people())
		"fodder":
			var herd: float = c.cattle + c.sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)
			return 999.0 if herd <= 0.0 else c.fodder * n("fodder_unit_covers", 40) / herd
	return 0.0

func warnings() -> Array:
	var w: Array = []
	if hold_load() > capacity():
		w.append("Overloaded: %.1f of %d units." % [hold_load(), int(capacity())])
	if cost() > silver() + 0.001:
		w.append("That costs %.1f marks; you have %.1f." % [cost(), silver()])
	for r in ["food", "drink", "fodder"]:
		if days_of(r) < crossing_days():
			w.append("%s lasts %d days; the crossing is planned at %d." % [r.capitalize(), floori(days_of(r)), crossing_days()])
	return w

func can_sail() -> bool:
	return hold_load() <= capacity() and cost() <= silver() + 0.001

## Set the relief voyage up from this load: the year after the homecoming, the people who came home and the new recruits.
func apply_to(v: Voyage) -> void:
	v.relief = true
	v.hulls = hulls()
	v.year = home.year + 1
	v.outfit = home.outfit
	v.people = people()
	v.cattle = int(c.cattle); v.sheep = int(c.sheep)
	v.food = float(c.food); v.drink = float(c.drink); v.fodder = float(c.fodder)
	v.cloth_units = int(c.cloth); v.iron_units = int(c.iron); v.trade = v.cloth_units + v.iron_units
	v.crew.members.clear()
	for m in home.crew:
		v.crew.add(str(m.name), str(m.role), bool(m.female))
	v.crew.recruit(v.people - v.crew.count(), v.rng)
