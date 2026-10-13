class_name RockRiver
extends Node2D

## Астероиды расставлены в сцене. Здесь слои и столкновения одного слоя.

const _LOOT_SCENE := preload("res://scenes/loot.tscn")
const CELL := 128.0
const DENSITY_MIN := 2
const DENSITY_MAX := 5

static var flow_density := 3

var _rocks: Array[SpaceRock] = []


func _ready() -> void:
	_assign_depths()
	_spawn_start_loot()


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
	var radii := {}
	var max_r := 0.0
	for rock in _rocks:
		var radius := rock.get_hit_radius()
		radii[rock] = radius
		max_r = maxf(max_r, radius)
	## Два самых больших камня ещё достают друг друга через столько клеток.
	var reach := maxi(int(ceil(max_r * 2.0 / CELL)), 1)
	for _pass in 6:
		var grid := _fill_grid()
		var dirty := false
		for rock in _rocks:
			var amount := _overlap_near(rock, grid, radii, reach)
			if amount <= 0.0:
				continue
			dirty = true
			var best_depth := rock.depth
			var best_amount := amount
			for depth in SpaceRock.DEPTH_COUNT:
				rock.depth = depth
				var trial := _overlap_near(rock, grid, radii, reach)
				if trial < best_amount:
					best_amount = trial
					best_depth = depth
			rock.depth = best_depth
			if best_amount > 0.0:
				_push_apart_near(rock, grid, radii, reach)
		if not dirty:
			break
	for rock in _rocks:
		rock.apply_depth_look()


func _spawn_start_loot() -> void:
	## Один баллон в кадре старта, не на камне.
	var start := _start_rock()
	if start == null or get_parent() == null:
		return
	var loot := _LOOT_SCENE.instantiate() as Loot
	loot.name = "Loot"
	add_child(loot)
	loot.place_near(start)


func _start_rock() -> Node2D:
	for child in get_children():
		var rock := child as SpaceRock
		if rock != null and rock.start_rock:
			return rock
	return null


func _fill_grid() -> Dictionary:
	var grid: Dictionary = {}
	for rock in _rocks:
		var cell := _cell(rock.global_position)
		if not grid.has(cell):
			grid[cell] = []
		grid[cell].append(rock)
	return grid


func _overlap_near(rock: SpaceRock, grid: Dictionary, radii: Dictionary, reach: int) -> float:
	var amount := 0.0
	var radius: float = radii[rock]
	var cell := _cell(rock.global_position)
	for oy in range(-reach, reach + 1):
		for ox in range(-reach, reach + 1):
			var bucket: Array = grid.get(cell + Vector2i(ox, oy), [])
			for other in bucket:
				var body := other as SpaceRock
				if body == null or body == rock or body.depth != rock.depth:
					continue
				var other_r: float = radii[body]
				var gap := rock.global_position.distance_to(body.global_position) - radius - other_r
				if gap < 0.0:
					amount -= gap
	return amount


func _push_apart_near(rock: SpaceRock, grid: Dictionary, radii: Dictionary, reach: int) -> void:
	var radius: float = radii[rock]
	var cell := _cell(rock.global_position)
	for oy in range(-reach, reach + 1):
		for ox in range(-reach, reach + 1):
			var bucket: Array = grid.get(cell + Vector2i(ox, oy), [])
			for other in bucket:
				var body := other as SpaceRock
				if body == null or body == rock or body.depth != rock.depth:
					continue
				var other_r: float = radii[body]
				var overlap := SpaceRock.circle_overlap(
					body.global_position, rock.global_position, other_r, radius
				)
				if not overlap.hit:
					continue
				var share := SpaceRock.separation_share(overlap.penetration, rock.get_mass(), body.get_mass())
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
