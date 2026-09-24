class_name Wanderer
extends CharacterBody2D

## Без ранца: на теле ходишь и отталкиваешься с разной силой.
## В пустоте — только инерция. Курс без пересечения с телами → гибель.
## Крутится только спрайт — камера ровная.

const FACE_EPS := 1.0
const RESTITUTION := 0.55
const DOCK_SPEED := 60.0
const DOCK_SEPARATION := 2.0
const WALK_SPEED := 70.0
const PUSH_MIN := 10.0
const PUSH_MAX := 100.0
const CHARGE_TIME := 0.85
const DOOM_INPUT_GRACE := 0.35
const RESPAWN_INPUT_PAUSE := 0.45
const LOST_DOOM_DELAY := 6.0
const MASS := 26.0 * 26.0
const HIT_FRICTION := 0.35

@export var start_rock_path: NodePath = ^"../Bodies/StaticNear"

@onready var _sprite: Sprite2D = $Sprite

var docked := false
var _dock_body: Node2D = null
var _dock_local := Vector2.ZERO
var _dock_radius := 0.0
var _dock_angle := 0.0

var _charging := false
var _charge := 0.0
var _self_radius := 0.0
var _dead := false
var _controls_locked := true
var _lost_time := 0.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	_self_radius = _own_hit_radius()
	_controls_locked = true
	_clear_charge()
	_free_orphan_doom_overlays()
	call_deferred("_spawn_on_start_rock")
	call_deferred("_unlock_controls_when_ready")


func _free_orphan_doom_overlays() -> void:
	## Старые оверлеи могли висеть на root и переживать reload.
	for child in get_tree().root.get_children():
		if child is CanvasLayer and child.name == "DoomOverlay":
			child.queue_free()


func reseat_on_start() -> void:
	_spawn_on_start_rock()


func _spawn_on_start_rock() -> void:
	var rock := get_node_or_null(start_rock_path) as Node2D
	if rock == null:
		push_error("Стартовый астероид не найден: %s" % start_rock_path)
		return
	var body := rock as SpaceRock
	var rock_r := body.get_hit_radius() if body != null else 0.0
	var dist := rock_r + _self_radius + DOCK_SEPARATION
	global_position = rock.global_position + Vector2(0, -dist)
	dock_to(rock, Vector2.UP)


func _unlock_controls_when_ready() -> void:
	## Ждём, пока отпустят ЛКМ (клик рестарта), затем пауза — и только потом можно толкаться.
	while Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		await get_tree().process_frame
	await get_tree().create_timer(RESPAWN_INPUT_PAUSE).timeout
	if is_instance_valid(self) and not _dead:
		_controls_locked = false


func _unhandled_input(event: InputEvent) -> void:
	if _dead or _controls_locked:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if docked:
				_charging = true
				_charge = 0.0
				get_viewport().set_input_as_handled()
		else:
			if _charging:
				_release_push()
				get_viewport().set_input_as_handled()


func _release_push() -> void:
	if not docked:
		_clear_charge()
		return
	var left_rock := _dock_body
	var to_target := get_global_mouse_position() - global_position
	if to_target.length_squared() <= 0.01:
		to_target = _surface_outward()
	var speed := lerpf(PUSH_MIN, PUSH_MAX, clampf(_charge, 0.0, 1.0))
	var desired := to_target.normalized() * speed
	var rock := left_rock as SpaceRock
	if rock != null:
		var share := rock.get_mass() / (MASS + rock.get_mass())
		velocity = rock.velocity_at(global_position) + desired * share
		var impulse := -desired * MASS * share
		rock.apply_impulse(impulse, global_position)
	else:
		velocity = desired + _space_velocity(left_rock)
	_clear_charge()
	undock()


func course_is_lost() -> bool:
	## В полёте нет будущего касания ни с одним астероидом → потерялись.
	## Своя скорость может быть нулевой: камень способен догнать сам.
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as Node2D
		if rock != null and _will_meet_rock(rock):
			return false
	return true


func _will_meet_rock(rock: Node2D) -> bool:
	var body := rock as SpaceRock
	var rock_vel := Vector2.ZERO
	var hit_radius := 0.0
	if body != null:
		rock_vel = body.get_space_velocity()
		hit_radius = body.get_hit_radius()
	var to_center := rock.global_position - global_position
	var radius := _self_radius + hit_radius
	if to_center.length() <= radius:
		return true
	var rel := velocity - rock_vel
	if rel.length_squared() < 0.0001:
		return false
	var t := to_center.dot(rel) / rel.length_squared()
	if t < 0.0:
		return false
	var closest := to_center - rel * t
	return closest.length() <= radius


func _begin_doom() -> void:
	if _dead:
		return
	_dead = true
	set_physics_process(false)
	set_process_unhandled_input(false)
	call_deferred("_show_doom_and_restart")


func _show_doom_and_restart() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "DoomOverlay"
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.color = Color(0.02, 0.02, 0.06, 0.72)
	root.add_child(dim)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text = "Вы умерли.\nБесконечно скитаясь в космосе.\n\nНажмите мышь — начать снова"
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color(0.92, 0.93, 1.0))
	label.position = Vector2(-420, -90)
	label.size = Vector2(840, 180)
	root.add_child(label)

	# Вешаем на текущую сцену — иначе слой переживает reload и остаётся поверх игры.
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(layer)
	else:
		get_tree().root.add_child(layer)

	await get_tree().process_frame
	await get_tree().create_timer(DOOM_INPUT_GRACE).timeout

	var restarting := false
	var do_restart := func() -> void:
		if restarting:
			return
		restarting = true
		if is_instance_valid(layer):
			layer.queue_free()
		GameMenu.restart(get_tree())

	var on_click := func(event: InputEvent) -> void:
		# Рестарт по отпусканию: зажатие не переносится в новую игру как заряд толчка.
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and not event.pressed:
			do_restart.call()
	dim.gui_input.connect(on_click)
	root.gui_input.connect(on_click)


func _surface_outward() -> Vector2:
	if _dock_local.length_squared() < 0.01:
		return Vector2.UP
	var outward := _dock_local.normalized()
	if _dock_body != null:
		outward = outward.rotated(_dock_body.global_rotation)
	return outward


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if docked:
		_lost_time = 0.0
		if _controls_locked:
			_clear_charge()
			follow_dock()
			_face_on_surface()
			return
		if _charging:
			_charge = minf(1.0, _charge + delta / CHARGE_TIME)
		else:
			_walk_on_surface(delta)
		follow_dock()
		_face_on_surface()
		return

	_clear_charge()

	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_resolve_hit(collision)
		if docked or _dead:
			_lost_time = 0.0
			return

	if course_is_lost():
		_lost_time += delta
		if _lost_time >= LOST_DOOM_DELAY:
			_begin_doom()
			return
	else:
		_lost_time = 0.0

	if velocity.length_squared() > FACE_EPS * FACE_EPS:
		_sprite.rotation = velocity.angle() + PI / 2.0


func _walk_axis() -> float:
	var axis := 0.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		axis -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		axis += 1.0
	return axis


func _walk_on_surface(delta: float) -> void:
	var axis := _walk_axis()
	if absf(axis) < 0.01:
		return
	var radius := maxf(_dock_radius, 1.0)
	_dock_angle += axis * (WALK_SPEED / radius) * delta
	_dock_local = Vector2.from_angle(_dock_angle) * _dock_radius


func _face_on_surface() -> void:
	var outward := _surface_outward()
	_sprite.rotation = outward.angle() + PI / 2.0


func _resolve_hit(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider() as Node2D
	var normal := collision.get_normal()
	var rock := collider as SpaceRock
	var contact := collision.get_position()
	var body_vel := rock.velocity_at(contact) if rock != null else _space_velocity(collider)
	var relative := velocity - body_vel
	var approach := -relative.dot(normal)
	var dock_limit := DOCK_SPEED
	if rock != null:
		dock_limit *= minf(rock.get_mass() / MASS, 1.0)

	if approach <= dock_limit:
		dock_to(collider, normal)
		return

	if rock == null:
		velocity = relative.bounce(normal) * RESTITUTION + body_vel
		global_position += normal * DOCK_SEPARATION
		return

	var inv_sum := 1.0 / MASS + 1.0 / rock.get_mass()
	var jn := (1.0 + RESTITUTION) * approach / inv_sum
	velocity += normal * jn / MASS
	rock.apply_impulse(-normal * jn, contact)
	var tangent := Vector2(-normal.y, normal.x)
	var slip := (velocity - rock.velocity_at(contact)).dot(tangent)
	var radius := rock.get_hit_radius()
	var inv_t := inv_sum + (radius * radius) / rock.get_inertia()
	var jt := clampf(slip / inv_t, -HIT_FRICTION * jn, HIT_FRICTION * jn)
	velocity -= tangent * jt / MASS
	rock.apply_impulse(tangent * jt, contact)
	global_position += normal * DOCK_SEPARATION
	var shove := collision.get_depth() * MASS / (MASS + rock.get_mass())
	rock.global_position -= normal * shove


func dock_to(body: Node2D, normal: Vector2) -> void:
	if body == null:
		return
	docked = true
	_dock_body = body
	global_position += normal * DOCK_SEPARATION
	_dock_local = body.to_local(global_position)
	_dock_radius = maxf(_dock_local.length(), 1.0)
	_dock_angle = _dock_local.angle()
	_dock_local = Vector2.from_angle(_dock_angle) * _dock_radius
	var rock := body as SpaceRock
	velocity = rock.velocity_at(global_position) if rock != null else _space_velocity(body)
	_clear_charge()
	_lost_time = 0.0
	_face_on_surface()


func follow_dock() -> void:
	if _dock_body == null or not is_instance_valid(_dock_body):
		undock()
		return
	global_position = _dock_body.to_global(_dock_local)
	var rock := _dock_body as SpaceRock
	velocity = rock.velocity_at(global_position) if rock != null else _space_velocity(_dock_body)


func undock() -> void:
	docked = false
	_dock_body = null
	_dock_local = Vector2.ZERO
	_dock_radius = 0.0
	_dock_angle = 0.0
	_clear_charge()


func _clear_charge() -> void:
	_charging = false
	_charge = 0.0


func _own_hit_radius() -> float:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is CircleShape2D:
		return 0.0
	var circle := shape_node.shape as CircleShape2D
	return circle.radius * maxf(absf(scale.x), absf(scale.y))


func _space_velocity(body: Node) -> Vector2:
	if body == null:
		return Vector2.ZERO
	var rock := body as SpaceRock
	if rock == null:
		return Vector2.ZERO
	return rock.get_space_velocity()
