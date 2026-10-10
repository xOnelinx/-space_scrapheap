class_name Dock
extends RefCounted

## Посадка скитальца на круг астероида или на железо корпуса.

var docked := false
## Внутри корпуса: тот же follow, но это не кромка и не прыжок в пустоту.
var inside := false
var body: Node2D = null
var local := Vector2.ZERO
var radius := 0.0
var angle := 0.0
var normal_local := Vector2.UP
var hull_face := 0.0
## Длина вдоль внешнего обвода силуэта.
var along := 0.0


func clear() -> void:
	docked = false
	inside = false
	body = null
	local = Vector2.ZERO
	radius = 0.0
	angle = 0.0
	normal_local = Vector2.UP
	hull_face = 0.0
	along = 0.0


func rock() -> SpaceRock:
	return body as SpaceRock


func has_hull() -> bool:
	var stood := rock()
	return stood != null and stood.hull


func has_outline() -> bool:
	return has_hull() and rock().outline != null


func has_shape() -> bool:
	var stood := rock()
	return stood != null and stood.shaped and stood.outline != null


func outward() -> Vector2:
	var dir := normal_local
	if dir.length_squared() < 0.01:
		dir = Vector2.UP
	if body != null:
		dir = dir.rotated(body.global_rotation)
	return dir


func follow(host: CharacterBody2D) -> bool:
	if body == null or not is_instance_valid(body):
		return false
	host.global_position = body.to_global(local)
	host.velocity = velocity_at(body, host.global_position)
	return true


static func velocity_at(body: Node, at: Vector2) -> Vector2:
	return Body.velocity_at(body, at)
