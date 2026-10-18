extends Node2D
## MG9 Smoke rack fire (Backlog F15). RS left/right moves the hide screen to keep the smoke under the rack ·
## RS up feeds the fire, down damps it. Warmth ramps in the pad with the heat and stutters when the fish
## case-hardens; the visual twin is the smoke turning from white to black.

signal finished(result: Dictionary)
signal closed

const RACK := Vector2(960, 300)
const FIRE := Vector2(960, 900)

var embedded := false
var autopilot := false
var bot_input: Callable          # tests: returns [steer, feed]
var difficulty := ""
var rules := SmokeRack.new()
var result: Dictionary = {}
var t := 0.0
var _cfg: Dictionary
var _font: Font
var _beat := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	if not embedded:
		start()

func start(seed: int = 0) -> void:
	_cfg = Game.tuning("smoke_rack", difficulty)
	rules = SmokeRack.new()
	rules.setup(_cfg, seed)
	result = {}
	t = 0.0

func _process(delta: float) -> void:
	t += delta
	_beat -= delta
	if result.is_empty():
		var steer := Controls.right_stick().x
		var feed := -Controls.right_stick().y
		var b: Array = []
		if autopilot:
			b = _bot()
		elif bot_input.is_valid():
			b = bot_input.call(self)
		if b.size() == 2:
			steer = b[0]; feed = b[1]
		var evs := rules.step(delta, steer, feed)
		if _beat <= 0.0:
			Controls.pulse(rules.heat * 0.4, 0.0, 0.1)          # warmth ramps with the heat
			_beat = 0.25
		if "harden" in evs:
			Controls.pulse(0.0, 0.8, 0.06)                      # the stutter
		if rules.done:
			result = {"quality": rules.quality(), "spoiled": rules.spoiled(), "hardening": rules.hardening}
			finished.emit(result)
	queue_redraw()

## Expert bot: leans the screen into the gusts and holds the fire in the middle of the band.
func _bot() -> Array:
	var r := rules
	var steer := clampf((-r.column - r.col_v * 0.35) / 50.0 - r.wind * float(_cfg.shove) / float(_cfg.steer), -1.0, 1.0)
	var mid := (float(_cfg.band[0]) + float(_cfg.band[1])) * 0.5
	var feed := clampf((mid + 0.03 - r.fuel) * 6.0 + (mid - r.heat) * 2.0, -1.0, 1.0)
	return [steer, feed]

func _unhandled_input(e: InputEvent) -> void:
	if not result.is_empty() and e.is_action_pressed("commit"):
		get_viewport().set_input_as_handled()
		if embedded:
			closed.emit()
		else:
			start()

func _draw() -> void:
	var ink := Color("ede3cc")
	var kb := Controls.keyboard
	var r := rules
	draw_rect(Rect2(0, 0, 1920, 1080), Color("a9b8c0"))
	draw_rect(Rect2(0, 700, 1920, 380), Color("6f7f4a"))
	# the rack and its fish
	draw_line(RACK + Vector2(-260, -40), RACK + Vector2(-260, 420), Color("5a4030"), 10.0)
	draw_line(RACK + Vector2(260, -40), RACK + Vector2(260, 420), Color("5a4030"), 10.0)
	draw_line(RACK + Vector2(-280, -30), RACK + Vector2(280, -30), Color("5a4030"), 8.0)
	var fish_col := Color("d8c39a").lerp(Color("8a5a2e"), r.cure).lerp(Color("2a1a10"), r.hardening * 0.8)
	for k in 9:
		var x := -220.0 + k * 55.0
		draw_line(RACK + Vector2(x, -30), RACK + Vector2(x, 10), Color("3a2a1c"), 2.0)
		draw_colored_polygon(PackedVector2Array([RACK + Vector2(x - 12, 10), RACK + Vector2(x + 12, 10), RACK + Vector2(x + 6, 90), RACK + Vector2(x - 6, 90)]), fish_col)
	var half := float(_cfg.rack_half)
	draw_rect(Rect2(RACK.x - half, RACK.y + 110, half * 2.0, 6), Color("6e8a4e", 0.8) if r.under else Color("9e3a2e", 0.6))
	# the fire and the hide screen
	draw_circle(FIRE, 50, Color("3a2a1c"))
	draw_circle(FIRE + Vector2(0, -10), 20 + r.heat * 25, Color("e8a23a").lerp(Color("ff6a2a"), r.heat))
	var screen_x := FIRE.x - clampf(r.column, -300, 300) * 0.4
	draw_rect(Rect2(screen_x - 90, FIRE.y - 160, 14, 160), Color("8a6d4e"))
	# the smoke column: white when it cures, black when it burns
	var smoke := Color(0.95, 0.95, 0.95, 0.6).lerp(Color(0.1, 0.1, 0.1, 0.8), clampf((r.heat - float(_cfg.band[1])) / 0.25, 0.0, 1.0))
	for k in 14:
		var f := k / 13.0
		var p := FIRE.lerp(RACK + Vector2(r.column, 120), f) + Vector2(sin(t * 3.0 + k) * 10.0, 0)
		draw_circle(p, 26 + f * 34, smoke)
	# wind
	draw_rect(Rect2(1300, 120, 360, 90), Color(0.1, 0.09, 0.07, 0.6))
	var wx := 1480.0 + r.wind * 160.0
	draw_line(Vector2(1480, 160), Vector2(wx, 160), Color(1, 1, 1, 0.85), 6.0)
	if absf(r.wind) > 0.05:
		draw_colored_polygon(PackedVector2Array([Vector2(wx + signf(r.wind) * 14, 160), Vector2(wx, 150), Vector2(wx, 170)]), Color(1, 1, 1, 0.85))
	draw_string(_font, Vector2(1320, 200), "wind", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(ink, 0.8))
	# heat gauge with the band
	draw_rect(Rect2(1700, 300, 50, 520), Color(0.1, 0.09, 0.07, 0.85))
	var b0 := float(_cfg.band[0]); var b1 := float(_cfg.band[1])
	draw_rect(Rect2(1700, 820 - 520 * b1, 50, 520 * (b1 - b0)), Color(0.43, 0.54, 0.31, 0.7))
	draw_rect(Rect2(1700, 820 - 520 * 1.0, 50, 520 * (1.0 - float(_cfg.hard_above))), Color(0.62, 0.23, 0.18, 0.6))
	draw_rect(Rect2(1690, 820 - 520 * r.heat - 4, 70, 8), Color("e8c35a"))
	draw_string(_font, Vector2(1690, 850), "heat", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	# HUD
	draw_rect(Rect2(24, 20, 1060, 190), Color(0.1, 0.09, 0.07, 0.85))
	draw_string(_font, Vector2(44, 60), "THE SMOKE RACK", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, ink)
	var help := "Left/Right move the screen · Up feed the fire · Down damp it" if kb else "RS left/right move the screen · RS up feed · RS down damp"
	draw_string(_font, Vector2(44, 98), help, HORIZONTAL_ALIGNMENT_LEFT, 1020, 20, Color(ink, 0.75))
	draw_rect(Rect2(44, 120, 400, 22), Color(0.2, 0.18, 0.15))
	draw_rect(Rect2(44, 120, 400 * r.cure, 22), Color("6e8a4e"))
	draw_string(_font, Vector2(456, 140), "cured %d%%" % roundi(r.cure * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	draw_rect(Rect2(44, 160, 400, 22), Color(0.2, 0.18, 0.15))
	draw_rect(Rect2(44, 160, 400 * r.hardening, 22), Color("9e3a2e"))
	draw_string(_font, Vector2(456, 180), "case-hardened %d%%   ·   %ds" % [roundi(r.hardening * 100), maxi(0, ceili(float(_cfg.session_seconds) - r.t))], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, ink)
	if bool(_cfg.get("banner", false)) and result.is_empty():
		var tip := ""
		if not r.under:
			tip = "The smoke is off the rack: move the screen %s (%s)." % ["left" if r.column > 0 else "right", "Left / Right" if kb else "right stick"]
		elif r.heat > float(_cfg.hard_above):
			tip = "Black smoke! Too hot: damp the fire (%s)." % ("Down" if kb else "right stick down")
		elif r.heat < b0:
			tip = "Too cool to cure: feed the fire (%s)." % ("Up" if kb else "right stick up")
		else:
			tip = "White smoke under the fish. Hold it there."
		draw_rect(Rect2(460, 980, 1100, 64), Color(0.08, 0.07, 0.06, 0.8))
		draw_string(_font, Vector2(490, 1024), tip, HORIZONTAL_ALIGNMENT_LEFT, 1060, 26, ink)
	if not result.is_empty():
		var line := "The rack is spoiled: crusted outside, soft within." if result.spoiled else "The fish came through %d%% cured." % roundi(result.quality * 100)
		draw_rect(Rect2(560, 420, 820, 180), Color(0.08, 0.07, 0.06, 0.92))
		draw_rect(Rect2(560, 420, 820, 8), Color("9e3a2e") if result.spoiled else Color("6e8a4e"))
		draw_string(_font, Vector2(600, 490), line, HORIZONTAL_ALIGNMENT_LEFT, 760, 26, ink)
		draw_string(_font, Vector2(600, 560), "A: back" if embedded else "A: another rack", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(ink, 0.6))
