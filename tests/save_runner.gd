extends Node
var fails := 0
func check(name: String, ok: bool, info := "") -> void:
	print(("PASS  " if ok else "FAIL  ") + name + ("  " + info if info != "" else ""))
	if not ok:
		fails += 1
func _ready() -> void:
	load("res://tests/test_save.gd").run(self)
	print("RESULT %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(1 if fails else 0)
