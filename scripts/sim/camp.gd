class_name Camp
extends RefCounted
## The camp at the Strait through the seasons (Backlog F06 camp day, F15 drying rack, F16 livestock and hay,
## F17 booths / longhouse / byre, F46 sickness, F47 winter camp).
## Morning: share the healthy crew between jobs and pick the one you work yourself.
## Day: you play your verb (the joint or the hand line); everyone else works by the knobs.
## Evening: a tally of what the day changed. Summer feeds the camp; what it dries and cuts feeds the winter.

const JOBS := ["build", "fish", "hunt", "forage", "dry", "timber", "hay", "tend"]
const JOB_NAMES := {"build": "Build", "fish": "Fish the shore", "hunt": "Hunt caribou", "forage": "Forage", "dry": "Smoke and dry",
	"timber": "Fell timber", "hay": "Cut hay", "tend": "Tend the sick"}
const PLAYABLE := {"build": "the joint", "fish": "the hand line", "hunt": "the hunt", "forage": "the berry patch", "dry": "the smoke rack"}
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
var assign := {"build": 8, "fish": 6, "hunt": 0, "forage": 4, "dry": 0, "timber": 2, "hay": 0, "tend": 0}
var hunt_far := false          # hunters range to the far grounds: more caribou, and fear can rise
var fish_net := false          # when you fish yourself: the net from the boat instead of the hand line (F14)
var outfit := ""               # F22, carried ashore from the voyage
var crew := Crew.new()         # F23
var smith_days := 0
var nets := 1
var fear := 0.0                # Goodwill / fear clock (F19): read by the market when it comes
var hides := 0                 # trade goods from the hunt
var patch_health := 1.0        # forage patches this season; greedy picking thins them until spring
# The market (F19-F21). Visitors are neutral placeholders until the cultural review (F59).
var goodwill := 0.0
var cloth_strips := 0          # madder-red cloth, cut into strips for trade
var iron_blades := 0
var pelts := 0                 # furs from the market: return cargo
var market_today := false
var market_pelts := 0          # pelts the visitors brought today
var weapon_request := false
var penned_today := false
var quiet_days := 0
var player_job := "build"
var state := "camp"            # camp | abandoned | lost | stranded
var second_spring := false     # the camp came through its first winter (the G1 milestone)
var hull := 0                  # the knarr drawn up on the shingle: 0 sound .. 3 holed
var shed := 0.0                # builder-days into the boat shed
var timber_felled := 0.0
var timber_winter := 0.0       # timber felled in winter seasons better (F25 grade)
var sailed := 0                # times the knarr has sailed home from here
var knarr_here := true         # the knarr is drawn up at the camp (false while she is away)
var relief_came := false       # the relief has reached the camp (F30)
var hop := {}                  # F27: the party away at Hóp {people, crew, days_left}
var hop_done := false
var vines := 0.0               # cargo units of vines and grapes from Hóp
var end_reason := ""
var history := {"joints_seated": 0, "joints_split": 0, "fish_watches": 0, "fish_pd": 0.0, "dried_pd": 0.0, "animals_lost": 0,
	"kills": 0, "hunts_played": 0, "forage_played": 0, "markets": 0, "weapon_sales": 0, "bull_loose": 0, "raids": 0}
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
	nets = int(n("nets_carried", 1))
	crew.build({"roles": {"skipper": 1, "pilot": 1, "shipwright": 1, "smith": 1, "healer": 1, "householder": 1, "hunter": 1}}, people, rng)
	cloth_strips = 20    # the default HoldCheck load carries two units of trade goods: cloth and iron
	iron_blades = 5
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
	cloth_strips = int(n("red_cloth_strips_per_trade_unit", 20)) * v.cloth_units
	iron_blades = int(n("iron_blades_per_trade_unit", 5)) * v.iron_units
	morale = v.morale
	ration = v.ration
	hull = v.hull
	outfit = v.outfit
	nets = v.nets
	crew.from_array(v.crew.to_array())
	default_assignments()

# ------------------------------------------------------------------ calendar
## An outfit's multiplier from the Assumptions sheet, or the fallback.
func om(key: String, fallback: float = 1.0) -> float:
	if outfit == "":
		return fallback
	return float(k.get(outfit + "_" + key, fallback))

## How long a new sickness lasts: a healer saves a day.
func sick_days() -> int:
	var d := int(n("days_a_sick_person_stays_sick", 5))
	if crew.has_role("healer"):
		d -= int(n("role_sick_days_saved_by_a_healer", 1))
	return maxi(1, d)

func byre_need() -> float:
	return n("work_to_raise_the_byre", 160) * om("byre_work_multiplier")

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
	for key in ["kills", "hunts_played", "forage_played", "markets", "weapon_sales", "bull_loose", "raids"]:
		if not history.has(key):
			history[key] = 0
	assign.fish = mini(int(assign.fish), hooks)
	while assigned() > healthy():
		for j in ["tend", "hay", "timber", "dry", "forage", "hunt", "build", "fish"]:
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
	return byre >= byre_need()

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
	var need := head * n("hay_per_head_of_cattle_per_winter_day", 0.06) / om("fodder_and_hay_go_further")
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
## What you play when you work a job yourself.
func playable(job: String) -> String:
	if job == "fish" and fish_net and nets > 0:
		return "the net"
	return PLAYABLE.get(job, "")

## player = {"job": "build"|"fish"|"", "seated": bool, "person_days": float, "hooks_lost": int}; {} = crew only.
## Smoke rack: {"job": "dry", "quality": 0..1, "spoiled": bool}.
func work_day(player: Dictionary = {}) -> Dictionary:
	default_assignments()
	var held_back := ""
	if penned_today:
		for j in ["build", "timber", "forage", "hunt", "fish", "dry", "hay"]:
			if int(assign[j]) > 0:
				assign[j] -= 1
				held_back = j
				break
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
	_build(j_gain * om("building_multiplier"), tally)
	# Fish
	var fishers := mini(int(assign.fish), hooks)
	var fish_pd := 0.0
	var auto_fishers := fishers - (1 if pjob == "fish" and fishers > 0 else 0)
	var fish_factor := n("winter_shore_fishing_factor", 0.3) if winter else 1.0
	for i in auto_fishers:
		fish_pd += n("shore_fishing_per_worker_day", 6) * rng.randf_range(0.5, 1.5) * fish_factor * om("shore_fishing_multiplier")
	if pjob == "fish" and fishers > 0:
		var mine := float(player.get("person_days", 0.0)) * fish_factor
		fish_pd += mine
		hooks = maxi(0, hooks - int(player.get("hooks_lost", 0)))
		history.fish_watches += 1
		history.fish_pd += mine
	if fish_pd > 0:
		fresh.append([fish_pd, 0])
		tally.lines.append("Fish: %d person-days landed%s." % [roundi(fish_pd), " through the ice" if winter else ""])
	# Hunt
	var hunters := int(assign.hunt)
	var auto_hunters := hunters - (1 if pjob == "hunt" and hunters > 0 else 0)
	var meat := 0.0
	var kill_p := n("hunt_kill_chance_per_hunter_day", 0.2) * (n("far_grounds_kill_bonus", 1.4) if hunt_far else 1.0) * (n("winter_hunting_factor", 0.7) if winter else 1.0) \
		* (n("role_kill_chance_multiplier_with_a_hunter", 1.15) if crew.has_role("hunter") else 1.0)
	var kills := 0
	for i in auto_hunters:
		if rng.randf() < kill_p:
			kills += 1
			meat += n("meat_per_kill", 75) * rng.randf_range(0.8, 1.2)
		if hunt_far and rng.randf() < n("far_grounds_fear_chance_per_hunter_day", 0.05):
			fear += 1.0
			tally.lines.append("Hunters ranging far were seen. Fear rises (%d of %d)." % [int(fear), int(n("fear_cap", 5))])
	if pjob == "hunt" and hunters > 0:
		history.hunts_played += 1
		if player.get("kill", false):
			kills += 1
			meat += float(player.get("person_days", 0.0))
			tally.lines.append("Your arrow flew true.")
		if player.get("fear_tick", false):
			fear += 1.0
			tally.lines.append("You were seen chasing far from camp. Fear rises (%d of %d)." % [int(fear), int(n("fear_cap", 5))])
	if kills > 0:
		hides += kills
		history.kills += kills
		fresh.append([meat, 0])
		tally.lines.append("Hunt: %d caribou, %d person-days of meat and %d hide%s." % [kills, roundi(meat), kills, "" if kills == 1 else "s"])
	elif hunters > 0:
		tally.lines.append("The hunters came back empty-handed.")
	fear = clampf(fear, 0.0, n("fear_cap", 5))
	# Forage and milk
	var forage_pd := 0.0
	if job_open("forage"):
		var foragers := int(assign.forage)
		var auto_foragers := foragers - (1 if pjob == "forage" and foragers > 0 else 0)
		forage_pd = auto_foragers * n("forage_per_worker_day", 4) * rng.randf_range(0.6, 1.4) * patch_health * om("forage_multiplier")
		if pjob == "forage" and foragers > 0:
			history.forage_played += 1
			forage_pd += float(player.get("person_days", 0.0))
			var ph := float(player.get("patch_health", 1.0))
			if ph < 0.99:
				patch_health = clampf(patch_health - (1.0 - ph) * n("stripped_patch_damage_carried_to_the_season", 0.5), 0.2, 1.0)
				tally.lines.append("The patches are thinner for the stripping (%d%% left this season)." % roundi(patch_health * 100))
	var cows := maxi(0, cattle - 1)            # one of the cattle is the bull
	var fed := not winter or hay > 0.0
	var milk_pd := cows * milk_per_cow() * (n("winter_milk_factor", 0.3) if winter else 1.0) * (1.0 if fed else 0.0)
	if forage_pd + milk_pd > 0.5:
		fresh.append([forage_pd + milk_pd, 1])  # eaten today or tomorrow
		tally.lines.append("Forage and milk: %d person-days." % roundi(forage_pd + milk_pd))
	# Timber and hay
	var t_gain := int(assign.timber) * n("timber_felled_per_worker_day", 0.05) * om("timber_felled_multiplier")
	timber += t_gain
	timber_felled += t_gain
	if winter:
		timber_winter += t_gain
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
		var per := n("drying_per_worker_day", 15)
		var mine := pjob == "dry"
		var cap := (dryers - (1 if mine else 0)) * per
		var dried := _take_fresh(cap)
		var kept := dried * n("dried_fish_yield", 0.9)
		if mine:
			# your own fire: a well-kept one cures more and loses nothing; a case-hardened rack is lost
			var q := clampf(float(player.get("quality", 0.0)), 0.0, 1.0)
			var my_dried := _take_fresh(per * n("tended_rack_capacity_at_the_best_fire", 1.5) * maxf(q, 0.3))
			history.racks_played = int(history.get("racks_played", 0)) + 1
			if player.get("spoiled", false):
				tally.lines.append("Your rack spoiled: %d person-days of fish crusted and rotted." % roundi(my_dried))
			else:
				var my_kept := my_dried * lerpf(n("tended_rack_yield_at_the_worst_fire", 0.6), n("tended_rack_yield_at_the_best_fire", 1.0), q)
				kept += my_kept
				tally.lines.append("Your fire cured %d person-days on the rack." % roundi(my_kept))
		if kept > 0.0:
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
			sick.append(sick_days())
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
		var names := crew.sync_to(people, rng)
		tally.lines.append("%s died. A cairn goes up above the shore." % (", ".join(names) if not names.is_empty() else "%d" % deaths))
	_smith(tally)
	var parts := str(k.get("morale_change_per_day_full_half_bare_rations", "1 / -2 / -5")).split("/")
	morale = clampf(morale + float(parts[["full", "half", "bare"].find(ration)]), 0, 100)
	if held_back != "":
		assign[held_back] += 1
		tally.lines.append("One of the crew stayed with the bull all day.")
	_hop_day(tally)
	penned_today = false
	market_today = false
	weapon_request = false
	_fear_week(tally)
	tally.idle = idle()
	_log(tally)
	_advance_calendar(tally)
	return tally

## Take up to cap person-days of fresh food off the pile for the rack, oldest first.
func _take_fresh(cap: float) -> float:
	var got := 0.0
	for f in fresh:
		var take := minf(cap - got, f[0])
		f[0] -= take
		got += take
	return got

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
			"spring":
				patch_health = 1.0
				tally.lines.append("The thaw. Meltwater in the brook, and the first green on the terrace.")
			"autumn": tally.lines.append("Autumn: the days shorten. %d days to the first snow." % days_to_snow())
	if people <= 0:
		state = "lost"
		end_reason = "No one is left at the camp."
	elif year >= int(n("full_game_length", 3)) and sailed == 0 and day_of_year >= int(n("first_snow", 305)):
		state = "stranded"
		end_reason = "The third winter came, and no ship had gone home. A camp that only feeds itself is forgotten when its ship does not return."
	elif year >= 2 and not second_spring and day_of_year >= int(n("camp_build_ends", 145)) and day_of_year < int(n("first_snow", 305)):
		second_spring = true
		tally.events.append("second_spring")

# ------------------------------------------------------------------ the market (F19, F20, F21)
## Morning check: do visitors come to the shore today? Sets market_today and what they bring.
func roll_market() -> bool:
	market_today = false
	weapon_request = false
	if is_winter() or day < int(n("first_market", 15)) or fear >= n("fear_cap", 5):
		return false
	var chance := n("market_chance_per_day", 0.06) + goodwill * n("market_chance_per_point_of_goodwill", 0.01)
	if rng.randf() >= chance:
		return false
	market_today = true
	var span := str(k.get("pelts_the_visitors_bring", "3 to 8")).split(" to ")
	market_pelts = rng.randi_range(int(span[0]), int(span[-1]))
	weapon_request = goodwill >= 2.0 and iron_blades > 0 and rng.randf() < n("weapon_request_chance_per_market", 0.25)
	return true

func pelt_price() -> float:
	return maxf(0.8, n("trade_value_for_one_pelt", 2.0) * om("pelt_price_multiplier") * (1.0 - goodwill * n("price_discount_per_point_of_goodwill", 0.05)))

## Most milk the camp can spare for one market: about five days of the cows' milk.
func milk_to_spare() -> int:
	var cows := maxi(0, cattle - 1)
	var cap := cows * milk_per_cow() * 5.0
	return int(minf(cap, food * n("food_unit_feeds", 168)))

func offer_value(cloth: int, milk_pd: int) -> float:
	return float(cloth) + float(milk_pd) / n("milk_per_trade_value", 10)

func pelts_for(cloth: int, milk_pd: int) -> int:
	return mini(market_pelts, floori(offer_value(cloth, milk_pd) / pelt_price() + 0.0001))

## Resolve a market. cloth = strips offered, milk_pd = person-days of milk offered.
func do_trade(cloth: int, milk_pd: int, bull_penned: bool) -> Dictionary:
	var out := {"pelts": 0, "goodwill": 0.0, "fear": 0.0, "lines": []}
	if not market_today:
		return out
	history.markets += 1
	cloth = clampi(cloth, 0, cloth_strips)
	milk_pd = clampi(milk_pd, 0, milk_to_spare())
	penned_today = bull_penned and not byre_done()
	# the bull (F21)
	if not byre_done() and not bull_penned and cattle > 0 and rng.randf() < n("bull_breaks_loose_chance", 0.25):
		history.bull_loose += 1
		fear += n("fear_from_the_bull", 2)
		goodwill = maxf(0.0, goodwill - 1.0)
		out.fear += n("fear_from_the_bull", 2)
		out.lines.append("The bull broke loose and charged out bellowing. The visitors scattered to their boats.")
		quiet_days = 0
		fear = clampf(fear, 0.0, n("fear_cap", 5))
		market_today = false
		return out
	var value := offer_value(cloth, milk_pd)
	if value <= 0.0:
		goodwill = maxf(0.0, goodwill - 1.0)
		out.goodwill = -1.0
		out.lines.append("We sent them away with nothing. They will remember it.")
		market_today = false
		return out
	var got := pelts_for(cloth, milk_pd)
	cloth_strips -= cloth
	food = maxf(0.0, food - float(milk_pd) / n("food_unit_feeds", 168))
	pelts += got
	out.pelts = got
	var gw := 1.0
	if got > 0 and value >= got * pelt_price() * 1.3:
		gw = 2.0
	gw *= om("goodwill_gain_multiplier")
	goodwill = minf(n("goodwill_cap", 10), goodwill + gw)
	out.goodwill = gw
	out.lines.append("Trade at the shore: %d strips of red cloth and %d person-days of milk for %d pelts." % [cloth, milk_pd, got])
	if gw >= 2.0:
		out.lines.append("They went away pleased with the bargain.")
	return out

## The visitors ask for iron blades (F21). Selling caps fear; refusing costs a little goodwill.
func answer_weapon_request(sell: bool) -> Dictionary:
	var out := {"pelts": 0, "lines": []}
	weapon_request = false
	if sell and iron_blades > 0:
		var blades := mini(2, iron_blades)
		iron_blades -= blades
		var extra := roundi(blades * n("weapon_sale_pelt_multiplier", 3.0))
		pelts += extra
		out.pelts = extra
		history.weapon_sales += 1
		fear = clampf(fear + n("fear_from_a_weapon_sale", 2), 0.0, n("fear_cap", 5))
		quiet_days = 0
		out.lines.append("You traded %d iron blades for %d pelts. Word of it spreads; fear rises." % [blades, extra])
	else:
		goodwill = maxf(0.0, goodwill - 0.5)
		out.lines.append("You refused the blades, as Karlsefni did. They were disappointed, but the peace holds.")
	market_today = false
	return out

## Fear fades over quiet weeks; at the cap, trade breaks and the camp is at risk.
func _fear_week(tally: Dictionary) -> void:
	quiet_days += 1
	if quiet_days >= 7:
		quiet_days = 0
		if fear >= n("fear_cap", 5) and rng.randf() < n("raid_chance_per_week_at_the_fear_cap", 0.3):
			history.raids += 1
			if sheep > 0 or cattle > 0:
				if sheep > 0:
					sheep -= 1
				else:
					cattle -= 1
				tally.lines.append("In the night, animals were driven off from the edge of the camp. Trade is broken.")
			else:
				sick.append(sick_days())
				tally.lines.append("A clash at the brook: one of the crew is hurt. Trade is broken.")
		elif fear > 0.0:
			fear = maxf(0.0, fear - n("fear_eased_per_quiet_week", 0.5))

## Milk a fed cow gives a day: more with a householder at the dairy, more again for a farm household.
func milk_per_cow() -> float:
	return n("milk_per_fed_cow_per_day", 2) * om("milk_multiplier") \
		* (n("role_milk_multiplier_with_a_householder", 1.2) if crew.has_role("householder") else 1.0)

## Weekly: the shipwright mends the knarr; the smith works a blade of trade iron into hooks when hooks run short.
func _smith(tally: Dictionary) -> void:
	smith_days += 1
	if smith_days < 7:
		return
	smith_days = 0
	if hull > 0 and crew.has_role("shipwright") and timber >= 0.2:
		hull = maxi(0, hull - int(n("hull_levels_mended_a_week_ashore_with_a_shipwright", 1)))
		timber -= 0.2
		tally.lines.append("The shipwright drove new strakes into the knarr (%s)." % ["sound", "strained", "sprung", "holed"][hull])
	if crew.has_role("smith") and iron_blades > 0 and hooks < int(n("role_hooks_the_camp_keeps_before_the_smith_works_iron", 6)):
		iron_blades -= 1
		var made := int(n("role_hooks_a_smith_makes_from_one_iron_blade", 4))
		hooks += made
		history.hooks_made = int(history.get("hooks_made", 0)) + made
		var who: String = str(crew.holders("smith")[0].name).split(" ")[0]
		tally.lines.append("%s the smith beat a blade of trade iron into %d hooks." % [who, made])

func trade_broken() -> bool:
	return fear >= n("fear_cap", 5)

# ------------------------------------------------------------------ building
## Build queue: booths until every plot is roofed, then the longhouse, then the byre.
func _build(work: float, tally: Dictionary) -> void:
	if work <= 0.0:
		return
	var per_booth := n("work_to_raise_a_booth", 16)
	var plots := int(n("booth_plots_at_the_camp", 3))
	var hall := n("work_to_raise_the_longhouse", 540)
	var byre_need := byre_need()
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
		var put3 := minf(byre_need - byre, work)
		byre += put3
		work -= put3
		if byre >= byre_need:
			tally.events.append("byre")
			tally.lines.append("The byre is finished. The herd will winter under a roof.")
		else:
			tally.lines.append("Byre: %d%% raised." % roundi(byre / byre_need * 100.0))
	var shed_need := n("work_to_raise_the_boat_shed", 80)
	if work > 0.0 and byre >= byre_need and shed < shed_need:
		shed = minf(shed_need, shed + work)
		if shed >= shed_need:
			tally.events.append("shed")
			tally.lines.append("The boat shed is roofed. The knarr can be readied for the voyage home.")
		else:
			tally.lines.append("Boat shed: %d%% raised." % roundi(shed / shed_need * 100.0))

func building_target() -> String:
	if booths < int(n("booth_plots_at_the_camp", 3)):
		return "booth %d of %d (%d%%)" % [booths + 1, int(n("booth_plots_at_the_camp", 3)), roundi(joints / n("work_to_raise_a_booth", 16) * 100.0)]
	if not hall_done():
		return "longhouse (%d%%)" % roundi(longhouse / n("work_to_raise_the_longhouse", 540) * 100.0)
	if not byre_done():
		return "byre (%d%%)" % roundi(byre / byre_need() * 100.0)
	if not shed_done():
		return "boat shed (%d%%)" % roundi(shed / n("work_to_raise_the_boat_shed", 80) * 100.0)
	return "all built"

func build_short() -> String:
	if booths < int(n("booth_plots_at_the_camp", 3)):
		return "booth"
	if not hall_done():
		return "longhouse"
	if not byre_done():
		return "byre"
	if not shed_done():
		return "boat shed"
	return "repairs"

func shed_done() -> bool:
	return shed >= n("work_to_raise_the_boat_shed", 80)

## Share of the timber felled in winter (seasoned, straighter: the appraisal's grade, F25).
func winter_share() -> float:
	return 0.0 if timber_felled <= 0.0 else clampf(timber_winter / timber_felled, 0.0, 1.0)

## What still stands between the camp and the voyage home (F24). Empty means the return gate is open.
func return_gate() -> Array:
	var why: Array = []
	if not knarr_here:
		why.append("The knarr is away at Eriksfjord. She comes back with the relief.")
	elif year < 2 or day_of_year < int(n("return_window_opens", 152)) or is_winter():
		why.append("The return window opens on 1 June of the second summer.")
	if not shed_done():
		why.append("Raise the boat shed (%d%%)." % roundi(shed / n("work_to_raise_the_boat_shed", 80) * 100.0))
	if hull > 1:
		why.append("The hull is %s: a shipwright must mend her." % ["sound", "strained", "sprung", "holed"][hull])
	if timber < n("timber_units_to_open_a_return", 4):
		why.append("Stack at least %d units of timber (%.1f)." % [int(n("timber_units_to_open_a_return", 4)), timber])
	if not crew.can_sail_home(int(n("role_fewest_crew_to_sail_a_knarr_home", 10))):
		why.append("She needs a skipper or a pilot and %d hands." % int(n("role_fewest_crew_to_sail_a_knarr_home", 10)))
	return why

# ------------------------------------------------------------------ the Hóp push (F27)
## What stands in the way of a push south to Hóp this summer. Empty means the knarr can go.
func hop_gate(party: int = -1) -> Array:
	var why: Array = []
	if party < 0:
		party = int(n("hop_smallest_party", 10))
	if hop_done or not hop.is_empty():
		why.append("The knarr has been to Hóp already.")
		return why
	if year < 2 or is_winter() or day_of_year < int(n("hop_earliest_start", 152)) or day_of_year > int(n("hop_latest_start", 205)):
		why.append("Hóp is a second-summer push: from 1 June to 24 July.")
	if not knarr_here:
		why.append("The knarr is away.")
	if hull > 1:
		why.append("The hull must be mended first.")
	if party < int(n("hop_smallest_party", 10)):
		why.append("She needs at least %d to sail south." % int(n("hop_smallest_party", 10)))
	if people - party < 4:
		why.append("Leave at least four to keep the camp.")
	return why

## Who goes to Hóp: the same order as the voyage home (skipper and pilot first; the camp keeps its healer and smith).
func hop_party(count: int) -> Array:
	var out: Array = []
	for role in ReturnPlan.SAIL_ORDER:
		for m in crew.alive():
			if out.size() >= count:
				return out
			if m.role == role:
				out.append(m)
	return out

func start_hop(count: int) -> bool:
	if not hop_gate(count).is_empty():
		return false
	var party := hop_party(count)
	if not party.any(func(m): return m.role in ["skipper", "pilot"]):
		return false
	hop = {"people": party.size(), "crew": party.map(func(m): return m.duplicate()), "days_left": int(n("hop_days_away", 30))}
	for m in party:
		m.away = true
	crew.members = crew.members.filter(func(m): return not m.get("away", false))
	people -= party.size()
	knarr_here = false
	hop_done = true
	history.hop = true
	return true

func _hop_day(tally: Dictionary) -> void:
	if hop.is_empty():
		return
	hop.days_left = int(hop.days_left) - 1
	if int(hop.days_left) > 0:
		return
	var p := int(hop.people)
	var got_vines := p * n("hop_vines_and_grapes_per_person", 0.25)
	var got_wheat := p * n("hop_self_sown_wheat_per_person", 0.08)
	var got_salmon := p * n("hop_salmon_per_person", 20) / n("food_unit_feeds", 168)
	vines += got_vines
	food += got_wheat + got_salmon
	people += p
	for m in hop.crew:
		crew.add(str(m.name), str(m.role), bool(m.female))
	knarr_here = true
	tally.lines.append("The knarr is back from Hóp with %.1f units of vines and grapes, self-sown wheat and dried salmon (%d days of food)." % [got_vines, roundi((got_wheat + got_salmon) * n("food_unit_feeds", 168) / maxf(1.0, people))])
	var chance := maxf(0.0, n("hop_chance_fear_rises", 0.35) - goodwill * n("hop_fear_chance_taken_off_per_point_of_goodwill", 0.03))
	if rng.randf() < chance:
		fear = clampf(fear + n("hop_fear_added", 2), 0.0, n("fear_cap", 5))
		quiet_days = 0
		tally.lines.append("Many people live at Hóp, and the meeting there went badly. Fear rises (%d of %d)." % [int(fear), int(n("fear_cap", 5))])
	if rng.randf() < n("hop_chance_the_hull_is_strained", 0.2):
		hull = mini(3, hull + 1)
		tally.lines.append("She came back strained from the southern shoals.")
	hop = {}

## While you are away the camp runs itself (F30): a sensible plan by season, scaled to who is left.
func auto_plan() -> void:
	var s := season()
	var a := {}
	var herd := cattle + sheep * n("sheep_fodder_as_share_of_a_cow", 0.25)
	if s == "winter":
		a = {"build": 6, "fish": 6, "hunt": 0, "forage": 0, "dry": 0, "timber": 6, "hay": 0, "tend": 3}
		ration = "full" if food_days() > winter_days_left() * 0.8 else "half"
	elif job_open("hay"):
		a = {"build": 5, "fish": 6, "hunt": 0, "forage": 2, "dry": 3, "timber": 1, "hay": 4 + (1 if herd > 4.0 else 0), "tend": 1}
		ration = "full"
	else:
		a = {"build": 8, "fish": 6, "hunt": 0, "forage": 3, "dry": 3, "timber": 2, "hay": 0, "tend": 1}
		ration = "full"
	var total := 0
	for j in a:
		total += int(a[j])
	var fit := people - sick.size()
	var scale := float(fit) / float(total) if total > 0 else 0.0
	for j in a:
		a[j] = int(floor(int(a[j]) * scale))
	if job_open("hay") and herd > 0.0:
		# enough haymakers to put up the herd's winter feed before the season closes
		var winter_len := 365 - int(n("first_snow", 305)) + int(n("spring_thaw", 110))
		var need := maxf(0.0, hay_per_day() * winter_len - hay)
		var days_left := maxi(1, int(n("forage_and_hay_season_ends", 290)) - day_of_year)
		var want := ceili(need / (n("hay_cut_per_worker_day", 0.15) * days_left))
		var hayers := clampi(want, int(a.hay), maxi(int(a.hay), fit / 2))
		var extra := hayers - int(a.hay)
		a.hay = hayers
		for j in ["build", "timber", "forage", "fish"]:
			var take := mini(extra, int(a[j]))
			a[j] = int(a[j]) - take
			extra -= take
	var used := 0
	for j in a:
		used += int(a[j])
	a.fish = int(a.fish) + maxi(0, fit - used)
	assign = a
	player_job = ""
	default_assignments()
	var spare := idle()
	if spare > 0:                      # more fishers than hooks: the spare hands fell timber
		assign.timber = int(assign.timber) + spare
		default_assignments()

## Run the camp on its own until a date (F30), trading at markets with the default offer and refusing weapons.
## Returns the lines worth telling: deaths, buildings, seasons, losses.
func catch_up(to_year: int, to_day: int) -> Array:
	var lines: Array = []
	var guard := 0
	while state == "camp" and (year < to_year or (year == to_year and day_of_year < to_day)) and guard < 800:
		guard += 1
		auto_plan()
		if roll_market():
			var r := do_trade(mini(cloth_strips, 4), mini(milk_to_spare(), 20), not byre_done())
			for l in r.lines:
				if "bull" in l: lines.append("%s: %s" % [date_text(), l])
			if weapon_request:
				answer_weapon_request(false)
		var tally := work_day()
		for l in tally.lines:
			if "died" in l or l.begins_with("A booth") or l.begins_with("The longhouse") or l.begins_with("The byre") or l.begins_with("The boat shed") \
					or l.begins_with("First snow") or l.begins_with("The thaw") or l.begins_with("No hay") or "driven off" in l or "clash" in l or "starved" in l:
				_tell(lines, tally.date, l)
	return lines.map(func(e): return ("%s: %s" % [e[0], e[2]]) if e[0] == e[1] else ("%s to %s: %s" % [e[0], e[1], e[2]]))

## Gather a told line; the same line on following days becomes one line over a span of dates.
func _tell(lines: Array, date: String, text: String) -> void:
	if not lines.is_empty() and lines[-1][2] == text:
		lines[-1][1] = date
	else:
		lines.append([date, date, text])

## The relief comes ashore (F30): first the camp's own months are lived out, then the newcomers join it.
## Returns {lines, alive_before, alive_after, dead_while_away}.
func reunite(v: Voyage) -> Dictionary:
	var before := people
	var dead_before := dead
	var lines := catch_up(v.year, v.day_of_year)
	var report := {"lines": lines, "alive_before": before, "alive_after": people if state == "camp" else 0,
		"dead_while_away": dead - dead_before, "state_before": state}
	year = v.year
	day_of_year = v.day_of_year
	if state != "camp":
		state = "camp"            # the relief resettles an empty or lost camp
		end_reason = ""
	people += v.people
	dead += v.dead
	for m in v.crew.alive():
		crew.add(str(m.name), str(m.role), bool(m.female))
	cattle += v.cattle
	sheep += v.sheep
	food += v.food
	for f in v.fresh_fish:
		fresh.append([f[0], f[1]])
	hooks += v.hooks
	cloth_strips += int(n("red_cloth_strips_per_trade_unit", 20)) * v.cloth_units
	iron_blades += int(n("iron_blades_per_trade_unit", 5)) * v.iron_units
	hull = v.hull
	knarr_here = true
	relief_came = true
	auto_plan()                    # a sensible board for the larger camp; the player changes it from here
	return report

func late_in_the_year() -> bool:
	return day_of_year > int(n("last_sensible_day_to_sail_home", 245))

# ------------------------------------------------------------------ save and log
const SAVE_FIELDS := ["day", "year", "day_of_year", "people", "dead", "cattle", "sheep", "fodderless_days", "food", "fresh", "hooks",
	"trade", "timber", "hay", "booths", "longhouse", "byre", "joints", "morale", "ration", "rain", "assign", "player_job", "state",
	"end_reason", "history", "hunt_far", "fish_net", "nets", "fear", "hides", "patch_health", "goodwill", "cloth_strips", "iron_blades", "pelts",
	"market_today", "market_pelts", "weapon_request", "penned_today", "quiet_days", "outfit", "smith_days",
	"second_spring", "hull", "shed", "timber_felled", "timber_winter", "sailed", "knarr_here", "relief_came", "hop", "hop_done", "vines"]

func to_dict() -> Dictionary:
	var d := {"sick": Array(sick), "rng_seed": str(rng.seed), "rng_state": str(rng.state), "crew": crew.to_array()}
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
	if d.has("crew"):
		crew.from_array(d.crew)
	sick.clear()
	for s in d.get("sick", []):
		sick.append(int(s))
	rng.seed = str(d.get("rng_seed", "1")).to_int()     # stored as text: JSON numbers cannot hold 64 bits
	rng.state = str(d.get("rng_state", "0")).to_int()

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
