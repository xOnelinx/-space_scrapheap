class_name TetherView
extends Node2D

## Плетёный железный трос. Стыковка поднимает газ и песок с камня.

const CABLE := preload("res://assets/tether_cable.png")
const TIP := preload("res://assets/tether_tip.png")
## Высота текстуры: иначе свивка сжимается и жилы пропадают.
const CABLE_WIDTH := 3.0
const POWDER := Color(1.0, 0.32, 0.02, 1.0)
const POWDER_CORE := Color(1.0, 0.55, 0.08, 1.0)
const GAS := Color(0.9, 0.93, 0.96, 1.0)
const SAND := Color(0.76, 0.62, 0.4, 1.0)
const SAND_DARK := Color(0.45, 0.38, 0.3, 1.0)

var _tip := Vector2.ZERO
var _flying := false
var _linked := false
var _burst_at := Vector2.ZERO
var _burst_age := -1.0
var _burst_dir := Vector2.ZERO
var _muzzle_at := Vector2.ZERO
var _muzzle_dir := Vector2.RIGHT
var _muzzle_age := -1.0
var _jaw_angle := 0.0
var _line: Line2D


func _ready() -> void:
	z_index = 1
	z_as_relative = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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


func show_rope(tip: Vector2, flying: bool, linked: bool, burst_at: Vector2, burst_age: float, muzzle_at: Vector2 = Vector2.ZERO, muzzle_dir: Vector2 = Vector2.RIGHT, muzzle_age: float = -1.0, burst_dir: Vector2 = Vector2.ZERO, jaw_angle: float = 0.0) -> void:
	_tip = tip
	_flying = flying
	_linked = linked
	_burst_at = burst_at
	_burst_age = burst_age
	_burst_dir = burst_dir
	_jaw_angle = jaw_angle
	_muzzle_at = muzzle_at
	_muzzle_dir = muzzle_dir
	_muzzle_age = muzzle_age
	_fit_cable()
	queue_redraw()


func _draw() -> void:
	if _muzzle_age >= 0.0:
		_draw_muzzle(to_local(_muzzle_at), _muzzle_dir, _muzzle_age)
	if _flying or _linked:
		_draw_head(to_local(_tip))
	## Пыль поверх губок, иначе начало струи прячется в наконечнике.
	if _burst_age >= 0.0:
		_draw_burst(to_local(_burst_at), _burst_age)


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
	## Трос кончается в пятке. На камне пятка крутится вместе с телом, не вдоль троса.
	var heel := tip - _jaw_aim() * TIP.get_width()
	if heel.length_squared() < 1.0:
		_line.points = PackedVector2Array()
		return
	_line.points = PackedVector2Array([Vector2.ZERO, heel])


func _jaw_aim() -> Vector2:
	return Vector2.from_angle(_jaw_angle - global_rotation)


func _draw_head(tip: Vector2) -> void:
	## Остриё в точке удара. После стыковки угол пришёл от тела, не от троса.
	if tip.length_squared() < 1.0:
		return
	var size := TIP.get_size()
	draw_set_transform(tip, _jaw_aim().angle(), Vector2.ONE)
	draw_texture_rect(TIP, Rect2(-size.x, -size.y * 0.5, size.x, size.y), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_muzzle(at: Vector2, dir: Vector2, age: float) -> void:
	## Порох и газ бьют конусом по ходу троса, а не кольцом вокруг скафандра.
	var life := clampf(age, 0.0, 1.0)
	var aim := dir.normalized() if dir.length_squared() > 0.01 else Vector2.RIGHT
	_draw_gas(at, aim, life)
	var flash := clampf(life / (Tether.FLASH_LIFE / Tether.MUZZLE_LIFE), 0.0, 1.0)
	var flash_alpha := 1.0 - flash
	if flash_alpha > 0.02:
		var mouth := at + aim * 10.0
		var radius := lerpf(14.0, 24.0, flash)
		draw_circle(mouth, radius * 0.72, Color(POWDER.r, POWDER.g, POWDER.b, flash_alpha * 0.95))
		draw_circle(mouth + aim * 6.0, radius * 0.4, Color(POWDER_CORE.r, POWDER_CORE.g, POWDER_CORE.b, flash_alpha))
		for i in 5:
			var spread := lerpf(-0.55, 0.55, float(i) / 4.0)
			var outward := Vector2.from_angle(aim.angle() + spread)
			var length := lerpf(20.0, 36.0, flash) * lerpf(1.0, 0.55, absf(spread) / 0.55)
			draw_line(mouth, mouth + outward * length, Color(POWDER.r, POWDER.g, POWDER.b, flash_alpha * 0.9), 4.0, false)


func _draw_gas(at: Vector2, aim: Vector2, life: float) -> void:
	var gas_alpha := (1.0 - life) * 0.85
	for i in 7:
		var spread := lerpf(-0.95, 0.95, float(i) / 6.0)
		var outward := Vector2.from_angle(aim.angle() + spread)
		var side := Vector2(-outward.y, outward.x) * sin(float(i) * 1.7 + life * 2.4) * 2.8
		var reach := lerpf(11.0, 26.0, life) * lerpf(1.0, 0.6, absf(spread) / 0.95)
		var inner := at + outward * lerpf(5.0, 8.0, life)
		var outer := at + outward * reach + side
		draw_line(inner, outer, Color(GAS.r, GAS.g, GAS.b, gas_alpha), 2.0, false)


func _draw_burst(at: Vector2, age: float) -> void:
	if _burst_dir.length_squared() <= 0.01:
		return
	_draw_dock_spray(at, _burst_dir, age)


func _draw_dock_spray(at: Vector2, dir: Vector2, age: float) -> void:
	## Удар в камень: газ и песок уходят от центра астероида и держатся, пока не разлетятся.
	var life := clampf(age, 0.0, 1.0)
	var fade := 1.0 - smoothstep(0.5, 1.0, life)
	var aim := dir.normalized()
	var gas_life := clampf(life * Tether.BURST_LIFE / Tether.MUZZLE_LIFE, 0.0, 1.0)
	_draw_gas(at, aim, gas_life)
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
