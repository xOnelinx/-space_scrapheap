class_name JumpAim
extends Node2D

## Курс — пунктир до края экрана. Стрелка вдоль того же курса.
## Контакт с астероидом сажает при любой скорости, поэтому удар не красится как отскок.

const DASH := 10.0
const GAP := 7.0
const PATH_WIDTH := 1.5
const ARROW_WIDTH := 2.2
const HEAD := 9.0
const VIEW_PAD := 3.0
const PATH_COLOR := Color(0.72, 0.88, 1.0, 0.55)
const ARROW_SAFE := Color(0.38, 0.95, 0.48, 0.95)
const ARROW_HARD := Color(0.95, 0.32, 0.28, 0.95)
const PUSH_COLOR := Color(1.0, 0.86, 0.12, 0.95)

var _path_end := Vector2.ZERO
var _arrow_end := Vector2.ZERO
var _push_end := Vector2.ZERO
var _arrow_color := ARROW_SAFE
var _shown := false

@onready var _wanderer: Wanderer = get_parent()


func _ready() -> void:
	z_index = -1
	z_as_relative = true


func _process(_delta: float) -> void:
	_refresh()


func _draw() -> void:
	if not _shown:
		return
	_draw_dashed(Vector2.ZERO, _path_end, PATH_COLOR, PATH_WIDTH)
	_draw_arrow(Vector2.ZERO, _arrow_end, _arrow_color)
	_draw_arrow(Vector2.ZERO, _push_end, PUSH_COLOR)


func path_end_local(launch: Vector2) -> Vector2:
	if launch.length_squared() < 0.25:
		return Vector2.ZERO
	var world_end := _ray_rect_exit(global_position, launch, _visible_world_rect())
	return to_local(world_end)


func velocity_end_local(launch: Vector2) -> Vector2:
	return launch


func push_end_local(desired: Vector2) -> Vector2:
	return desired


func _refresh() -> void:
	if _wanderer == null or not _wanderer.is_aiming():
		if _shown:
			_shown = false
			queue_redraw()
		return
	var launch := _wanderer.launch_velocity(_wanderer.aim_target(), _wanderer.aim_charge())
	if launch.length_squared() < 0.25:
		if _shown:
			_shown = false
			queue_redraw()
		return
	_path_end = path_end_local(launch)
	var horizon := _path_end.length() / launch.length()
	_arrow_end = velocity_end_local(launch)
	_arrow_color = ARROW_HARD if _wanderer.aim_too_fast_for_meteor(launch, horizon) else ARROW_SAFE
	_push_end = push_end_local(_wanderer.push_desired(_wanderer.aim_target(), _wanderer.aim_charge()))
	_shown = true
	queue_redraw()


func _visible_world_rect() -> Rect2:
	var canvas := get_viewport().get_canvas_transform()
	var view := get_viewport().get_visible_rect()
	var inv := canvas.affine_inverse()
	var p0: Vector2 = inv * view.position
	var p1: Vector2 = inv * Vector2(view.end.x, view.position.y)
	var p2: Vector2 = inv * view.end
	var p3: Vector2 = inv * Vector2(view.position.x, view.end.y)
	var top_left := p0.min(p1).min(p2).min(p3)
	var bottom_right := p0.max(p1).max(p2).max(p3)
	return Rect2(top_left, bottom_right - top_left).grow(-VIEW_PAD)


func _ray_rect_exit(origin: Vector2, direction: Vector2, rect: Rect2) -> Vector2:
	var axis := direction.normalized()
	var t_max := INF
	if absf(axis.x) < 0.0001:
		if origin.x < rect.position.x or origin.x > rect.end.x:
			return origin + axis * 2000.0
	else:
		var t1 := (rect.position.x - origin.x) / axis.x
		var t2 := (rect.end.x - origin.x) / axis.x
		t_max = minf(t_max, maxf(t1, t2))
	if absf(axis.y) < 0.0001:
		if origin.y < rect.position.y or origin.y > rect.end.y:
			return origin + axis * 2000.0
	else:
		var t1 := (rect.position.y - origin.y) / axis.y
		var t2 := (rect.end.y - origin.y) / axis.y
		t_max = minf(t_max, maxf(t1, t2))
	if t_max < 0.0:
		return origin + axis * 2000.0
	return origin + axis * t_max


func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 1.0:
		return
	var direction := delta / length
	var walked := 0.0
	while walked < length:
		var start := from + direction * walked
		var stop := from + direction * minf(walked + DASH, length)
		draw_line(start, stop, color, width, true)
		walked += DASH + GAP


func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 2.0:
		return
	var direction := delta / length
	draw_line(from, to, color, ARROW_WIDTH, true)
	var left := to - direction.rotated(0.5) * HEAD
	var right := to - direction.rotated(-0.5) * HEAD
	draw_colored_polygon(PackedVector2Array([to, left, right]), color)
