extends "res://tests/scene_check.gd"

## Шов: масса груза, трос, импульс в пустоте, боковой снос, люк.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	wanderer.set_physics_process(false)
	if not _check_signals_and_cargo(scene, wanderer):
		return
	if not _check_leak(scene, wanderer):
		return
	if not _check_void(wanderer):
		return
	if not _check_tether(scene, wanderer):
		return
	if not _check_hatch(scene, wanderer):
		return
	print("CORE_OK")
	quit(0)


func _check_signals_and_cargo(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	rock.sync_to_physics = false
	rock.spin = 0.0
	rock.drift_velocity = Vector2.ZERO
	_stand(wanderer, rock)
	var bare := SpaceRock.push_share(Wanderer.MASS, rock.get_mass())
	var bare_launch := wanderer.launch_velocity(Vector2.RIGHT, 1.0).length()
	wanderer.cargo_mass = 2000.0
	var loaded := SpaceRock.push_share(wanderer.get_mass(), rock.get_mass())
	if loaded >= bare:
		fail("Груз не уменьшил долю скорости скитальца")
		return false
	var loaded_launch := wanderer.launch_velocity(Vector2.RIGHT, 1.0).length()
	if loaded_launch >= bare_launch - 0.5:
		fail("Прицел не стал короче от массы груза")
		return false
	if wanderer.asteroid_dock_speed(rock) < 1.0e12:
		fail("Груз не должен возвращать порог скорости посадки")
		return false
	wanderer.cargo_mass = 0.0

	var pushes: Array[float] = []
	wanderer.pushed.connect(func(desired: Vector2, charge: float) -> void:
		pushes.append(charge)
		if desired.length_squared() < 1.0:
			pushes.append(-1.0)
	)
	var docks: Array[bool] = []
	wanderer.dock_changed.connect(func(docked: bool, _body: Node2D) -> void:
		docks.append(docked)
	)
	wanderer._charge = 1.0
	wanderer._commit_push(Vector2.RIGHT)
	if pushes.size() != 1 or pushes[0] != 1.0:
		fail("Толчок не отдал сигнал pushed")
		return false
	if docks.is_empty() or docks[docks.size() - 1]:
		fail("Толчок не сообщил, что ноги отцепились")
		return false
	return true


func _check_leak(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	_stand(wanderer, rock)
	wanderer.leak_bias = 0.0
	var straight := wanderer.push_desired(Vector2.RIGHT, 1.0)
	wanderer.leak_bias = 0.5
	var biased := wanderer.push_desired(Vector2.RIGHT, 1.0)
	var launch := wanderer.launch_velocity(Vector2.RIGHT, 1.0)
	wanderer.leak_bias = 0.0
	if absf(straight.y) > 0.01:
		fail("Без пробоины толчок ушёл вбок")
		return false
	if biased.y <= straight.length() * 0.4:
		fail("Пробоина не сносит вектор толчка")
		return false
	if launch.y <= 0.0:
		fail("Прицел не показывает боковой снос")
		return false
	return true


func _check_void(wanderer: Wanderer) -> bool:
	var rock := wanderer.dock.rock()
	if rock != null and wanderer.add_void_impulse(Vector2.RIGHT, 40.0):
		fail("Импульс в пустоте сработал, пока ноги на теле")
		return false
	wanderer.undock()
	wanderer.global_position = Vector2(-80000, -80000)
	wanderer.velocity = Vector2.ZERO
	if not wanderer.add_void_impulse(Vector2.RIGHT, 40.0):
		fail("Импульс в пустоте не принят")
		return false
	if wanderer.dock.docked:
		fail("Импульс без опоры посадил на тело")
		return false
	if absf(wanderer.velocity.x - 40.0) > 0.05 or absf(wanderer.velocity.y) > 0.05:
		fail("Импульс в пустоте не совпал со скоростью")
		return false
	return true


func _check_tether(scene: Node, wanderer: Wanderer) -> bool:
	var heavy := scene.get_node("Bodies/StaticNear") as SpaceRock
	var light := scene.get_node("Bodies/StaticMid") as SpaceRock
	_quiet(heavy)
	_quiet(light)
	light.scale = Vector2(0.35, 0.35)
	if light.get_mass() >= wanderer.get_mass():
		fail("Подопытный камень не стал легче скитальца")
		return false
	if heavy.get_mass() <= wanderer.get_mass():
		fail("Тяжёлый камень легче скитальца")
		return false

	wanderer.undock()
	wanderer.velocity = Vector2(25, 0)
	heavy.drift_velocity = Vector2(-4, 0)
	wanderer.global_position = heavy.global_position + Vector2(80, 0)
	wanderer.tether.plant(wanderer, heavy, heavy.global_position)
	wanderer.tether.length = 400.0
	var keep_v := wanderer.velocity
	var keep_d := heavy.drift_velocity
	wanderer.tether.integrate(wanderer, 0.016)
	if wanderer.velocity.distance_to(keep_v) > 0.01 or heavy.drift_velocity.distance_to(keep_d) > 0.01:
		fail("Слабина потянула")
		return false

	if not _pulls(wanderer, heavy, true):
		return false
	if not _pulls(wanderer, light, false):
		return false

	wanderer.tether.release()
	wanderer.global_position = Vector2(90000, 90000)
	wanderer.velocity = Vector2.ZERO
	light.global_position = wanderer.global_position + Vector2(90, 0)
	light.drift_velocity = Vector2.ZERO
	wanderer.tether.fire(wanderer, wanderer.global_position, Vector2.RIGHT, null)
	for _i in 12:
		wanderer.tether.integrate(wanderer, 0.05)
	if not wanderer.tether.linked() or wanderer.tether.anchor != light:
		fail("Болт не зацепился за камень на курсе")
		return false
	if not wanderer.tether.ignited:
		fail("Вплавление без вспышки")
		return false
	var reach := wanderer.character_size() * Tether.BODIES
	if absf(wanderer.tether.length - reach) > 0.5:
		fail("Длина троса не равна %d размерам скитальца" % int(Tether.BODIES))
		return false

	if light.drift_velocity.x <= 1.0:
		fail("Попадание не дало импульс телу")
		return false
	wanderer.tether.release()
	if wanderer.tether.linked():
		fail("Трос не отцепился")
		return false
	if not wanderer.tether.ignited or wanderer.tether.burst <= 0.0:
		fail("Отцеп без вспышки в точке крепления")
		return false

	if not _check_recoil_reel_and_cap(wanderer, heavy, light):
		return false

	wanderer.tether.plant(wanderer, heavy, heavy.global_position)
	wanderer.global_position = Vector2(-90000, 40000)
	wanderer.velocity = Vector2(-200, 0)
	wanderer._lost_time = 5.0
	wanderer._physics_process(0.2)
	if wanderer._dead or wanderer._lost_time > 0.01:
		fail("На тросе сработал курс в никуда")
		return false
	return true


func _check_recoil_reel_and_cap(wanderer: Wanderer, heavy: SpaceRock, light: SpaceRock) -> bool:
	wanderer.tether.release()
	wanderer.undock()
	wanderer.global_position = Vector2(-70000, -70000)
	wanderer.velocity = Vector2.ZERO
	wanderer.fire_harpoon(Vector2.RIGHT)
	if wanderer.dock.docked:
		fail("Отдача выстрела оставила ноги на теле")
		return false
	if wanderer.velocity.x >= -Tether.RECOIL_SPEED + 1.0:
		fail("Выстрел не толкнул назад")
		return false
	wanderer.tether.release()

	_quiet(heavy)
	_stand(wanderer, heavy)
	var before := heavy.drift_velocity.x
	wanderer.fire_harpoon(Vector2.RIGHT)
	if wanderer.dock.docked or wanderer.velocity.x >= -1.0:
		fail("С тела выстрел не отдал назад")
		return false
	if heavy.drift_velocity.x <= before + 0.2:
		fail("Опора не получила реакцию выстрела")
		return false
	wanderer.tether.release()

	_quiet(heavy)
	wanderer.undock()
	wanderer.velocity = Vector2.ZERO
	wanderer.global_position = Vector2(-60000, -60000)
	heavy.global_position = wanderer.global_position + Vector2(100, 0)
	wanderer.tether.plant(wanderer, heavy, heavy.global_position)
	wanderer.tether.length = 180.0
	wanderer.tether.integrate(wanderer, 1.0, true)
	if wanderer.tether.length > 50.0:
		fail("Втягивание не укоротило трос")
		return false
	if wanderer.velocity.x <= 1.0:
		fail("Втягивание не ускорило к телу")
		return false

	_quiet(light)
	wanderer.velocity = Vector2.ZERO
	wanderer.tether.plant(wanderer, light, light.global_position)
	wanderer.tether.length = 30.0
	wanderer.global_position = light.global_position + Vector2(160, 0)
	wanderer.tether.integrate(wanderer, 0.016, false)
	var span := wanderer.global_position.distance_to(wanderer.tether.anchor_global())
	if span > wanderer.tether.length + 1.5:
		fail("Трос растянулся дальше своей длины")
		return false

	var far := wanderer.character_size() * Tether.BODIES + 80.0
	wanderer.tether.release()
	wanderer.velocity = Vector2.ZERO
	light.global_position = wanderer.global_position + Vector2(far, 0)
	light.drift_velocity = Vector2.ZERO
	wanderer.tether.fire(wanderer, wanderer.global_position, Vector2.RIGHT, null)
	for _i in 40:
		wanderer.tether.integrate(wanderer, 0.05, false)
	if wanderer.tether.linked():
		fail("Болт зацепился дальше двадцати размеров")
		return false
	return true


func _pulls(wanderer: Wanderer, rock: SpaceRock, host_moves_more: bool) -> bool:
	_quiet(rock)
	wanderer.undock()
	wanderer.tether.release()
	wanderer.velocity = Vector2.ZERO
	wanderer.global_position = rock.global_position + Vector2(140, 0)
	wanderer.tether.plant(wanderer, rock, rock.global_position)
	wanderer.tether.length = 20.0
	wanderer.tether.integrate(wanderer, 0.016)
	var host_speed := absf(wanderer.velocity.x)
	var rock_speed := absf(rock.drift_velocity.x)
	if wanderer.velocity.x >= -1.0:
		fail("Натяг не потянул скитальца к телу")
		return false
	if rock.drift_velocity.x <= 1.0:
		fail("Натяг не потянул тело к скитальцу")
		return false
	if host_moves_more and host_speed <= rock_speed:
		fail("Тяжёлое тело сдвинулось сильнее скитальца")
		return false
	if not host_moves_more and rock_speed <= host_speed:
		fail("Лёгкое тело не приехало к скитальцу")
		return false
	return true


func _check_hatch(scene: Node, wanderer: Wanderer) -> bool:
	var asteroid := scene.get_node("Bodies/StaticNear") as SpaceRock
	var hull := scene.get_node("Bodies/HullFed01") as SpaceRock
	_quiet(hull)
	wanderer.tether.release()
	wanderer.undock()
	if wanderer.enter_interior(asteroid):
		fail("В астероид пустил люк")
		return false
	wanderer.global_position = hull.global_position
	if not wanderer.enter_interior(hull):
		fail("В корпус не пустил люк")
		return false
	if not wanderer.dock.inside:
		fail("После входа скиталец не внутри")
		return false
	var shape := wanderer.get_node("CollisionShape2D") as CollisionShape2D
	if not shape.disabled:
		fail("Внутри корпус всё ещё толкает круг")
		return false
	wanderer.velocity = Vector2(4000, 0)
	wanderer._lost_time = 4.0
	wanderer._physics_process(0.5)
	if not wanderer.dock.inside or wanderer._dead or wanderer._lost_time > 0.01:
		fail("Внутри сработала гибель или выкинуло в космос")
		return false
	var local := hull.to_local(wanderer.global_position)
	if not Geometry2D.is_point_in_polygon(local, hull.outline.points):
		fail("Внутри скиталец стоит снаружи контура")
		return false
	wanderer.exit_interior()
	if wanderer.dock.inside or wanderer.dock.docked:
		fail("Выход из люка оставил посадку")
		return false
	local = hull.to_local(wanderer.global_position)
	if Geometry2D.is_point_in_polygon(local, hull.outline.points):
		fail("Выход из люка оставил скитальца в контуре")
		return false
	if shape.disabled:
		fail("Снаружи круг так и выключен")
		return false
	return true


func _stand(wanderer: Wanderer, rock: SpaceRock) -> void:
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)


func _quiet(rock: SpaceRock) -> void:
	rock.sync_to_physics = false
	rock.spin = 0.0
	rock.drift_velocity = Vector2.ZERO
