extends SceneTree

## Старт на астероиде; в пустоте тяги нет; толчок к Mid безопасен.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		quit(1)
		return
	await process_frame
	await process_frame
	await process_frame

	var wanderer: CharacterBody2D = get_current_scene().get_node("Wanderer")
	if not wanderer.docked:
		push_error("Скиталец должен стартовать на астероиде")
		quit(1)
		return

	wanderer.undock()
	wanderer.global_position = Vector2(100, 100)
	wanderer.velocity = Vector2.ZERO
	# Заблокируем doom на один кадр проверки тяги — сразу вернём на камень
	wanderer.set_physics_process(false)

	var rock: Node2D = get_current_scene().get_node("Bodies/StaticNear")
	var mid: Node2D = get_current_scene().get_node("Bodies/StaticMid")
	wanderer.global_position = rock.global_position + Vector2(0, -60)
	wanderer.dock_to(rock, Vector2.UP)
	var push: Vector2 = (mid.global_position - wanderer.global_position).normalized() * 100.0
	wanderer.velocity = push
	wanderer.undock()
	print("SAFE=%s SPEED=%.1f" % [not wanderer.course_is_lost(), wanderer.velocity.length()])
	if wanderer.course_is_lost():
		push_error("Толчок к Mid потерян")
		quit(1)
		return

	var catcher := mid as SpaceRock
	catcher.sync_to_physics = false
	wanderer.global_position = Vector2(0, 0)
	wanderer.velocity = Vector2.ZERO
	catcher.global_position = Vector2(-180, 0)
	catcher.drift_velocity = Vector2(40, 0)
	if not wanderer._will_meet_rock(catcher) or wanderer.course_is_lost():
		push_error("Стоящего скитальца должен догнать астероид")
		quit(1)
		return

	wanderer.velocity = Vector2(15, 0)
	catcher.global_position = Vector2(-220, 12)
	catcher.drift_velocity = Vector2(55, 0)
	if not wanderer._will_meet_rock(catcher):
		push_error("Догоняющий астероид должен быть на курсе")
		quit(1)
		return

	wanderer.velocity = Vector2(20, 0)
	catcher.global_position = Vector2(-200, 0)
	catcher.drift_velocity = Vector2(5, 0)
	if wanderer._will_meet_rock(catcher):
		push_error("Отстающий астероид не должен быть на курсе")
		quit(1)
		return

	print("PUSH_OK")
	quit(0)
