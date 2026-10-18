extends Node
## Runs only the novice sweep: godot --headless --path . res://tests/novice_runner.tscn
var fails := 0
func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1
func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func(): print("RESULT FAIL (watchdog)"); get_tree().quit(2))
	await load("res://tests/test_novice.gd").run(self)
	print("RESULT %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
