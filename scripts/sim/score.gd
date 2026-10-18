class_name Score
extends RefCounted
## The score at the end of a run (Backlog F31, first pass for F30): cargo delivered, people alive in both
## places, goodwill left on the table. Two cargoes and one relief ship with a living camp is the full win (P7).
## Loading everyone and leaving is allowed, and scored below a living camp, never scolded (P8).

static func compute(k: Dictionary, d: Dictionary) -> Dictionary:
	var n := func(key: String, fb: float) -> float: return float(k.get(key, fb))
	var lines: Array = []
	var total := 0.0
	var add := func(label: String, pts: float) -> void:
		lines.append("%s   %+d" % [label, roundi(pts)])
	var value: float = float(d.get("cargo_value", float(d.get("timber", 0)) * n.call("silver_per_timber_unit_sound_grade", 3)))
	var t: float = value * n.call("score_per_mark_of_cargo_sold", 0.65)
	add.call("Cargo sold at Eriksfjord: %d units of timber%s, %.0f marks" % [int(d.get("timber", 0)), (", %d of vines" % int(d.get("vines", 0))) if int(d.get("vines", 0)) > 0 else "", value], t); total += t
	var cg: float = d.get("cargoes", 0) * n.call("score_per_cargo_home", 10)
	add.call("%d cargo%s home" % [int(d.get("cargoes", 0)), "" if int(d.get("cargoes", 0)) == 1 else "es"], cg); total += cg
	var alive: int = int(d.get("camp_alive", 0)) + int(d.get("home_alive", 0))
	var al: float = alive * n.call("score_per_person_alive_at_the_end", 3)
	add.call("%d alive (%d at the camp, %d at home)" % [alive, int(d.get("camp_alive", 0)), int(d.get("home_alive", 0))], al); total += al
	if d.get("relief", false):
		var rl: float = n.call("score_for_a_relief_that_reached_the_camp", 10)
		add.call("The relief reached the camp", rl); total += rl
	var living: bool = int(d.get("camp_alive", 0)) > 0
	if living:
		var lc: float = n.call("score_for_a_living_camp_at_the_end", 25)
		add.call("A living camp at the Strait", lc); total += lc
	var gw: float = float(d.get("goodwill", 0.0)) * n.call("score_per_point_of_goodwill_left", 1)
	if gw > 0.0:
		add.call("Goodwill left with the people of the land", gw); total += gw
	var dd: float = -int(d.get("dead", 0)) * n.call("score_per_death", 2)
	if dd < 0.0:
		add.call("%d dead" % int(d.get("dead", 0)), dd); total += dd
	var arc: bool = int(d.get("cargoes", 0)) >= int(n.call("cargoes_for_the_full_win", 2)) and d.get("relief", false) and living
	var full: bool = arc and int(d.get("dead", 0)) <= int(n.call("most_deaths_for_the_full_saga", 3))
	var title := "The full saga"
	var line := "Two cargoes home, a relief across, and a living camp at the Strait. The timber built the next hull; the story built the next crew."
	if not full:
		if arc:
			title = "A dear-bought saga"
			line = "Two cargoes home, a relief across, a living camp: everything the saga asks. The cairns above the shore are the price, and the saga names them."
		elif not living and int(d.get("cargoes", 0)) > 0:
			title = "Home and rich"
			line = "They loaded what they could and came home with it. The booths at the Strait stand empty; the saga tells it so, and it is still a saga."
		elif living and int(d.get("cargoes", 0)) == 0:
			title = "A camp without a ship"
			line = "The camp lived, but no cargo ever went home, and no one at Eriksfjord knew to send help."
		elif living:
			title = "A camp at the Strait"
			line = "The camp lives and timber went home. The full arc, two cargoes and a relief, was not quite closed."
		else:
			title = "A hard road"
			line = "Few came through it. The way west is known now, and others will follow it."
	return {"total": maxi(0, roundi(total)), "lines": lines, "title": title, "line": line, "full": full}
