class_name GunView
extends Node2D

## Игла, не луч. Удар в астероид поднимает песок.

const NEEDLE := Color(0.16, 0.15, 0.14, 1.0)
## Светлый кант: само тело на фоне космоса пропадает.
const NEEDLE_EDGE := Color(0.86, 0.84, 0.78, 1.0)
const SAND := Color(0.76, 0.62, 0.4, 1.0)
const SAND_DARK := Color(0.45, 0.38, 0.3, 1.0)

var _gun: Gun


func _ready() -> void:
	z_index = 2
	z_as_relative = true


func show_gun(gun: Gun) -> void:
	_gun = gun
	queue_redraw()


func _draw() -> void:
	if _gun == null:
		return
	for round in _gun.rounds:
		if round.vel.length_squared() < 1.0:
			continue
		var dir := round.vel.normalized()
		var side := Vector2(-dir.y, dir.x)
		var tail := round.pos - dir * 16.0
		_draw_needle(round.pos, tail, side * 2.4, NEEDLE_EDGE)
		_draw_needle(round.pos - dir * 3.0, tail + dir * 2.0, side * 1.1, NEEDLE)
	for spark in _gun.sparks:
		var age := 1.0 - spark.life / Gun.SPARK_LIFE
		_draw_sand(to_local(spark.at), spark.dir, age)


func _draw_needle(tip: Vector2, tail: Vector2, side: Vector2, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		to_local(tip),
		to_local(tail + side),
		to_local(tail - side),
	]), color)


func _draw_sand(at: Vector2, dir: Vector2, age: float) -> void:
	var aim := dir.rotated(-global_rotation)
	if aim.length_squared() <= 0.01:
		return
	aim = aim.normalized()
	var life := clampf(age, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.5, 1.0, life)
	for i in 12:
		var spread := lerpf(-1.45, 1.45, float(i) / 11.0)
		var outward := Vector2.from_angle(aim.angle() + spread * 0.8)
		var hop := lerpf(0.65, 1.15, float(i % 3) / 2.0)
		var dist := lerpf(8.0, 48.0, life) * hop
		var side := Vector2(-outward.y, outward.x) * sin(float(i) * 2.1) * life * 6.0
		var grain := at + outward * dist + side
		var shade := SAND if i % 2 == 0 else SAND_DARK
		var s := lerpf(3.6, 2.2, life)
		draw_rect(Rect2(grain - Vector2(s, s) * 0.5, Vector2(s, s)), Color(shade.r, shade.g, shade.b, fade))
