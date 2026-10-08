extends "res://tests/scene_check.gd"

## Пять крупных метеоритов: у каждого свой силуэт, посадка снаружи, шаг по кромке.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var names: Array[String] = ["Meteor01", "Meteor02", "Meteor03", "Meteor04", "Meteor05"]
	var signatures: Array[String] = []
	for rock_name in names:
		var rock := scene.get_node("Bodies/%s" % rock_name) as SpaceRock
		if rock == null or not rock.shaped or rock.hull:
			fail("Нет силуэта: %s" % rock_name)
			return
		if rock.outline == null or rock.outline.points.size() < 8 or rock.outline.length < 40.0:
			fail("Контур не собрался: %s" % rock_name)
			return
		var circle := rock.get_node("CollisionShape2D") as CollisionShape2D
		if circle == null or not circle.disabled:
			fail("Круг всё ещё сталкивается: %s" % rock_name)
			return
		var poly := rock.get_node("Silhouette") as CollisionPolygon2D
		if poly == null or poly.polygon.size() < 8:
			fail("Нет полигона коллизии: %s" % rock_name)
			return
		## Как самый крупный круг потока: радиус 26 при масштабе 1.6497.
		if absf(rock.get_hit_radius() - 42.89) > 0.6:
			fail("Размер не как у крупного старого камня: %s %.2f" % [rock_name, rock.get_hit_radius()])
			return
		if not _solid(rock):
			fail("Середина камня пустая: %s" % rock_name)
			return
		signatures.append(_signature(poly.polygon))
	for i in signatures.size():
		for j in range(i + 1, signatures.size()):
			if signatures[i] == signatures[j]:
				fail("Два метеорита с одной и той же формой")
				return
	var round := scene.get_node("Bodies/StaticNear") as SpaceRock
	if round.shaped or round.get_node_or_null("Silhouette") != null:
		fail("Стартовая скала не должна быть силуэтом")
		return
	var wanderer := scene.get_node("Wanderer") as Wanderer
	for rock_name in names:
		if not _stands_and_walks(wanderer, scene.get_node("Bodies/%s" % rock_name) as SpaceRock):
			return
	if not _bolt_hits_rim(scene.get_node("Bodies/Meteor02") as SpaceRock):
		return
	print("SHAPES_OK")
	quit(0)


func _solid(rock: SpaceRock) -> bool:
	var pts := rock.outline.points
	var centroid := Vector2.ZERO
	for point in pts:
		centroid += point
	centroid /= float(pts.size())
	return Geometry2D.is_point_in_polygon(centroid, pts)


func _signature(poly: PackedVector2Array) -> String:
	return "%d:%.1f:%.1f" % [poly.size(), poly[0].x, poly[poly.size() / 2].y]


func _stands_and_walks(wanderer: Wanderer, rock: SpaceRock) -> bool:
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 40.0)
	wanderer.dock_to(rock, Vector2.UP)
	if not wanderer.dock.docked or wanderer.dock.has_hull():
		fail("Не встал на силуэт")
		return false
	if Geometry2D.is_point_in_polygon(rock.to_local(wanderer.global_position), rock.outline.points):
		fail("Посадка внутри камня")
		return false
	var outward: Vector2 = wanderer.dock.outward()
	var sprite: Sprite2D = wanderer.get_node("Sprite")
	var feet: Vector2 = Vector2(0, 1).rotated(sprite.rotation)
	if feet.dot(-outward) < 0.8:
		fail("На силуэте ноги не к камню")
		return false
	var before := wanderer.global_position
	var along0 := wanderer.dock.along
	var duration := 0.6
	var steps := 36
	var prev_out := wanderer.dock.outward()
	for _i in steps:
		wanderer._walk_shape(1.0, duration / float(steps))
		wanderer.follow_dock()
		if Geometry2D.is_point_in_polygon(rock.to_local(wanderer.global_position), rock.outline.points):
			fail("Шаг зашёл в камень: %s" % rock.name)
			return false
		var next_out := wanderer.dock.outward()
		var turn := absf(prev_out.angle_to(next_out))
		if turn > deg_to_rad(12.0):
			fail("Угол к поверхности скачет: %s %.0f°" % [rock.name, rad_to_deg(turn)])
			return false
		prev_out = next_out
	var traveled := absf(wanderer.dock.along - along0)
	if traveled > rock.outline.rim * 0.5:
		traveled = rock.outline.rim - traveled
	var world := traveled * rock.uniform_scale()
	if world < Wanderer.WALK_SPEED * duration * 0.85:
		fail("По контуру почти не сдвинулся: %.1f" % world)
		return false
	if wanderer.global_position.x - before.x < 8.0:
		fail("С вершины D не ведёт вправо")
		return false
	return true


func _bolt_hits_rim(rock: SpaceRock) -> bool:
	var origin := rock.global_position + Vector2(-rock.get_hit_radius() - 80.0, 0)
	var t := rock.ray_hit(origin, Vector2.RIGHT)
	if t <= 20.0 or t >= rock.get_hit_radius() + 80.0:
		fail("Болт не встретил силуэт")
		return false
	var hit := rock.to_local(origin + Vector2.RIGHT * t)
	var rim := rock.outline.nearest_rim(hit)
	if rim.distance > 3.0:
		fail("Попадание не на кромке: %.1f" % rim.distance)
		return false
	return true
