extends "res://tests/scene_check.gd"

## Контур корпуса. По кромке камня ходят A/D. По железу — в четыре стороны.

const _HULLS: Array[String] = [
	"HullFed01", "HullFed02", "HullFed03", "HullFed04",
	"HullAuto01", "HullAuto02", "HullAuto03", "HullAuto04",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	if not _check_outlines(scene):
		return
	if not _check_groups_in_stream(scene):
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	if not _check_rim_walk(scene, wanderer):
		return
	if not await _check_hull_walk_and_jump(scene, wanderer):
		return
	quit(0)


func _check_outlines(scene: Node) -> bool:
	for hull_name in _HULLS:
		var hull := scene.get_node("Bodies/%s" % hull_name) as SpaceRock
		if hull == null or not hull.hull or hull.outline == null:
			fail("Нет контура: %s" % hull_name)
			return false
		var outline := hull.outline
		if outline.points.size() < 6 or outline.length < 80.0:
			fail("Слишком простой контур %s pts=%d len=%.1f" % [hull_name, outline.points.size(), outline.length])
			return false
		_save_preview(hull, "/tmp/hull_%s.png" % hull_name)
		var inside := 0
		var worst := 0.0
		var n := outline.stance.size()
		for i in n:
			var jump: float = outline.stance[i].distance_to(outline.stance[(i + 1) % n])
			worst = maxf(worst, jump)
			var pose := outline.pose_at(outline.cum[i])
			var pt: Vector2 = pose.point
			var normal: Vector2 = pose.normal
			if normal.length_squared() < 0.5:
				fail("Нет наружной нормали: %s" % hull_name)
				return false
			if Geometry2D.is_point_in_polygon(pt, outline.points):
				inside += 1
		if inside > 0:
			fail("Подошва внутри железа: %s (%d/%d)" % [hull_name, inside, n])
			return false
		if worst > 160.0:
			fail("Скачок подошвы %s: %.1f" % [hull_name, worst])
			return false
	return true


func _check_groups_in_stream(scene: Node) -> bool:
	## Группы внутри потока, между ними несколько экранов, астероиды не задевают корпуса.
	var screen := 1280.0
	var hulls: Array[SpaceRock] = []
	for hull_name in _HULLS:
		hulls.append(scene.get_node("Bodies/%s" % hull_name) as SpaceRock)
	var fed_left := INF
	var fed_right := -INF
	var auto_left := INF
	var auto_right := -INF
	for hull in hulls:
		var x := hull.global_position.x
		var reach := hull.get_hit_radius()
		if hull.name.begins_with("HullFed"):
			fed_left = minf(fed_left, x - reach)
			fed_right = maxf(fed_right, x + reach)
		else:
			auto_left = minf(auto_left, x - reach)
			auto_right = maxf(auto_right, x + reach)
		if hull.global_position.y < -120.0 or hull.global_position.y > 840.0:
			fail("Обломок вне потока: %s y=%.0f" % [hull.name, hull.global_position.y])
			return false
	var between := fed_left - auto_right if fed_left > auto_right else auto_left - fed_right
	if between < screen * 2.5:
		fail("Группы обломков ближе нескольких экранов: %.0f" % between)
		return false
	for hull in hulls:
		for node in scene.get_node("Bodies").get_children():
			var rock := node as SpaceRock
			if rock == null or rock == hull or rock.hull:
				continue
			var rel_x := hull.global_position.x - rock.global_position.x
			var rel_y := hull.global_position.y - rock.global_position.y
			var need := hull.get_hit_radius() + rock.get_hit_radius() + 16.0
			if absf(rel_x) >= need:
				continue
			var rel_vy := hull.drift_velocity.y - rock.drift_velocity.y
			if absf(rel_vy) < 0.05 and absf(rel_y) > need:
				continue
			if absf(rel_y) <= need or rel_y * rel_vy < 0.0:
				fail("Астероид %s пересекает %s" % [rock.name, hull.name])
				return false
	return true


func _check_rim_walk(scene: Node, wanderer: Wanderer) -> bool:
	var rock := scene.get_node("Bodies/StaticNear") as SpaceRock
	wanderer.dock_to(rock, Vector2.UP)
	if wanderer.dock.has_shape():
		var along_before := wanderer.dock.along
		wanderer._walk_shape(1.0, 0.5)
		if absf(wanderer.dock.along - along_before) < 1.0:
			fail("По кромке астероида не сдвинулись")
			return false
	else:
		var rim_before := wanderer.dock.angle
		wanderer._walk_rim(1.0, 0.5)
		if absf(wanderer.dock.angle - rim_before) < 0.2:
			fail("По кромке астероида не сдвинулись")
			return false
		if absf(wanderer.dock.local.length() - wanderer.dock.radius) > 1.5:
			fail("Ходьба по кромке ушла с окружности")
			return false
	var rim_parked := wanderer.dock.local
	wanderer._step_on_hull(Vector2(0, -1), 0.5)
	if wanderer.dock.local.distance_to(rim_parked) > 0.01:
		fail("WASD не должен таскать по астероиду")
		return false
	return true


func _check_hull_walk_and_jump(scene: Node, wanderer: Wanderer) -> bool:
	var fed := scene.get_node("Bodies/HullFed01") as SpaceRock
	wanderer.undock()
	wanderer.global_position = fed.global_position + Vector2(0, -fed.get_hit_radius() - 20.0)
	wanderer.dock_to(fed, Vector2.UP)
	if not Geometry2D.is_point_in_polygon(wanderer.dock.local, fed.outline.points):
		fail("Посадка на корпус оказалась мимо железа")
		return false
	var before: Vector2 = wanderer.dock.local
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
	var moved := 0.0
	var open_dir := Vector2.ZERO
	for dir in dirs:
		wanderer.dock.local = before
		wanderer._step_on_hull(dir, 0.35)
		if not Geometry2D.is_point_in_polygon(wanderer.dock.local, fed.outline.points):
			fail("Шаг по корпусу ушёл с железа")
			return false
		var step := wanderer.dock.local.distance_to(before)
		if step > moved:
			moved = step
			open_dir = dir
	if moved < 8.0:
		fail("По корпусу некуда шагнуть: %.1f" % moved)
		return false
	wanderer.dock.local = before
	wanderer._step_on_hull(open_dir, 8.0)
	if not Geometry2D.is_point_in_polygon(wanderer.dock.local, fed.outline.points):
		fail("Длинный шаг прошёл сквозь кромку корпуса")
		return false
	wanderer.dock.local = before
	wanderer.global_position = fed.to_global(before)
	wanderer.dock.docked = true
	wanderer.dock.body = fed
	wanderer._charge = 1.0
	var aim := Vector2.LEFT
	var stood := wanderer.global_position
	wanderer._commit_push(aim)
	if wanderer.global_position.distance_to(stood) > 0.01:
		fail("Прыжок сдвинул с места стояния")
		return false
	if wanderer.dock.docked:
		fail("С середины корпуса не прыгнули")
		return false
	var away: float = (wanderer.velocity - fed.velocity_at(wanderer.global_position)).dot(aim)
	if away <= 0.0:
		fail("Прыжок не совпал с прицелом: %.1f" % away)
		return false
	paused = false
	await physics_frame
	var first := wanderer.global_position.distance_to(stood)
	if first > 6.0:
		fail("Первый кадр прыжка улетел на %.1f" % first)
		return false
	var left := false
	for _step in 180:
		await physics_frame
		var local := fed.to_local(wanderer.global_position)
		if not Geometry2D.is_point_in_polygon(local, fed.outline.points):
			left = true
			break
	if not left:
		fail("Прыжок не вынес за контур")
		return false

	_save_preview(fed, "/tmp/hull_fed01.png")
	_save_preview(scene.get_node("Bodies/HullAuto03") as SpaceRock, "/tmp/hull_auto03.png")
	_save_preview(scene.get_node("Bodies/HullFed02") as SpaceRock, "/tmp/hull_fed02.png")
	print("HULL_OK boot_step=%.1f" % moved)
	return true


func _save_preview(hull: SpaceRock, path: String) -> void:
	var sprite := hull.get_node("Sprite") as Sprite2D
	var image := sprite.texture.get_image()
	if image.is_compressed():
		image.decompress()
	image = image.duplicate()
	var pad := 48
	var canvas := Image.create(image.get_width() + pad * 2, image.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0.02, 0.03, 0.06))
	canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(pad, pad))
	var origin := Vector2(image.get_size()) * 0.5 + Vector2(pad, pad)
	var outline := hull.outline
	var n := outline.points.size()
	for i in n:
		_line(canvas, outline.points[i], outline.points[(i + 1) % n], Color(1, 0.3, 0.2), origin)
	var m := outline.stance.size()
	for i in m:
		_line(canvas, outline.stance[i], outline.stance[(i + 1) % m], Color(0.3, 1, 0.45), origin)
	canvas.save_png(path)


func _line(image: Image, a: Vector2, b: Vector2, color: Color, origin: Vector2) -> void:
	var steps := int(a.distance_to(b)) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(maxi(steps, 1))) + origin
		var x := int(round(p.x))
		var y := int(round(p.y))
		if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
			continue
		image.set_pixel(x, y, color)
