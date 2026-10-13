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
	var light_reach := 26.0 * 0.35
	light.scale *= light_reach / maxf(light.get_hit_radius(), 1.0)
	if light.get_mass() >= wanderer.get_mass():
		fail("Подопытный камень не стал легче скитальца")
		return false
	if heavy.get_mass() <= wanderer.get_mass():
		fail("Тяжёлый камень легче скитальца")
		return false
	if not _check_rope_ride(wanderer, heavy, light):
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
	var span := wanderer.global_position.distance_to(wanderer.tether.anchor_global())
	if absf(wanderer.tether.length - span) > 1.0:
		fail("После зацепа трос не натянут до крюка")
		return false
	if wanderer.tether.length > reach + 0.5:
		fail("Трос длиннее %d размеров скитальца" % int(Tether.BODIES))
		return false

	if light.drift_velocity.x <= 1.0:
		fail("Попадание не дало импульс телу")
		return false
	wanderer.tether.release()
	if wanderer.tether.linked():
		fail("Трос не отцепился")
		return false
	if wanderer.tether.ignited:
		fail("Отцеп зажёг вспышку у наконечника")
		return false

	if not _check_recoil_reel_and_cap(wanderer, heavy, light):
		return false

	if not _check_pin(wanderer, heavy, light):
		return false
	if not _check_rope_shares_motion(wanderer, heavy, light):
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


func _check_rope_ride(wanderer: Wanderer, heavy: SpaceRock, light: SpaceRock) -> bool:
	_quiet(heavy)
	_quiet(light)
	heavy.rotation = 0.0
	light.rotation = 0.0
	light.global_position = heavy.global_position + Vector2(400, 0)
	wanderer.tether.release()
	wanderer.undock()
	wanderer.global_position = heavy.global_position + Vector2(0, -heavy.get_hit_radius() - 30.0)
	wanderer.dock_to(heavy, Vector2.UP)
	wanderer.tether.plant(wanderer, light, light.global_position + Vector2(-light.get_hit_radius(), 0))
	var locked := wanderer._controls_locked
	wanderer._controls_locked = false
	var feet := wanderer.global_position
	wanderer.tether.burst = 0.0
	wanderer.tether.burst_dir = Vector2.ZERO
	if not wanderer.pin_tether():
		wanderer._controls_locked = locked
		fail("Трос для поездки не закрепился")
		return false
	wanderer._controls_locked = locked
	var laid := wanderer.fixed_ropes[wanderer.fixed_ropes.size() - 1]
	if laid.burst <= 0.0 or laid.burst_dir.dot(laid.home_global() - heavy.global_position) <= 0.0:
		_clear_ride(wanderer)
		fail("Второй конец сел без пыли стыковки")
		return false
	if laid.home_global().distance_to(heavy.global_position) > feet.distance_to(heavy.global_position) - 4.0:
		_clear_ride(wanderer)
		fail("Второй конец остался на месте героя")
		return false
	var frozen := laid.length
	var gap := laid.home_global().distance_to(laid.anchor_global())
	if absf(frozen - gap) > 1.0:
		_clear_ride(wanderer)
		fail("Закреплённый трос не зафиксировал длину")
		return false
	var light_at := light.global_position
	var heavy_at := heavy.global_position
	var light_rot := light.rotation
	var heavy_rot := heavy.rotation
	var pull := light.global_position - heavy.global_position
	if pull.length_squared() < 1.0:
		_clear_ride(wanderer)
		fail("Концы закреплённого троса совпали")
		return false
	pull = pull.normalized()
	light.global_position -= pull * 20.0
	laid.integrate(wanderer, 0.016, false)
	if absf(laid.length - frozen) > 0.01:
		_clear_ride(wanderer)
		fail("Длина закреплённого троса изменилась")
		return false
	if light.drift_velocity.dot(pull) <= 1.0:
		_clear_ride(wanderer)
		fail("Укороченный трос не раздвинул камни")
		return false
	light.global_position = light_at
	heavy.global_position = heavy_at
	light.rotation = light_rot
	heavy.rotation = heavy_rot
	light.drift_velocity = Vector2.ZERO
	heavy.drift_velocity = Vector2.ZERO
	light.spin = 0.0
	heavy.spin = 0.0
	var home := laid.home_global()
	var hook := laid.anchor_global()
	wanderer.drop_rope()
	wanderer.undock()
	wanderer.global_position = home + Vector2(0, 400)
	wanderer._controls_locked = false
	wanderer.toggle_hatch()
	wanderer._controls_locked = locked
	if wanderer._ride != null:
		_clear_ride(wanderer)
		fail("Далёкий трос принял F")
		return false
	var mid := home.lerp(hook, 0.5)
	wanderer.global_position = mid + Vector2(0, 20)
	if not wanderer.grab_nearest_rope():
		_clear_ride(wanderer)
		fail("Близкий трос не принял героя")
		return false
	var span := hook - home
	var rel := wanderer.global_position - home
	var off_rope := absf(rel.x * span.y - rel.y * span.x) / span.length()
	if off_rope > 1.0 or wanderer.global_position.distance_to(mid) > 25.0:
		_clear_ride(wanderer)
		fail("Герой сел мимо троса")
		return false
	var before := wanderer.global_position
	wanderer._slide_rope(1.0, 0.25)
	if wanderer.global_position.distance_to(before) < 5.0:
		_clear_ride(wanderer)
		fail("D не сдвинул по тросу")
		return false
	var sprite := wanderer.get_node("Sprite") as Sprite2D
	var arm := Vector2.RIGHT.rotated(sprite.rotation)
	if absf(absf(arm.dot(span.normalized())) - 1.0) > 0.05:
		_clear_ride(wanderer)
		fail("Герой на тросе не лежит боком")
		return false
	if sprite.texture != wanderer.GRAB_SPRITE or sprite.frame != Wanderer.GRAB_FRAME_COUNT - 1:
		_clear_ride(wanderer)
		fail("На тросе руки не сжались как на астероиде")
		return false
	if sprite.position.length() < 4.0:
		_clear_ride(wanderer)
		fail("Трос проходит через центр, а не через руки")
		return false
	var body_below := sprite.position
	if span.cross(Vector2(0, 20)) * span.cross(body_below) <= 0.0:
		_clear_ride(wanderer)
		fail("Снизу корпус смотрит не в сторону подхода")
		return false
	var held := wanderer.global_position
	wanderer.drop_rope()
	wanderer.global_position = mid + Vector2(0, -20)
	if not wanderer.grab_nearest_rope():
		_clear_ride(wanderer)
		fail("Подход сверху не принял трос")
		return false
	if span.cross(Vector2(0, -20)) * span.cross(sprite.position) <= 0.0 or body_below.dot(sprite.position) >= 0.0:
		_clear_ride(wanderer)
		fail("Сверху сторона зацепа не сменилась")
		return false
	wanderer.drop_rope()
	wanderer.global_position = held
	if not wanderer.grab_nearest_rope():
		_clear_ride(wanderer)
		fail("Возврат на трос после смены стороны не вышел")
		return false
	wanderer._slide_rope(-1.0, 0.25)
	if wanderer.global_position.distance_to(before) > 2.0:
		_clear_ride(wanderer)
		fail("A не вернул по тросу")
		return false
	wanderer._slide_rope(1.0, 30.0)
	var past := wanderer.global_position.distance_to(home) > home.distance_to(hook) + 1.0
	past = past or wanderer.global_position.distance_to(hook) > home.distance_to(hook) + 1.0
	if past:
		_clear_ride(wanderer)
		fail("Герой съехал за конец троса")
		return false
	wanderer._publish_views()
	var view := wanderer.get_node("TetherView") as TetherView
	var line: Line2D = view._fixed_lines[view._fixed_lines.size() - 1]
	if line.points.size() < 2:
		_clear_ride(wanderer)
		fail("У конца трос пропал")
		return false
	var cable := line.points[1] - line.points[0]
	var to_hero := -line.points[0]
	var off := absf(to_hero.x * cable.y - to_hero.y * cable.x) / cable.length()
	if off > 1.5:
		_clear_ride(wanderer)
		fail("Герой сошёл с линии троса")
		return false
	wanderer.global_position = mid
	wanderer._ride_u = 0.5
	wanderer._lost_time = 5.0
	wanderer._physics_process(0.05)
	if wanderer._lost_time > 0.01 or wanderer._ride != laid:
		_clear_ride(wanderer)
		fail("Поездка по тросу пустила курс в никуда")
		return false
	wanderer._controls_locked = false
	wanderer.toggle_hatch()
	wanderer._controls_locked = locked
	if wanderer._ride != null or wanderer.dock.docked:
		_clear_ride(wanderer)
		fail("F без астероида не отпустил трос")
		return false
	var pin := laid.anchor_global()
	wanderer._ride = laid
	wanderer._ride_u = 1.0
	wanderer.global_position = pin
	var steps := 0
	while wanderer._buried_asteroid() != null and steps < 24:
		wanderer.global_position += Vector2.DOWN * 8.0
		steps += 1
	if wanderer._buried_asteroid() != null:
		_clear_ride(wanderer)
		fail("Конец троса не вывести из периметра")
		return false
	wanderer._controls_locked = false
	wanderer.toggle_hatch()
	wanderer._controls_locked = locked
	if wanderer._ride != null or not wanderer.dock.docked or wanderer.dock.body != light:
		_clear_ride(wanderer)
		fail("F у конца троса не посадил на камень")
		return false
	wanderer._controls_locked = false
	wanderer.toggle_hatch()
	wanderer._controls_locked = locked
	if wanderer.dock.docked or wanderer._ride != null:
		_clear_ride(wanderer)
		fail("F на астероиде не отпустил его")
		return false
	if wanderer.velocity.length() > 4.0:
		_clear_ride(wanderer)
		fail("Отпускание без шага бросило героя")
		return false
	wanderer.dock_to(light, Vector2.LEFT)
	var outward := wanderer.dock.outward()
	Input.action_press(&"move_right")
	wanderer._controls_locked = false
	wanderer.toggle_hatch()
	Input.action_release(&"move_right")
	wanderer._controls_locked = locked
	var tangent := Vector2(-outward.y, outward.x)
	if wanderer.velocity.length() < 20.0 or absf(wanderer.velocity.dot(outward)) > absf(wanderer.velocity.dot(tangent)):
		_clear_ride(wanderer)
		fail("Отпускание на шаге ушло не по касательной")
		return false
	wanderer._physics_process(0.05)
	if wanderer.dock.docked:
		_clear_ride(wanderer)
		fail("Отпущенный астероид сразу поймал героя")
		return false
	_clear_ride(wanderer)
	return true


func _clear_ride(wanderer: Wanderer) -> void:
	wanderer.drop_rope()
	wanderer.fixed_ropes.clear()
	wanderer.tether.release()
	wanderer.undock()


func _check_pin(wanderer: Wanderer, heavy: SpaceRock, light: SpaceRock) -> bool:
	wanderer.tether.release()
	wanderer.undock()
	_quiet(heavy)
	_quiet(light)
	light.global_position = heavy.global_position + Vector2(220, 0)
	wanderer.global_position = heavy.global_position + Vector2(0, -heavy.get_hit_radius() - 30.0)
	wanderer.dock_to(heavy, Vector2.UP)
	if not wanderer.dock.docked or wanderer.dock.body != heavy:
		fail("Не встал на камень для второго конца")
		return false
	if wanderer.tether.pin_home(wanderer):
		fail("Второй конец сел без крюка")
		return false
	wanderer.tether.plant(wanderer, light, light.global_position + Vector2(light.get_hit_radius(), 0))
	var feet := wanderer.global_position
	wanderer.tether.burst = 0.0
	wanderer.tether.burst_dir = Vector2.ZERO
	if not wanderer.pin_tether():
		fail("Второй конец не сел на камень под ногами")
		return false
	if wanderer.tether.linked() or wanderer.tether.pinned():
		fail("После закрепления у героя не появился новый трос")
		return false
	var laid := wanderer.fixed_ropes[0]
	if laid.burst <= 0.0 or laid.burst_dir.dot(laid.home_global() - heavy.global_position) <= 0.0:
		fail("Второй конец сел без пыли стыковки")
		return false
	if laid.home_global().distance_to(heavy.global_position) > feet.distance_to(heavy.global_position) - 4.0:
		fail("Второй конец остался на месте героя")
		return false
	var before := laid.home_global()
	heavy.rotation += 0.6
	if laid.home_global().distance_to(before) < 1.0:
		fail("Второй конец не повернулся вместе с астероидом")
		return false
	wanderer.global_position += Vector2(90, 0)
	wanderer.velocity = Vector2(40, 0)
	var keep := wanderer.velocity
	laid.integrate(wanderer, 0.016, true)
	if wanderer.velocity.distance_to(keep) > 0.01:
		fail("Закреплённый трос потянул героя")
		return false
	wanderer.tether.release()
	if wanderer.fixed_ropes.is_empty() or not laid.pinned():
		fail("Q снял закреплённый трос")
		return false
	return true


func _check_rope_shares_motion(wanderer: Wanderer, heavy: SpaceRock, light: SpaceRock) -> bool:
	wanderer.tether.release()
	wanderer.undock()
	_quiet(heavy)
	_quiet(light)
	heavy.rotation = 0.0
	light.rotation = 0.0
	heavy.spin = 0.0
	light.spin = 0.0
	light.global_position = heavy.global_position + Vector2(400, 0)
	wanderer.global_position = heavy.global_position + Vector2(0, -heavy.get_hit_radius() - 30.0)
	wanderer.dock_to(heavy, Vector2.UP)
	wanderer.tether.plant(wanderer, light, light.global_position + Vector2(-light.get_hit_radius(), 0))
	if not wanderer.pin_tether():
		fail("Трос между камнями не закрепился")
		return false
	var laid := wanderer.fixed_ropes[0]
	var origin := laid.anchor_global()
	var other := laid.home_global()
	var along := other - origin
	if along.length_squared() < 1.0:
		fail("Концы троса совпали")
		return false
	along = along.normalized()
	laid.length = maxf(origin.distance_to(other) - 2.0, Tether.MIN_LENGTH)
	light.drift_velocity = -along * 90.0
	heavy.drift_velocity = Vector2.ZERO
	var pulling := light.drift_velocity.dot(-along)
	laid.integrate(wanderer, 0.016, false)
	if heavy.drift_velocity.dot(-along) <= 1.0:
		fail("Трос не передал движение второму астероиду")
		return false
	if light.drift_velocity.dot(-along) >= pulling - 1.0:
		fail("Трос не забрал скорость у астероида, который тянет")
		return false
	wanderer.tether.release()
	if wanderer.fixed_ropes.is_empty():
		fail("Q снял трос между астероидами")
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
	if not wanderer.tether.flying() or wanderer.tether.anchor == heavy:
		fail("Выстрел с камня сразу сел на него")
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
	if wanderer.tether.length > 180.0 - Tether.REEL_RATE + 5.0:
		fail("Втягивание не укоротило трос")
		return false
	if wanderer.velocity.x <= 1.0:
		fail("Втягивание не ускорило к телу")
		return false

	_quiet(heavy)
	_stand(wanderer, heavy)
	wanderer.velocity = Vector2.ZERO
	heavy.drift_velocity = Vector2.ZERO
	heavy.spin = 0.0
	wanderer.tether.plant(wanderer, heavy, heavy.global_position)
	wanderer.tether.length = 8.0
	for _i in 30:
		wanderer.tether.integrate(wanderer, 0.016, true)
		if wanderer.dock.docked:
			wanderer.follow_dock()
	if not wanderer.dock.docked or wanderer.dock.body != heavy:
		fail("Втягивание на своём астероиде оторвало ноги")
		return false
	if heavy.drift_velocity.length() > 1.0 or absf(heavy.spin) > 0.05:
		fail("Втягивание на своём астероиде разогнало камень")
		return false
	if wanderer.velocity.length() > 1.0:
		fail("Втягивание на своём астероиде разогнало скитальца")
		return false

	_quiet(light)
	wanderer.undock()
	wanderer.tether.release()
	wanderer.velocity = Vector2.ZERO
	light.drift_velocity = Vector2.ZERO
	light.spin = 0.0
	wanderer.global_position = light.global_position + Vector2(4, 0)
	wanderer.tether.plant(wanderer, light, light.global_position + Vector2(light.get_hit_radius(), 0))
	wanderer.tether.length = 8.0
	wanderer.tether.integrate(wanderer, 0.016, true)
	if light.drift_velocity.length() > 1.0 or absf(light.spin) > 0.05:
		fail("Стыковка на крюке раскрутила астероид")
		return false

	_quiet(light)
	wanderer.velocity = Vector2.ZERO
	light.drift_velocity = Vector2.ZERO
	wanderer.tether.plant(wanderer, light, light.global_position)
	wanderer.tether.length = 30.0
	wanderer.global_position = light.global_position + Vector2(160, 0)
	var stayed := wanderer.global_position
	wanderer.tether.integrate(wanderer, 0.016, false)
	var span := wanderer.global_position.distance_to(wanderer.tether.anchor_global())
	if wanderer.global_position.distance_to(stayed) > 1.5:
		fail("Без E трос вернул скитальца")
		return false
	if wanderer.velocity.length() > 1.0 or light.drift_velocity.length() > 1.0:
		fail("Без E трос толкнул")
		return false
	if absf(wanderer.tether.length - span) > 1.5:
		fail("Без E трос не отпустил от крюка")
		return false
	var reach := wanderer.character_size() * Tether.BODIES
	wanderer.tether.length = reach
	wanderer.velocity = Vector2.ZERO
	light.drift_velocity = Vector2.ZERO
	wanderer.global_position = light.global_position + Vector2(reach + 80.0, 0)
	wanderer.tether.integrate(wanderer, 0.016, false)
	span = wanderer.global_position.distance_to(wanderer.tether.anchor_global())
	if span > wanderer.tether.length + 1.5:
		fail("Трос растянулся дальше предела")
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
	wanderer.tether.integrate(wanderer, 0.016, true)
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
