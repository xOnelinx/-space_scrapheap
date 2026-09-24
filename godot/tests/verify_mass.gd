extends SceneTree

## Глубина без наложений на старте, масса от размера, удар одного слоя.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var err := change_scene_to_file("res://scenes/main.tscn")
	if err != OK:
		quit(1)
		return
	for _i in 4:
		await process_frame

	var rocks := get_nodes_in_group("space_rocks")
	if rocks.size() < 2:
		push_error("Нет астероидов")
		quit(1)
		return

	var start := get_current_scene().get_node("Bodies/StaticNear") as SpaceRock
	if start.spin != 0.0:
		push_error("Стартовая скала не должна крутиться")
		quit(1)
		return

	var heavy: SpaceRock = null
	var light: SpaceRock = null
	for node in rocks:
		var rock := node as SpaceRock
		if rock.depth < 0 or rock.depth >= SpaceRock.DEPTH_COUNT:
			push_error("Глубина вне 0..9: %s" % rock.name)
			quit(1)
			return
		if heavy == null or rock.get_hit_radius() > heavy.get_hit_radius():
			heavy = rock
		if light == null or rock.get_hit_radius() < light.get_hit_radius():
			light = rock

	if heavy.get_mass() <= light.get_mass():
		push_error("Крупный должен быть тяжелее мелкого")
		quit(1)
		return

	for i in rocks.size():
		var a := rocks[i] as SpaceRock
		for j in range(i + 1, rocks.size()):
			var b := rocks[j] as SpaceRock
			if a.depth != b.depth:
				continue
			var gap := a.global_position.distance_to(b.global_position) - a.get_hit_radius() - b.get_hit_radius()
			if gap < -0.5:
				push_error("Наложение на одном слое: %s %s" % [a.name, b.name])
				quit(1)
				return

	var saved_a := light.global_position
	var saved_b := heavy.global_position
	var depth_b := heavy.depth
	light.sync_to_physics = false
	heavy.sync_to_physics = false
	light.depth = 0
	heavy.depth = 0
	light.drift_velocity = Vector2(80, 0)
	heavy.drift_velocity = Vector2.ZERO
	light.spin = 0.0
	heavy.spin = 0.0
	light.global_position = Vector2(0, 0)
	heavy.global_position = Vector2(light.get_hit_radius() + heavy.get_hit_radius() - 4.0, 0)
	SpaceRock.bounce(light, heavy)
	if light.drift_velocity.x >= 80.0 or heavy.drift_velocity.x <= 0.0:
		push_error("Удар не передал импульс: %.1f -> %.1f" % [light.drift_velocity.x, heavy.drift_velocity.x])
		quit(1)
		return
	var before := heavy.drift_velocity.x
	light.depth = 1
	heavy.depth = 0
	light.drift_velocity = Vector2(80, 0)
	heavy.drift_velocity = Vector2.ZERO
	light.global_position = Vector2(0, 0)
	heavy.global_position = Vector2(light.get_hit_radius() + heavy.get_hit_radius() - 4.0, 0)
	SpaceRock.bounce(light, heavy)
	if absf(heavy.drift_velocity.x - before) < 0.01 and heavy.drift_velocity.x != 0.0:
		pass
	if heavy.drift_velocity.x != 0.0:
		push_error("Чужой слой не должен сталкиваться")
		quit(1)
		return

	light.global_position = saved_a
	heavy.global_position = saved_b
	heavy.depth = depth_b
	print("MASS_OK layers=%d heavy=%.0f light=%.0f" % [rocks.size(), heavy.get_mass(), light.get_mass()])
	quit(0)
