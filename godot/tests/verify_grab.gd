extends "res://tests/scene_check.gd"

## Посадка на астероид проигрывает захват и держит последний кадр.
## Корпус и отрыв возвращают обычный спрайт.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot(4)
	if scene == null:
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	var sprite: Sprite2D = wanderer.get_node("Sprite")
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	rock.sync_to_physics = false
	rock.spin = 0.0
	rock.drift_velocity = Vector2.ZERO

	_redock(wanderer, rock)
	if not _grab_started(sprite):
		fail("Захват не начался с первого кадра")
		return
	if not await _grab_holds(sprite):
		return

	wanderer.undock()
	if not _is_idle(sprite):
		fail("После отрыва остался захват")
		return

	var hull := scene.get_node("Bodies/HullFed01") as SpaceRock
	wanderer.dock_to(hull, Vector2.UP)
	if not wanderer.dock.has_hull() or not _is_idle(sprite):
		fail("На корпусе должен остаться обычный спрайт")
		return

	var meteor := scene.get_node("Bodies/Meteor01") as SpaceRock
	_redock(wanderer, meteor)
	if not wanderer.dock.has_shape() or not _grab_started(sprite):
		fail("На силуэте захват не начался")
		return

	print("GRAB_OK")
	quit(0)


func _redock(wanderer: Wanderer, rock: SpaceRock) -> void:
	wanderer.undock()
	var gap := rock.get_hit_radius() + 40.0
	wanderer.global_position = rock.global_position + Vector2(0, -gap)
	wanderer.dock_to(rock, Vector2.UP)


func _grab_started(sprite: Sprite2D) -> bool:
	return sprite.hframes == Wanderer.GRAB_FRAME_COUNT \
			and sprite.frame == 0 \
			and str(sprite.texture.resource_path).ends_with("wanderer_grab.png")


func _is_idle(sprite: Sprite2D) -> bool:
	return sprite.hframes == 1 and str(sprite.texture.resource_path).ends_with("wanderer.png") \
			and not str(sprite.texture.resource_path).ends_with("wanderer_grab.png")


func _grab_holds(sprite: Sprite2D) -> bool:
	var last := Wanderer.GRAB_FRAME_COUNT - 1
	paused = false
	for _i in 45:
		if sprite.frame == last:
			break
		await physics_frame
	if sprite.frame != last:
		fail("Захват не дошёл до последнего кадра")
		return false
	for _i in 12:
		await physics_frame
	if sprite.frame != last or sprite.hframes != Wanderer.GRAB_FRAME_COUNT:
		fail("Последний кадр захвата не держится")
		return false
	return true
