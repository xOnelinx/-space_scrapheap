extends Node2D

## Короткая струя воздуха от скитальца: против нажатого WASD или из пробоины.

const REACH := 16.0
const ROOT := 12.0

var reach := REACH
var color := Color(0.78, 0.92, 1.0)
var width := 1.0

var _dir := Vector2.ZERO
var _phase := 0.0


func _process(delta: float) -> void:
	if _dir == Vector2.ZERO:
		return
	_phase += delta
	queue_redraw()


func set_direction(dir: Vector2) -> void:
	var next := Vector2.ZERO
	if dir.length_squared() > 0.01:
		next = dir.normalized()
	if next == _dir:
		if next != Vector2.ZERO:
			queue_redraw()
		return
	_dir = next
	if _dir == Vector2.ZERO:
		_phase = 0.0
	queue_redraw()


func direction() -> Vector2:
	return _dir


func is_shown() -> bool:
	return _dir != Vector2.ZERO


func _draw() -> void:
	if _dir == Vector2.ZERO:
		return
	var side := Vector2(-_dir.y, _dir.x)
	var puffs := maxi(3, roundi(reach / 6.0))
	for i in puffs:
		var along := fposmod(_phase * 22.0 + float(i) * 6.0, reach)
		var fade := along / reach
		var center := _dir * (ROOT + along)
		var half := lerpf(2.5, 1.0, fade) * width
		var tint := Color(color.r, color.g, color.b, lerpf(0.75, 0.0, fade))
		draw_line(center - _dir * half, center + _dir * half, tint, width)
		if i % 2 == 1:
			var spread := 1.5 * width
			draw_line(center - side * spread, center + side * spread, Color(tint.r, tint.g, tint.b, tint.a * 0.45), width)
