class_name Bodies
extends RefCounted

## Кто лежит в мире. Камни — группа space_rocks, толкаемые ещё и loot.
## Новый вид тела регистрируют здесь, а не в каждом луче.


static func rocks(tree: SceneTree) -> Array:
	if tree == null:
		return []
	return tree.get_nodes_in_group("space_rocks")


static func pushable(tree: SceneTree) -> Array:
	var nodes := rocks(tree)
	if tree == null:
		return nodes
	nodes.append_array(tree.get_nodes_in_group("loot"))
	return nodes


static func along_ray(tree: SceneTree, origin: Vector2, direction: Vector2, reach: float, ignore: Node2D, with_loot: bool) -> Node2D:
	if direction.length_squared() <= 0.0001 or reach <= 0.0:
		return null
	var dir := direction.normalized()
	var best_t := reach
	var found: Node2D = null
	var nodes := pushable(tree) if with_loot else rocks(tree)
	for node in nodes:
		var body := node as Node2D
		if body == null or body == ignore or not Body.is_body(body):
			continue
		var t := Body.ray_distance(body, origin, dir)
		if t >= 0.0 and t < INF and t <= best_t:
			best_t = t
			found = body
	return found


static func will_meet(from: Vector2, velocity: Vector2, radius: float, other: Node2D) -> bool:
	if other == null:
		return false
	var to_center := other.global_position - from
	var reach := radius + Body.hit_radius(other)
	if to_center.length() <= reach:
		return true
	var rel := velocity - Body.velocity_at(other, other.global_position)
	if rel.length_squared() < 0.0001:
		return false
	var t := to_center.dot(rel) / rel.length_squared()
	if t < 0.0:
		return false
	var closest := to_center - rel * t
	return closest.length() <= reach


static func any_meet(tree: SceneTree, from: Vector2, velocity: Vector2, radius: float) -> bool:
	for node in rocks(tree):
		var body := node as Node2D
		if body != null and will_meet(from, velocity, radius, body):
			return true
	return false


static func nearest_overlap(tree: SceneTree, origin: Vector2, radius: float, skip_hull: bool) -> Node2D:
	var found: Node2D = null
	var best := INF
	for node in rocks(tree):
		var body := node as Node2D
		if body == null or not Body.is_body(body):
			continue
		if skip_hull and bool(body.get("hull")):
			continue
		var reach := radius + Body.hit_radius(body)
		var dist := origin.distance_to(body.global_position)
		if dist < reach and dist < best:
			best = dist
			found = body
	return found


static func soonest(tree: SceneTree, ignore: Node, horizon: float, time_of: Callable) -> Node2D:
	var best := INF
	var found: Node2D = null
	for node in rocks(tree):
		var body := node as Node2D
		if body == null or body == ignore:
			continue
		var t := float(time_of.call(body))
		if t > 0.0 and t <= horizon and t < best:
			best = t
			found = body
	return found
