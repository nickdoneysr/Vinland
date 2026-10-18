extends Node
## Run state: the hold, the party, the calendar. Systems contract lives on the plan's Systems sheet.

signal hold_changed
signal day_advanced(day: int)

var settings := {"haptics": true, "text_scale": 1.0, "difficulty": "forgiving"}
const DIFFICULTIES := ["forgiving", "standard", "hard"]
const DIFFICULTY_NAMES := {"forgiving": "Forgiving", "standard": "Standard", "hard": "Hard"}

var _mg: Dictionary = {}

## Mini-game feel tuning for one game, with the chosen difficulty's overrides applied.
func tuning(game: String, difficulty: String = "") -> Dictionary:
	if _mg.is_empty():
		_mg = JSON.parse_string(FileAccess.open("res://data/minigames.json", FileAccess.READ).get_as_text())
	var d := difficulty if difficulty != "" else str(settings.difficulty)
	var out: Dictionary = (_mg[game] as Dictionary).duplicate(true)
	var over: Dictionary = _mg.difficulty.get(d, {}).get(game, {})
	for key in over:
		out[key] = over[key]
	return out

var day := 0            # days since departure
var watch := 0          # 0..5, six four-hour watches a day
var hold := {}          # cargo kind -> count
var voyage: Voyage = null  # the live voyage, when one is running
var camp: Camp = null      # the camp at the Strait, once ashore
var loadout: Dictionary = {}  # the load chosen at Eriksfjord (F53); empty means the plan's HoldCheck load

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

# ------------------------------------------------------------------ saving (F50)
## Autosaves rotate through three slots. Each write goes to a temp file first and is renamed into place,
## so a crash mid-write never leaves a broken save (Risk R15).
const SAVE_DIR := "user://save"
const SLOTS := 3
var loaded_stage := ""        # "voyage" or "camp" when a scene should resume from a loaded save

func save_game(stage: String) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var data := {"version": 1, "stage": stage, "settings": settings, "saved_utc": Time.get_datetime_string_from_system(true)}
	if voyage != null:
		data.voyage = voyage.to_dict()
	if camp != null and stage == "camp":
		data.camp = camp.to_dict()
	data.where = _where(stage)
	var tmp := SAVE_DIR + "/autosave.tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var dir := DirAccess.open(SAVE_DIR)
	for i in range(SLOTS - 1, 0, -1):
		var older := "autosave_%d.json" % i
		var newer := "autosave_%d.json" % (i - 1)
		if dir.file_exists(newer):
			if dir.file_exists(older):
				dir.remove(older)
			dir.rename(newer, older)
	return dir.rename("autosave.tmp", "autosave_0.json") == OK

func _where(stage: String) -> String:
	if stage == "camp" and camp != null:
		return "%s, year %d, at the Strait" % [camp.date_text(), camp.year]
	if voyage != null:
		return "%s, %s" % [voyage.date_text(), voyage.leg().name]
	return ""

## The newest save that reads cleanly, or {} when there is none.
func latest_save() -> Dictionary:
	for i in SLOTS:
		var p := SAVE_DIR + "/autosave_%d.json" % i
		if not FileAccess.file_exists(p):
			continue
		var d = JSON.parse_string(FileAccess.get_file_as_string(p))
		if d is Dictionary and d.has("stage"):
			return d
	return {}

## Rebuild the run from a save. Returns the scene to open.
func load_game(d: Dictionary) -> String:
	var legs_data: Dictionary = JSON.parse_string(FileAccess.open("res://data/legs.json", FileAccess.READ).get_as_text())
	if d.has("settings"):
		for key in d.settings:
			settings[key] = d.settings[key]
	voyage = null
	camp = null
	if d.has("voyage"):
		voyage = Voyage.new()
		voyage.from_dict(Knobs._v, legs_data, d.voyage)
	if d.has("camp"):
		camp = Camp.new()
		camp.from_dict(Knobs._v, d.camp)
	loaded_stage = str(d.stage)
	return "res://scenes/camp.tscn" if loaded_stage == "camp" else "res://scenes/voyage.tscn"

func clear_saves() -> void:
	for i in SLOTS:
		var p := SAVE_DIR + "/autosave_%d.json" % i
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
