extends SceneTree

## Общий запуск сцены и выход с ошибкой для проверок.
## По умолчанию стенд с камнем. Раскладку игры передают res://scenes/main.tscn.

const STAND_SCENE := "res://tests/stand.tscn"


func boot(frames: int = 4, scene_path: String = STAND_SCENE) -> Node:
	var err := change_scene_to_file(scene_path)
	if err != OK:
		fail("Сцена не загрузилась")
		return null
	for _i in frames:
		await process_frame
	return get_current_scene()


func fail(message: String) -> void:
	push_error(message)
	quit(1)
