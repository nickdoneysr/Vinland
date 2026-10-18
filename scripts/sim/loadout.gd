class_name Loadout
extends RefCounted
## Eriksfjord loadout (Backlog F53): what goes into the knarr's 24-unit hold. Same arithmetic as the
## plan's HoldCheck sheet, so the default load is the plan's load and fills the hull exactly.

const ROWS := ["people", "cattle", "sheep", "food", "drink", "fodder", "cloth", "iron"]
const LABELS := {"people": "People", "cattle": "Cattle (one bull, the rest cows)", "sheep": "Sheep and goats",
	"food": "Food (dried fish, meal, butter)", "drink": "Drink (whey and water casks)", "fodder": "Fodder (hay for the crossing)",
	"cloth": "Red cloth (trade)", "iron": "Iron blades (trade)"}
const LIMITS := {"people": [12, 40], "cattle": [0, 4], "sheep": [0, 12], "food": [0, 8], "drink": [0, 8],
	"fodder": [0, 6], "cloth": [0, 4], "iron": [0, 4]}

var k: Dictionary
var c := {}       # row -> count

func setup(knobs: Dictionary) -> void:
	k = knobs
	reset()

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

## The plan's HoldCheck load.
func reset() -> void:
	c = {"people": int(n("party_size_default", 24)), "cattle": int(n("cattle_at_departure", 2)),
		"sheep": int(n("sheep_and_goats_at_departure", 6))}
	var trade := int(n("trade_goods_carried", 2))
	c.cloth = ceili(trade / 2.0)
	c.iron = trade - c.cloth
	var p := provisions_for(c.people, c.cattle, c.sheep)
	c.food = p.food; c.drink = p.drink; c.fodder = p.fodder

## Planned crossing in days: route at a good day's sail, padded for weather and lost days.
func crossing_days() -> int:
	return ceili(n("outbound_route_distance", 1200) / n("good_day_s_sail", 120) * n("weather_and_lost_day_factor", 1.3))

## Units of food, drink and fodder that cover the planned crossing for this party and herd.
func provisions_for(people: int, cattle: int, sheep: int) -> Dictionary:
	var d := crossing_days()
	return {"food": ceili(people * d / n("food_unit_feeds", 168)), "drink": ceili(people * d / n("drink_unit_covers", 120)),
		"fodder": ceili((cattle + sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)) * d / n("fodder_unit_covers", 40))}

func unit_cost(row: String) -> float:
	match row:
		"people": return n("cargo_units_per_person", 0.4)
		"cattle": return n("cargo_units_per_head_of_cattle", 1.5)
		"sheep": return n("cargo_units_per_sheep_or_goat", 0.4)
		_: return 1.0

func hold_load() -> float:
	var u := 0.0
	for r in ROWS:
		u += c[r] * unit_cost(r)
	return snappedf(u, 0.1)

func capacity() -> float:
	return n("knarr_cargo_units", 24)

func change(row: String, d: int) -> void:
	c[row] = clampi(c[row] + d, LIMITS[row][0], LIMITS[row][1])

## Days each store lasts at full rations.
func days_of(row: String) -> float:
	match row:
		"food": return 999.0 if c.people == 0 else c.food * n("food_unit_feeds", 168) / c.people
		"drink": return 999.0 if c.people == 0 else c.drink * n("drink_unit_covers", 120) / c.people
		"fodder":
			var herd: float = c.cattle + c.sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)
			return 999.0 if herd <= 0.0 else c.fodder * n("fodder_unit_covers", 40) / herd
	return 0.0

## One line for each row: what this choice means at sea and at the camp.
func readout(row: String) -> String:
	match row:
		"people": return "%.1f units · %d hands to build and fish at the camp" % [c.people * unit_cost("people"), c.people]
		"cattle":
			if c.cattle == 0: return "no herd: no milk at the camp, nothing to trade but cloth and iron"
			return "%.1f units · a bull and %d cow%s for milk" % [c.cattle * unit_cost("cattle"), c.cattle - 1, "" if c.cattle == 2 else "s"]
		"sheep": return "%.1f units · wool and meat for the camp" % (c.sheep * unit_cost("sheep"))
		"food", "drink", "fodder":
			var d := days_of(row)
			var what := "for the herd" if row == "fodder" else "at full rations"
			return "%s · %s" % [_units(c[row]), "no animals to feed" if d >= 999.0 else "%d days %s" % [floori(d), what]]
		"cloth": return "%s · %d strips to trade" % [_units(c.cloth), c.cloth * int(n("red_cloth_strips_per_trade_unit", 20))]
		"iron": return "%s · %d blades (Karlsefni forbade selling weapons)" % [_units(c.iron), c.iron * int(n("iron_blades_per_trade_unit", 5))]
	return ""

func _units(u: int) -> String:
	return "1 unit" if u == 1 else "%d units" % u

## Problems with the load, worst first. Over capacity blocks sailing; the rest are warnings.
func warnings() -> Array:
	var w: Array = []
	if hold_load() > capacity():
		w.append("Overloaded: %.1f of %d units. She would wallow and ship water; take something out." % [hold_load(), int(capacity())])
	var d := crossing_days()
	for r in ["food", "drink", "fodder"]:
		var days := days_of(r)
		if days < d:
			w.append("%s lasts %d days; the crossing is planned at %d. You will be on short rations or fishing hard." % [r.capitalize(), floori(days), d])
	if c.cattle == 1:
		w.append("One beast is the bull alone: no cows, no milk.")
	return w

func can_sail() -> bool:
	return hold_load() <= capacity()

## Put this load aboard a voyage that has just been set up.
func apply_to(v: Voyage) -> void:
	v.people = c.people
	v.cattle = c.cattle
	v.sheep = c.sheep
	v.food = float(c.food)
	v.drink = float(c.drink)
	v.fodder = float(c.fodder)
	v.cloth_units = c.cloth
	v.iron_units = c.iron
	v.trade = c.cloth + c.iron

func to_dict() -> Dictionary:
	return c.duplicate()
