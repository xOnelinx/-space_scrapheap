class_name RockRiver
extends Node2D

## Генерация отключена: астероиды расставлены в сцене main.tscn.
## Общий дрейф вправо и небольшой случайный сдвиг вверх или вниз.
## flow_density в настройках пока не влияет на раскладку.

const _ROCK_SCENE := preload("res://scenes/space_rock.tscn")
const _START_ROCK_NAME := "StaticNear"
const DENSITY_MIN := 2
const DENSITY_MAX := 5
const STREAM_SCREENS := 10
const ROCKS_PER_SCREEN := 8

const _STREAM_STATIC := 0
const _STREAM_SLOW := 1
const _STREAM_CROSS := 2
const _STREAM_SWIFT := 3
const _STREAM_FAST := 4

const _SLOW_SPEED := 18.0
const _SWIFT_SPEED := 50.0
const _FAST_SPEED := 96.0
const _CROSS_ALONG := 12.0
const _CROSS_ACROSS := 62.0

const CELL := 128.0

@export var origin := Vector2(220, 400)
@export var lane_offset := 80.0

static var flow_density := 3

var _rocks: Array[SpaceRock] = []


func _ready() -> void:
	_assign_depths()


func _physics_process(_delta: float) -> void:
	_collide_same_depth()


static func density_blurb(density: int) -> String:
	match clampi(density, DENSITY_MIN, DENSITY_MAX):
		2:
			return "Статика и медленный поток"
		3:
			return "Ещё поток поперёк реки"
		4:
			return "Ещё поток быстрее медленного"
		_:
			return "Ещё самый быстрый поток"


func apply_density(density: int) -> void:
	flow_density = clampi(density, DENSITY_MIN, DENSITY_MAX)


func _build_streams() -> void:
	var screen_w := _screen_width()
	var spacing := screen_w / float(ROCKS_PER_SCREEN)
	var length := screen_w * float(STREAM_SCREENS)
	var steps := STREAM_SCREENS * ROCKS_PER_SCREEN
	for stream in _STREAM_FAST + 1:
		for i in steps + 1:
			var along := spacing * float(i)
			if along > length:
				along = length
			var rock := _spawn(_rock_name(stream, i))
			_configure(rock, stream, i, along, spacing)


func _rock_name(stream: int, i: int) -> String:
	if stream == _STREAM_STATIC and i == 0:
		return _START_ROCK_NAME
	if stream == _STREAM_STATIC and i == 1:
		return "StaticMid"
	return "S%d_%d" % [stream, i]


func _spawn(node_name: String) -> SpaceRock:
	var rock := _ROCK_SCENE.instantiate() as SpaceRock
	rock.name = node_name
	add_child(rock)
	return rock


func _configure(rock: SpaceRock, stream: int, i: int, along: float, spacing: float) -> void:
	var wave := sin(float(i) * 0.85) * 16.0
	var wobble := float(i % 4) * 2.0
	var pos := origin
	var vel := Vector2.ZERO
	var rock_scale := 0.8 + float((i + stream) % 3) * 0.2
	match stream:
		_STREAM_STATIC:
			pos += Vector2(along, wave)
			if i == 0:
				rock_scale = 1.35
		_STREAM_SLOW:
			pos += Vector2(along + spacing * 0.5, -lane_offset + wave)
			vel = Vector2(_SLOW_SPEED + wobble, 0.0)
		_STREAM_CROSS:
			var from_above := i % 2 == 0
			var side := -1.0 if from_above else 1.0
			pos += Vector2(along + spacing * 0.35, side * _cross_span() + wave * 0.25)
			vel = Vector2(_CROSS_ALONG, -side * (_CROSS_ACROSS + wobble))
		_STREAM_SWIFT:
			pos += Vector2(along + spacing * 0.25, lane_offset + wave)
			vel = Vector2(_SWIFT_SPEED + wobble, 0.0)
		_:
			pos += Vector2(along + spacing * 0.75, -lane_offset * 0.4 + wave)
			vel = Vector2(_FAST_SPEED + wobble, 0.0)
	_place(rock, pos, rock_scale, vel)


func _place(rock: SpaceRock, pos: Vector2, rock_scale: float, vel: Vector2) -> void:
	## sync_to_physics на паузе возвращает тело в старую точку.
	var sync := rock.sync_to_physics
	rock.sync_to_physics = false
	rock.position = pos
	rock.scale = Vector2(rock_scale, rock_scale)
	rock.drift_velocity = vel
	rock.sync_to_physics = sync


func _screen_width() -> float:
	var width := get_viewport_rect().size.x
	if width < 1.0:
		width = float(ProjectSettings.get_setting("display/window/size/viewport_width", 1280))
	return width


func _cross_span() -> float:
	var height := get_viewport_rect().size.y
	if height < 1.0:
		height = float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
	return height * 0.33


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
		var delta := rock.global_position - other.global_position
		var dist := delta.length()
		var min_dist := radius + other.get_hit_radius()
		if dist >= min_dist:
			continue
		var normal := delta / dist if dist > 0.01 else Vector2.RIGHT
		var share := other.get_mass() / (rock.get_mass() + other.get_mass())
		rock.global_position += normal * (min_dist - dist) * share


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


func _reseat_if_docked() -> void:
	var wanderer := get_parent().get_node_or_null("Wanderer") as Wanderer
	if wanderer == null or not wanderer.docked:
		return
	wanderer.reseat_on_start()
