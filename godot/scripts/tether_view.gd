class_name TetherView
extends Node2D

## Линия троса, вплавленный наконечник и вспышка микровзрыва.

const ROPE := Color(0.78, 0.84, 0.9, 0.85)
const BOLT := Color(0.95, 0.78, 0.35, 0.95)
const WELD := Color(1.0, 0.55, 0.22, 0.95)
const SPARK := Color(1.0, 0.62, 0.18, 1.0)
const FLASH := Color(1.0, 0.95, 0.75, 1.0)


func _ready() -> void:
	z_index = 1
	z_as_relative = true


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var host := get_parent() as Wanderer
	if host == null:
		return
	var tether := host.tether
	if tether.burst > 0.0:
		var age := 1.0 - tether.burst / Tether.BURST_LIFE
		_draw_burst(to_local(tether.burst_at), age)
	if tether.flying():
		var tip := to_local(tether.bolt_global)
		draw_line(Vector2.ZERO, tip, ROPE, 1.25, true)
		draw_circle(tip, 2.5, BOLT)
	elif tether.linked():
		var tip := to_local(tether.anchor_global())
		draw_line(Vector2.ZERO, tip, ROPE, 1.25, true)
		draw_circle(tip, 2.2, WELD)


func _draw_burst(at: Vector2, age: float) -> void:
	var life := clampf(age, 0.0, 1.0)
	var alpha := 1.0 - life
	var ring := lerpf(3.0, 18.0, life)
	draw_arc(at, ring, 0.0, TAU, 14, Color(SPARK.r, SPARK.g, SPARK.b, alpha), 1.6, true)
	draw_circle(at, lerpf(5.5, 1.2, life), Color(FLASH.r, FLASH.g, FLASH.b, alpha))
	for i in 8:
		var dir := Vector2.from_angle(float(i) * TAU / 8.0 + life * 1.4)
		var inner := at + dir * lerpf(2.0, 5.0, life)
		var outer := at + dir * lerpf(7.0, 17.0, life)
		draw_line(inner, outer, Color(SPARK.r, SPARK.g, SPARK.b, alpha), 1.3, true)
