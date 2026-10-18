extends Node
## Balance sweep: godot --headless --path . res://tests/balance_runner.tscn -- --n=12
func _ready() -> void:
	var n := 10
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--n="): n = int(a.trim_prefix("--n="))
	var b: Dictionary = load("res://tests/balance.gd").sweep(n)
	var ok: bool = b.planner.full >= 0.75 and b.average.full >= 0.15 and b.average.full <= 0.8 and b.careless.full <= 0.1
	print("RESULT %s (balance targets: planner 75%%+, average 15-80%%, careless 10%% or less)" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)
