extends "res://tests/scene_check.gd"

## Пушка: отдача, попадание делит ход и спин, изнутри выстрела нет.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	wanderer.set_physics_process(false)
	if not _check_hit(scene, wanderer):
		return
	if not _check_kick_off(scene, wanderer):
		return
	if not _check_inside(scene, wanderer):
		return
	print("GUN_OK")
	quit(0)


func _check_hit(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticMid") as SpaceRock
	_quiet(rock)
	rock.rotation = 0.0
	rock.global_position = Vector2(120000, 120000)
	wanderer.undock()
	wanderer.velocity = Vector2.ZERO
	var rim := rock.get_hit_radius() * 0.65
	wanderer.global_position = rock.global_position + Vector2(-(rock.get_hit_radius() + 80.0), rim)
	wanderer.fire_gun(Vector2.RIGHT)
	if absf(wanderer.velocity.x + Gun.RECOIL_SPEED) > 0.05 or absf(wanderer.velocity.y) > 0.05:
		fail("Выстрел в пустоте не отдал назад: %s" % wanderer.velocity)
		return false
	for _i in 12:
		wanderer.gun.integrate(wanderer, 0.05)
	if rock.drift_velocity.x <= 1.0 or absf(rock.spin) <= 0.05:
		fail("Боковое попадание не поделило ход и спин: v %.1f w %.3f" % [rock.drift_velocity.x, rock.spin])
		return false
	if wanderer.gun.rounds.size() != 0:
		fail("Пуля осталась после попадания")
		return false
	return true


func _check_kick_off(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	_quiet(rock)
	rock.global_position = Vector2(-120000, -120000)
	wanderer.gun.rounds.clear()
	wanderer.undock()
	wanderer.velocity = Vector2.ZERO
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 14.0)
	wanderer.dock_to(rock, Vector2.UP)
	wanderer.fire_gun(Vector2.RIGHT)
	if wanderer.dock.docked or wanderer.velocity.x >= -1.0:
		fail("Выстрел с камня не оттолкнул")
		return false
	if rock.drift_velocity.x <= 0.01:
		fail("Опора не получила отдачу выстрела")
		return false
	wanderer.gun.integrate(wanderer, 0.05)
	if wanderer.gun.rounds.is_empty():
		fail("Пуля сразу села в камень под ногами")
		return false
	return true


func _check_inside(scene: Node, wanderer: Wanderer) -> bool:
	var hull := scene.get_node("Bodies/HullFed01") as SpaceRock
	_quiet(hull)
	wanderer.gun.rounds.clear()
	wanderer.undock()
	wanderer.global_position = hull.global_position
	if not wanderer.enter_interior(hull):
		fail("Для проверки пушки не пустил внутрь")
		return false
	var kept := wanderer.velocity
	wanderer.fire_gun(Vector2.RIGHT)
	if wanderer.gun.rounds.size() != 0 or wanderer.velocity.distance_to(kept) > 0.01:
		fail("Внутри корпуса пушка выстрелила")
		return false
	return true


func _quiet(rock: SpaceRock) -> void:
	rock.sync_to_physics = false
	rock.spin = 0.0
	rock.drift_velocity = Vector2.ZERO
