extends Node
## Camp tests only: godot --headless --path . res://tests/camp_runner.tscn
var fails := 0
func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1
func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func(): print("RESULT FAIL (watchdog)"); get_tree().quit(2))
	load("res://tests/test_camp.gd").run(self)
	print("RESULT %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
