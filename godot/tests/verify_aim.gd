extends "res://tests/scene_check.gd"

## Прицел прыжка: та же скорость, что толчок; спин опоры; курс до края экрана.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	if wanderer.get_node_or_null("JumpAim") == null:
		fail("Нет узла JumpAim")
		return
	wanderer.set_physics_process(false)
	if not _check_matches_push(scene, wanderer):
		return
	if not _check_spin_inherited(scene, wanderer):
		return
	if not _check_skips_stand(scene, wanderer):
		return
	if not _check_stops_on_other(scene, wanderer):
		return
	if not _check_path_and_arrow(wanderer):
		return
	if not _check_push_debug_grows(scene, wanderer):
		return
	if not _check_cursor_distance_sets_charge(wanderer):
		return
	if not _check_aim_release_cancels_charge(scene, wanderer):
		return
	if not _check_arrow_dock_color(scene, wanderer):
		return
	if not _check_fast_contact_docks(wanderer):
		return
	print("AIM_OK")
	quit(0)


func _check_matches_push(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	wanderer.dock_to(rock, Vector2.UP)
	wanderer._charge = 1.0
	var aim := Vector2.RIGHT
	var predicted := wanderer.launch_velocity(aim, 1.0)
	wanderer._commit_push(aim)
	if wanderer.velocity.distance_to(predicted) > 0.05:
		fail("Прогноз не совпал с толчком")
		return false
	if wanderer.dock.docked:
		fail("После сверки прогноза всё ещё на камне")
		return false
	return true


func _check_spin_inherited(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticMid") as SpaceRock
	rock.sync_to_physics = false
	rock.spin = 1.8
	rock.drift_velocity = Vector2(24, -8)
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)
	var aim := Vector2.UP
	var launch := wanderer.launch_velocity(aim, 0.0)
	var inherit := rock.velocity_at(wanderer.global_position)
	var share := rock.get_mass() / (Wanderer.MASS + rock.get_mass())
	var expected := inherit + aim.normalized() * Wanderer.PUSH_MIN * share
	if launch.distance_to(expected) > 0.08:
		fail("Прицел не учёл вращение опоры")
		return false
	var toward_cursor := aim.normalized() * Wanderer.PUSH_MIN * share
	if launch.distance_to(toward_cursor) < 8.0:
		fail("Спин не сдвинул прогноз с направления курсора")
		return false
	return true


func _check_skips_stand(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	rock.spin = 0.0
	rock.drift_velocity = Vector2.ZERO
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)
	var inward := -wanderer.dock.outward()
	var launch := wanderer.launch_velocity(inward, 1.0)
	var hit_t := wanderer.first_aim_hit(launch, 0.2)
	if hit_t < 0.05:
		fail("Прицел упёрся в камень, с которого толкаемся")
		return false
	return true


func _check_stops_on_other(scene: Node, wanderer: Wanderer) -> bool:
	var stand := scene.get_node("Bodies/StaticNear") as SpaceRock
	var target := scene.get_node("Bodies/StaticMid") as SpaceRock
	stand.spin = 0.0
	stand.drift_velocity = Vector2.ZERO
	stand.sync_to_physics = false
	target.spin = 0.0
	target.drift_velocity = Vector2.ZERO
	target.sync_to_physics = false
	wanderer.undock()
	wanderer.global_position = stand.global_position + Vector2(0, -stand.get_hit_radius() - 14.0)
	wanderer.dock_to(stand, Vector2.UP)
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var other := node as SpaceRock
		if other == null or other == stand or other == target:
			continue
		other.sync_to_physics = false
		other.global_position.y += 20000.0
	target.global_position = wanderer.global_position + Vector2(180, 0)
	var launch := Vector2(90, 0)
	var hit_t := wanderer.first_aim_hit(launch, Wanderer.AIM_HORIZON)
	if hit_t >= INF:
		fail("Прицел не нашёл тело на курсе")
		return false
	var gap := target.global_position.x - wanderer.global_position.x
	var radii := wanderer._self_radius + target.get_hit_radius()
	var expect := (gap - radii) / launch.x
	if absf(hit_t - expect) > 0.08:
		fail("Стоп прицела не на кромке тела: t=%.3f ждут %.3f" % [hit_t, expect])
		return false
	if wanderer.first_aim_hit(Vector2(0, -80), 0.35) < INF:
		fail("Короткий уход вверх не должен сразу бить тело")
		return false
	return true


func _check_path_and_arrow(wanderer: Wanderer) -> bool:
	var aim := wanderer.get_node("JumpAim") as JumpAim
	var launch := Vector2(80, 0)
	var path := aim.path_end_local(launch)
	var arrow := aim.velocity_end_local(launch)
	if path.length() < 200.0:
		fail("Курс не дошёл до края экрана: %.1f" % path.length())
		return false
	if arrow.distance_to(launch) > 0.05:
		fail("Стрелка должна совпадать с курсом полёта")
		return false
	if absf(arrow.angle_to(path)) > 0.01:
		fail("Стрелка смотрит не вдоль пути")
		return false
	if arrow.length() >= path.length():
		fail("Стрелка скорости не короче курса")
		return false
	return true


func _check_push_debug_grows(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)
	var aim := wanderer.get_node("JumpAim") as JumpAim
	var toward := Vector2.RIGHT
	var weak := wanderer.push_desired(toward, 0.0)
	var strong := wanderer.push_desired(toward, 1.0)
	if absf(weak.length() - Wanderer.PUSH_MIN) > 0.05:
		fail("Жёлтый вектор на минимуме должен быть PUSH_MIN")
		return false
	if absf(strong.length() - Wanderer.PUSH_MAX) > 0.05:
		fail("Жёлтый вектор на полном заряде должен быть PUSH_MAX")
		return false
	if strong.length() <= weak.length() + 1.0:
		fail("Жёлтый вектор не растёт с зарядом")
		return false
	if aim.push_end_local(weak).distance_to(weak) > 0.05:
		fail("Жёлтая стрелка не совпала с вектором толчка")
		return false
	if absf(weak.angle_to(toward)) > 0.01 or absf(strong.angle_to(toward)) > 0.01:
		fail("Жёлтый вектор должен смотреть в сторону толчка")
		return false
	return true


func _check_cursor_distance_sets_charge(wanderer: Wanderer) -> bool:
	var near := wanderer.charge_from_offset(Vector2(Wanderer.CHARGE_DIST_MIN * 0.4, 0.0))
	var mid := wanderer.charge_from_offset(
			Vector2((Wanderer.CHARGE_DIST_MIN + Wanderer.CHARGE_DIST_MAX) * 0.5, 0.0))
	var far := wanderer.charge_from_offset(Vector2(Wanderer.CHARGE_DIST_MAX + 80.0, 0.0))
	var pulled := wanderer.charge_from_offset(Vector2(Wanderer.CHARGE_DIST_MIN, 0.0))
	if near > 0.01:
		fail("Курсор у персонажа должен давать минимум")
		return false
	if pulled > 0.01:
		fail("На CHARGE_DIST_MIN заряд ещё ноль")
		return false
	if far < 0.99:
		fail("Дальний курсор должен давать максимум")
		return false
	if not (near < mid and mid < far):
		fail("Заряд должен расти с удалением курсора")
		return false
	if wanderer.charge_from_offset(Vector2(100.0, 0.0)) <= wanderer.charge_from_offset(Vector2(40.0, 0.0)):
		fail("Вернуть курсор ближе должно ослабить толчок")
		return false
	return true


func _check_aim_release_cancels_charge(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	wanderer._controls_locked = false
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)
	_mouse(wanderer, MOUSE_BUTTON_LEFT, true)
	wanderer._charge = 0.7
	if not wanderer._charging:
		fail("Заряд ЛКМ не начался")
		return false
	_mouse(wanderer, MOUSE_BUTTON_RIGHT, false)
	if wanderer._charging or wanderer._charge > 0.0:
		fail("Отпуск ПКМ должен сбросить заряд")
		return false
	if not wanderer.dock.docked:
		fail("Отпуск ПКМ не должен толкать")
		return false
	_mouse(wanderer, MOUSE_BUTTON_LEFT, false)
	if not wanderer.dock.docked:
		fail("Отпуск старой ЛКМ после сброса не должен толкать")
		return false
	_mouse(wanderer, MOUSE_BUTTON_LEFT, true)
	wanderer._charge = 1.0
	_mouse(wanderer, MOUSE_BUTTON_LEFT, false)
	if wanderer.dock.docked:
		fail("После нового зажима ЛКМ должны оттолкнуться")
		return false
	return true


func _mouse(wanderer: Wanderer, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	wanderer._unhandled_input(event)


func _check_arrow_dock_color(scene: Node, wanderer: Wanderer) -> bool:
	var stand := scene.get_node("Bodies/StaticNear") as SpaceRock
	var meteor := scene.get_node("Bodies/StaticMid") as SpaceRock
	var hull := scene.get_node("Bodies/HullFed01") as SpaceRock
	if wanderer.asteroid_dock_speed(hull) < 1.0e12 or wanderer.asteroid_dock_speed(stand) < 1.0e12:
		fail("К телу нет порога скорости")
		return false
	stand.sync_to_physics = false
	meteor.sync_to_physics = false
	stand.spin = 0.0
	stand.drift_velocity = Vector2.ZERO
	meteor.spin = 0.0
	meteor.drift_velocity = Vector2.ZERO
	wanderer.undock()
	wanderer.global_position = stand.global_position + Vector2(0, -stand.get_hit_radius() - 14.0)
	wanderer.dock_to(stand, Vector2.UP)
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var other := node as SpaceRock
		if other == null or other == stand:
			continue
		other.sync_to_physics = false
		other.global_position.y += 20000.0
	var fast_void := Vector2(200.0, 0.0)
	if wanderer.aim_too_fast_for_meteor(fast_void, 8.0):
		fail("Без тела на курсе абсолютная скорость не красит стрелку")
		return false
	if wanderer.aim_relative_velocity(fast_void, 8.0) != Vector2.ZERO:
		fail("Без тела на курсе относительная скорость должна быть нулевой")
		return false
	meteor.global_position = wanderer.global_position + Vector2(180, 0)
	meteor.drift_velocity = Vector2(40, 0)
	var launch := Vector2(90, 0)
	var rel := wanderer.aim_relative_velocity(launch, 8.0)
	var expect := launch - meteor.drift_velocity
	if rel.distance_to(expect) > 0.2:
		fail("Относительная скорость к метеориту на курсе неверна: %s ≠ %s" % [rel, expect])
		return false
	if wanderer.aim_too_fast_for_meteor(meteor.drift_velocity + Vector2(30.0, 0.0), 8.0):
		fail("Мягкий подход к метеориту должен быть зелёным")
		return false
	if wanderer.aim_too_fast_for_meteor(meteor.drift_velocity + Vector2(280.0, 0.0), 8.0):
		fail("Жёсткий подход к метеориту тоже цепляется")
		return false
	meteor.drift_velocity = Vector2.ZERO
	var clip := Vector2(280.0, 0.0)
	var radii := wanderer._self_radius + meteor.get_hit_radius()
	meteor.global_position = wanderer.global_position + Vector2(200, radii * 0.92)
	if wanderer.first_aim_rock(clip, 8.0) != meteor:
		fail("Скользящий курс должен бить в метеорит")
		return false
	if wanderer.aim_too_fast_for_meteor(clip, 8.0):
		fail("Скользящий удар цепляется — стрелка не должна быть красной")
		return false
	return true


func _check_fast_contact_docks(wanderer: Wanderer) -> bool:
	var meteor := wanderer.get_tree().current_scene.get_node("Bodies/StaticMid") as SpaceRock
	for node in wanderer.get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null:
			continue
		rock.sync_to_physics = false
		rock.drift_velocity = Vector2.ZERO
		rock.spin = 0.0
		if rock != meteor:
			rock.global_position += Vector2(0, 50000)
	meteor.global_position = Vector2(4000, 4000)
	meteor.scale = Vector2(0.5, 0.5)
	wanderer._controls_locked = true
	if not _flies_into(wanderer, meteor, 320.0):
		fail("Быстрый удар в лёгкий астероид должен цеплять")
		return false
	wanderer.undock()
	var reach := meteor.get_hit_radius() + wanderer._self_radius
	wanderer.global_position = meteor.global_position + Vector2(reach - 8.0, 0.0)
	wanderer.velocity = Vector2(300.0, 40.0)
	wanderer._physics_process(1.0 / 60.0)
	if not wanderer.dock.docked or wanderer.dock.body != meteor:
		fail("Уже внутри астероида на скорости должны прилипнуть, а не вылететь")
		return false
	wanderer.global_position = meteor.global_position + Vector2(reach + 2.0, 0.0)
	wanderer.velocity = Vector2(160.0, 0.0)
	wanderer.dock_to(meteor, Vector2.RIGHT)
	wanderer.undock()
	for _i in 6:
		wanderer._physics_process(1.0 / 60.0)
		if wanderer.dock.docked:
			fail("Прыжок прочь не должен сразу прилипать обратно")
			return false
	return true


func _flies_into(wanderer: Wanderer, meteor: SpaceRock, speed: float) -> bool:
	wanderer.undock()
	var reach := meteor.get_hit_radius() + wanderer._self_radius
	wanderer.global_position = meteor.global_position + Vector2(reach + 20.0, 0.0)
	wanderer.velocity = Vector2(-speed, 0.0)
	for _i in 20:
		wanderer._physics_process(1.0 / 60.0)
		if wanderer.dock.docked:
			return wanderer.dock.body == meteor
	return false
