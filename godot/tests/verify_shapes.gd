extends "res://tests/scene_check.gd"

## Пять крупных метеоритов: картинка своя, коллизия — сплошной выпуклый обвод.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var names: Array[String] = ["Meteor01", "Meteor02", "Meteor03", "Meteor04", "Meteor05"]
	var seen: Array[String] = []
	for rock_name in names:
		var rock := scene.get_node("Bodies/%s" % rock_name) as SpaceRock
		if rock == null or not rock.shaped or rock.hull or rock.outline == null:
			fail("Нет обвода метеорита: %s" % rock_name)
			return
		var circle := rock.get_node("CollisionShape2D") as CollisionShape2D
		if circle == null or not circle.disabled:
			fail("Круг всё ещё сталкивается: %s" % rock_name)
			return
		var poly := rock.get_node_or_null("Silhouette") as CollisionPolygon2D
		if poly == null or poly.polygon.size() < 6 or not _convex(poly.polygon):
			fail("Нет сплошного выпуклого обвода: %s" % rock_name)
			return
		if not Geometry2D.is_point_in_polygon(Vector2.ZERO, poly.polygon):
			fail("Середина камня пустая: %s" % rock_name)
			return
		## Как самый крупный круг потока: радиус 26 при масштабе 1.6497.
		if absf(rock.get_hit_radius() - 42.89) > 0.6:
			fail("Размер не как у крупного старого камня: %s %.2f" % [rock_name, rock.get_hit_radius()])
			return
		var picture := ""
		var sprite := rock.get_node_or_null("Sprite") as Sprite2D
		if sprite != null and sprite.texture != null:
			picture = str(sprite.texture.resource_path)
		if picture.is_empty() or seen.has(picture):
			fail("У метеоритов должна быть своя картинка: %s" % rock_name)
			return
		seen.append(picture)
	var long_rock := scene.get_node("Bodies/Meteor02") as SpaceRock
	var long_poly := (long_rock.get_node("Silhouette") as CollisionPolygon2D).polygon
	if _radial_aspect(long_poly) < 1.35:
		fail("Вытянутый метеорит остался круглым: %.2f" % _radial_aspect(long_poly))
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


func _stands_and_walks(wanderer: Wanderer, rock: SpaceRock) -> bool:
	wanderer.undock()
	wanderer.global_position = rock.global_position + Vector2(0, -rock.get_hit_radius() - 12.0)
	wanderer.dock_to(rock, Vector2.UP)
	if not wanderer.dock.docked or wanderer.dock.has_hull() or not wanderer.dock.has_shape():
		fail("Не встал на обвод метеорита")
		return false
	if Geometry2D.is_point_in_polygon(rock.to_local(wanderer.global_position), rock.outline.points):
		fail("Посадка внутри камня")
		return false
	var before := wanderer.global_position
	var duration := 0.6
	var steps := 36
	for _i in steps:
		wanderer._walk_shape(1.0, duration / float(steps))
		wanderer.follow_dock()
		if Geometry2D.is_point_in_polygon(rock.to_local(wanderer.global_position), rock.outline.points):
			fail("Шаг зашёл в камень: %s" % rock.name)
			return false
	var traveled := wanderer.global_position.distance_to(before)
	if traveled < Wanderer.WALK_SPEED * duration * 0.7:
		fail("По обводу слишком медленно: %.1f" % traveled)
		return false
	if wanderer.global_position.x <= before.x:
		fail("С вершины D не ведёт вправо")
		return false
	return true


func _bolt_hits_rim(rock: SpaceRock) -> bool:
	var origin := rock.global_position + Vector2(-rock.get_hit_radius() - 80.0, 0)
	var t := rock.ray_hit(origin, Vector2.RIGHT)
	if t < 1.0 or t > rock.get_hit_radius() + 80.0:
		fail("Болт не встретил обвод: %.1f" % t)
		return false
	var hit := rock.to_local(origin + Vector2.RIGHT * t)
	if rock.outline.nearest_rim(hit).distance > 3.0:
		fail("Попадание не на кромке: %.1f" % rock.outline.nearest_rim(hit).distance)
		return false
	return true


func _radial_aspect(poly: PackedVector2Array) -> float:
	var far := 0.0
	var near := INF
	for point in poly:
		var dist := point.length()
		far = maxf(far, dist)
		near = minf(near, dist)
	if near < 1.0:
		return 1.0
	return far / near


func _convex(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	var turn := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var c := poly[(i + 2) % n]
		var cross := (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x)
		if absf(cross) < 0.01:
			continue
		if turn == 0.0:
			turn = signf(cross)
		elif signf(cross) != turn:
			return false
	return turn != 0.0
