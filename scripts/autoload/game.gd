extends Node
## Run state: the hold, the party, the calendar. Systems contract lives on the plan's Systems sheet.

signal hold_changed
signal day_advanced(day: int)

var settings := {"haptics": true, "text_scale": 1.0}

var day := 0            # days since departure
var watch := 0          # 0..5, six four-hour watches a day
var hold := {}          # cargo kind -> count
var voyage: Voyage = null  # the live voyage, when one is running
var camp: Camp = null      # the camp at the Strait, once ashore

func new_run() -> void:
	day = 0
	watch = 0
	hold = {
		"people": int(Knobs.num("party_size_default", 24)),
		"cattle": int(Knobs.num("cattle_at_departure", 2)),
		"sheep": int(Knobs.num("sheep_and_goats_at_departure", 6)),
		"food": 0, "drink": 0, "fodder": 0,
		"trade": int(Knobs.num("trade_goods_carried", 2)),
		"timber": 0,
	}
	hold_changed.emit()

## Cargo units each kind takes in the hull (Systems: Cargo hold).
func unit_cost(kind: String) -> float:
	match kind:
		"people": return Knobs.num("cargo_units_per_person", 0.4)
		"cattle": return Knobs.num("cargo_units_per_head_of_cattle", 1.5)
		"sheep": return Knobs.num("cargo_units_per_sheep_or_goat", 0.4)
		"timber": return Knobs.num("cargo_units_per_timber_unit", 1.0)
		_: return 1.0

func hold_load() -> float:
	var total := 0.0
	for k in hold:
		total += hold[k] * unit_cost(k)
	return snappedf(total, 0.01)

func hold_capacity() -> float:
	return Knobs.num("knarr_cargo_units", 24)
