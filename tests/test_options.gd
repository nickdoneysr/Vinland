extends RefCounted
## Pause and options (F51): settings persist, prompts follow the setting, vibration can be turned off.

static func run(t) -> void:
	var keep: Dictionary = Game.settings.duplicate()
	Game.settings.difficulty = "forgiving"; Game.settings.prompts = "auto"
	t.check("options: prompts on by default on Forgiving", Game.prompts_on() and Game.tuning("hunt").get("banner", false))
	Game.settings.difficulty = "hard"
	t.check("options: prompts off by default on Hard", not Game.prompts_on() and not Game.tuning("hunt").get("banner", false))
	Game.settings.prompts = "on"
	t.check("options: prompts forced on show on Hard too", Game.prompts_on() and Game.tuning("hunt").banner and Game.tuning("hand_line").bite_banner)
	Game.settings.difficulty = "forgiving"; Game.settings.prompts = "off"
	t.check("options: prompts forced off hide them on Forgiving", not Game.prompts_on() and not Game.tuning("forage").banner)
	# cycling through the menu rows
	Game.settings.prompts = "auto"
	Pause.change("difficulty", 1)
	Pause.change("difficulty", 1)
	Pause.change("difficulty", 1)
	t.check("options: difficulty steps up and stops at Hard", Game.settings.difficulty == "hard")
	Pause.change("vibration", 1)
	t.check("options: vibration toggles off", Game.settings.haptics == false)
	Pause.change("prompts", 1)
	t.check("options: prompts cycle auto -> always", Game.settings.prompts == "on")
	# settings survive a restart
	Game.save_settings()
	Game.settings = {"haptics": true, "text_scale": 1.0, "difficulty": "forgiving", "prompts": "auto"}
	Game.load_settings()
	t.check("options: settings are saved and read back", Game.settings.difficulty == "hard" and Game.settings.haptics == false and Game.settings.prompts == "on")
	# a save keeps its run's difficulty but not the player's vibration choice
	Game.settings.haptics = true
	Game.load_game({"stage": "camp", "settings": {"difficulty": "standard", "haptics": false}, "camp": _camp_dict()})
	t.check("options: loading a save restores its difficulty and leaves vibration alone", Game.settings.difficulty == "standard" and Game.settings.haptics == true)
	Game.camp = null; Game.loaded_stage = ""
	# the menu opens and pauses the tree, and closes again
	Pause.show_menu()
	var paused: bool = Engine.get_main_loop().paused
	Pause.hide_menu()
	t.check("options: the menu pauses play and resumes it", paused and not Engine.get_main_loop().paused and not Pause.open)
	Game.settings = keep
	Game.save_settings()

static func _camp_dict() -> Dictionary:
	var c := Camp.new()
	c.setup(Knobs._v, 3)
	return JSON.parse_string(JSON.stringify(c.to_dict()))

