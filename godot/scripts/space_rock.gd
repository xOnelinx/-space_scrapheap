@tool
class_name SpaceRock
extends AnimatableBody2D

## Обломок. Дрейф и спин скриптом, без RigidBody.
## Масса круче площади, чтобы мелкий и крупный отличались в прыжке.
## depth 0..9 — один слой сталкивается, остальные проходят над и под.
## hull_texture — кусок корпуса: в редакторе это иконка спрайта, в игре ещё контур ходьбы.

const DEPTH_COUNT := 10
const REFERENCE_RADIUS := 26.0
const PAIR_RESTITUTION := 0.4
const PAIR_FRICTION := 0.35
## Радиус скитальца 12 и зазор посадки 2. Подошва стоит снаружи железа.
const BOOT_CLEARANCE := 14.0

@export var drift_velocity := Vector2.ZERO
@export var spin := 0.0
## Стартовая скала: без случайного спина. Река ставит баллон рядом.
@export var start_rock := false
@export var hull_texture: Texture2D:
	set(value):
		hull_texture = value
		_show_hull_texture()
## Крупный метеорит: своя картинка, коллизия — сплошной выпуклый обвод этой картинки.
@export var shape_texture: Texture2D:
	set(value):
		shape_texture = value
		_apply_shape()

var depth := 0
var hull := false
var shaped := false
var outline: HullOutline


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
	_show_hull_texture()
	_apply_shape()


func _ready() -> void:
	if Engine.is_editor_hint():
		_show_hull_texture()
		_apply_shape()
		return
	add_to_group("space_rocks")
	if hull_texture != null:
		hull = true
		_show_hull_texture()
	_apply_shape()
	if shaped:
		_make_shape_outline()
	_assign_ambient_spin()
	if hull:
		_make_hull()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if drift_velocity != Vector2.ZERO:
		global_position += drift_velocity * delta
	if spin != 0.0:
		rotation += spin * delta


func _show_hull_texture() -> void:
	if hull_texture == null:
		return
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == hull_texture:
		return
	sprite.texture = hull_texture


func _assign_ambient_spin() -> void:
	## Стартовая скала не крутится: иначе скитальца унесёт по ободу сразу.
	if start_rock or spin != 0.0:
		return
	var steps := (absi(hash(name)) % 9) - 4
	spin = float(steps) * 0.12


func get_space_velocity() -> Vector2:
	return drift_velocity


func velocity_at(world_point: Vector2) -> Vector2:
	var offset := world_point - global_position
	return drift_velocity + spin * Vector2(-offset.y, offset.x)


func get_mass() -> float:
	var radius := maxf(_mass_world_radius(), 1.0)
	var ref := REFERENCE_RADIUS
	var ratio := radius / ref
	return ref * ref * ratio * ratio * ratio * ratio


func get_inertia() -> float:
	var radius := maxf(_mass_world_radius(), 1.0)
	return 0.5 * get_mass() * radius * radius


func apply_impulse(impulse: Vector2, world_point: Vector2) -> void:
	var mass := get_mass()
	drift_velocity += impulse / mass
	var offset := world_point - global_position
	var torque := offset.x * impulse.y - offset.y * impulse.x
	var inertia := get_inertia()
	if inertia > 0.0:
		spin += torque / inertia


func get_hit_radius() -> float:
	if outline != null:
		return outline.bound_radius * uniform_scale()
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is CircleShape2D:
		return 0.0
	var circle := shape_node.shape as CircleShape2D
	return circle.radius * uniform_scale()


func apply_depth_look() -> void:
	z_index = depth
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var depth_t := float(depth) / float(DEPTH_COUNT - 1)
	if hull or shape_texture != null:
		## Контур уже в пикселях спрайта. Дополнительный масштаб разъедется с коллизией.
		sprite.scale = Vector2.ONE
		var shade := lerpf(0.86, 1.0, depth_t)
		sprite.modulate = Color(shade, shade, shade)
		return
	var visual := lerpf(0.88, 1.0, depth_t)
	sprite.scale = Vector2(visual, visual)
	var radius := get_hit_radius()
	var mass_t := clampf((radius - 18.0) / 22.0, 0.0, 1.0)
	sprite.modulate = Color(1.12, 1.1, 1.04).lerp(Color(0.58, 0.6, 0.7), mass_t)


func _mass_world_radius() -> float:
	if outline != null:
		return outline.mass_radius * uniform_scale()
	return get_hit_radius()


func uniform_scale() -> float:
	return maxf(maxf(absf(global_scale.x), absf(global_scale.y)), 0.001)


func ray_hit(origin: Vector2, dir: Vector2) -> float:
	if not shaped or outline == null or outline.points.size() < 3:
		return INF
	var best := INF
	var pts := outline.points
	var n := pts.size()
	for i in n:
		var a := to_global(pts[i])
		var b := to_global(pts[(i + 1) % n])
		var t := _ray_segment(origin, dir, a, b)
		if t >= 0.0 and t < best:
			best = t
	return best


func _apply_shape() -> void:
	if shape_texture == null:
		return
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	sprite.texture = shape_texture
	sprite.scale = Vector2.ONE
	var circle := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if circle == null:
		return
	var solid := _solid_outline(HullOutline.local_points_from_texture(shape_texture, 2.0))
	if solid.size() < 3:
		return
	var poly := get_node_or_null("Silhouette") as CollisionPolygon2D
	if poly == null or poly.is_queued_for_deletion():
		poly = CollisionPolygon2D.new()
		poly.name = "Silhouette"
		add_child(poly)
	poly.build_mode = CollisionPolygon2D.BUILD_SOLIDS
	poly.polygon = solid
	circle.disabled = true
	shaped = true


static func _solid_outline(points: PackedVector2Array) -> PackedVector2Array:
	## Выпуклый обвод: выемки картинки не становятся дырами, длинная ось остаётся длинной.
	if points.size() < 3:
		return PackedVector2Array()
	var hull := Geometry2D.convex_hull(points)
	var closed := hull.size() >= 2 and hull[0].distance_squared_to(hull[hull.size() - 1]) < 0.25
	var count := hull.size() - 1 if closed else hull.size()
	if count < 3:
		return PackedVector2Array()
	var solid := PackedVector2Array()
	solid.resize(count)
	for i in count:
		solid[i] = hull[i]
	return solid


func _make_shape_outline() -> void:
	var poly := get_node_or_null("Silhouette") as CollisionPolygon2D
	if poly == null or poly.polygon.size() < 3:
		shaped = false
		return
	outline = HullOutline.from_points(poly.polygon, uniform_scale(), BOOT_CLEARANCE)
	if outline == null:
		shaped = false


static func _ray_segment(origin: Vector2, dir: Vector2, a: Vector2, b: Vector2) -> float:
	var edge := b - a
	var denom := dir.x * edge.y - dir.y * edge.x
	if absf(denom) < 0.000001:
		return INF
	var diff := a - origin
	var t := (diff.x * edge.y - diff.y * edge.x) / denom
	var u := (diff.x * dir.y - diff.y * dir.x) / denom
	if t >= 0.0 and u >= 0.0 and u <= 1.0:
		return t
	return INF


func _make_hull() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null or sprite.texture == null:
		push_error("У корпуса нет спрайта: %s" % name)
		hull = false
		return
	outline = HullOutline.from_texture(sprite.texture, uniform_scale(), BOOT_CLEARANCE)
	if outline == null:
		push_error("Не собрался контур корпуса: %s" % name)
		hull = false
		return
	var poly := CollisionPolygon2D.new()
	poly.name = "HullShape"
	poly.polygon = outline.points
	add_child(poly)
	var circle := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if circle != null:
		circle.disabled = true


class CircleOverlap:
	var hit := false
	var normal := Vector2.RIGHT
	var penetration := 0.0


## Нормаль из from в to. hit — круги уже пересеклись.
static func circle_overlap(from: Vector2, to: Vector2, from_radius: float, to_radius: float) -> CircleOverlap:
	var overlap := CircleOverlap.new()
	var delta := to - from
	var dist := delta.length()
	var min_dist := from_radius + to_radius
	if dist >= min_dist or min_dist <= 0.0:
		return overlap
	overlap.hit = true
	overlap.normal = delta / dist if dist > 0.01 else Vector2.RIGHT
	overlap.penetration = min_dist - dist
	return overlap


## Сдвиг этого тела при разведении: чем оно легче, тем больше уступает.
static func separation_share(penetration: float, mass_self: float, mass_other: float) -> float:
	return penetration * mass_other / (mass_self + mass_other)


## Доля желаемой относительной скорости, которая остаётся у того, кто толкает.
## Встречный импульс тела = -desired * mass_actor * share.
static func push_share(mass_actor: float, mass_other: float) -> float:
	var sum := mass_actor + mass_other
	if sum <= 0.0:
		return 0.0
	return mass_other / sum


static func bounce(a: Node2D, b: Node2D, restitution: float = PAIR_RESTITUTION, friction: float = PAIR_FRICTION) -> void:
	Body.collide(a, b, restitution, friction)
