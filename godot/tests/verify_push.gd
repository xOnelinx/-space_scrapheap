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
	if not _check_asteroid_sticks(wanderer):
		return
	if not _check_flight_nudge(wanderer):
		return

	print("PUSH_OK")
	quit(0)


func _check_flight_nudge(wanderer: Wanderer) -> bool:
	wanderer.undock()
	wanderer._controls_locked = true
	wanderer.velocity = Vector2(40, 0)
	wanderer._nudge_flight(1.0)
	if wanderer.velocity.distance_to(Vector2(40, 0)) > 0.01:
		fail("Правка курса при заблокированном вводе")
		return false
	wanderer._controls_locked = false
	wanderer._apply_flight_nudge(Vector2(0, -1), 1.0)
	var nudged := Vector2(40, -Wanderer.FLIGHT_NUDGE)
	if wanderer.velocity.distance_to(nudged) > 0.01:
		fail("Правка курса в полёте: %s" % wanderer.velocity)
		return false
	if Wanderer.FLIGHT_NUDGE >= Wanderer.PUSH_MIN:
		fail("Правка курса не должна быть сильнее слабого толчка")
		return false
	wanderer.velocity = Vector2(40, 0)
	wanderer._apply_flight_nudge(Vector2.ZERO, 1.0)
	if wanderer.velocity.distance_to(Vector2(40, 0)) > 0.01:
		fail("Без кнопок скорость в полёте не должна меняться")
		return false
	var jet := wanderer.get_node("FlightJet")
	wanderer._show_flight_jet(-Vector2.RIGHT)
	if not jet.is_shown() or jet.direction() != Vector2.LEFT:
		fail("Струя должна бить против кнопки")
		return false
	wanderer._show_flight_jet(Vector2.ZERO)
	if jet.is_shown():
		fail("Без кнопки струя должна гаснуть")
		return false
	var air := wanderer.get_node("Oxygen") as Oxygen
	air.seconds = 40.0
	air.double_left = 0.0
	wanderer._using_flight_correction = true
	wanderer._breathe(1.0)
	if absf(air.seconds - (40.0 - 1.0 - Wanderer.FLIGHT_OXYGEN)) > 0.01:
		fail("Правка курса должна тратить 3 кислорода в секунду, сейчас %.2f" % air.seconds)
		return false
	wanderer._using_flight_correction = false
	wanderer._breathe(1.0)
	if absf(air.seconds - (40.0 - 1.0 - Wanderer.FLIGHT_OXYGEN - 1.0)) > 0.01:
		fail("Без правки курса остаётся обычное дыхание")
		return false
	if wanderer.dock.docked or wanderer._flight_correction_held():
		fail("Без кнопки коррекция не должна считаться включённой")
		return false
	return true


func _check_asteroid_sticks(wanderer: Wanderer) -> bool:
	## И медленный удар о лёгкий камень, и быстрый о тяжёлый сажают, а не отскакивают.
	var heavy: SpaceRock = null
	var light: SpaceRock = null
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null or rock.hull:
			continue
		if heavy == null or rock.get_mass() > heavy.get_mass():
			heavy = rock
		if light == null or rock.get_mass() < light.get_mass():
			light = rock
	if heavy == null or light == null or light.get_mass() >= Wanderer.MASS:
		fail("Нет лёгкого астероида для проверки захвата")
		return false
	if not _sticks(wanderer, heavy, 140.0):
		fail("Быстрый контакт с астероидом должен цеплять")
		return false
	if not _sticks(wanderer, light, 8.0):
		fail("Медленный контакт с лёгким астероидом должен цеплять")
		return false
	var away := (wanderer.global_position - light.global_position).normalized()
	wanderer.velocity = away * 40.0
	wanderer.undock()
	wanderer._physics_process(0.25)
	if wanderer.dock.docked:
		fail("Прыжок от астероида не должен сразу прилипать обратно")
		return false
	return true


func _sticks(wanderer: Wanderer, rock: SpaceRock, speed: float) -> bool:
	var slot := 0
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var other := node as SpaceRock
		if other == null or other == rock:
			continue
		slot += 1
		other.drift_velocity = Vector2.ZERO
		other.spin = 0.0
		other.global_position = Vector2(-100000.0, slot * 500.0)
	rock.drift_velocity = Vector2.ZERO
	rock.spin = 0.0
	rock.global_position = Vector2(3000.0, 3000.0)
	wanderer.undock()
	var extra := 10.0
	var start := rock.get_hit_radius() + wanderer._self_radius + extra
	wanderer.global_position = rock.global_position + Vector2(start, 0.0)
	wanderer.velocity = Vector2(-speed, 0.0)
	wanderer._physics_process(extra / speed + 0.05)
	return wanderer.dock.docked and wanderer.dock.body == rock


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
	# В стороне от старых поз тел: физический круг мог ещё стоять на прежнем месте.
	wanderer.global_position = Vector2(250000, 250000)
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
