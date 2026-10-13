class_name Tether
extends RefCounted

## Трос. Выстрел толкает стрелка назад. Стыковка поднимает газ и песок с камня.
## Втягивание коротит трос и ускоряет к телу. Дальше 30 размеров скитальца он не тянется.

enum Phase { IDLE, BOLT, LINKED }

const BODIES := 30.0
const BOLT_SPEED := 640.0
const RECOIL_SPEED := 90.0
## Доля импульса выстрела, которую наконечник отдаёт телу. Целиком камень слишком крутит.
const HIT_PUSH := 0.25
const REEL_RATE := 70.0
const MIN_LENGTH := 16.0
const TAUT_MAX_CLOSE := 280.0
const LINK_COUNT := 16
const BURST_LIFE := 1.05
## Свет пороха гаснет раньше: газ ещё висит, когда вспышка уже погасла.
const FLASH_LIFE := 0.20
const MUZZLE_LIFE := 0.58

var phase := Phase.IDLE
var anchor: Node2D = null
var anchor_local := Vector2.ZERO
## Угол губок в системе якоря: после стыковки крутится вместе с телом.
var anchor_angle := 0.0
## Второй конец: железо камня, на котором стоял герой в момент СКМ.
var home: Node2D = null
var home_local := Vector2.ZERO
var length := 0.0
var bolt_global := Vector2.ZERO
var bolt_velocity := Vector2.ZERO
var burst := 0.0
var burst_at := Vector2.ZERO
## Куда от камня летит пыль стыковки.
var burst_dir := Vector2.ZERO
var ignited := false
var muzzle := 0.0
var muzzle_at := Vector2.ZERO
var muzzle_dir := Vector2.ZERO
var _flown := 0.0
var _ignore: Node2D = null
var _shot := Vector2.ZERO
var _links := PackedVector2Array()
var _link_prev := PackedVector2Array()
var _bend_sign := 1.0


func linked() -> bool:
	return phase == Phase.LINKED and anchor != null and is_instance_valid(anchor)


func flying() -> bool:
	return phase == Phase.BOLT


func anchor_global() -> Vector2:
	if linked():
		return anchor.to_global(anchor_local)
	return bolt_global


func pinned() -> bool:
	return home != null and is_instance_valid(home)


func home_global() -> Vector2:
	if pinned():
		return home.to_global(home_local)
	return Vector2.ZERO


func pin_home(host: Wanderer) -> bool:
	## Конец садится на железо под ногами, не в центр героя. Крюк при этом уже должен держаться.
	if not linked() or host.dock.inside or not host.dock.docked:
		return false
	var stood := host.dock.body
	if stood == null or not is_instance_valid(stood):
		return false
	home = stood
	home_local = _skin_local(stood, host.dock.local)
	## Размер замирает на текущем расстоянии между концами и дальше не растёт и не коротится.
	var span := home_global().distance_to(anchor_global())
	length = minf(maxf(span, 0.001), max_length(host))
	_spawn_links()
	var stick := home_global()
	_ignite(stick, stick - stood.global_position)
	return true


func jaw_angle() -> float:
	## В мире. На якоре — угол тела плюс тот, с которым губки вошли.
	if linked():
		return anchor.global_rotation + anchor_angle
	if _shot.length_squared() > 0.01:
		return _shot.angle()
	return 0.0


func link_points() -> PackedVector2Array:
	if not _ensure_links():
		return PackedVector2Array()
	return _links.duplicate()


func link_span() -> float:
	if not _ensure_links():
		return 0.0
	return _polyline_length(_links)


func closest_on_links(point: Vector2) -> Vector3:
	if not _ensure_links():
		return Vector3(point.x, point.y, 0.0)
	return _closest_on_polyline(_links, point)


func point_on_links(u: float) -> Vector2:
	if not _ensure_links():
		return Vector2.ZERO
	return _point_on_polyline(_links, u)


func tangent_on_links(u: float) -> Vector2:
	if not _ensure_links():
		return Vector2.RIGHT
	var ahead := _point_on_polyline(_links, clampf(u + 0.02, 0.0, 1.0))
	var behind := _point_on_polyline(_links, clampf(u - 0.02, 0.0, 1.0))
	var dir := ahead - behind
	if dir.length_squared() < 0.0001:
		dir = _links[_links.size() - 1] - _links[0]
	if dir.length_squared() < 0.0001:
		return Vector2.RIGHT
	return dir.normalized()


func release() -> void:
	phase = Phase.IDLE
	anchor = null
	anchor_local = Vector2.ZERO
	anchor_angle = 0.0
	home = null
	home_local = Vector2.ZERO
	bolt_velocity = Vector2.ZERO
	length = 0.0
	_flown = 0.0
	_ignore = null
	_shot = Vector2.ZERO
	ignited = false
	_links = PackedVector2Array()
	_link_prev = PackedVector2Array()


func max_length(host: Wanderer) -> float:
	return host.character_size() * BODIES


func shoot(host: Wanderer, direction: Vector2) -> void:
	## Выстрел: отдача назад, болт вперёд. Камень под ногами этот выстрел не ловит.
	if direction.length_squared() <= 0.01:
		return
	var aim := direction.normalized()
	var stand: Node2D = host.dock.body if host.dock.docked and not host.dock.inside else null
	var from := host.global_position
	_recoil(host, aim)
	fire(host, from, aim, stand)


func plant(host: Wanderer, rock: Node2D, world_point: Vector2) -> void:
	if rock == null:
		return
	var reach := max_length(host)
	release()
	phase = Phase.LINKED
	anchor = rock
	var stick := _on_surface(rock, world_point)
	anchor_local = rock.to_local(stick)
	_remember_jaw(rock, stick - host.global_position)
	length = reach
	_ignite(stick, stick - rock.global_position)


func fire(host: Wanderer, from: Vector2, direction: Vector2, ignore: Node2D) -> void:
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
	_light_muzzle(from, _shot)


func integrate(host: Wanderer, delta: float, reeling: bool = false) -> void:
	if burst > 0.0:
		burst = maxf(0.0, burst - delta)
	if muzzle > 0.0:
		muzzle = maxf(0.0, muzzle - delta)
	if phase == Phase.BOLT:
		_fly_bolt(host, delta)
	elif linked():
		if pinned():
			_tie_bodies(host, delta)
			return
		if length > max_length(host):
			length = max_length(host)
		if not is_instance_valid(home):
			home = null
		if _aboard_anchor(host) or _at_anchor_skin(host):
			_hold_rope_aboard(host, delta, reeling)
		else:
			if reeling:
				_reel(delta)
			else:
				_pay_out(host)
			_constrain(host, delta)


static func first_along(host: Node, origin: Vector2, direction: Vector2, reach: float, ignore: Node2D) -> Node2D:
	if host == null:
		return null
	return Bodies.along_ray(host.get_tree(), origin, direction, reach, ignore, true)


static func ray_circle(origin: Vector2, dir: Vector2, center: Vector2, radius: float) -> float:
	return Body.ray_circle(origin, dir, center, radius)


func _recoil(host: Wanderer, aim: Vector2) -> void:
	var back := -aim * RECOIL_SPEED
	var stood := host.dock.body
	if host.dock.docked and not host.dock.inside and Body.is_body(stood):
		var share := SpaceRock.push_share(host.get_mass(), Body.mass(stood))
		host.velocity = Body.velocity_at(stood, host.global_position) + back * share
		host.add_body_impulse(stood, -back * host.get_mass() * share, host.global_position)
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
		var hit_t := Body.ray_distance(rock, bolt_global, dir)
		_attach(host, rock, bolt_global + dir * hit_t)
		return
	bolt_global += dir * dist
	if _flown >= reach or host.global_position.distance_to(bolt_global) >= reach - 0.5:
		release()


func _attach(host: Wanderer, rock: Node2D, world_point: Vector2) -> void:
	phase = Phase.LINKED
	anchor = rock
	anchor_local = rock.to_local(world_point)
	_remember_jaw(rock, _shot)
	## Сразу до крюка, не на весь запас: иначе E долго выбирает слабину, прежде чем тянуть.
	var span := host.global_position.distance_to(anchor.to_global(anchor_local))
	length = clampf(span, MIN_LENGTH, max_length(host))
	bolt_velocity = Vector2.ZERO
	_ignore = null
	_flown = 0.0
	_hit(host, rock, world_point)
	_ignite(world_point, world_point - rock.global_position)


func _aboard_anchor(host: Wanderer) -> bool:
	return host.dock.docked and host.dock.body == anchor


func _at_anchor_skin(host: Wanderer) -> bool:
	## Уже у тела: прямой натяг до крюка не достаёт и бьёт камень в стыковке.
	if anchor == null or not is_instance_valid(anchor):
		return false
	var pad := host.character_size() * 0.5 + 4.0
	var rock := anchor as SpaceRock
	if rock != null and rock.shaped and rock.outline != null:
		return rock.overlaps_circle(host.global_position, pad)
	var reach := Body.hit_radius(anchor) + pad
	return host.global_position.distance_squared_to(anchor.global_position) <= reach * reach


func _hold_rope_aboard(host: Wanderer, delta: float, reeling: bool) -> void:
	## Свободный натяг здесь швыряет обоих: кадр сбрасывает скорость ног, камень импульс копит.
	var span := host.global_position.distance_to(anchor_global())
	if length < span:
		length = span
	if not reeling:
		return
	_reel(delta)
	if length < span:
		length = span


func _pay_out(host: Wanderer) -> void:
	## Без E трос отпускает и от крюка, пока не выбран весь запас.
	var span := host.global_position.distance_to(anchor_global())
	if span > length:
		length = minf(span, max_length(host))


func _reel(delta: float) -> void:
	length = maxf(length - REEL_RATE * delta, MIN_LENGTH)


func _tie_bodies(_host: Wanderer, delta: float) -> void:
	## Длиннее закреплённого трос не растёт. Рывок в крепление делится на ход и спин. Короче — провисает.
	if not pinned() or not is_instance_valid(anchor) or home == anchor:
		return
	var origin := anchor_global()
	var other := home_global()
	var offset := other - origin
	var dist := offset.length()
	if dist < 0.001:
		return
	var along := offset / dist
	var inv := _linear_inv(anchor) + _linear_inv(home)
	var stretch := maxf(dist - length, 0.0)
	if dist + 0.001 >= length:
		Body.resist(anchor, origin, home, other, along, 0.0)
	if stretch > 0.0 and inv > 0.0:
		anchor.global_position += along * stretch * _linear_inv(anchor) / inv
		home.global_position -= along * stretch * _linear_inv(home) / inv
	_step_links(delta)


func _linear_inv(body: Node2D) -> float:
	var mass := Body.mass(body)
	if mass <= 0.0:
		return 0.0
	return 1.0 / mass


func _ensure_links() -> bool:
	if not pinned() or not is_instance_valid(anchor):
		return false
	if _links.size() == LINK_COUNT:
		return true
	_spawn_links()
	return _links.size() == LINK_COUNT


func _spawn_links() -> void:
	var home_at := home_global()
	var hook_at := anchor_global()
	_links = PackedVector2Array()
	_link_prev = PackedVector2Array()
	_links.resize(LINK_COUNT)
	_link_prev.resize(LINK_COUNT)
	for i in LINK_COUNT:
		var at := home_at.lerp(hook_at, float(i) / float(LINK_COUNT - 1))
		_links[i] = at
		_link_prev[i] = at
	_bend_sign = 1.0


func _step_links(_delta: float) -> void:
	if not _ensure_links():
		return
	var home_at := home_global()
	var hook_at := anchor_global()
	var chord := hook_at - home_at
	var dist := chord.length()
	if dist < 1.0:
		return
	if dist >= length - 0.5:
		for i in LINK_COUNT:
			var at := home_at.lerp(hook_at, float(i) / float(LINK_COUNT - 1))
			_links[i] = at
			_link_prev[i] = at
		return
	for i in range(1, LINK_COUNT - 1):
		var vel := _links[i] - _link_prev[i]
		_link_prev[i] = _links[i]
		_links[i] = _links[i] + vel
	_links[0] = home_at
	_links[LINK_COUNT - 1] = hook_at
	_satisfy_links(home_at, hook_at)
	if _off_chord() < 2.0:
		_bow_slack(home_at, hook_at, chord / dist, dist)
		_satisfy_links(home_at, hook_at)


func _satisfy_links(home_at: Vector2, hook_at: Vector2) -> void:
	var seg := length / float(LINK_COUNT - 1)
	for _iter in 12:
		for i in LINK_COUNT - 1:
			var a := _links[i]
			var b := _links[i + 1]
			var delta := b - a
			var span := delta.length()
			if span < 0.001:
				continue
			var corr := delta * ((span - seg) / span) * 0.5
			if i > 0:
				_links[i] = _links[i] + corr
			if i + 1 < LINK_COUNT - 1:
				_links[i + 1] = _links[i + 1] - corr
		_links[0] = home_at
		_links[LINK_COUNT - 1] = hook_at


func _bow_slack(home_at: Vector2, hook_at: Vector2, along: Vector2, dist: float) -> void:
	## Ровная цепочка при сближении концов уходит вбок и дальше живёт своей скоростью.
	var side := Vector2(-along.y, along.x)
	## Середина отстаёт от концов: провис смотрит против их бокового хода.
	var drift := Body.velocity_at(home, home_at) + Body.velocity_at(anchor, hook_at)
	var lateral := drift.dot(side)
	if absf(lateral) > 2.0:
		_bend_sign = -signf(lateral)
	if _bend_sign < 0.0:
		side = -side
	var half := dist * 0.5
	var rope_half := length * 0.5
	var sag := 0.0
	if rope_half > half:
		sag = sqrt(rope_half * rope_half - half * half) * 0.65
	for i in range(1, LINK_COUNT - 1):
		var u := float(i) / float(LINK_COUNT - 1)
		var bell := sin(u * PI)
		var placed := home_at.lerp(hook_at, u) + side * sag * bell
		_link_prev[i] = placed - side * bell * 0.5
		_links[i] = placed


func _off_chord() -> float:
	var home_at := _links[0]
	var hook_at := _links[_links.size() - 1]
	var chord := hook_at - home_at
	var span := chord.length()
	if span < 1.0:
		return 0.0
	var best := 0.0
	for i in range(1, _links.size() - 1):
		var rel := _links[i] - home_at
		var off := absf(rel.x * chord.y - rel.y * chord.x) / span
		best = maxf(best, off)
	return best


func _polyline_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


func _closest_on_polyline(points: PackedVector2Array, point: Vector2) -> Vector3:
	var total := _polyline_length(points)
	if total < 1.0:
		return Vector3(points[0].x, points[0].y, 0.0)
	var best_d := INF
	var best := Vector3(points[0].x, points[0].y, 0.0)
	var acc := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var span := ab.length()
		if span < 0.001:
			continue
		var t := clampf((point - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var at := a + ab * t
		var dist := point.distance_squared_to(at)
		if dist < best_d:
			best_d = dist
			best = Vector3(at.x, at.y, (acc + span * t) / total)
		acc += span
	return best


func _point_on_polyline(points: PackedVector2Array, u: float) -> Vector2:
	var total := _polyline_length(points)
	if total < 1.0:
		return points[0]
	var target := total * clampf(u, 0.0, 1.0)
	var acc := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var span := a.distance_to(b)
		if acc + span >= target - 0.0001:
			var t := 0.0 if span < 0.001 else (target - acc) / span
			return a.lerp(b, clampf(t, 0.0, 1.0))
		acc += span
	return points[points.size() - 1]


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
	var closing := (host.velocity - Body.velocity_at(anchor, origin)).dot(along)
	var want := clampf((dist - length) / maxf(delta, 0.001), 0.0, TAUT_MAX_CLOSE)
	if closing < want:
		var needed := want - closing
		var share := SpaceRock.push_share(host.get_mass(), Body.mass(anchor))
		host.add_impulse(along * needed * share * host.get_mass())
		## В центр, не в крюк: рывок у стыковки иначе крутит камень вокруг точки крепления.
		host.add_body_impulse(anchor, -along * needed * (1.0 - share) * Body.mass(anchor), anchor.global_position)
	origin = anchor.to_global(anchor_local)
	offset = host.global_position - origin
	dist = offset.length()
	if dist <= length or dist < 0.001:
		return
	var fix := dist - length
	var pull := -offset / dist
	var share_fix := SpaceRock.push_share(host.get_mass(), Body.mass(anchor))
	host.global_position += pull * fix * share_fix
	anchor.global_position -= pull * fix * (1.0 - share_fix)


func _hit(host: Wanderer, rock: Node2D, world_point: Vector2) -> void:
	if _shot.length_squared() <= 0.01:
		return
	host.add_body_impulse(rock, _shot * RECOIL_SPEED * HIT_PUSH * host.get_mass(), world_point)


func _remember_jaw(rock: Node2D, into: Vector2) -> void:
	var aim := into
	if aim.length_squared() <= 0.01:
		aim = Vector2.RIGHT
	anchor_angle = aim.angle() - rock.global_rotation


func _ignite(at: Vector2, away: Vector2 = Vector2.ZERO) -> void:
	burst = BURST_LIFE
	burst_at = at
	burst_dir = away.normalized() if away.length_squared() > 0.01 else Vector2.ZERO
	ignited = true


func _light_muzzle(at: Vector2, dir: Vector2) -> void:
	muzzle = MUZZLE_LIFE
	muzzle_at = at
	muzzle_dir = dir if dir.length_squared() > 0.01 else Vector2.RIGHT


func _skin_local(body: Node2D, seat: Vector2) -> Vector2:
	## Подошва стоит с зазором. Трос входит в ближайшее железо, а не остаётся на месте героя.
	var rock := body as SpaceRock
	if rock != null and rock.outline != null and rock.outline.points.size() >= 3:
		return rock.outline.closest_iron(seat)
	return body.to_local(_on_surface(body, body.to_global(seat)))


func _on_surface(rock: Node2D, world_point: Vector2) -> Vector2:
	var away := world_point - rock.global_position
	var radius := Body.hit_radius(rock)
	if away.length_squared() < 1.0 or radius <= 0.0:
		return rock.global_position
	return rock.global_position + away.normalized() * radius
