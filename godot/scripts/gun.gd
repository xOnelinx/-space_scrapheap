class_name Gun
extends RefCounted

## Пушка. Выстрел толкает стрелка назад и не впивается. Попадание делит импульс на ход и спин.

const MUZZLE_SPEED := 780.0
const RECOIL_SPEED := 64.0
const RANGE := 960.0
const SPARK_LIFE := 0.16

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
	for i in range(rounds.size() - 1, -1, -1):
		if _fly(host, rounds[i], delta):
			rounds.remove_at(i)


func _recoil(host: Wanderer, aim: Vector2) -> void:
	## С опоры отдача делится и отпускает ноги, как выстрел гарпуна.
	var back := -aim * RECOIL_SPEED
	var stood := host.dock.body
	if host.dock.docked and not host.dock.inside and Body.is_body(stood):
		var share := SpaceRock.push_share(host.get_mass(), Body.mass(stood))
		host.velocity = Body.velocity_at(stood, host.global_position) + back * share
		host.add_body_impulse(stood, -back * host.get_mass() * share, host.global_position)
		host.undock()
		return
	host.add_impulse(back * host.get_mass())


func _fly(host: Wanderer, round: Round, delta: float) -> bool:
	var step := round.vel * delta
	var dist := step.length()
	if dist <= 0.001:
		return true
	var dir := round.vel.normalized()
	var room := RANGE - round.flown
	if room <= 0.0:
		return true
	dist = minf(dist, room)
	var rock := Bodies.along_ray(host.get_tree(), round.pos, dir, dist, round.ignore, true)
	round.flown += dist
	if rock != null:
		var hit_t := Body.ray_distance(rock, round.pos, dir)
		_strike(host, rock, round.pos + dir * hit_t, dir)
		return true
	round.pos += dir * dist
	return round.flown >= RANGE


func _strike(host: Wanderer, rock: Node2D, world_point: Vector2, dir: Vector2) -> void:
	var spark := Spark.new()
	spark.at = world_point
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
	var life := 0.0
