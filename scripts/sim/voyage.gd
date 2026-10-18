class_name Voyage
extends RefCounted
## The outbound voyage as pure rules (Backlog F01 hold and rations, F02 watches and legs, F09 weather deck,
## F35 season clock, F37 drink casks, F38 pace and drift, F39 run log, F45/F46 basics).
## No drawing, no input: scenes call these methods and show the events they return.
## Every number comes from the knobs dictionary (data/knobs.json, exported from the plan).

const WATCHES_PER_DAY := 6
const NIGHT_WATCH := 4                 # the fix is taken in the fifth watch
const RATION := {"full": 1.0, "half": 0.5, "bare": 0.25}
const ANIMAL_RATION := {"full": 1.0, "half": 0.5, "none": 0.0}
const PACES := ["crack", "easy", "heave"]
const PACE_NAMES := {"crack": "Crack on", "easy": "Easy", "heave": "Heave to"}

var k: Dictionary
var legs: Array = []
var wx: Dictionary = {}
var rng := RandomNumberGenerator.new()

var day := 0                 # days since departure
var day_of_year := 145
var watch := 0
var leg_i := 0
var leg_left := 0.0          # nm left on this leg
var sailed_nm := 0.0
var drift_nm_total := 0.0
var state := "sailing"       # sailing | arrived | lost
var loss_reason := ""

var people := 24
var sick: Array[int] = []    # days left sick, one entry per sick person
var dead := 0
var cattle := 2
var sheep := 6
var fodderless_days := 0
var food := 0.0              # food units
var fresh_fish: Array = []   # [person_days, age_days]
var drink := 0.0
var fodder := 0.0
var trade := 2
var hooks := 6
var timber := 0

var ration := "full"
var animal_ration := "full"
var pace := "easy"
var morale := 70.0
var hull := 0                # 0 sound, 1 strained, 2 sprung, 3 holed
var sail_torn := false
var sail_strain := 0.0

var weather := "fair"
var deck: Array = []
var fix_today := -1          # RingFix.Result or -1 when no fix was taken
var fished_today := false
var day_nm := 0.0
var starving_days := 0
var animals_lost := 0
var fixes := [0, 0, 0]
var log_rows: Array = []

# ------------------------------------------------------------------ setup
func setup(knobs: Dictionary, legs_data: Dictionary, seed: int = 0) -> void:
	k = knobs
	legs = legs_data.legs
	wx = legs_data.weather
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	day_of_year = int(n("departure_day_of_year", 145))
	people = int(n("party_size_default", 24))
	cattle = int(n("cattle_at_departure", 2))
	sheep = int(n("sheep_and_goats_at_departure", 6))
	trade = int(n("trade_goods_carried", 2))
	hooks = int(n("hooks_carried", 6))
	var load := default_provisions()
	food = load.food
	drink = load.drink
	fodder = load.fodder
	leg_i = 0
	leg_left = leg_length(0)
	_new_deck()

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

## Same arithmetic as the HoldCheck sheet: provisions for the planned crossing.
func default_provisions() -> Dictionary:
	var days := ceili(n("outbound_route_distance", 1200) / n("good_day_s_sail", 120) * n("weather_and_lost_day_factor", 1.3))
	var p := float(people)
	return {
		"days": days,
		"food": float(ceili(p * days / n("food_unit_feeds", 168))),
		"drink": float(ceili(p * days / n("drink_unit_covers", 120))),
		"fodder": float(ceili((cattle + sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)) * days / n("fodder_unit_covers", 40))),
	}

func leg_length(i: int) -> float:
	var L: Dictionary = legs[i]
	if L.open_water:
		return n("open_water_leg", 400)
	var coastal_total := n("outbound_route_distance", 1200) - n("open_water_leg", 400)
	return coastal_total * float(L.share)

func leg() -> Dictionary:
	return legs[leg_i]

func is_coastal() -> bool:
	return bool(leg().coastal)

# ------------------------------------------------------------------ hold (Systems: Cargo hold)
func hold_load() -> float:
	var u := people * n("cargo_units_per_person", 0.4) + cattle * n("cargo_units_per_head_of_cattle", 1.5) \
		+ sheep * n("cargo_units_per_sheep_or_goat", 0.4) + ceilf(food) + ceilf(drink) + ceilf(fodder) + trade \
		+ timber * n("cargo_units_per_timber_unit", 1.0)
	return snappedf(u, 0.1)

func hold_capacity() -> float:
	return n("knarr_cargo_units", 24)

## Days of food left at today's ration (fresh fish included).
func food_days() -> float:
	var per_day: float = people * RATION[ration]
	if per_day <= 0:
		return 999.0
	var pd := food * n("food_unit_feeds", 168)
	for f in fresh_fish:
		pd += f[0]
	return pd / per_day

func drink_days() -> float:
	return 999.0 if people == 0 else drink * n("drink_unit_covers", 120) / people

# ------------------------------------------------------------------ weather deck (F09)
func _new_deck() -> void:
	deck.clear()
	var w: Dictionary = leg().weather
	for card in w:
		for i in int(w[card]):
			deck.append(card)
	# Fisher-Yates with our own rng so seeds replay exactly
	for i in range(deck.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = deck[i]; deck[i] = deck[j]; deck[j] = t

func start_day() -> Dictionary:
	if deck.is_empty():
		_new_deck()
	weather = deck.pop_back()
	fix_today = -1
	fished_today = false
	day_nm = 0.0
	return {"type": "weather", "card": weather, "info": wx[weather]}

func weather_info() -> Dictionary:
	return wx[weather]

## Which star ring conditions tonight's sky gives; "" means no sky at all.
func ring_preset() -> String:
	var p: String = wx[weather].ring
	if p == "clear":
		if day_of_year >= 160 and day_of_year <= 205:
			return "twilight"          # the short northern night
		if rng.randf() < 0.3:
			return "clouded"
	return p

# ------------------------------------------------------------------ the watch (F02)
func pace_mult() -> float:
	match pace:
		"crack": return n("pace_multiplier_crack_on", 1.25)
		"heave": return n("pace_multiplier_heave_to", 0.15)
		_: return n("pace_multiplier_easy", 1.0)

func sail_watch() -> Array:
	var ev: Array = []
	if state != "sailing":
		return ev
	var info: Dictionary = wx[weather]
	var speed := n("good_day_s_sail", 120) / WATCHES_PER_DAY * pace_mult() * float(info.speed)
	if sail_torn:
		speed *= 0.7
	if hull >= 2:
		speed *= 0.85
	if morale < 25:
		speed *= 0.85
	_advance(speed, ev)
	# Ship condition (F45 basics)
	if pace == "crack" and info.rough:
		sail_strain += n("sail_strain_per_watch_cracking_on_in_wind", 0.08)
		if sail_strain >= 1.0 and not sail_torn:
			sail_torn = true
			sail_strain = 0.0
			ev.append({"type": "sail_torn"})
	if weather == "storm":
		var chance := n("sprung_strake_chance_per_storm_watch_hove_to", 0.02) if pace == "heave" else n("sprung_strake_chance_per_storm_watch_running", 0.12)
		if rng.randf() < chance:
			hull += 1
			ev.append({"type": "strake", "hull": hull})
			if hull >= 3:
				_lose("The hull opened in the storm, with no camp behind her.", ev)
	watch += 1
	if watch >= WATCHES_PER_DAY and state == "sailing":
		ev.append_array(end_day())
	return ev

func _advance(nm: float, ev: Array) -> void:
	day_nm += nm
	sailed_nm += nm
	leg_left -= nm
	while leg_left <= 0.0 and state == "sailing":
		var over := -leg_left
		ev.append({"type": "landfall", "leg": leg().name})
		morale = clampf(morale + n("morale_change_landfall", 8), 0, 100)
		if hull > 0:
			hull -= 1
			ev.append({"type": "repair", "hull": hull})
		if leg_i >= legs.size() - 1:
			state = "arrived"
			ev.append({"type": "arrived"})
			return
		leg_i += 1
		leg_left = leg_length(leg_i) - over
		_new_deck()
		ev.append({"type": "new_leg", "leg": leg().name, "nm": leg_left})

func can_fish() -> bool:
	return state == "sailing" and not fished_today and is_coastal() and watch < WATCHES_PER_DAY and hooks > 0

## Fishing spends a watch at anchor (Systems: once a day, coastal only).
## The hand-line mini-game passes its catch in; without it (bots, tests) the knob's average is rolled.
func fish(quality: float = -1.0, caught_pd: float = -1.0, hooks_lost: int = 0) -> Array:
	var ev: Array = []
	if not can_fish():
		return ev
	fished_today = true
	hooks = maxi(0, hooks - hooks_lost)
	if quality < 0.0:
		quality = rng.randf_range(0.3, 1.4)
	var pd := caught_pd if caught_pd >= 0.0 else n("hand_line_catch_per_fishing_day", 18) * quality
	fresh_fish.append([pd, 0])
	ev.append({"type": "fished", "person_days": pd, "hooks_lost": hooks_lost})
	watch += 1
	if watch >= WATCHES_PER_DAY:
		ev.append_array(end_day())
	return ev

## The night fix from the star ring. Only one per day counts.
func take_fix(result: int) -> Array:
	var ev: Array = []
	if fix_today == -1:
		fix_today = result
		fixes[result] += 1
		if result == 2:
			morale = clampf(morale + n("morale_change_clean_fix", 2), 0, 100)
		ev.append({"type": "fix", "result": result})
	return ev

# ------------------------------------------------------------------ end of day
func end_day() -> Array:
	var ev: Array = []
	var info: Dictionary = wx[weather]
	# Drift (Systems): no fix walks downwind, partial halves, clean refunds.
	var mult := 1.0 if fix_today < 0 else RingFix.drift_multiplier(fix_today)
	var drift := n("daily_drift_with_no_fix", 24) * float(info.drift) * float(leg().get("drift_mult", 1.0)) * mult
	drift_nm_total += drift
	leg_left += drift
	if drift > 0.5:
		ev.append({"type": "drift", "nm": drift, "fix": fix_today})
	# Food: fresh fish first, then stores.
	var need: float = people * RATION[ration]
	for f in fresh_fish:
		var take := minf(need, f[0])
		f[0] -= take
		need -= take
	var spoiled := 0.0
	for f in fresh_fish:
		f[1] += 1
		if f[1] >= 3 and f[0] > 0:
			spoiled += f[0]
			f[0] = 0.0
	fresh_fish = fresh_fish.filter(func(f): return f[0] > 0.01)
	if spoiled > 0:
		ev.append({"type": "spoiled", "person_days": spoiled})
	food -= need / n("food_unit_feeds", 168)
	var starving := food < 0.0
	if starving:
		food = 0.0
		starving_days += 1
		ev.append({"type": "starving"})
	drink -= people / n("drink_unit_covers", 120)
	var thirsty := drink < 0.0
	if thirsty:
		drink = 0.0
		ev.append({"type": "thirst"})
	# Casks (F37)
	if info.rough and drink >= 1.0 and rng.randf() < n("cask_breach_chance_per_rough_day", 0.1):
		drink -= 1.0
		ev.append({"type": "cask_breach"})
	# Animals
	var herd := cattle + sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)
	fodder -= herd * ANIMAL_RATION[animal_ration] / n("fodder_unit_covers", 40)
	if fodder <= 0.0 or animal_ration == "none":
		fodder = maxf(fodder, 0.0)
		fodderless_days += 1
		if fodderless_days >= int(n("fodderless_days_before_an_animal_dies", 3)) and (cattle + sheep) > 0:
			fodderless_days = 0
			if cattle > 0:
				cattle -= 1
				animals_lost += 1
				ev.append({"type": "animal_died", "kind": "cattle"})
			else:
				sheep -= 1
				animals_lost += 1
				ev.append({"type": "animal_died", "kind": "sheep"})
	else:
		fodderless_days = 0
	# Sickness and death (F46 basics)
	var base: float = {"full": n("sickness_chance_per_person_day_full_ration", 0.0005),
		"half": n("sickness_chance_per_person_day_half_ration", 0.0015),
		"bare": n("sickness_chance_per_person_day_bare_bones", 0.004)}[ration]
	var chance: float = base * (2.0 if info.wet else 1.0) * (n("starvation_sickness_multiplier", 15) if starving else 1.0) * (n("thirst_sickness_multiplier", 25) if thirsty else 1.0)
	var healthy := people - sick.size()
	var new_sick := 0
	for i in healthy:
		if rng.randf() < chance:
			new_sick += 1
			sick.append(int(n("days_a_sick_person_stays_sick", 5)))
	if new_sick > 0:
		ev.append({"type": "sick", "count": new_sick})
	var deaths := 0
	if starving or thirsty:
		var keep: Array[int] = []
		for d in sick:
			if rng.randf() < n("death_chance_per_sick_person_day_when_starving", 0.05):
				deaths += 1
			else:
				keep.append(d)
		sick = keep
	var still: Array[int] = []
	for d in sick:
		if d - 1 > 0:
			still.append(d - 1)
	sick = still
	if deaths > 0:
		people -= deaths
		dead += deaths
		ev.append({"type": "death", "count": deaths})
	# Morale
	var parts := str(k.get("morale_change_per_day_full_half_bare_rations", "1 / -2 / -5")).split("/")
	var rm := {"full": float(parts[0]), "half": float(parts[1]), "bare": float(parts[2])}
	morale += rm[ration]
	if weather == "storm":
		morale += n("morale_change_storm_day", -3)
	morale += deaths * n("morale_change_a_death", -10)
	morale = clampf(morale, 0, 100)
	_log_day()
	# Calendar (F35)
	day += 1
	day_of_year += 1
	watch = 0
	if people <= 0:
		_lose("No one is left to sail her.", ev)
	elif day_of_year > int(n("last_safe_day_at_sea", 273)):
		_lose("Still at sea in October. The autumn storms took the ship.", ev)
	ev.append({"type": "day_end", "day": day})
	return ev

func _lose(reason: String, ev: Array) -> void:
	state = "lost"
	loss_reason = reason
	ev.append({"type": "lost", "reason": reason})

# ------------------------------------------------------------------ calendar and log
func date_text() -> String:
	var months := [["May", 121], ["June", 152], ["July", 182], ["August", 213], ["September", 244], ["October", 274], ["November", 305]]
	for i in range(months.size() - 1, -1, -1):
		if day_of_year >= months[i][1]:
			return "%d %s" % [day_of_year - months[i][1] + 1, months[i][0]]
	return "day %d" % day_of_year

func _log_day() -> void:
	log_rows.append([day, date_text(), leg().name, snappedf(leg_left, 0.1), weather, pace, ration, animal_ration,
		fix_today, snappedf(day_nm, 0.1), snappedf(food, 0.01), snappedf(drink, 0.01), snappedf(fodder, 0.01),
		people, sick.size(), dead, cattle, sheep, roundi(morale), hull, sail_torn])

const LOG_HEADER := "day,date,leg,nm_left,weather,pace,ration,animal_ration,fix,nm_sailed,food,drink,fodder,people,sick,dead,cattle,sheep,morale,hull,sail_torn"

func write_log(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(LOG_HEADER)
	for r in log_rows:
		f.store_line(",".join(r.map(func(x): return str(x))))

# ------------------------------------------------------------------ save (F50)
const SAVE_FIELDS := ["day", "day_of_year", "watch", "leg_i", "leg_left", "sailed_nm", "drift_nm_total", "state", "loss_reason",
	"people", "dead", "cattle", "sheep", "fodderless_days", "food", "fresh_fish", "drink", "fodder", "trade", "hooks", "timber",
	"ration", "animal_ration", "pace", "morale", "hull", "sail_torn", "sail_strain", "weather", "deck", "fix_today", "fished_today",
	"day_nm", "starving_days", "animals_lost", "fixes"]

func to_dict() -> Dictionary:
	var d := {"sick": Array(sick), "rng_seed": str(rng.seed), "rng_state": str(rng.state)}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	return d

func from_dict(knobs: Dictionary, legs_data: Dictionary, d: Dictionary) -> void:
	k = knobs
	legs = legs_data.legs
	wx = legs_data.weather
	for f in SAVE_FIELDS:
		if d.has(f):
			var v = d[f]
			if typeof(get(f)) == TYPE_INT and typeof(v) == TYPE_FLOAT:
				v = int(v)
			set(f, v)
	var fx: Array = []
	for x in fixes:
		fx.append(int(x))
	fixes = fx
	sick.clear()
	for s in d.get("sick", []):
		sick.append(int(s))
	rng.seed = str(d.get("rng_seed", "1")).to_int()     # stored as text: JSON numbers cannot hold 64 bits
	rng.state = str(d.get("rng_state", "0")).to_int()
