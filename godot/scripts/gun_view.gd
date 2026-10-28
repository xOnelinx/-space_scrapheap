class_name GunView
extends Node2D

## Короткий след пули и искра попадания.


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
		var at := to_local(round.pos)
		var tail := to_local(round.pos - round.vel.normalized() * 12.0)
		draw_line(tail, at, Color(1.0, 0.94, 0.62), 2.0, false)
	for spark in _gun.sparks:
		var fade := clampf(spark.life / Gun.SPARK_LIFE, 0.0, 1.0)
		var at := to_local(spark.at)
		var color := Color(1.0, 0.62, 0.2, fade)
		draw_line(at + Vector2(-3, 0), at + Vector2(3, 0), color, 1.0, false)
		draw_line(at + Vector2(0, -3), at + Vector2(0, 3), color, 1.0, false)
