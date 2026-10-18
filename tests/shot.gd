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
	if a.has("rain") and n.has_method("start"):
		n.start(true)
	if a.has("camp_days"):
		for i in int(a.camp_days):
			n.camp.default_assignments()
			n.camp.work_day({})
	if a.has("clear"):
		n.cards.clear()
		n.mode = a.get("mode", "morning")
	if a.has("market"):
		n.camp.market_today = true
		n.camp.market_pelts = 7
		n.offer = {"cloth": mini(n.camp.cloth_strips, 4), "milk": mini(n.camp.milk_to_spare(), 20), "pen": true}
		n.mode = "market"
	if a.has("pause"):
		get_tree().current_scene = n
		Pause.show_menu()
	for i in int(a.get("frames", "60")):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(a.get("out", "/tmp/shot.png"))
	get_tree().quit()
