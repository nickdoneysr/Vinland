extends Node
## Looks up art by asset ID from data/art_manifest.json (built from the art asset list).
## Real art saved at its listed path always wins; otherwise the placeholder of the same size is used.

var manifest: Dictionary = {}

func _ready() -> void:
	var f := FileAccess.open("res://data/art_manifest.json", FileAccess.READ)
	if f == null:
		push_error("Art: data/art_manifest.json missing")
		return
	manifest = JSON.parse_string(f.get_as_text())

func tex(id: String, variant: String = "") -> Texture2D:
	var e: Dictionary = manifest.get(id, {})
	if e.is_empty():
		push_warning("Art: unknown asset id %s" % id)
		return null
	var real: String = e.get("path", "")
	if variant != "" and real.ends_with(".png"):
		var v := real.trim_suffix(".png") + "_" + variant + ".png"
		if ResourceLoader.exists(v):
			return load(v)
	if real.ends_with(".png") and ResourceLoader.exists(real):
		return load(real)
	var ph: String = e.get("placeholder", "")
	if ph != "" and ResourceLoader.exists(ph):
		return load(ph)
	return null

func size_of(id: String) -> Vector2:
	var s: Array = manifest.get(id, {}).get("size", [256, 256])
	return Vector2(s[0], s[1])

func is_final(id: String) -> bool:
	var p: String = manifest.get(id, {}).get("path", "")
	return p.ends_with(".png") and ResourceLoader.exists(p)

## Share of manifest assets that have real art in place, by phase (for the debug overlay).
func coverage(phase: String = "") -> float:
	var total := 0
	var done := 0
	for id in manifest:
		var e: Dictionary = manifest[id]
		if not str(e.get("path", "")).begins_with("res://art/"):
			continue
		if phase != "" and e.get("phase", "") != phase:
			continue
		total += 1
		if is_final(id):
			done += 1
	return 0.0 if total == 0 else float(done) / total
