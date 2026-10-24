class_name HullRooms
extends Node2D

## Две комнаты на куске. Точки в локали корпуса: центр спрайта — ноль.
## Нулевая комната с дырой. Дыра не заделывается, поэтому нулевая всегда травится.

const BREACH_REACH := 18.0
const DOOR_REACH := 16.0
## Дырка в стене текстуры: столбцы 65–79. Отрезок door_a–door_b короче и уже её.
const OPENING_X0 := 65
const OPENING_X1 := 80
const TEX_ORIGIN_X := 64.5
const PLATE_THICK := 6
## Аварийный борт: пиксель железа темнее, пиксель сразу снаружи ярче.
const GLOW_INNER := Color(0.769, 0.318, 0.047)
const GLOW_OUTER := Color(1.0, 0.478, 0.094)
## Круг скитальца. Подошва стоит внутри железа на этот радиус, делённый на масштаб куска.
const WALKER_RADIUS := 9.0
## Половинки уезжают в косяки. Рисуется только то, что ещё в проёме.
const DOOR_TIME := 0.25
const LEAF_W := ((OPENING_X1 - OPENING_X0) + 1) >> 1

@export var interior: Texture2D
@export var breach := Vector2.ZERO
@export var breach_out := Vector2.RIGHT
@export var door_a := Vector2.ZERO
@export var door_b := Vector2.ZERO
@export var room_breach: PackedVector2Array
@export var room_far: PackedVector2Array

var door_open := false
## 0 — на проёме, 1 — уехала в стену.
var _slide := 0.0

var _inside := false
var _plate: Sprite2D
var _left: Sprite2D
var _right: Sprite2D
var _plate_center := Vector2.ZERO
var _glow: Sprite2D


static func of(body: Node) -> HullRooms:
	if body == null:
		return null
	return body.get_node_or_null(^"Rooms") as HullRooms


func _ready() -> void:
	_plate = Sprite2D.new()
	_plate.name = "Door"
	_plate.centered = true
	_plate.z_index = 2
	_plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_left = _make_leaf("Left", false)
	_right = _make_leaf("Right", true)
	_plate.add_child(_left)
	_plate.add_child(_right)
	var span := door_b - door_a
	_plate_center = Vector2(
		(OPENING_X0 + OPENING_X1) * 0.5 - TEX_ORIGIN_X,
		(door_a.y + door_b.y) * 0.5
	)
	_plate.position = _plate_center
	if span.length_squared() > 0.01:
		_plate.rotation = span.angle()
	add_child(_plate)
	_apply_door_plate()
	_glow = Sprite2D.new()
	_glow.name = "BreachGlow"
	_glow.centered = true
	_glow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_glow.texture = _glow_texture()
	_glow.visible = _glow.texture != null
	add_child(_glow)


func _process(delta: float) -> void:
	_step_door(delta)
	if _glow == null or not _glow.visible:
		return
	var wave := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.002)
	_glow.modulate = Color(1.0, 1.0, 1.0, lerpf(0.45, 1.0, wave))


func show_layer(rock: SpaceRock, inside: bool) -> void:
	var sprite := rock.get_node_or_null("Sprite") as Sprite2D
	_inside = inside and interior != null
	if sprite != null:
		if _inside:
			sprite.texture = interior
		elif rock.hull_texture != null:
			sprite.texture = rock.hull_texture
	_apply_door_plate()
	if _glow != null:
		_glow.visible = not _inside and _glow.texture != null


func near_breach(local: Vector2) -> bool:
	return local.distance_to(breach) <= BREACH_REACH


func near_door(local: Vector2) -> bool:
	return _dist_to_segment(local, door_a, door_b) <= DOOR_REACH


func vented(room_index: int) -> bool:
	if room_index == 0:
		return true
	return passage_open()


func passage_open() -> bool:
	return _slide >= 0.99


func contains(room_index: int, point: Vector2) -> bool:
	var poly := room_breach if room_index == 0 else room_far
	if poly.size() < 3:
		return false
	return Geometry2D.is_point_in_polygon(point, poly)


func stop_at_door(from: Vector2, to: Vector2, half: Vector2, rel_rot: float) -> Vector2:
	var axis := _door_axis()
	if axis == Vector2.ZERO:
		return to
	var normal := Vector2(-axis.y, axis.x)
	var reach := _support(half, rel_rot, axis) + (OPENING_X1 - OPENING_X0) * 0.5
	if absf((to - _plate_center).dot(axis)) > reach:
		return to
	var limit := _support(half, rel_rot, normal) + PLATE_THICK * 0.5
	var side := (from - _plate_center).dot(normal)
	var dist := (to - _plate_center).dot(normal)
	if side >= 0.0:
		if dist >= limit:
			return to
		return to + normal * (limit - dist)
	if dist <= -limit:
		return to
	return to + normal * (-limit - dist)


func door_clearance(center: Vector2, half: Vector2, rel_rot: float) -> float:
	var axis := _door_axis()
	if axis == Vector2.ZERO:
		return 999.0
	var normal := Vector2(-axis.y, axis.x)
	var reach := _support(half, rel_rot, axis) + (OPENING_X1 - OPENING_X0) * 0.5
	if absf((center - _plate_center).dot(axis)) > reach:
		return 999.0
	var dist := absf((center - _plate_center).dot(normal))
	return dist - _support(half, rel_rot, normal) - PLATE_THICK * 0.5


func crosses_door(from: Vector2, to: Vector2) -> bool:
	if _segments_cross(from, to, door_a, door_b):
		return true
	return _dist_to_segment(from, door_a, door_b) <= 4.0 or _dist_to_segment(to, door_a, door_b) <= 4.0


func outside_local(outline: HullOutline, margin: float) -> Vector2:
	var dir := breach_out
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var p := breach
	for _i in 48:
		p += dir * 4.0
		if outline == null or not Geometry2D.is_point_in_polygon(p, outline.points):
			return p + dir * (margin + 2.0)
	return p


func _glow_texture() -> ImageTexture:
	var rock := get_parent() as SpaceRock
	if rock == null or rock.hull_texture == null:
		return null
	var hull := rock.hull_texture.get_image()
	if hull == null:
		return null
	if hull.is_compressed():
		hull.decompress()
	var dir := breach_out
	if dir.length_squared() < 0.01:
		dir = Vector2.RIGHT
	dir = dir.normalized()
	var along_x := absf(dir.x) >= absf(dir.y)
	var forward := dir.x >= 0.0 if along_x else dir.y >= 0.0
	var image := Image.create(hull.get_width(), hull.get_height(), false, Image.FORMAT_RGBA8)
	_paint_rim(hull, image, along_x, forward)
	return ImageTexture.create_from_image(image)


func _paint_rim(hull: Image, image: Image, along_x: bool, forward: bool) -> void:
	var lines := hull.get_height() if along_x else hull.get_width()
	var span := hull.get_width() if along_x else hull.get_height()
	var edge := PackedInt32Array()
	edge.resize(lines)
	edge.fill(-1)
	for i in lines:
		var best := -1
		for j in span:
			var x := j if along_x else i
			var y := i if along_x else j
			if hull.get_pixel(x, y).a < 0.2:
				continue
			if best < 0 or (forward and j > best) or (not forward and j < best):
				best = j
		edge[i] = best
	var out_along := 1 if forward else -1
	for i in lines:
		if edge[i] < 0:
			continue
		_paint_pair(hull, image, edge[i], i, out_along, 0, along_x)
		if i + 1 >= lines or edge[i + 1] < 0 or edge[i] == edge[i + 1]:
			continue
		var lo := mini(edge[i], edge[i + 1]) + 1
		var hi := maxi(edge[i], edge[i + 1])
		var further := edge[i] > edge[i + 1] if forward else edge[i] < edge[i + 1]
		var ledge_i := i if further else i + 1
		var ledge_out := 1 if further else -1
		for j in range(lo, hi + 1):
			_paint_pair(hull, image, j, ledge_i, 0, ledge_out, along_x)


func _paint_pair(hull: Image, image: Image, along: int, line: int, out_along: int, out_line: int, along_x: bool) -> void:
	var x := along if along_x else line
	var y := line if along_x else along
	if x < 0 or y < 0 or x >= hull.get_width() or y >= hull.get_height():
		return
	if hull.get_pixel(x, y).a < 0.2:
		return
	var origin := Vector2(hull.get_width(), hull.get_height()) * 0.5
	var local := Vector2(x + 0.5, y + 0.5) - origin
	var outward := Vector2(
		out_along if along_x else out_line,
		out_line if along_x else out_along
	)
	## Подошва внутри кромки. Снаружи круга входа F не пускает, полоска там не нужна.
	var stand := local - outward * _walk_inset()
	if stand.distance_to(breach) > BREACH_REACH:
		return
	image.set_pixel(x, y, GLOW_INNER)
	var ox := x + (out_along if along_x else out_line)
	var oy := y + (out_line if along_x else out_along)
	if ox < 0 or oy < 0 or ox >= hull.get_width() or oy >= hull.get_height():
		return
	if hull.get_pixel(ox, oy).a >= 0.2:
		return
	if image.get_pixel(ox, oy).a > 0.5:
		return
	image.set_pixel(ox, oy, GLOW_OUTER)


func _walk_inset() -> float:
	var rock := get_parent() as SpaceRock
	var body_scale := rock.uniform_scale() if rock != null else 1.0
	return WALKER_RADIUS / body_scale


func _step_door(delta: float) -> void:
	var goal := 1.0 if door_open else 0.0
	if is_equal_approx(_slide, goal):
		return
	_slide = move_toward(_slide, goal, delta / DOOR_TIME)
	_apply_door_plate()


func _apply_door_plate() -> void:
	if _plate == null or _left == null:
		return
	_plate.position = _plate_center
	_plate.visible = _inside
	var width := float(OPENING_X1 - OPENING_X0)
	var travel := float(LEAF_W) * _slide
	var shown := maxf(0.0, float(LEAF_W) - travel)
	_place_leaf(_left, shown, travel, -1.0, width)
	_place_leaf(_right, shown, 0.0, 1.0, width)


func _place_leaf(leaf: Sprite2D, shown: float, region_x: float, side: float, width: float) -> void:
	leaf.visible = shown >= 0.5
	var draw := maxf(shown, 0.0)
	leaf.position = Vector2(side * (width * 0.5 - draw * 0.5), 0.0)
	if shown < 0.5:
		return
	leaf.region_rect = Rect2(region_x, 0, shown, PLATE_THICK)


func _make_leaf(leaf_name: String, inner_on_left: bool) -> Sprite2D:
	var leaf := Sprite2D.new()
	leaf.name = leaf_name
	leaf.centered = true
	leaf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	leaf.texture = _leaf_texture(inner_on_left)
	leaf.region_enabled = true
	return leaf


func _leaf_texture(inner_on_left: bool) -> ImageTexture:
	var image := Image.create(LEAF_W, PLATE_THICK, false, Image.FORMAT_RGBA8)
	var plate := Color(0.55, 0.53, 0.50)
	var edge := Color(0.78, 0.76, 0.72)
	var handle := Color(0.32, 0.31, 0.29)
	image.fill(plate)
	for x in LEAF_W:
		image.set_pixel(x, 0, edge)
	var handle_x := 0 if inner_on_left else LEAF_W - 1
	var neighbor := 1 if inner_on_left else LEAF_W - 2
	for y in range(2, 4):
		image.set_pixel(handle_x, y, handle)
		image.set_pixel(neighbor, y, handle)
	return ImageTexture.create_from_image(image)


func _door_axis() -> Vector2:
	var span := door_b - door_a
	if span.length_squared() < 0.0001:
		return Vector2.ZERO
	return span.normalized()


func _support(half: Vector2, rel_rot: float, dir: Vector2) -> float:
	var right := Vector2.RIGHT.rotated(rel_rot)
	var down := Vector2.DOWN.rotated(rel_rot)
	return half.x * absf(right.dot(dir)) + half.y * absf(down.dot(dir))


func _dist_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / len2, 0.0, 1.0)
	return point.distance_to(a + ab * t)


func _segments_cross(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool:
	var ab := b - a
	var cd := d - c
	var denom := ab.x * cd.y - ab.y * cd.x
	if absf(denom) < 0.000001:
		return false
	var ac := c - a
	var t := (ac.x * cd.y - ac.y * cd.x) / denom
	var u := (ac.x * ab.y - ac.y * ab.x) / denom
	return t >= 0.0 and t <= 1.0 and u >= 0.0 and u <= 1.0
