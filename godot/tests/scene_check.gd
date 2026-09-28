extends SceneTree

## Общий запуск сцены и выход с ошибкой для проверок.


func boot(frames: int = 4) -> Node:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		fail("Сцена не загрузилась")
		return null
	for _i in frames:
		await process_frame
	return get_current_scene()


func fail(message: String) -> void:
	push_error(message)
	quit(1)
