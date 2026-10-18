class_name Camp
extends RefCounted
## The camp at the Strait through the seasons (Backlog F06 camp day, F15 drying rack, F16 livestock and hay,
## F17 booths / longhouse / byre, F46 sickness, F47 winter camp).
## Morning: share the healthy crew between jobs and pick the one you work yourself.
## Day: you play your verb (the joint or the hand line); everyone else works by the knobs.
## Evening: a tally of what the day changed. Summer feeds the camp; what it dries and cuts feeds the winter.

const JOBS := ["build", "fish", "forage", "dry", "timber", "hay", "tend"]
const JOB_NAMES := {"build": "Build", "fish": "Fish the shore", "forage": "Forage", "dry": "Smoke and dry fish",
	"timber": "Fell timber", "hay": "Cut hay", "tend": "Tend the sick"}
const PLAYABLE := {"build": "the joint", "fish": "the hand line"}
const RATION := {"full": 1.0, "half": 0.5, "bare": 0.25}
const MONTHS := [["January", 1], ["February", 32], ["March", 60], ["April", 91], ["May", 121], ["June", 152], ["July", 182],
	["August", 213], ["September", 244], ["October", 274], ["November", 305], ["December", 335]]

var k: Dictionary
var rng := RandomNumberGenerator.new()
var day := 0
var year := 1
var day_of_year := 160
var people := 24
var sick: Array[int] = []
var dead := 0
var cattle := 2
var sheep := 6
var fodderless_days := 0
var food := 0.0                # stores, in food units (dried fish counts here)
var fresh: Array = []          # [person_days, age]
var hooks := 6
var trade := 2
var timber := 0.0
var hay := 0.0
var booths := 0
var longhouse := 0.0           # builder-days put into the longhouse
var byre := 0.0                # builder-days put into the byre
var joints := 0.0              # builder-days toward the next booth
var morale := 70.0
var ration := "full"
var rain := false              # wet day: rain in summer, snow in winter
var assign := {"build": 8, "fish": 6, "forage": 4, "dry": 0, "timber": 2, "hay": 0, "tend": 0}
var player_job := "build"
var state := "camp"            # camp | ended | lost
var end_reason := ""
var history := {"joints_seated": 0, "joints_split": 0, "fish_watches": 0, "fish_pd": 0.0, "dried_pd": 0.0, "animals_lost": 0}
var log_rows: Array = []

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

func setup(knobs: Dictionary, seed: int = 0) -> void:
	k = knobs
	if seed != 0:
		rng.seed = seed
	else:
		rng.randomize()
	food = 1.0
	_roll_weather()

## Carry the ship's company ashore. The hold empties into the camp stores.
func from_voyage(v: Voyage) -> void:
	setup(v.k, v.rng.randi())
	day_of_year = v.day_of_year
	people = v.people
	sick = v.sick.duplicate()
	dead = v.dead
	cattle = v.cattle
	sheep = v.sheep
	food = v.food
	for f in v.fresh_fish:
		fresh.append([f[0], f[1]])
	hooks = v.hooks
	trade = v.trade
	morale = v.morale
	ration = v.ration
	default_assignments()

# ------------------------------------------------------------------ calendar
func season() -> String:
	var d := day_of_year
	if d >= int(n("first_snow", 305)) or d < int(n("spring_thaw", 110)):
		return "winter"
	if d < int(n("departure_day_of_year", 145)):
		return "spring"
	if d < 244:
		return "summer"
	return "autumn"

func is_winter() -> bool:
	return season() == "winter"

func date_text() -> String:
	for i in range(MONTHS.size() - 1, -1, -1):
		if day_of_year >= MONTHS[i][1]:
			return "%d %s" % [day_of_year - MONTHS[i][1] + 1, MONTHS[i][0]]
	return "day %d" % day_of_year

func days_to_snow() -> int:
	var snow := int(n("first_snow", 305))
	return snow - day_of_year if day_of_year < snow else 0

# ------------------------------------------------------------------ crew
func healthy() -> int:
	return people - sick.size()

func assigned() -> int:
	var s := 0
	for j in assign:
		s += int(assign[j])
	return s

func idle() -> int:
	return healthy() - assigned()

func job_open(job: String) -> bool:
	var d := day_of_year
	var season_end := int(n("forage_and_hay_season_ends", 290))
	match job:
		"hay":
			return d >= int(n("first_hay_day", 213)) and d <= season_end
		"forage":
			return not is_winter() and d <= season_end and d >= 140
		"dry":
			return not is_winter()
	return true

func job_note(job: String) -> String:
	if job_open(job):
		return ""
	match job:
		"hay": return "(Aug-Oct)"
		"forage": return "(not in winter)"
		"dry": return "(not in winter)"
	return ""

## Clamp assignments to who is fit to work and what each job allows.
func default_assignments() -> void:
	for j in JOBS:
		if not assign.has(j):
			assign[j] = 0
		if not job_open(j):
			assign[j] = 0
	assign.fish = mini(int(assign.fish), hooks)
	while assigned() > healthy():
		for j in ["tend", "hay", "timber", "dry", "forage", "build", "fish"]:
			if assign[j] > 0 and assigned() > healthy():
				assign[j] -= 1

func set_assign(job: String, count: int) -> void:
	if not job_open(job):
		return
	var cap := healthy() - (assigned() - int(assign[job]))
	if job == "fish":
		cap = mini(cap, hooks)
	assign[job] = clampi(count, 0, maxi(0, cap))

# ------------------------------------------------------------------ shelter, stores, herd
func hall_done() -> bool:
	return longhouse >= n("work_to_raise_the_longhouse", 540)

func byre_done() -> bool:
	return byre >= n("work_to_raise_the_byre", 160)

func sheltered() -> int:
	var per := float(n("people_sheltered_per_booth", 8))
	if is_winter():
		per *= n("booth_shelter_in_winter", 0.5)
	return int(booths * per)

func sheltered_total() -> int:
	return people if hall_done() else mini(people, sheltered())

func food_days() -> float:
	var per_day: float = people * RATION[ration]
	if per_day <= 0.0:
		return 999.0
	var pd := food * n("food_unit_feeds", 168)
	for f in fresh:
		pd += f[0]
	return pd / per_day

## Hay units the herd eats per winter day.
func hay_per_day() -> float:
	var head := cattle + sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)
	var need := head * n("hay_per_head_of_cattle_per_winter_day", 0.06)
	if not byre_done():
		need *= n("hay_needed_without_a_byre", 1.5)
	return need

func hay_days() -> float:
	var d := hay_per_day()
	return 999.0 if d <= 0.0 else hay / d

## Days of winter still ahead (to the thaw), for planning readouts.
func winter_days_left() -> int:
	var thaw := int(n("spring_thaw", 110))
	var snow := int(n("first_snow", 305))
	if day_of_year >= snow:
		return 365 - day_of_year + thaw
	if day_of_year < thaw:
		return thaw - day_of_year
	return 365 - snow + thaw

func _roll_weather() -> void:
	rain = rng.randf() < (0.35 if is_winter() else 0.3)

# ------------------------------------------------------------------ the day
## player = {"job": "build"|"fish"|"", "seated": bool, "person_days": float, "hooks_lost": int}; {} = crew only.
func work_day(player: Dictionary = {}) -> Dictionary:
	default_assignments()
	var winter := is_winter()
	var tally := {"day": day + 1, "date": date_text(), "season": season(), "rain": rain, "lines": [], "events": []}
	var pjob: String = player.get("job", "")
	# Build
	var builders := int(assign.build)
	var auto_builders := builders - (1 if pjob == "build" and builders > 0 else 0)
	var j_gain := float(auto_builders)
	if pjob == "build" and builders > 0:
		if player.get("seated", false):
			j_gain += n("your_seated_joint_counts_as", 3)
			history.joints_seated += 1
			tally.lines.append("Your joint seated home.")
		else:
			history.joints_split += 1
			tally.lines.append("Your log split; that day's work is lost.")
	if winter:
		j_gain *= n("winter_building_factor", 0.5)
	_build(j_gain, tally)
	# Fish
	var fishers := mini(int(assign.fish), hooks)
	var fish_pd := 0.0
	var auto_fishers := fishers - (1 if pjob == "fish" and fishers > 0 else 0)
	var fish_factor := n("winter_shore_fishing_factor", 0.3) if winter else 1.0
	for i in auto_fishers:
		fish_pd += n("shore_fishing_per_worker_day", 6) * rng.randf_range(0.5, 1.5) * fish_factor
	if pjob == "fish" and fishers > 0:
		var mine := float(player.get("person_days", 0.0)) * fish_factor
		fish_pd += mine
		hooks = maxi(0, hooks - int(player.get("hooks_lost", 0)))
		history.fish_watches += 1
		history.fish_pd += mine
	if fish_pd > 0:
		fresh.append([fish_pd, 0])
		tally.lines.append("Fish: %d person-days landed%s." % [roundi(fish_pd), " through the ice" if winter else ""])
	# Forage and milk
	var forage_pd := 0.0
	if job_open("forage"):
		forage_pd = int(assign.forage) * n("forage_per_worker_day", 4) * rng.randf_range(0.6, 1.4)
	var cows := maxi(0, cattle - 1)            # one of the cattle is the bull
	var fed := not winter or hay > 0.0
	var milk_pd := cows * n("milk_per_fed_cow_per_day", 2) * (n("winter_milk_factor", 0.3) if winter else 1.0) * (1.0 if fed else 0.0)
	if forage_pd + milk_pd > 0.5:
		fresh.append([forage_pd + milk_pd, 1])  # eaten today or tomorrow
		tally.lines.append("Forage and milk: %d person-days." % roundi(forage_pd + milk_pd))
	# Timber and hay
	var t_gain := int(assign.timber) * n("timber_felled_per_worker_day", 0.05)
	timber += t_gain
	if t_gain > 0:
		tally.lines.append("Timber: %.2f units felled (%.1f stacked for the return)." % [t_gain, timber])
	if job_open("hay"):
		var h := int(assign.hay) * n("hay_cut_per_worker_day", 0.15)
		hay += h
		if h > 0:
			tally.lines.append("Hay: %.1f units cut (%.1f in stacks, %d days of winter feed)." % [h, hay, roundi(minf(hay_days(), 999.0))])
	# Eat: fresh first, then the stores
	var need: float = people * RATION[ration]
	fresh.sort_custom(func(a, b): return a[1] > b[1])   # oldest first
	for f in fresh:
		var take := minf(need, f[0])
		f[0] -= take
		need -= take
	# The rack: what is left over is smoked and dried into stores (F15). Fair days only.
	var dryers := int(assign.dry)
	if dryers > 0 and not rain:
		var cap := dryers * n("drying_per_worker_day", 15)
		var dried := 0.0
		for f in fresh:
			var take2 := minf(cap - dried, f[0])
			f[0] -= take2
			dried += take2
		if dried > 0.0:
			var kept := dried * n("dried_fish_yield", 0.9)
			food += kept / n("food_unit_feeds", 168)
			history.dried_pd += kept
			tally.lines.append("The rack: %d person-days smoked and dried into stores." % roundi(kept))
	elif dryers > 0:
		tally.lines.append("Too wet to dry fish today.")
	var spoiled := 0.0
	for f in fresh:
		f[1] += 1
		if f[1] >= 3 and f[0] > 0:
			spoiled += f[0]
			f[0] = 0.0
	fresh = fresh.filter(func(f): return f[0] > 0.01)
	if spoiled > 1:
		tally.lines.append("%d person-days spoiled before they were eaten or dried." % roundi(spoiled))
	food -= need / n("food_unit_feeds", 168)
	var starving := food < 0.0
	if starving:
		food = 0.0
		tally.lines.append("The stores are empty. People go hungry.")
	# The herd: grazing in the open seasons, hay in winter
	if winter and (cattle + sheep) > 0:
		var eat := hay_per_day()
		if hay >= eat:
			hay -= eat
			fodderless_days = 0
		else:
			hay = 0.0
			fodderless_days += 1
			tally.lines.append("No hay. The animals are bawling in the %s." % ("byre" if byre_done() else "cold"))
			if fodderless_days >= int(n("fodderless_days_before_an_animal_dies", 3)):
				fodderless_days = 0
				if cattle > 0:
					cattle -= 1
					tally.lines.append("A cow starved. The byre is a tomb without hay.")
				elif sheep > 0:
					sheep -= 1
					tally.lines.append("A sheep starved.")
				history.animals_lost += 1
	# Sickness: shelter, weather, hunger, cold
	var base: float = {"full": n("sickness_chance_per_person_day_full_ration", 0.0005),
		"half": n("sickness_chance_per_person_day_half_ration", 0.0015),
		"bare": n("sickness_chance_per_person_day_bare_bones", 0.004)}[ration]
	if winter:
		base *= n("winter_sickness_factor", 1.5)
	var unsheltered := maxi(0, people - sheltered_total())
	var exposed_mult := n("unsheltered_winter_sickness_multiplier", 6) if winter else n("unsheltered_sickness_multiplier", 3)
	var new_sick := 0
	var h_now := healthy()
	for i in h_now:
		var exposed := i < unsheltered
		var chance := base * (2.0 if rain else 1.0) * (exposed_mult if exposed else 1.0) * (n("starvation_sickness_multiplier", 15) if starving else 1.0)
		if rng.randf() < chance:
			new_sick += 1
			sick.append(int(n("days_a_sick_person_stays_sick", 5)))
	if new_sick > 0:
		tally.lines.append("%d fell sick%s." % [new_sick, " (no roof over them)" if unsheltered > 0 else ""])
	var deaths := 0
	var cure := int(assign.tend) * int(n("tending_shortens_sickness_by", 1))
	var keep: Array[int] = []
	var sick_exposed := mini(sick.size(), unsheltered)
	for i in sick.size():
		var d := sick[i]
		var die_chance := 0.0
		if starving:
			die_chance += n("death_chance_per_sick_person_day_when_starving", 0.05)
		if winter and i < sick_exposed:
			die_chance += n("death_chance_per_exposed_sick_person_day_in_winter", 0.02)
		if die_chance > 0.0 and rng.randf() < die_chance:
			deaths += 1
			continue
		var left := d - 1
		if cure > 0:
			left -= 1
			cure -= 1
		if left > 0:
			keep.append(left)
	sick = keep
	if deaths > 0:
		people -= deaths
		dead += deaths
		morale = clampf(morale + deaths * n("morale_change_a_death", -10), 0, 100)
		tally.lines.append("%d died. A cairn goes up above the shore." % deaths)
	var parts := str(k.get("morale_change_per_day_full_half_bare_rations", "1 / -2 / -5")).split("/")
	morale = clampf(morale + float(parts[["full", "half", "bare"].find(ration)]), 0, 100)
	tally.idle = idle()
	_log(tally)
	_advance_calendar(tally)
	return tally

func _advance_calendar(tally: Dictionary) -> void:
	var was := season()
	day += 1
	day_of_year += 1
	if day_of_year > 365:
		day_of_year = 1
		year += 1
	_roll_weather()
	var now := season()
	if now != was:
		tally.events.append("season")
		match now:
			"winter": tally.lines.append("First snow. Foraging and the rack are done for the year; the herd lives on hay now.")
			"spring": tally.lines.append("The thaw. Meltwater in the brook, and the first green on the terrace.")
			"autumn": tally.lines.append("Autumn: the days shorten. %d days to the first snow." % days_to_snow())
	if people <= 0:
		state = "lost"
		end_reason = "No one is left at the camp."
	elif year >= 2 and day_of_year >= int(n("camp_build_ends", 145)) and day_of_year < int(n("first_snow", 305)):
		state = "ended"
		end_reason = "Spring"

# ------------------------------------------------------------------ building
## Build queue: booths until every plot is roofed, then the longhouse, then the byre.
func _build(work: float, tally: Dictionary) -> void:
	if work <= 0.0:
		return
	var per_booth := n("work_to_raise_a_booth", 16)
	var plots := int(n("booth_plots_at_the_camp", 3))
	var hall := n("work_to_raise_the_longhouse", 540)
	var byre_need := n("work_to_raise_the_byre", 160)
	while work > 0.0 and booths < plots:
		var need := per_booth - joints
		var put := minf(need, work)
		joints += put
		work -= put
		if joints >= per_booth - 0.001:
			joints = 0.0
			booths += 1
			morale = clampf(morale + 5.0, 0, 100)
			tally.events.append("booth")
			tally.lines.append("A booth is finished: shelter for %d in summer." % int(n("people_sheltered_per_booth", 8)))
	if booths < plots:
		tally.lines.append("Building: the next booth is %d%% raised." % roundi(joints / per_booth * 100.0))
		return
	if work > 0.0 and longhouse < hall:
		var put2 := minf(hall - longhouse, work)
		longhouse += put2
		work -= put2
		if longhouse >= hall:
			tally.events.append("longhouse")
			morale = clampf(morale + 10.0, 0, 100)
			tally.lines.append("The longhouse roof is on. Everyone sleeps warm this winter.")
		else:
			tally.lines.append("Longhouse: %d%% raised." % roundi(longhouse / hall * 100.0))
	if work > 0.0 and byre < byre_need:
		byre = minf(byre_need, byre + work)
		if byre >= byre_need:
			tally.events.append("byre")
			tally.lines.append("The byre is finished. The herd will winter under a roof.")
		else:
			tally.lines.append("Byre: %d%% raised." % roundi(byre / byre_need * 100.0))

func building_target() -> String:
	if booths < int(n("booth_plots_at_the_camp", 3)):
		return "booth %d of %d (%d%%)" % [booths + 1, int(n("booth_plots_at_the_camp", 3)), roundi(joints / n("work_to_raise_a_booth", 16) * 100.0)]
	if not hall_done():
		return "longhouse (%d%%)" % roundi(longhouse / n("work_to_raise_the_longhouse", 540) * 100.0)
	if not byre_done():
		return "byre (%d%%)" % roundi(byre / n("work_to_raise_the_byre", 160) * 100.0)
	return "all built"

func build_short() -> String:
	if booths < int(n("booth_plots_at_the_camp", 3)):
		return "booth"
	if not hall_done():
		return "longhouse"
	if not byre_done():
		return "byre"
	return "repairs"

# ------------------------------------------------------------------ save and log
const SAVE_FIELDS := ["day", "year", "day_of_year", "people", "dead", "cattle", "sheep", "fodderless_days", "food", "fresh", "hooks",
	"trade", "timber", "hay", "booths", "longhouse", "byre", "joints", "morale", "ration", "rain", "assign", "player_job", "state",
	"end_reason", "history"]

func to_dict() -> Dictionary:
	var d := {"sick": Array(sick), "rng_seed": rng.seed, "rng_state": rng.state}
	for f in SAVE_FIELDS:
		d[f] = get(f)
	return d

func from_dict(knobs: Dictionary, d: Dictionary) -> void:
	k = knobs
	for f in SAVE_FIELDS:
		if d.has(f):
			var v = d[f]
			if typeof(get(f)) == TYPE_INT and typeof(v) == TYPE_FLOAT:
				v = int(v)
			set(f, v)
	sick.clear()
	for s in d.get("sick", []):
		sick.append(int(s))
	rng.seed = int(d.get("rng_seed", 1))
	rng.state = int(d.get("rng_state", 0))

func _log(tally: Dictionary) -> void:
	log_rows.append([day, year, date_text(), season(), rain, assign.build, assign.fish, assign.forage, assign.dry, assign.timber, assign.hay, assign.tend,
		snappedf(food, 0.01), people, sick.size(), dead, booths, snappedf(longhouse, 0.1), snappedf(byre, 0.1), snappedf(timber, 0.01),
		snappedf(hay, 0.1), cattle, sheep, hooks, roundi(morale)])

const LOG_HEADER := "day,year,date,season,wet,build,fish,forage,dry,timber,hay,tend,food,people,sick,dead,booths,longhouse_days,byre_days,timber_units,hay_units,cattle,sheep,hooks,morale"

func write_log(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(LOG_HEADER)
	for r in log_rows:
		f.store_line(",".join(r.map(func(x): return str(x))))
