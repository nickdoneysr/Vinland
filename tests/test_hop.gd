extends RefCounted
## The Hóp push (F27).

static func run(t) -> void:
	var TR = load("res://tests/test_return.gd")
	var c: Camp = TR.ready_camp(1100)
	t.check("hóp: open in the second June with the knarr home", c.hop_gate().is_empty(), str(c.hop_gate()))
	var early: Camp = load("res://tests/test_outfits.gd").camp_for("merchant", 1101)
	t.check("hóp: closed in the first summer", not early.hop_gate().is_empty())
	t.check("hóp: needs ten to sail and four left at the camp", not c.hop_gate(8).is_empty() and not c.hop_gate(c.people - 2).is_empty())
	var before := c.people; var vines := c.vines; var food := c.food
	t.check("hóp: the party sails with a skipper or pilot", c.start_hop(10) and c.people == before - 10 and not c.knarr_here and c.crew.count() == c.people)
	t.check("hóp: no second push, and no voyage home while she is away", not c.hop_gate().is_empty() and not c.return_gate().is_empty())
	for i in int(c.n("hop_days_away", 30)): c.work_day()
	t.check("hóp: back after a month with vines, wheat and salmon", c.knarr_here and c.people >= before - 1 and c.vines > vines + 2.0 and c.crew.count() == c.people,
		"%.1f vines, %d people" % [c.vines, c.people])
	var fears := 0; var good_fears := 0
	for s in 40:
		var a: Camp = TR.ready_camp(1200 + s); a.goodwill = 0.0; a.fear = 0.0
		a.start_hop(10)
		for i in 30: a.work_day()
		if a.history.get("hop", false) and a.fear >= 1.5: fears += 1
		var b: Camp = TR.ready_camp(1200 + s); b.goodwill = 10.0; b.fear = 0.0
		b.start_hop(10)
		for i in 30: b.work_day()
		if b.fear >= 1.5: good_fears += 1
	t.check("hóp: fear can rise there, less with goodwill", fears > good_fears and fears >= 6, "%d vs %d of 40" % [fears, good_fears])
	var p := ReturnPlan.new(); p.setup(Knobs._v, c)
	t.check("hóp: the vines go first in the hold home", p.c.vines == int(floor(c.vines)) and p.can_sail(), "%d vines, %d timber" % [p.c.vines, p.c.timber])
	var v := p.launch(TR.legs_data(), 1300)
	TR.sail(v)
	var h := Home.new(); h.setup(Knobs._v, v, c, Game.outfit_table().merchant)
	t.check("hóp: vines sell for twice the timber, and the story counts the voyage south", is_equal_approx(h.vine_silver, v.vines * 6.0) and h.story_lines.any(func(l): return "Hóp" in l),
		"%.1f marks for %d units" % [h.vine_silver, v.vines])
	var sv := Camp.new()
	var mid: Camp = TR.ready_camp(1400); mid.start_hop(10); mid.work_day()
	sv.from_dict(Knobs._v, JSON.parse_string(JSON.stringify(mid.to_dict())))
	t.check("hóp: an expedition in progress survives a save", int(sv.hop.days_left) == int(mid.hop.days_left) and sv.hop.crew.size() == 10)
	# is it worth it? planners with and without the push
	var B = load("res://tests/balance.gd")
	var with_s := 0; var without_s := 0; var with_f := 0; var without_f := 0; var n := 12
	for s in n:
		var a2: Dictionary = B.whole_run("merchant", "planner", 60000 + s * 7)
		var b2: Dictionary = B.whole_run("merchant", "planner_hop", 60000 + s * 7)
		without_s += int(a2.score); with_s += int(b2.score)
		without_f += int(a2.title == "The full saga"); with_f += int(b2.title == "The full saga")
	print("INFO  hóp worth: planner %.0f score, %d of %d full; with the push %.0f score, %d of %d full" % [float(without_s) / n, without_f, n, float(with_s) / n, with_f, n])
	t.check("hóp: a push south is a real choice: it pays in score without making the full saga a sure thing", with_s > without_s and with_f <= without_f, "%.0f vs %.0f" % [float(with_s) / n, float(without_s) / n])
