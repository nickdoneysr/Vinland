class_name ReturnPlan
extends RefCounted
## Loading the knarr for home (Backlog F24 with the plan's HoldCheck RETURN section): who sails, how much
## timber and how many pelts, and the stores for the crossing, against the same 24-unit hull.
## Whoever does not sail winters at the camp. Everyone sailing abandons the camp (the saga ending, P8).

const ROWS := ["sailors", "timber", "pelts", "food", "drink"]
const LABELS := {"sailors": "Who sails home", "timber": "Timber (units)", "pelts": "Pelts (bales of ten)", "food": "Food (units)", "drink": "Drink (casks of whey and water)"}
## Who goes first: the ship needs a skipper and a pilot; the camp keeps its healer, smith, householder and hunter longest.
const SAIL_ORDER := ["skipper", "pilot", "hand", "shipwright", "hunter", "householder", "smith", "healer"]

var k: Dictionary
var camp: Camp
var c := {}

func setup(knobs: Dictionary, the_camp: Camp) -> void:
	k = knobs
	camp = the_camp
	reset()

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

func crossing_days() -> int:
	return ceili(n("outbound_route_distance", 1200) / n("good_day_s_sail", 120) * n("weather_and_lost_day_factor", 1.3))

func pelt_bales() -> int:
	return ceili(camp.pelts / n("pelts_per_cargo_unit", 10))

## The plan's return load: the return crew, stores for the crossing, then as much timber and pelts as fit.
func reset() -> void:
	c = {"sailors": mini(camp.people, int(n("crew_sailing_the_return", 10)))}
	var d := crossing_days()
	c.food = mini(int(floor(camp.food)), ceili(c.sailors * d / n("food_unit_feeds", 168)))
	c.drink = ceili(c.sailors * d / n("drink_unit_covers", 120))
	c.timber = 0; c.pelts = 0
	var room := capacity() - hold_load()
	c.timber = mini(int(floor(camp.timber)), int(floor(room)))
	room = capacity() - hold_load()
	c.pelts = mini(pelt_bales(), int(floor(room)))

func limits(row: String) -> Array:
	match row:
		"sailors": return [1, camp.people]
		"timber": return [0, int(floor(camp.timber))]
		"pelts": return [0, pelt_bales()]
		"food": return [0, int(floor(camp.food))]
		"drink": return [0, 6]
	return [0, 0]

func change(row: String, d: int) -> void:
	var lim := limits(row)
	c[row] = clampi(int(c[row]) + d, lim[0], lim[1])

func hold_load() -> float:
	return snappedf(c.sailors * n("cargo_units_per_person", 0.4) + c.timber * n("cargo_units_per_timber_unit", 1) + c.pelts + c.food + c.drink, 0.1)

func capacity() -> float:
	return n("knarr_cargo_units", 24)

func days_of(row: String) -> float:
	if c.sailors <= 0:
		return 999.0
	match row:
		"food": return c.food * n("food_unit_feeds", 168) / c.sailors
		"drink": return c.drink * n("drink_unit_covers", 120) / c.sailors
	return 0.0

## The named crew who would sail, in SAIL_ORDER.
func sailing_crew() -> Array:
	var living: Array = camp.crew.alive()
	var out: Array = []
	for role in SAIL_ORDER:
		for m in living:
			if out.size() >= int(c.sailors):
				return out
			if m.role == role:
				out.append(m)
	return out

func stayers() -> int:
	return camp.people - int(c.sailors)

func readout(row: String) -> String:
	match row:
		"sailors":
			if stayers() <= 0:
				return "everyone: the camp is left empty"
			return "%.1f units · %d stay to winter the camp" % [c.sailors * n("cargo_units_per_person", 0.4), stayers()]
		"timber": return "%d of %.1f stacked · %d%% felled in winter" % [c.timber, camp.timber, roundi(camp.winter_share() * 100)]
		"pelts": return "%d of %d pelts" % [mini(c.pelts * int(n("pelts_per_cargo_unit", 10)), camp.pelts), camp.pelts]
		"food", "drink": return "%d days at full rations" % floori(days_of(row))
	return ""

func warnings() -> Array:
	var w: Array = []
	if hold_load() > capacity():
		w.append("Overloaded: %.1f of %d units." % [hold_load(), int(capacity())])
	var crew := sailing_crew()
	var has_nav := crew.any(func(m): return m.role in ["skipper", "pilot"])
	if c.sailors < int(n("role_fewest_crew_to_sail_a_knarr_home", 10)) or not has_nav:
		w.append("She needs a skipper or a pilot and at least %d aboard." % int(n("role_fewest_crew_to_sail_a_knarr_home", 10)))
	for r in ["food", "drink"]:
		if days_of(r) < crossing_days():
			w.append("%s lasts %d days; the crossing is planned at %d." % [r.capitalize(), floori(days_of(r)), crossing_days()])
	if c.timber < n("timber_units_to_open_a_return", 4):
		w.append("Less than %d units of timber: hardly worth the voyage." % int(n("timber_units_to_open_a_return", 4)))
	if stayers() <= 0:
		w.append("Everyone sails: the camp is abandoned. The saga allows it; the score counts a living camp higher.")
	elif camp.food * n("food_unit_feeds", 168) - c.food * n("food_unit_feeds", 168) < stayers() * 30:
		w.append("The %d who stay have less than a month of stores." % stayers())
	return w

func can_sail() -> bool:
	var crew := sailing_crew()
	return hold_load() <= capacity() and c.sailors >= int(n("role_fewest_crew_to_sail_a_knarr_home", 10)) \
		and crew.any(func(m): return m.role in ["skipper", "pilot"])

## Sail: build the homeward voyage and take its people and cargo out of the camp.
func launch(legs_data: Dictionary, seed: int = 0) -> Voyage:
	var v := Voyage.new()
	v.setup_return(k, legs_data, seed, camp)
	var sailing := sailing_crew()
	v.crew.members.clear()
	for m in sailing:
		v.crew.members.append(m.duplicate())
		m.alive = false               # gone from the camp (not dead: they are at sea)
		m.away = true
	camp.crew.members = camp.crew.members.filter(func(m): return not m.get("away", false))
	v.people = sailing.size()
	camp.people -= v.people
	v.timber = int(c.timber)
	camp.timber -= c.timber
	var pelts_taken := mini(int(c.pelts) * int(n("pelts_per_cargo_unit", 10)), camp.pelts)
	v.pelts = pelts_taken
	v.pelt_bales = int(c.pelts)
	camp.pelts -= pelts_taken
	v.food = float(c.food)
	camp.food -= c.food
	v.drink = float(c.drink)
	var hooks_taken := mini(camp.hooks, 3)
	v.hooks = hooks_taken
	camp.hooks -= hooks_taken
	camp.sailed += 1
	if camp.people <= 0:
		camp.state = "abandoned"
		camp.end_reason = "Everyone sailed home."
	return v
