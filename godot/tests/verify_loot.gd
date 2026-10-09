extends SceneTree

## Один свободный баллон у старта. Отскакивает от камня любой глубины.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		quit(1)
		return
	for _i in 4:
		await process_frame

	var loots := get_nodes_in_group("loot")
	if loots.size() != 1:
		push_error("На старте должен быть один баллон, сейчас %d" % loots.size())
		quit(1)
		return

	var loot := loots[0] as Loot
	if loot.get_parent() is SpaceRock:
		push_error("Баллон не должен висеть на астероиде")
		quit(1)
		return

	var start := get_current_scene().get_node("Bodies/StaticNear") as SpaceRock
	var gap := loot.global_position.distance_to(start.global_position) - start.get_hit_radius() - Loot.HIT_RADIUS
	if gap < 8.0:
		push_error("Баллон внутри стартового камня")
		quit(1)
		return
	var wanderer := get_current_scene().get_node("Wanderer") as Wanderer
	if loot.global_position.distance_to(wanderer.global_position) > 320.0:
		push_error("Баллон не в стартовом кадре")
		quit(1)
		return

	var rock_a: SpaceRock = null
	var rock_b: SpaceRock = null
	for node in get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == start:
			continue
		if rock_a == null:
			rock_a = rock
			continue
		if rock.depth != rock_a.depth:
			rock_b = rock
			break
	if rock_a == null or rock_b == null:
		push_error("Нет двух камней разной глубины")
		quit(1)
		return
	if not _bounces_off(loot, rock_a) or not _bounces_off(loot, rock_b):
		push_error("Баллон должен отскакивать от камней любой глубины")
		quit(1)
		return

	wanderer._controls_locked = false
	wanderer._oxygen = 1800.0
	wanderer.global_position = loot.global_position
	loot._physics_process(0.016)
	if loot.is_queued_for_deletion():
		push_error("Полный запас не должен забирать баллон")
		quit(1)
		return

	wanderer._oxygen = 100.0
	loot._physics_process(0.016)
	if not loot.is_queued_for_deletion() or absf(wanderer._oxygen - 700.0) > 0.01:
		push_error("Подбор: кислород %.1f" % wanderer._oxygen)
		quit(1)
		return

	print("LOOT_OK")
	quit(0)


func _bounces_off(loot: Loot, rock: SpaceRock) -> bool:
	rock.drift_velocity = Vector2.ZERO
	rock.spin = 0.0
	var min_dist := Loot.HIT_RADIUS + rock.get_hit_radius()
	loot.global_position = rock.global_position + Vector2(min_dist + 4.0, 0.0)
	loot.velocity = Vector2(-120.0, 0.0)
	loot.spin = 0.0
	for _i in 6:
		loot._physics_process(0.05)
	var outside := loot.global_position.distance_to(rock.global_position) >= min_dist - 0.5
	return outside and loot.velocity.x > 0.0
