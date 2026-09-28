class_name HullOutline
extends RefCounted

## Контур корпуса в локальных пикселях спрайта.
## points — железо, по нему ходят. stance — внешний обвод, не тропа.

var points := PackedVector2Array()
var stance := PackedVector2Array()
var normals := PackedVector2Array()
var cum := PackedFloat32Array()
var length := 0.0
var bound_radius := 0.0
var mass_radius := 0.0
var clearance_local := 0.0


class Pose:
	var point := Vector2.ZERO
	var normal := Vector2.UP


class Rim:
	var distance := INF
	var normal := Vector2.UP


class SegmentHit:
	var point := Vector2.ZERO
	var t := 0.0
	var dist_sq := 0.0


static func from_texture(texture: Texture2D, body_scale: float, world_clearance: float) -> HullOutline:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return null
	if image.is_compressed():
		image.decompress()
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(image, 0.2)
	var rect := Rect2i(Vector2i.ZERO, image.get_size())
	var polys: Array = bitmap.opaque_to_polygons(rect, 3.2)
	if polys.is_empty():
		return null
	var best: PackedVector2Array = polys[0]
	var best_area := _abs_area(best)
	for poly in polys:
		var area := _abs_area(poly)
		if area > best_area:
			best = poly
			best_area = area
	if best.size() < 3 or best_area < 8.0:
		return null
	var center := Vector2(image.get_size()) * 0.5
	var local := PackedVector2Array()
	local.resize(best.size())
	for i in best.size():
		local[i] = best[i] - center
	var outline := HullOutline.new()
	outline.points = local
	outline.clearance_local = world_clearance / maxf(absf(body_scale), 0.001)
	outline._measure()
	outline._build_stance()
	return outline


func pose_at(along: float) -> Pose:
	var n := stance.size()
	if n < 2 or length <= 0.001:
		return _pose(Vector2.ZERO, Vector2.UP)
	along = fposmod(along, length)
	for i in n:
		var a_s := cum[i]
		var b_s := length if i == n - 1 else cum[i + 1]
		if along > b_s and i < n - 1:
			continue
		var span := maxf(b_s - a_s, 0.0001)
		var t := clampf((along - a_s) / span, 0.0, 1.0)
		var point := stance[i].lerp(stance[(i + 1) % n], t)
		var normal := normals[i].lerp(normals[(i + 1) % n], t)
		if normal.length_squared() < 0.0001:
			normal = normals[i]
		else:
			normal = normal.normalized()
		return _pose(point, normal)
	return _pose(stance[0], normals[0])


func nearest_rim(point: Vector2) -> Rim:
	## Ближняя кромка: дистанция и нормаль наружу, от железа.
	var rim := Rim.new()
	var best_d := INF
	var n := points.size()
	for i in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		var ab := b - a
		if ab.length_squared() < 0.0001:
			continue
		var hit := _closest(point, a, b)
		var dist := sqrt(hit.dist_sq)
		if dist >= best_d:
			continue
		best_d = dist
		var normal := _unit_perp(ab)
		if (point - hit.point).dot(normal) > 0.0:
			normal = -normal
		rim.normal = normal
	rim.distance = best_d
	return rim


func fit_margin(point: Vector2, wanted: float) -> float:
	var margin := wanted
	for _i in 6:
		if on_face(point, margin):
			return margin
		margin *= 0.5
	return 0.0


func slide(origin: Vector2, motion: Vector2, margin: float) -> Vector2:
	var dest := origin + motion
	if on_face(dest, margin):
		return dest
	var along_x := origin + Vector2(motion.x, 0.0)
	if on_face(along_x, margin):
		return along_x
	var along_y := origin + Vector2(0.0, motion.y)
	if on_face(along_y, margin):
		return along_y
	if not on_face(origin, margin):
		return origin
	var lo := origin
	var hi := dest
	for _i in 6:
		var mid := (lo + hi) * 0.5
		if on_face(mid, margin):
			lo = mid
		else:
			hi = mid
	return lo


func seat(local: Vector2, inward: Vector2, margin: float) -> Vector2:
	if inward.length_squared() < 0.01:
		inward = Vector2.UP
	inward = inward.normalized()
	var placed: Variant = _first_on_face(local, inward, margin)
	if placed != null:
		return placed
	placed = _first_on_face(local, inward, 0.0)
	if placed != null:
		return placed
	return _any_face_point(margin)


func on_face(point: Vector2, margin: float) -> bool:
	if not Geometry2D.is_point_in_polygon(point, points):
		return false
	if margin <= 0.5:
		return true
	var limit := margin * margin
	var n := points.size()
	for i in n:
		if _closest(point, points[i], points[(i + 1) % n]).dist_sq < limit:
			return false
	return true


func closest_s(local_point: Vector2) -> float:
	var best_d := INF
	var best_s := 0.0
	var n := stance.size()
	for i in n:
		var a: Vector2 = stance[i]
		var b: Vector2 = stance[(i + 1) % n]
		var ab := b - a
		var span := ab.length()
		if span < 0.0001:
			continue
		var hit := _closest(local_point, a, b)
		if hit.dist_sq < best_d:
			best_d = hit.dist_sq
			best_s = cum[i] + span * hit.t
	return best_s


func _measure() -> void:
	bound_radius = 0.0
	for vertex in points:
		bound_radius = maxf(bound_radius, vertex.length())
	var area := absf(_signed_area())
	mass_radius = sqrt(maxf(area, 1.0) / PI)


func _signed_area() -> float:
	return _signed_area_of(points)


func _edge_outward(a: Vector2, b: Vector2, turn: float) -> Vector2:
	## Один знак на весь обход. Если сторона оказалась внутрь, её переворачивает проверка в _build_stance.
	var normal := _unit_perp(b - a)
	if turn < 0.0:
		normal = -normal
	return normal


func _place(origin: Vector2, normal: Vector2) -> Vector2:
	## Идём наружу, но останавливаемся перед противоположной стенкой узкой щели.
	var best := origin
	var steps := 8
	var step := clearance_local / float(steps)
	for i in steps:
		var nxt := origin + normal * step * float(i + 1)
		if Geometry2D.is_point_in_polygon(nxt, points):
			break
		best = nxt
	if best.distance_squared_to(origin) < 0.25:
		var nudge := origin + normal * 1.5
		if not Geometry2D.is_point_in_polygon(nudge, points):
			return nudge
		nudge = origin - normal * 1.5
		if not Geometry2D.is_point_in_polygon(nudge, points):
			return nudge
	return best


func _build_stance() -> void:
	## Каждое ребро сдвигается наружу на зазор. Хорда не ведётся сквозь железо.
	var n := points.size()
	var turn := _signed_area()
	var edge_n := PackedVector2Array()
	edge_n.resize(n)
	for i in n:
		edge_n[i] = _edge_outward(points[i], points[(i + 1) % n], turn)
	var outside := 0
	for i in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		var mid := (a + b) * 0.5 + edge_n[i] * 0.75
		if not Geometry2D.is_point_in_polygon(mid, points):
			outside += 1
	if outside * 2 < n:
		for i in n:
			edge_n[i] = -edge_n[i]
	stance = PackedVector2Array()
	normals = PackedVector2Array()
	for i in n:
		var normal: Vector2 = edge_n[i]
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		if a.distance_squared_to(b) < 1.0:
			continue
		var start := _place(a, normal)
		var finish := _place(b, normal)
		if stance.is_empty() or stance[stance.size() - 1].distance_to(start) > 0.75:
			stance.append(start)
			normals.append(normal)
		stance.append(finish)
		normals.append(normal)
	_cut_chords()
	_lift_inside_vertices()
	n = stance.size()
	if n < 3:
		length = 0.0
		return
	cum.resize(n)
	cum[0] = 0.0
	for i in range(1, n):
		cum[i] = cum[i - 1] + stance[i - 1].distance_to(stance[i])
	length = cum[n - 1] + stance[n - 1].distance_to(stance[0])


func _lift_inside_vertices() -> void:
	for i in stance.size():
		if not Geometry2D.is_point_in_polygon(stance[i], points):
			continue
		var edge_i := _nearest_edge(stance[i])
		var a: Vector2 = points[edge_i]
		var b: Vector2 = points[(edge_i + 1) % points.size()]
		var normal := _edge_outward(a, b, _signed_area())
		var mid := (a + b) * 0.5
		if Geometry2D.is_point_in_polygon(mid + normal * 0.75, points):
			normal = -normal
		var lifted := _place(mid, normal)
		if Geometry2D.is_point_in_polygon(lifted, points):
			lifted = _nearest_exit(stance[i])
		if not Geometry2D.is_point_in_polygon(lifted, points):
			stance[i] = lifted
			normals[i] = normal


func _nearest_exit(origin: Vector2) -> Vector2:
	var best := origin
	var best_d := INF
	var limit := bound_radius * 2.0 + clearance_local + 4.0
	for dir_i in 24:
		var dir := Vector2.from_angle(TAU * float(dir_i) / 24.0)
		var along := 0.0
		while along < limit:
			along += 1.0
			var nxt := origin + dir * along
			if Geometry2D.is_point_in_polygon(nxt, points):
				continue
			if along < best_d:
				best_d = along
				best = nxt
			break
	return best


func _nearest_edge(point: Vector2) -> int:
	var best_i := 0
	var best_d := INF
	var n := points.size()
	for i in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		if a.distance_squared_to(b) < 0.000001:
			continue
		var hit := _closest(point, a, b, 0.0)
		if hit.dist_sq < best_d:
			best_d = hit.dist_sq
			best_i = i
	return best_i


func _escape(origin: Vector2, normal: Vector2) -> Vector2:
	var along := 0.0
	var step := 1.5
	while along < clearance_local * 2.0:
		along += step
		var nxt := origin + normal * along
		if not Geometry2D.is_point_in_polygon(nxt, points):
			return nxt
	return origin


func _cut_chords() -> void:
	## Хорда угла, которая сечёт железо, выгибается до ближайшего выхода наружу.
	var budget := stance.size()
	var added := 0
	var i := 0
	while i < stance.size() and added < budget:
		var n := stance.size()
		var a: Vector2 = stance[i]
		var b: Vector2 = stance[(i + 1) % n]
		var mid := (a + b) * 0.5
		if a.distance_to(b) < 2.0 or not Geometry2D.is_point_in_polygon(mid, points):
			i += 1
			continue
		var normal: Vector2 = normals[i]
		if normal.length_squared() < 0.01:
			normal = Vector2.RIGHT
		else:
			normal = normal.normalized()
		var forward := _escape(mid, normal)
		var back := _escape(mid, -normal)
		var inserted := forward
		if Geometry2D.is_point_in_polygon(forward, points) or forward.distance_squared_to(mid) < 1.0:
			inserted = back
		elif not Geometry2D.is_point_in_polygon(back, points) and back.distance_squared_to(mid) + 0.01 < forward.distance_squared_to(mid):
			inserted = back
		if Geometry2D.is_point_in_polygon(inserted, points) or inserted.distance_squared_to(mid) < 1.0:
			i += 1
			continue
		stance.insert(i + 1, inserted)
		normals.insert(i + 1, normal if inserted == forward else -normal)
		added += 1
		i += 2


static func _abs_area(poly: PackedVector2Array) -> float:
	return absf(_signed_area_of(poly))


static func _signed_area_of(poly: PackedVector2Array) -> float:
	var area := 0.0
	var n := poly.size()
	for i in n:
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % n]
		area += a.x * b.y - b.x * a.y
	return area * 0.5


static func _unit_perp(edge: Vector2) -> Vector2:
	var normal := Vector2(edge.y, -edge.x)
	if normal.length_squared() < 0.0001:
		return Vector2.UP
	return normal.normalized()


static func _closest(point: Vector2, a: Vector2, b: Vector2, degenerate := 0.0001) -> SegmentHit:
	var hit := SegmentHit.new()
	var ab := b - a
	var span := ab.length_squared()
	hit.point = a
	if span < degenerate:
		hit.dist_sq = point.distance_squared_to(a)
		return hit
	hit.t = clampf((point - a).dot(ab) / span, 0.0, 1.0)
	hit.point = a + ab * hit.t
	hit.dist_sq = point.distance_squared_to(hit.point)
	return hit


func _pose(point: Vector2, normal: Vector2) -> Pose:
	var pose := Pose.new()
	pose.point = point
	pose.normal = normal
	return pose


func _first_on_face(local: Vector2, inward: Vector2, margin: float) -> Variant:
	for i in 28:
		var spot := local + inward * float(i) * 4.0
		if on_face(spot, margin):
			return spot
	return null


func _any_face_point(margin: float) -> Vector2:
	var n := points.size()
	for i in n:
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % n]
		var mid := (a + b) * 0.5
		var tangent := b - a
		if tangent.length_squared() < 0.01:
			continue
		var side := _unit_perp(tangent)
		for sign_i in 2:
			var sign := 1.0 if sign_i == 0 else -1.0
			var spot := mid + side * sign * (margin + 3.0)
			if on_face(spot, margin):
				return spot
			if on_face(spot, 0.0):
				return spot
	return points[0]
