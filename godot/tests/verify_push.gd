extends "res://tests/scene_check.gd"

## Старт на астероиде; в пустоте тяги нет; толчок к Mid безопасен.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot(3)
	if scene == null:
		return

	var wanderer: Wanderer = scene.get_node("Wanderer")
	if not wanderer.dock.docked:
		fail("Скиталец должен стартовать на астероиде")
		return
	var outward: Vector2 = wanderer.dock.outward()
	var sprite: Sprite2D = wanderer.get_node("Sprite")
	var feet: Vector2 = Vector2(0, 1).rotated(sprite.rotation)
	var backpack: Vector2 = Vector2(0, -1).rotated(sprite.rotation)
	if feet.dot(-outward) < 0.8:
		fail("К астероиду должны быть ноги, не рюкзак")
		return
	if backpack.dot(outward) < 0.8:
		fail("Рюкзак должен смотреть от астероида")
		return

	wanderer.undock()
	wanderer.global_position = Vector2(100, 100)
	wanderer.velocity = Vector2.ZERO
	# Заблокируем doom на один кадр проверки тяги — сразу вернём на камень
	wanderer.set_physics_process(false)

	var rock: Node2D = scene.get_node("Bodies/StaticNear")
	var mid: Node2D = scene.get_node("Bodies/StaticMid")
	wanderer.global_position = rock.global_position + Vector2(0, -60)
	wanderer.dock_to(rock, Vector2.UP)
	var push: Vector2 = (mid.global_position - wanderer.global_position).normalized() * 100.0
	wanderer.velocity = push
	wanderer.undock()
	print("SAFE=%s SPEED=%.1f" % [not wanderer.course_is_lost(), wanderer.velocity.length()])
	if wanderer.course_is_lost():
		fail("Толчок к Mid потерян")
		return

	var catcher := mid as SpaceRock
	catcher.sync_to_physics = false
	wanderer.global_position = Vector2(0, 0)
	wanderer.velocity = Vector2.ZERO
	catcher.global_position = Vector2(-180, 0)
	catcher.drift_velocity = Vector2(40, 0)
	if not wanderer._will_meet_rock(catcher) or wanderer.course_is_lost():
		fail("Стоящего скитальца должен догнать астероид")
		return

	wanderer.velocity = Vector2(15, 0)
	catcher.global_position = Vector2(-220, 12)
	catcher.drift_velocity = Vector2(55, 0)
	if not wanderer._will_meet_rock(catcher):
		fail("Догоняющий астероид должен быть на курсе")
		return

	wanderer.velocity = Vector2(20, 0)
	catcher.global_position = Vector2(-200, 0)
	catcher.drift_velocity = Vector2(5, 0)
	if wanderer._will_meet_rock(catcher):
		fail("Отстающий астероид не должен быть на курсе")
		return

	if not _check_lost_warning(scene, wanderer):
		return

	print("PUSH_OK")
	quit(0)


func _check_lost_warning(scene: Node, wanderer: Wanderer) -> bool:
	var warning := scene.get_node_or_null("LostWarning") as LostWarning
	if warning == null:
		fail("Нет узла LostWarning")
		return false
	if wanderer.lost_progress() > 0.0:
		fail("На старте не должно быть потери курса")
		return false
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null:
			continue
		rock.sync_to_physics = false
		rock.global_position += Vector2(0, 80000.0)
		rock.drift_velocity = Vector2.ZERO
	wanderer.undock()
	wanderer.velocity = Vector2(40, 0)
	if not wanderer.course_is_lost():
		fail("После увода тел курс должен быть потерян")
		return false
	wanderer._physics_process(Wanderer.LOST_DOOM_DELAY * 0.5)
	if wanderer.lost_progress() < 0.4:
		fail("Таймер пустоты не идёт")
		return false
	warning._process(0.0)
	if not warning.is_shown():
		fail("Предупреждение не показалось")
		return false
	wanderer.dock_to(scene.get_node("Bodies/StaticNear") as Node2D, Vector2.UP)
	if wanderer.lost_progress() > 0.0:
		fail("Посадка должна сбросить таймер пустоты")
		return false
	warning._process(0.0)
	if warning.is_shown():
		fail("На теле предупреждение должно скрыться")
		return false
	return true
