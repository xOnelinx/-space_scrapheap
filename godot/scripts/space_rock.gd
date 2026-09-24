class_name SpaceRock
extends AnimatableBody2D

## Обломок. Дрейф и спин скриптом, без RigidBody.
## Масса круче площади, чтобы мелкий и крупный отличались в прыжке.
## depth 0..9 — один слой сталкивается, остальные проходят над и под.

const DEPTH_COUNT := 10
const REFERENCE_RADIUS := 26.0
const PAIR_RESTITUTION := 0.4
const PAIR_FRICTION := 0.35

@export var drift_velocity := Vector2.ZERO
@export var spin := 0.0

var depth := 0


func _ready() -> void:
	add_to_group("space_rocks")
	_assign_ambient_spin()


func _physics_process(delta: float) -> void:
	if drift_velocity != Vector2.ZERO:
		global_position += drift_velocity * delta
	if spin != 0.0:
		rotation += spin * delta


func _assign_ambient_spin() -> void:
	## Стартовая скала не крутится: иначе скитальца унесёт по ободу сразу.
	if name == "StaticNear" or spin != 0.0:
		return
	var steps := (absi(hash(name)) % 9) - 4
	spin = float(steps) * 0.12


func get_space_velocity() -> Vector2:
	return drift_velocity


func velocity_at(world_point: Vector2) -> Vector2:
	var offset := world_point - global_position
	return drift_velocity + spin * Vector2(-offset.y, offset.x)


func get_mass() -> float:
	var radius := maxf(get_hit_radius(), 1.0)
	var ref := REFERENCE_RADIUS
	var ratio := radius / ref
	return ref * ref * ratio * ratio * ratio * ratio


func get_inertia() -> float:
	var radius := maxf(get_hit_radius(), 1.0)
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
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is CircleShape2D:
		return 0.0
	var circle := shape_node.shape as CircleShape2D
	return circle.radius * maxf(absf(scale.x), absf(scale.y))


func apply_depth_look() -> void:
	z_index = depth
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var depth_t := float(depth) / float(DEPTH_COUNT - 1)
	var visual := lerpf(0.88, 1.0, depth_t)
	sprite.scale = Vector2(visual, visual)
	var radius := get_hit_radius()
	var mass_t := clampf((radius - 18.0) / 22.0, 0.0, 1.0)
	sprite.modulate = Color(1.12, 1.1, 1.04).lerp(Color(0.58, 0.6, 0.7), mass_t)


static func bounce(a: SpaceRock, b: SpaceRock) -> void:
	if a.depth != b.depth:
		return
	var delta := b.global_position - a.global_position
	var dist := delta.length()
	var ra := a.get_hit_radius()
	var rb := b.get_hit_radius()
	var min_dist := ra + rb
	if dist >= min_dist or min_dist <= 0.0:
		return
	var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
	var tangent := Vector2(-normal.y, normal.x)
	var inv_a := 1.0 / a.get_mass()
	var inv_b := 1.0 / b.get_mass()
	var pen := min_dist - dist
	var corr := pen / (inv_a + inv_b)
	a.global_position -= normal * corr * inv_a
	b.global_position += normal * corr * inv_b

	var contact := a.global_position + normal * ra
	var rel := a.velocity_at(contact) - b.velocity_at(contact)
	var approach := rel.dot(normal)
	if approach <= 0.0:
		return
	var jn := (1.0 + PAIR_RESTITUTION) * approach / (inv_a + inv_b)
	var impulse_n := normal * jn
	a.apply_impulse(-impulse_n, contact)
	b.apply_impulse(impulse_n, contact)

	rel = a.velocity_at(contact) - b.velocity_at(contact)
	var slip := rel.dot(tangent)
	var inv_t := inv_a + inv_b + (ra * ra) / a.get_inertia() + (rb * rb) / b.get_inertia()
	var jt := clampf(slip / inv_t, -PAIR_FRICTION * jn, PAIR_FRICTION * jn)
	var impulse_t := tangent * jt
	a.apply_impulse(-impulse_t, contact)
	b.apply_impulse(impulse_t, contact)
