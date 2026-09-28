class_name RockRiver
extends Node2D

## Астероиды расставлены в сцене. Здесь слои и столкновения одного слоя.

const CELL := 128.0
const DENSITY_MIN := 2
const DENSITY_MAX := 5

static var flow_density := 3

var _rocks: Array[SpaceRock] = []


func _ready() -> void:
	_assign_depths()


func _physics_process(_delta: float) -> void:
	_collide_same_depth()


func apply_density(density: int) -> void:
	flow_density = clampi(density, DENSITY_MIN, DENSITY_MAX)


func _assign_depths() -> void:
	_rocks.clear()
	for child in get_children():
		var rock := child as SpaceRock
		if rock == null:
			continue
		rock.depth = absi(hash(rock.name)) % SpaceRock.DEPTH_COUNT
		_rocks.append(rock)
	for _pass in 6:
		var dirty := false
		for rock in _rocks:
			if _overlap_amount(rock) <= 0.0:
				continue
			dirty = true
			var best_depth := rock.depth
			var best_amount := _overlap_amount(rock)
			for depth in SpaceRock.DEPTH_COUNT:
				rock.depth = depth
				var amount := _overlap_amount(rock)
				if amount < best_amount:
					best_amount = amount
					best_depth = depth
			rock.depth = best_depth
			if best_amount > 0.0:
				_push_apart(rock)
		if not dirty:
			break
	for rock in _rocks:
		rock.apply_depth_look()


func _overlap_amount(rock: SpaceRock) -> float:
	var amount := 0.0
	var radius := rock.get_hit_radius()
	for other in _rocks:
		if other == rock or other.depth != rock.depth:
			continue
		var gap := rock.global_position.distance_to(other.global_position) - radius - other.get_hit_radius()
		if gap < 0.0:
			amount -= gap
	return amount


func _push_apart(rock: SpaceRock) -> void:
	var radius := rock.get_hit_radius()
	for other in _rocks:
		if other == rock or other.depth != rock.depth:
			continue
		var overlap := SpaceRock.circle_overlap(
			other.global_position, rock.global_position, other.get_hit_radius(), radius
		)
		if not overlap.hit:
			continue
		var share := SpaceRock.separation_share(overlap.penetration, rock.get_mass(), other.get_mass())
		rock.global_position += overlap.normal * share


func _collide_same_depth() -> void:
	var grid := {}
	for rock in _rocks:
		var cell := _cell(rock.global_position)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(rock)
	for rock in _rocks:
		var cell := _cell(rock.global_position)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var bucket: Array = grid.get(cell + Vector2i(ox, oy), [])
				for other in bucket:
					if rock.get_instance_id() >= other.get_instance_id():
						continue
					if rock.depth == other.depth:
						SpaceRock.bounce(rock, other)


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(int(floor(point.x / CELL)), int(floor(point.y / CELL)))
