class_name TetherView
extends Node2D

## Плетёный железный трос, вплавленный наконечник и вспышка микровзрыва.

const CABLE := preload("res://assets/tether_cable.png")
const CABLE_WIDTH := 4.0
const BOLT := Color(0.95, 0.78, 0.35, 0.95)
const WELD := Color(1.0, 0.55, 0.22, 0.95)
const SPARK := Color(1.0, 0.62, 0.18, 1.0)
const FLASH := Color(1.0, 0.95, 0.75, 1.0)

var _tip := Vector2.ZERO
var _flying := false
var _linked := false
var _burst_at := Vector2.ZERO
var _burst_age := -1.0
var _line: Line2D


func _ready() -> void:
	z_index = 1
	z_as_relative = true
	_line = Line2D.new()
	_line.name = "Cable"
	_line.texture = CABLE
	_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	_line.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_line.width = CABLE_WIDTH
	_line.default_color = Color.WHITE
	_line.antialiased = false
	_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_line.begin_cap_mode = Line2D.LINE_CAP_BOX
	_line.end_cap_mode = Line2D.LINE_CAP_BOX
	## Под наконечником и вспышкой, которые рисует сам узел.
	_line.z_index = -1
	add_child(_line)


func show_rope(tip: Vector2, flying: bool, linked: bool, burst_at: Vector2, burst_age: float) -> void:
	_tip = tip
	_flying = flying
	_linked = linked
	_burst_at = burst_at
	_burst_age = burst_age
	_fit_cable()
	queue_redraw()


func _draw() -> void:
	if _burst_age >= 0.0:
		_draw_burst(to_local(_burst_at), _burst_age)
	if _flying:
		draw_circle(to_local(_tip), 2.5, BOLT)
	elif _linked:
		draw_circle(to_local(_tip), 2.2, WELD)


func _fit_cable() -> void:
	if _line == null:
		return
	if not _flying and not _linked:
		_line.points = PackedVector2Array()
		return
	var tip := to_local(_tip)
	if tip.length_squared() < 1.0:
		_line.points = PackedVector2Array()
		return
	_line.points = PackedVector2Array([Vector2.ZERO, tip])


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
