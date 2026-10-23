extends SceneTree
## godot --path <project> --script res://scripts/review_tree.gd   (REVIEW_DIR=<dir for stills>)
var _c


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	for i in 5:
		await process_frame
	while main.get("mission") == null:
		await process_frame
	_c = load("res://scripts/review_shots.gd").new()
	_c.call("review", main, OS.get_environment("REVIEW_DIR"))
