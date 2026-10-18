class_name Camp
extends RefCounted
## The summer camp at the Strait (Backlog F06 one camp day loop; groundwork for F16, F17, F46).
## Morning: share the healthy crew between jobs and pick the one you work yourself.
## Day: you play your verb (the joint or the hand line); everyone else works by the knobs.
## Evening: a tally of what the day changed, in the stores, the booths, and the people.

const JOBS := ["build", "fish", "forage", "timber", "hay", "tend"]
const JOB_NAMES := {"build": "Build booths", "fish": "Fish the shore", "forage": "Forage", "timber": "Fell timber", "hay": "Cut hay", "tend": "Tend the sick"}
const PLAYABLE := {"build": "the joint", "fish": "the hand line"}
const RATION := {"full": 1.0, "half": 0.5, "bare": 0.25}

var k: Dictionary
var rng := RandomNumberGenerator.new()
var day := 0
var day_of_year := 160
var people := 24
var sick: Array[int] = []
var dead := 0
var cattle := 2
var sheep := 6
var food := 0.0
var fresh: Array = []          # [person_days, age]
var hooks := 6
var trade := 2
var timber := 0.0
var hay := 0.0
var booths := 0
var longhouse := 0.0         # builder-days put into the longhouse
var joints := 0.0            # builder-days toward the next booth
var morale := 70.0
var ration := "full"
var rain := false
var assign := {"build": 8, "fish": 6, "forage": 4, "timber": 2, "hay": 0, "tend": 0}
var player_job := "build"
var state := "camp"            # camp | ended | lost
var end_reason := ""
var history := {"joints_seated": 0, "joints_split": 0, "fish_watches": 0, "fish_pd": 0.0}
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
	if job == "hay":
		return day_of_year >= int(n("first_hay_day", 213))
	return true

## Clamp assignments to who is fit to work and what each job allows.
func default_assignments() -> void:
	for j in assign:
		if not job_open(j):
			assign[j] = 0
	assign.fish = mini(int(assign.fish), hooks)
	while assigned() > healthy():
		for j in ["tend", "hay", "timber", "forage", "build", "fish"]:
			if assign[j] > 0 and assigned() > healthy():
				assign[j] -= 1

func set_assign(job: String, count: int) -> void:
	if not job_open(job):
		return
	var cap := healthy() - (assigned() - int(assign[job]))
	if job == "fish":
		cap = mini(cap, hooks)
	assign[job] = clampi(count, 0, maxi(0, cap))

func sheltered() -> int:
	return booths * int(n("people_sheltered_per_booth", 8))

func food_days() -> float:
	var per_day: float = people * RATION[ration]
	if per_day <= 0.0:
		return 999.0
	var pd := food * n("food_unit_feeds", 168)
	for f in fresh:
		pd += f[0]
	return pd / per_day

func _roll_weather() -> void:
	rain = rng.randf() < 0.3

## Resolve one day. player = {"job": "build"|"fish"|"", "seated": bool, "person_days": float, "hooks_lost": int}
## An empty player dict means the crew worked without you.
func work_day(player: Dictionary = {}) -> Dictionary:
	default_assignments()
	var tally := {"day": day + 1, "date": date_text(), "rain": rain, "lines": [], "events": []}
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
	_build(j_gain, tally)
	# Fish
	var fishers := mini(int(assign.fish), hooks)
	var fish_pd := 0.0
	var auto_fishers := fishers - (1 if pjob == "fish" and fishers > 0 else 0)
	for i in auto_fishers:
		fish_pd += n("shore_fishing_per_worker_day", 6) * rng.randf_range(0.5, 1.5)
	if pjob == "fish" and fishers > 0:
		fish_pd += float(player.get("person_days", 0.0))
		hooks = maxi(0, hooks - int(player.get("hooks_lost", 0)))
		history.fish_watches += 1
		history.fish_pd += float(player.get("person_days", 0.0))
	if fish_pd > 0:
		fresh.append([fish_pd, 0])
		tally.lines.append("Fish: %d person-days landed." % roundi(fish_pd))
	# Forage, milk
	var forage_pd := int(assign.forage) * n("forage_per_worker_day", 4) * rng.randf_range(0.6, 1.4)
	var cows := maxi(0, cattle - 1)            # one of the cattle is the bull
	var milk_pd := cows * n("milk_per_fed_cow_per_day", 2)
	if forage_pd + milk_pd > 0:
		fresh.append([forage_pd + milk_pd, 1])  # eaten today or tomorrow
		tally.lines.append("Forage and milk: %d person-days." % roundi(forage_pd + milk_pd))
	# Timber, hay
	var t_gain := int(assign.timber) * n("timber_felled_per_worker_day", 0.25)
	timber += t_gain
	if t_gain > 0:
		tally.lines.append("Timber: %.2f units felled (%.1f stacked for the return)." % [t_gain, timber])
	if job_open("hay"):
		var h := int(assign.hay) * n("hay_cut_per_worker_day", 0.5)
		hay += h
		if h > 0:
			tally.lines.append("Hay: %.1f units cut (%.1f in stacks)." % [h, hay])
	# Eat: fresh first, then the stores
	var need: float = people * RATION[ration]
	fresh.sort_custom(func(a, b): return a[1] > b[1])   # oldest first
	for f in fresh:
		var take := minf(need, f[0])
		f[0] -= take
		need -= take
	var spoiled := 0.0
	for f in fresh:
		f[1] += 1
		if f[1] >= 3 and f[0] > 0:
			spoiled += f[0]
			f[0] = 0.0
	fresh = fresh.filter(func(f): return f[0] > 0.01)
	if spoiled > 1:
		tally.lines.append("%d person-days spoiled before they were eaten." % roundi(spoiled))
	food -= need / n("food_unit_feeds", 168)
	var starving := food < 0.0
	if starving:
		food = 0.0
		tally.lines.append("The stores are empty. People go hungry.")
	# Sickness: shelter, rain, hunger
	var base: float = {"full": n("sickness_chance_per_person_day_full_ration", 0.0005),
		"half": n("sickness_chance_per_person_day_half_ration", 0.0015),
		"bare": n("sickness_chance_per_person_day_bare_bones", 0.004)}[ration]
	var unsheltered := maxi(0, people - sheltered_total())
	var new_sick := 0
	var h_now := healthy()
	for i in h_now:
		var exposed := i < unsheltered
		var chance := base * (2.0 if rain else 1.0) * (n("unsheltered_sickness_multiplier", 3) if exposed else 1.0) * (n("starvation_sickness_multiplier", 15) if starving else 1.0)
		if rng.randf() < chance:
			new_sick += 1
			sick.append(int(n("days_a_sick_person_stays_sick", 5)))
	if new_sick > 0:
		tally.lines.append("%d fell sick%s." % [new_sick, " (no roof over them)" if unsheltered > 0 else ""])
	var deaths := 0
	var cure := int(assign.tend) * int(n("tending_shortens_sickness_by", 1))
	var keep: Array[int] = []
	for d in sick:
		if starving and rng.randf() < n("death_chance_per_sick_person_day_when_starving", 0.05):
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
	day += 1
	day_of_year += 1
	_roll_weather()
	if people <= 0:
		state = "lost"
		end_reason = "No one is left at the camp."
	elif day_of_year >= int(n("slice_ends", 244)):
		state = "ended"
		end_reason = "Autumn"
	return tally

## Build queue: booths until every plot is roofed, then the longhouse.
func _build(work: float, tally: Dictionary) -> void:
	if work <= 0.0:
		return
	var per_booth := n("work_to_raise_a_booth", 16)
	var plots := int(n("booth_plots_at_the_camp", 3))
	var hall := n("work_to_raise_the_longhouse", 360)
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
			tally.lines.append("A booth is finished: shelter for %d." % int(n("people_sheltered_per_booth", 8)))
	if booths < plots:
		tally.lines.append("Building: the next booth is %d%% raised." % roundi(joints / per_booth * 100.0))
	elif work > 0.0 and longhouse < hall:
		var before := longhouse
		longhouse = minf(hall, longhouse + work)
		tally.lines.append("Longhouse: %d%% raised." % roundi(longhouse / hall * 100.0))
		if before < hall and longhouse >= hall:
			tally.events.append("longhouse")
			tally.lines.append("The longhouse roof is on. The camp can face a winter.")

func building_target() -> String:
	if booths < int(n("booth_plots_at_the_camp", 3)):
		return "booth %d of %d (%d%%)" % [booths + 1, int(n("booth_plots_at_the_camp", 3)), roundi(joints / n("work_to_raise_a_booth", 16) * 100.0)]
	return "longhouse (%d%%)" % roundi(longhouse / n("work_to_raise_the_longhouse", 360) * 100.0)

func sheltered_total() -> int:
	return sheltered() + (people if longhouse >= n("work_to_raise_the_longhouse", 360) else 0)

func date_text() -> String:
	var months := [["May", 121], ["June", 152], ["July", 182], ["August", 213], ["September", 244], ["October", 274], ["November", 305]]
	for i in range(months.size() - 1, -1, -1):
		if day_of_year >= months[i][1]:
			return "%d %s" % [day_of_year - months[i][1] + 1, months[i][0]]
	return "day %d" % day_of_year

func _log(tally: Dictionary) -> void:
	log_rows.append([day, date_text(), rain, assign.build, assign.fish, assign.forage, assign.timber, assign.hay, assign.tend,
		snappedf(food, 0.01), people, sick.size(), dead, booths, snappedf(longhouse, 0.1), snappedf(timber, 0.01), snappedf(hay, 0.1), hooks, roundi(morale)])

const LOG_HEADER := "day,date,rain,build,fish,forage,timber,hay,tend,food,people,sick,dead,booths,longhouse_days,timber_units,hay,hooks,morale"

func write_log(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line(LOG_HEADER)
	for r in log_rows:
		f.store_line(",".join(r.map(func(x): return str(x))))
