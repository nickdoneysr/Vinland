extends Node
## xvfb-run godot --path . res://tests/shot_voyage.tscn -- --weather=storm --days=6 --out=/tmp/v.png
func _ready() -> void:
	var a := {}
	for s in OS.get_cmdline_user_args():
		var kv := s.trim_prefix("--").split("=", true, 1)
		a[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var scene: Node = load("res://scenes/voyage.tscn").instantiate()
	add_child(scene)
	var v: Voyage = scene.v
	for d in int(a.get("days", "0")):
		for i in 6:
			v.sail_watch()
		v.start_day()
	v.weather = a.get("weather", v.weather)
	v.watch = int(a.get("watch", "2"))
	v.pace = a.get("pace", v.pace)
	scene.cards.clear()
	scene.mode = "sail"
	for i in 40:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("out", "/tmp/v.png"))
	get_tree().quit()
