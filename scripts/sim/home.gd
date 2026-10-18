class_name Home
extends RefCounted
## Eriksfjord, autumn: the knarr is home (Backlog F25 appraisal and sale, F26 recruitment and second hull).
## The timber's grade and amount set what the cargo buys. A living crew and a true story recruit better
## than silver: volunteers come for the story; silver hires the rest and can buy a second hull.

var k: Dictionary
var outfit := ""
var silver_start := 0.0
var timber := 0
var winter_share := 0.0
var pelts := 0
var grade := "sound"           # rough | sound | prime
var timber_silver := 0.0
var pelt_silver := 0.0
var story := 0.0
var story_lines: Array = []
var volunteers := 0
var buy_hull := false
var hires := 0
var came_home := 0
var at_camp := 0
var dead := 0
var crew: Array = []           # who came home (named)
var year := 2
var cargoes := 1               # cargoes delivered this run

func n(key: String, fallback: float = 0.0) -> float:
	return float(k.get(key, fallback))

## Appraise and sell the cargo, and weigh the story the crew tells.
func setup(knobs: Dictionary, v: Voyage, camp: Camp, outfit_data: Dictionary) -> void:
	k = knobs
	outfit = v.outfit
	silver_start = n("starting_silver_" + str(outfit_data.get("silver", "Medium")).to_lower(), 6)
	timber = v.timber
	pelts = v.pelts
	came_home = v.people
	crew = v.crew.to_array().filter(func(m): return m.alive)
	at_camp = camp.people if camp.state == "camp" else 0
	dead = camp.dead + v.dead
	year = camp.year
	winter_share = camp.winter_share()
	grade = timber_grade(winter_share, outfit == "shipwright_s_kin")
	timber_silver = timber * n("silver_per_timber_unit_sound_grade", 3) * grade_multiplier(grade)
	pelt_silver = pelts * n("silver_per_pelt", 0.25)
	_weigh_story(camp)
	volunteers = mini(int(n("most_volunteers_in_a_winter", 30)), floori(story * n("volunteers_per_point_of_story", 0.5)))

func timber_grade(share: float, shipwright: bool) -> String:
	var g := 1
	if share >= n("winter_felled_share_for_prime_timber", 0.5):
		g = 2
	elif share < n("winter_felled_share_below_which_timber_is_rough", 0.15):
		g = 0
	if shipwright:
		g = mini(2, g + 1)          # a shipwright's eye picks the straight trees
	return ["rough", "sound", "prime"][g]

func grade_multiplier(g: String) -> float:
	match g:
		"prime": return n("prime_timber_price_multiplier", 1.4)
		"rough": return n("rough_timber_price_multiplier", 0.7)
	return 1.0

func _weigh_story(camp: Camp) -> void:
	story_lines.clear()
	var alive := came_home + at_camp
	var buildings := camp.booths + (1 if camp.hall_done() else 0) + (1 if camp.byre_done() else 0) + (1 if camp.shed_done() else 0)
	var p_alive := alive * n("story_points_per_person_alive", 1)
	var p_build := buildings * n("story_points_per_building_raised", 2)
	var p_dead := -dead * n("story_points_lost_per_death", 1)
	var p_good := camp.goodwill * n("story_points_per_point_of_goodwill", 0.5)
	story = maxf(0.0, p_alive + p_build + p_dead + p_good)
	story_lines.append("%d alive (%d home, %d at the camp): %+d" % [alive, came_home, at_camp, roundi(p_alive)])
	story_lines.append("%d buildings raised at the Strait: %+d" % [buildings, roundi(p_build)])
	if dead > 0:
		story_lines.append("%d dead since Eriksfjord: %+d" % [dead, roundi(p_dead)])
	if camp.goodwill > 0.0:
		story_lines.append("Peace and trade with the people of the land: %+d" % roundi(p_good))
	if at_camp <= 0:
		story_lines.append("No one is left at the camp: a tale of a place, not of a home.")

func silver() -> float:
	return silver_start + timber_silver + pelt_silver

func hull_price() -> float:
	return n("second_hull_price", 40)

func hire_price() -> float:
	return n("silver_to_hire_a_recruit", 1)

func spent() -> float:
	return (hull_price() if buy_hull else 0.0) + hires * hire_price()

func left() -> float:
	return silver() - spent()

func can_buy_hull() -> bool:
	return buy_hull or left() >= hull_price()

## Room in the relief: each hull carries so many people with stores and stock.
func room() -> int:
	return hulls() * int(n("most_people_a_relief_hull_carries", 30))

## Volunteers who can find a place aboard (the rest wait for another year).
func volunteers_aboard() -> int:
	return mini(volunteers, maxi(0, room() - came_home))

func max_hires() -> int:
	var by_silver := hires + floori((left() + 0.0001) / hire_price())
	var by_room := maxi(0, room() - came_home - volunteers_aboard())
	return mini(by_silver, by_room)

func set_hull(on: bool) -> void:
	if on and not buy_hull and left() < hull_price():
		return
	buy_hull = on
	hires = mini(hires, max_hires())

func set_hires(h: int) -> void:
	hires = clampi(h, 0, max_hires())

## How many sail with the relief in spring: those who came home, the volunteers and the hired.
func relief_party() -> int:
	return came_home + volunteers_aboard() + hires

func hulls() -> int:
	return 2 if buy_hull else 1

func to_dict() -> Dictionary:
	return {"outfit": outfit, "silver_start": silver_start, "timber": timber, "winter_share": winter_share, "pelts": pelts, "grade": grade,
		"timber_silver": timber_silver, "pelt_silver": pelt_silver, "story": story, "story_lines": story_lines, "volunteers": volunteers,
		"buy_hull": buy_hull, "hires": hires, "came_home": came_home, "at_camp": at_camp, "dead": dead, "crew": crew, "year": year, "cargoes": cargoes}

func from_dict(knobs: Dictionary, d: Dictionary) -> void:
	k = knobs
	for key in d:
		if key in self:
			var val = d[key]
			if typeof(get(key)) == TYPE_INT and typeof(val) == TYPE_FLOAT:
				val = int(val)
			set(key, val)
