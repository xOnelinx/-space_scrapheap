class_name Tether
extends RefCounted

## Трос. Выстрел толкает стрелка назад. Наконечник вплавляется вспышкой.
## Втягивание коротит трос и ускоряет к телу. Дальше 20 размеров скитальца он не тянется.

enum Phase { IDLE, BOLT, LINKED }

const BODIES := 20.0
const BOLT_SPEED := 640.0
const RECOIL_SPEED := 90.0
const REEL_RATE := 140.0
const MIN_LENGTH := 16.0
const TAUT_MAX_CLOSE := 280.0
const BURST_LIFE := 0.32

var phase := Phase.IDLE
var anchor: SpaceRock = null
var anchor_local := Vector2.ZERO
var length := 0.0
var bolt_global := Vector2.ZERO
var bolt_velocity := Vector2.ZERO
var burst := 0.0
var burst_at := Vector2.ZERO
var ignited := false
var _flown := 0.0
var _ignore: SpaceRock = null
var _shot := Vector2.ZERO


func linked() -> bool:
	return phase == Phase.LINKED and anchor != null and is_instance_valid(anchor)


func flying() -> bool:
	return phase == Phase.BOLT


func anchor_global() -> Vector2:
	if linked():
		return anchor.to_global(anchor_local)
	return bolt_global


func release() -> void:
	var blow := linked()
	var at := anchor_global() if blow else Vector2.ZERO
	phase = Phase.IDLE
	anchor = null
	anchor_local = Vector2.ZERO
	bolt_velocity = Vector2.ZERO
	length = 0.0
	_flown = 0.0
	_ignore = null
	_shot = Vector2.ZERO
	if blow:
		_ignite(at)
		return
	ignited = false


func max_length(host: Wanderer) -> float:
	return host.character_size() * BODIES


func shoot(host: Wanderer, direction: Vector2) -> void:
	## Выстрел: отдача назад, болт вперёд. Мимо — вплавление в тело под ногами.
	if direction.length_squared() <= 0.01:
		return
	var aim := direction.normalized()
	var stand := host.dock.rock() if host.dock.docked and not host.dock.inside else null
	var from := host.global_position
	var reach := max_length(host)
	var hit := first_along(host, from, aim, reach, stand)
	_recoil(host, aim)
	if hit != null:
		fire(host, from, aim, stand)
		return
	if stand != null:
		plant(host, stand, from)
		return
	fire(host, from, aim, null)


func plant(host: Wanderer, rock: SpaceRock, world_point: Vector2) -> void:
	if rock == null:
		return
	var reach := max_length(host)
	release()
	phase = Phase.LINKED
	anchor = rock
	var stick := _on_surface(rock, world_point)
	anchor_local = rock.to_local(stick)
	length = reach
	_ignite(stick)


func fire(host: Wanderer, from: Vector2, direction: Vector2, ignore: SpaceRock) -> void:
	release()
	if direction.length_squared() <= 0.01:
		return
	phase = Phase.BOLT
	bolt_global = from
	_shot = direction.normalized()
	bolt_velocity = _shot * BOLT_SPEED
	length = max_length(host)
	_ignore = ignore
	_flown = 0.0


func integrate(host: Wanderer, delta: float, reeling: bool = false) -> void:
	if burst > 0.0:
		burst = maxf(0.0, burst - delta)
	if phase == Phase.BOLT:
		_fly_bolt(host, delta)
	elif linked():
		if length > max_length(host):
			length = max_length(host)
		if reeling:
			_reel(delta)
		_constrain(host, delta)


static func first_along(host: Node, origin: Vector2, direction: Vector2, reach: float, ignore: SpaceRock) -> SpaceRock:
	if direction.length_squared() <= 0.0001 or reach <= 0.0:
		return null
	var tree := host.get_tree()
	if tree == null:
		return null
	var dir := direction.normalized()
	var best_t := reach
	var found: SpaceRock = null
	for node in tree.get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null or rock == ignore:
			continue
		var t := rock.ray_hit(origin, dir) if rock.shaped else ray_circle(origin, dir, rock.global_position, rock.get_hit_radius())
		if t >= 0.0 and t < INF and t <= best_t:
			best_t = t
			found = rock
	return found


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


func _recoil(host: Wanderer, aim: Vector2) -> void:
	var back := -aim * RECOIL_SPEED
	var rock := host.dock.rock()
	if host.dock.docked and not host.dock.inside and rock != null:
		var share := SpaceRock.push_share(host.get_mass(), rock.get_mass())
		host.velocity = rock.velocity_at(host.global_position) + back * share
		host.add_body_impulse(rock, -back * host.get_mass() * share, host.global_position)
		host.undock()
		return
	host.add_impulse(back * host.get_mass())


func _fly_bolt(host: Wanderer, delta: float) -> void:
	var reach := length if length > 1.0 else max_length(host)
	var room := reach - host.global_position.distance_to(bolt_global)
	if room <= 1.0:
		release()
		return
	var step := bolt_velocity * delta
	var dist := minf(step.length(), room)
	if dist <= 0.001:
		release()
		return
	var dir := bolt_velocity.normalized()
	var rock := first_along(host, bolt_global, dir, dist, _ignore)
	_flown += dist
	if rock != null:
		var hit_t := rock.ray_hit(bolt_global, dir) if rock.shaped else ray_circle(bolt_global, dir, rock.global_position, rock.get_hit_radius())
		_attach(host, rock, bolt_global + dir * hit_t)
		return
	bolt_global += dir * dist
	if _flown >= reach or host.global_position.distance_to(bolt_global) >= reach - 0.5:
		release()


func _attach(host: Wanderer, rock: SpaceRock, world_point: Vector2) -> void:
	phase = Phase.LINKED
	anchor = rock
	anchor_local = rock.to_local(world_point)
	length = max_length(host)
	bolt_velocity = Vector2.ZERO
	_ignore = null
	_flown = 0.0
	_hit(host, rock, world_point)
	_ignite(world_point)


func _reel(delta: float) -> void:
	length = maxf(length - REEL_RATE * delta, MIN_LENGTH)


func _constrain(host: Wanderer, delta: float) -> void:
	if host.dock.inside:
		return
	if not is_instance_valid(anchor):
		release()
		return
	var origin := anchor.to_global(anchor_local)
	var offset := host.global_position - origin
	var dist := offset.length()
	if dist <= length or dist < 0.001:
		return
	if host.dock.docked:
		host.undock()
		offset = host.global_position - anchor.to_global(anchor_local)
		dist = offset.length()
		if dist <= length or dist < 0.001:
			return
	var along := -offset / dist
	var closing := (host.velocity - anchor.velocity_at(origin)).dot(along)
	var want := clampf((dist - length) / maxf(delta, 0.001), 0.0, TAUT_MAX_CLOSE)
	if closing < want:
		var needed := want - closing
		var share := SpaceRock.push_share(host.get_mass(), anchor.get_mass())
		host.add_impulse(along * needed * share * host.get_mass())
		host.add_body_impulse(anchor, -along * needed * (1.0 - share) * anchor.get_mass(), origin)
	origin = anchor.to_global(anchor_local)
	offset = host.global_position - origin
	dist = offset.length()
	if dist <= length or dist < 0.001:
		return
	var fix := dist - length
	var pull := -offset / dist
	var share_fix := SpaceRock.push_share(host.get_mass(), anchor.get_mass())
	host.global_position += pull * fix * share_fix
	anchor.global_position -= pull * fix * (1.0 - share_fix)


func _hit(host: Wanderer, rock: SpaceRock, world_point: Vector2) -> void:
	if _shot.length_squared() <= 0.01:
		return
	host.add_body_impulse(rock, _shot * RECOIL_SPEED * host.get_mass(), world_point)


func _ignite(at: Vector2) -> void:
	burst = BURST_LIFE
	burst_at = at
	ignited = true


func _on_surface(rock: SpaceRock, world_point: Vector2) -> Vector2:
	var away := world_point - rock.global_position
	var radius := rock.get_hit_radius()
	if away.length_squared() < 1.0 or radius <= 0.0:
		return rock.global_position
	return rock.global_position + away.normalized() * radius
