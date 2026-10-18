extends Node
## Tuning values exported from the plan's Assumptions sheet (tools/export_knobs.py).
## Gameplay code reads numbers from here, never from literals (Backlog F01, Risk R2).

var _v: Dictionary = {}

func _ready() -> void:
	var f := FileAccess.open("res://data/knobs.json", FileAccess.READ)
	if f == null:
		push_error("Knobs: data/knobs.json missing")
		return
	_v = JSON.parse_string(f.get_as_text())

func num(key: String, fallback: float = 0.0) -> float:
	if not _v.has(key):
		push_warning("Knobs: missing key %s" % key)
		return fallback
	return float(_v[key])

func text(key: String, fallback: String = "") -> String:
	return str(_v.get(key, fallback))

func has(key: String) -> bool:
	return _v.has(key)
