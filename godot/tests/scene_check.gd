extends SceneTree

## Общий запуск сцены и выход с ошибкой для проверок.


func boot(frames: int = 4) -> Node:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		fail("Сцена не загрузилась")
		return null
	for _i in frames:
		await process_frame
	var scene := get_current_scene()
	## Проверки считают скафандр целым: стартовая пробоина кренила бы каждый прыжок.
	var wanderer := scene.get_node_or_null("Wanderer") as Wanderer
	if wanderer != null:
		(wanderer.get_node("Oxygen") as Oxygen).punctures = 0
		wanderer.leak_bias = 0.0
	return scene


func fail(message: String) -> void:
	push_error(message)
	quit(1)
