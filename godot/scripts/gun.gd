class_name Gun
extends RefCounted

## Пушка. Выстрел толкает стрелка назад и не впивается. Попадание делит импульс на ход и спин.

const MUZZLE_SPEED := 780.0
const RECOIL_SPEED := 64.0
const RANGE := 960.0
## Столько же, сколько пыль стыковки гарпуна: песчинки успевают разлететься.
const SPARK_LIFE := 1.05
## Клетка крупнее камня: пуля смотрит пару вёдер, а не всю сцену.
const CELL := 256.0

var rounds: Array[Round] = []
var sparks: Array[Spark] = []


# shortcut: патроны бесконечные, когда пушка будет находкой — конечный запас
func shoot(host: Wanderer, direction: Vector2) -> void:
	if direction.length_squared() <= 0.01:
		return
	var aim := direction.normalized()
	var stand: Node2D = host.dock.body if host.dock.docked and not host.dock.inside else null
	_recoil(host, aim)
	var round := Round.new()
	round.pos = host.global_position
	## Скорость в мире, как у болта гарпуна: собственный ход стрелка в пулю не входит.
	round.vel = aim * MUZZLE_SPEED
	round.ignore = stand
	rounds.append(round)


func integrate(host: Wanderer, delta: float) -> void:
	for i in range(sparks.size() - 1, -1, -1):
		sparks[i].life -= delta
		if sparks[i].life <= 0.0:
			sparks.remove_at(i)
	if rounds.is_empty():
		return
	## Иначе каждая пуля заново берёт группу из сотен камней.
	var tree := host.get_tree()
	var nodes: Array = Bodies.pushable(tree) if tree != null else []
	var grid := _body_grid(nodes)
	for i in range(rounds.size() - 1, -1, -1):
		if _fly(host, rounds[i], delta, grid):
			rounds.remove_at(i)


func _recoil(host: Wanderer, aim: Vector2) -> void:
	## Пуля уносит импульс вперёд. Ноги давят на камень в ту же сторону, что и отдача, не вслед за иглой.
	var back := -aim * RECOIL_SPEED
	var stood := host.dock.body
	if host.dock.docked and not host.dock.inside and Body.is_body(stood):
		var share := SpaceRock.push_share(host.get_mass(), Body.mass(stood))
		host.velocity = Body.velocity_at(stood, host.global_position) + back * share
		host.add_body_impulse(stood, back * host.get_mass() * share, host.global_position)
		host.undock()
		return
	host.add_impulse(back * host.get_mass())


func _fly(host: Wanderer, round: Round, delta: float, grid: Dictionary) -> bool:
	var step := round.vel * delta
	var dist := step.length()
	if dist <= 0.001:
		return true
	var dir := round.vel.normalized()
	var room := RANGE - round.flown
	if room <= 0.0:
		return true
	dist = minf(dist, room)
	var rock := _nearest(grid, round.pos, dir, dist, round.ignore)
	round.flown += dist
	if rock != null:
		var hit_t := Body.ray_distance(rock, round.pos, dir)
		_strike(host, rock, round.pos + dir * hit_t, dir)
		return true
	round.pos += dir * dist
	return round.flown >= RANGE


func _body_grid(nodes: Array) -> Dictionary:
	var grid: Dictionary = {}
	for node in nodes:
		var body := node as Node2D
		if body == null or not Body.is_body(body):
			continue
		var radius := Body.hit_radius(body)
		var center := body.global_position
		var min_c := _cell(center - Vector2(radius, radius))
		var max_c := _cell(center + Vector2(radius, radius))
		for y in range(min_c.y, max_c.y + 1):
			for x in range(min_c.x, max_c.x + 1):
				var key := Vector2i(x, y)
				if not grid.has(key):
					grid[key] = []
				var bucket: Array = grid[key]
				bucket.append(body)
	return grid


func _nearest(grid: Dictionary, origin: Vector2, dir: Vector2, reach: float, ignore: Node2D) -> Node2D:
	var best_t := reach
	var found: Node2D = null
	var end := origin + dir * reach
	var c0 := _cell(origin)
	var c1 := _cell(end)
	for y in range(mini(c0.y, c1.y), maxi(c0.y, c1.y) + 1):
		for x in range(mini(c0.x, c1.x), maxi(c0.x, c1.x) + 1):
			var key := Vector2i(x, y)
			if not grid.has(key):
				continue
			var bucket: Array = grid[key]
			for node in bucket:
				var body := node as Node2D
				if body == null or body == ignore:
					continue
				var t := Body.ray_distance(body, origin, dir, best_t)
				if t >= 0.0 and t < INF and t <= best_t:
					best_t = t
					found = body
	return found


func _cell(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / CELL), floori(at.y / CELL))


func _strike(host: Wanderer, rock: Node2D, world_point: Vector2, dir: Vector2) -> void:
	var away := world_point - rock.global_position
	var stone := rock as SpaceRock
	if stone != null and not stone.hull and away.length_squared() > 1.0:
		var spark := Spark.new()
		spark.at = world_point
		spark.dir = away.normalized()
		spark.life = SPARK_LIFE
		sparks.append(spark)
	## Импульс в центр: спин пишется отдельно, иначе плечо посчитается дважды.
	var tip_mass := Wanderer.MASS * RECOIL_SPEED / MUZZLE_SPEED
	var mass := Body.mass(rock)
	var rel := (dir * MUZZLE_SPEED - Body.velocity_at(rock, world_point)).dot(dir)
	if rel <= 0.0 or tip_mass <= 0.0 or mass <= 0.0:
		return
	var radius := maxf(Body.hit_radius(rock), 1.0)
	var lever := world_point - rock.global_position
	var cross := lever.x * dir.y - lever.y * dir.x
	var glance := clampf(absf(cross) / radius, 0.0, 1.0)
	var motion := lerpf(1.0, 0.5, glance)
	var impulse := rel / ((1.0 / tip_mass) + (1.0 / mass))
	host.add_body_impulse(rock, dir * motion * impulse, rock.global_position)
	var inertia := Body.inertia(rock)
	if inertia <= 0.0 or glance <= 0.0:
		return
	rock.set("spin", float(rock.get("spin")) + cross * (1.0 - motion) * impulse / inertia)


class Round extends RefCounted:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var flown := 0.0
	var ignore: Node2D = null


class Spark extends RefCounted:
	var at := Vector2.ZERO
	var dir := Vector2.ZERO
	var life := 0.0
