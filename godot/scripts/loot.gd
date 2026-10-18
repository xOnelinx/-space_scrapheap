class_name Loot
extends Node2D

## Находка в потоке: летит сама и отскакивает от любого камня. Касание забирает.
## По умолчанию — баллон кислорода. Изолента — та же находка без воздуха.

const PICKUP_REACH := 18.0
const OXYGEN_GRANT := 600.0
const WORLD_HEIGHT := 28.0
const HIT_RADIUS := 9.0
const MASS := 40.0
const RESTITUTION := 0.55
const FRICTION := 0.2

## Секунды воздуха за касание. Полный запас тогда находку не забирает.
@export var oxygen_grant := OXYGEN_GRANT
@export var tape_grant := 0
@export var mass := MASS
## Масса идёт в груз скитальца. Изолента в кармане веса не прибавляет.
@export var adds_cargo := true
@export var world_height := WORLD_HEIGHT
@export var hit_radius := HIT_RADIUS

var velocity := Vector2.ZERO
var spin := 0.0
var _taken := false


func _ready() -> void:
	add_to_group("loot")
	z_index = 12
	_fit_sprite()


func _physics_process(delta: float) -> void:
	if _taken:
		return
	global_position += velocity * delta
	rotation += spin * delta
	for node in Bodies.rocks(get_tree()):
		var rock := node as Node2D
		if rock != null:
			_bounce_rock(rock)
	_try_pickup()


## side = -1 ставит находку по другую сторону камня.
func place_near(rock: Node2D, side := 1.0) -> void:
	var hit := Body.hit_radius(rock)
	if hit <= 0.0:
		hit = 26.0
	global_position = rock.global_position + Vector2(hit + hit_radius + 48.0, -36.0) * side
	velocity = Vector2(22.0, -14.0) * side
	spin = 0.7 * side
	_shove_clear()


func get_hit_radius() -> float:
	return hit_radius


func get_mass() -> float:
	return mass


func get_inertia() -> float:
	return 0.5 * mass * hit_radius * hit_radius


func velocity_at(world_point: Vector2) -> Vector2:
	var offset := world_point - global_position
	return velocity + spin * Vector2(-offset.y, offset.x)


func apply_impulse(impulse: Vector2, world_point: Vector2) -> void:
	velocity += impulse / mass
	var offset := world_point - global_position
	var torque := offset.x * impulse.y - offset.y * impulse.x
	var inertia := get_inertia()
	if inertia > 0.0:
		spin += torque / inertia


func _fit_sprite() -> void:
	var sprite := get_node_or_null("Sprite") as Sprite2D
	var tex_h := 64.0
	if sprite != null and sprite.texture != null and sprite.texture.get_height() > 0:
		tex_h = float(sprite.texture.get_height())
	var sprite_scale := world_height / tex_h
	scale = Vector2(sprite_scale, sprite_scale)


func _try_pickup() -> void:
	var host := get_tree().get_first_node_in_group("wanderer") as Wanderer
	if host == null:
		return
	if global_position.distance_squared_to(host.global_position) > PICKUP_REACH * PICKUP_REACH:
		return
	var air := get_tree().get_first_node_in_group("oxygen") as Oxygen
	if air == null or not air.open:
		return
	if oxygen_grant > 0.0 and not air.grant(oxygen_grant):
		return
	if tape_grant > 0:
		air.add_tape(tape_grant)
	if adds_cargo:
		host.cargo_mass += mass
	_taken = true
	queue_free()


func _shove_clear() -> void:
	for node in Bodies.rocks(get_tree()):
		var rock := node as Node2D
		if rock != null:
			_separate(rock)


func _bounce_rock(rock: Node2D) -> void:
	Body.collide(self, rock, RESTITUTION, FRICTION)


func _separate(rock: Node2D) -> void:
	var delta := rock.global_position - global_position
	var dist := delta.length()
	var min_dist := hit_radius + Body.hit_radius(rock)
	if dist >= min_dist or min_dist <= 0.0:
		return
	var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
	global_position -= normal * (min_dist - dist + 2.0)
