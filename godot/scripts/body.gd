class_name Body
extends RefCounted

## Тело, которое можно толкнуть: get_mass, get_inertia, velocity_at, apply_impulse, get_hit_radius.
## Контур корпуса сюда не входит.


static func is_body(node: Node) -> bool:
	return node != null \
			and node.has_method("get_mass") \
			and node.has_method("apply_impulse") \
			and node.has_method("velocity_at")


static func mass(node: Node) -> float:
	if node == null or not node.has_method("get_mass"):
		return 0.0
	return float(node.call("get_mass"))


static func inertia(node: Node) -> float:
	if node == null or not node.has_method("get_inertia"):
		return 0.0
	return float(node.call("get_inertia"))


static func velocity_at(node: Node, at: Vector2) -> Vector2:
	if node == null or not node.has_method("velocity_at"):
		return Vector2.ZERO
	return node.call("velocity_at", at) as Vector2


static func hit_radius(node: Node) -> float:
	if node == null or not node.has_method("get_hit_radius"):
		return 0.0
	return float(node.call("get_hit_radius"))


static func apply_impulse(node: Node, impulse: Vector2, at: Vector2) -> void:
	if not is_body(node) or impulse.length_squared() < 0.0000001:
		return
	node.call("apply_impulse", impulse, at)


static func ray_circle(origin: Vector2, dir: Vector2, center: Vector2, radius: float) -> float:
	var offset := origin - center
	var b := 2.0 * offset.dot(dir)
	var c := offset.dot(offset) - radius * radius
	var disc := b * b - 4.0 * c
	if disc < 0.0:
		return INF
	var root := sqrt(disc)
	var t_near := (-b - root) * 0.5
	if t_near >= 0.0:
		return t_near
	var t_far := (-b + root) * 0.5
	if t_far >= 0.0:
		return t_far
	return INF


static func ray_distance(node: Node2D, origin: Vector2, direction: Vector2) -> float:
	if node == null:
		return INF
	var shape_flag: Variant = node.get("shaped")
	if shape_flag != null and bool(shape_flag) and node.has_method("ray_hit"):
		var along := float(node.call("ray_hit", origin, direction))
		if along < 0.0:
			return INF
		return along
	var radius := hit_radius(node)
	if radius <= 0.0:
		return INF
	return ray_circle(origin, direction, node.global_position, radius)


static func collide(a: Node2D, b: Node2D, restitution: float, friction: float) -> void:
	if not is_body(a) or not is_body(b) or _other_layer(a, b):
		return
	var ra := hit_radius(a)
	var rb := hit_radius(b)
	var delta := b.global_position - a.global_position
	var dist := delta.length()
	var min_dist := ra + rb
	if dist >= min_dist or min_dist <= 0.0:
		return
	var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
	var pen := min_dist - dist
	var tangent := Vector2(-normal.y, normal.x)
	var mass_a := mass(a)
	var mass_b := mass(b)
	var mass_sum := mass_a + mass_b
	if mass_sum <= 0.0:
		return
	a.global_position -= normal * pen * mass_b / mass_sum
	b.global_position += normal * pen * mass_a / mass_sum

	var contact := a.global_position + normal * ra
	var rel := velocity_at(a, contact) - velocity_at(b, contact)
	var approach := rel.dot(normal)
	if approach <= 0.0:
		return
	var inv_a := 1.0 / mass_a
	var inv_b := 1.0 / mass_b
	var jn := (1.0 + restitution) * approach / (inv_a + inv_b)
	var impulse_n := normal * jn
	apply_impulse(a, -impulse_n, contact)
	apply_impulse(b, impulse_n, contact)

	rel = velocity_at(a, contact) - velocity_at(b, contact)
	var slip := rel.dot(tangent)
	var inertia_a := inertia(a)
	var inertia_b := inertia(b)
	var spin_a := 0.0 if inertia_a <= 0.0 else (ra * ra) / inertia_a
	var spin_b := 0.0 if inertia_b <= 0.0 else (rb * rb) / inertia_b
	var inv_t := inv_a + inv_b + spin_a + spin_b
	var jt := clampf(slip / inv_t, -friction * jn, friction * jn)
	var impulse_t := tangent * jt
	apply_impulse(a, -impulse_t, contact)
	apply_impulse(b, impulse_t, contact)


static func _other_layer(a: Node, b: Node) -> bool:
	var da: Variant = a.get("depth")
	var db: Variant = b.get("depth")
	if typeof(da) != TYPE_INT and typeof(da) != TYPE_FLOAT:
		return false
	if typeof(db) != TYPE_INT and typeof(db) != TYPE_FLOAT:
		return false
	return int(da) != int(db)
