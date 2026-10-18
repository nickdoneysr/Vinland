extends Node
## Screenshot helper. Example:
## xvfb-run godot --path . res://tests/shot.tscn -- --scene=res://scenes/star_ring.tscn --preset=fog --frames=90 --out=/tmp/ring.png [--bot]

func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var n = load(a.get("scene", "res://scenes/boot.tscn")).instantiate()
	add_child(n)
	if a.has("preset") and n.has_method("new_night"):
		n.new_night(a.preset)
	if a.has("bot"):
		n.autopilot = true
	for i in int(a.get("frames", "60")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("out", "/tmp/shot.png"))
	get_tree().quit()
