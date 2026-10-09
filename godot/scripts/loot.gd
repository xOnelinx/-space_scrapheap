class_name Loot
extends Node2D

## Баллон кислорода. Летит сам и отскакивает от любого камня.

const PICKUP_REACH := 18.0
const OXYGEN_GRANT := 600.0
const WORLD_HEIGHT := 28.0
const HIT_RADIUS := 9.0
const MASS := 40.0
const RESTITUTION := 0.55
const FRICTION := 0.2

var velocity := Vector2.ZERO
var spin := 0.0
var _taken := false


func _ready() -> void:
	add_to_group("loot")
	z_index = 12
	_fit_sprite()


func place_near(rock: Node2D) -> void:
	var body := rock as SpaceRock
	var hit := body.get_hit_radius() if body != null else 26.0
	global_position = rock.global_position + Vector2(hit + HIT_RADIUS + 48.0, -36.0)
	velocity = Vector2(22.0, -14.0)
	spin = 0.7
	_shove_clear()


func _fit_sprite() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	var tex_h := 64.0
	if sprite != null and sprite.texture != null and sprite.texture.get_height() > 0:
		tex_h = float(sprite.texture.get_height())
	var sprite_scale := WORLD_HEIGHT / tex_h
	scale = Vector2(sprite_scale, sprite_scale)


func _physics_process(delta: float) -> void:
	if _taken:
		return
	global_position += velocity * delta
	rotation += spin * delta
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock != null:
			_bounce_rock(rock)
	_try_pickup()


func _try_pickup() -> void:
	var wanderer := get_tree().get_first_node_in_group("wanderer") as Wanderer
	if wanderer == null:
		return
	if global_position.distance_squared_to(wanderer.global_position) > PICKUP_REACH * PICKUP_REACH:
		return
	if not wanderer.grant_oxygen(OXYGEN_GRANT):
		return
	_taken = true
	queue_free()


func _shove_clear() -> void:
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock != null:
			_separate(rock)


func _bounce_rock(rock: SpaceRock) -> void:
	var delta := rock.global_position - global_position
	var dist := delta.length()
	var min_dist := HIT_RADIUS + rock.get_hit_radius()
	if dist >= min_dist or min_dist <= 0.0:
		return
	var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
	var tangent := Vector2(-normal.y, normal.x)
	var inv_loot := 1.0 / MASS
	var inv_rock := 1.0 / rock.get_mass()
	var pen := min_dist - dist
	var corr := pen / (inv_loot + inv_rock)
	global_position -= normal * corr * inv_loot
	rock.global_position += normal * corr * inv_rock

	var contact := global_position + normal * HIT_RADIUS
	var rel := velocity_at(contact) - rock.velocity_at(contact)
	var approach := rel.dot(normal)
	if approach <= 0.0:
		return
	var jn := (1.0 + RESTITUTION) * approach / (inv_loot + inv_rock)
	var impulse_n := normal * jn
	apply_impulse(-impulse_n, contact)
	rock.apply_impulse(impulse_n, contact)

	rel = velocity_at(contact) - rock.velocity_at(contact)
	var slip := rel.dot(tangent)
	var inv_t := inv_loot + inv_rock + (HIT_RADIUS * HIT_RADIUS) / get_inertia() + (rock.get_hit_radius() * rock.get_hit_radius()) / rock.get_inertia()
	var jt := clampf(slip / inv_t, -FRICTION * jn, FRICTION * jn)
	var impulse_t := tangent * jt
	apply_impulse(-impulse_t, contact)
	rock.apply_impulse(impulse_t, contact)


func _separate(rock: SpaceRock) -> void:
	var delta := rock.global_position - global_position
	var dist := delta.length()
	var min_dist := HIT_RADIUS + rock.get_hit_radius()
	if dist >= min_dist or min_dist <= 0.0:
		return
	var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
	global_position -= normal * (min_dist - dist + 2.0)


func get_mass() -> float:
	return MASS


func get_inertia() -> float:
	return 0.5 * MASS * HIT_RADIUS * HIT_RADIUS


func velocity_at(world_point: Vector2) -> Vector2:
	var offset := world_point - global_position
	return velocity + spin * Vector2(-offset.y, offset.x)


func apply_impulse(impulse: Vector2, world_point: Vector2) -> void:
	velocity += impulse / MASS
	var offset := world_point - global_position
	var torque := offset.x * impulse.y - offset.y * impulse.x
	var inertia := get_inertia()
	if inertia > 0.0:
		spin += torque / inertia
