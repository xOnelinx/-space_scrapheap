class_name Wanderer
extends CharacterBody2D

## Без ранца: отталкиваешься с разной силой. В пустоте — только инерция.
## По кромке астероида — A/D. По корпусу — WASD.
## Магнитные ботинки: к обломку цепляется при любом ударе.
## С любой точки корпуса прыжок в любую сторону.
## Курс без пересечения с телами → гибель. Крутится только спрайт.
## ПКМ — курс до края экрана и стрелка скорости (спин опоры).
## Сила толчка — по расстоянию курсора: дальше сильнее, ближе слабее.
## Кислород кончается сам. Секунда зажатого толчка — потом 5 секунд двойного расхода.

const FACE_EPS := 1.0
const RESTITUTION := 0.55
const DOCK_SPEED := 60.0
const DOCK_SEPARATION := 2.0
const WALK_SPEED := 70.0
const PUSH_MIN := 10.0
const PUSH_MAX := 100.0
## Курсор у персонажа — минимум, дальше CHARGE_DIST_MAX — полный толчок.
const CHARGE_DIST_MIN := 28.0
const CHARGE_DIST_MAX := 220.0
const DOOM_INPUT_GRACE := 0.35
const RESPAWN_INPUT_PAUSE := 0.45
const LOST_DOOM_DELAY := 6.0
const OXYGEN_SECONDS := 1800.0
const OXYGEN_START := 200.0
const OXYGEN_DOUBLE_PER_HOLD := 5.0
const OXYGEN_COLOR := Color(0.4, 0.78, 1.0)
const OXYGEN_DOUBLE_COLOR := Color(1.0, 0.62, 0.28)
const LOST_DEATH_TEXT := "Вы умерли.\nБесконечно скитаясь в космосе.\n\nНажмите мышь — начать снова"
const OXYGEN_DEATH_TEXT := "В космосе нет кислорода, как и в ваших легких\n\nНажмите мышь — начать снова"
const MASS := 26.0 * 26.0
const HIT_FRICTION := 0.35
const AIM_HORIZON := 3.0
## Верх спрайта — прямоугольный рюкзак, это спина. Низ — ноги, ими встаём на камень.
const FOOT_EXTENT := 10.0

@export var start_rock_path: NodePath = ^"../Bodies/StaticNear"

@onready var _sprite: Sprite2D = $Sprite

var dock := Dock.new()

var _charging := false
var _charge := 0.0
## Корпус, с которого только что прыгнули: круг ещё внутри, столкновение выключено.
var _slip_body: Node2D = null
var _hold_time := 0.0
var _oxygen_double := 0.0
var _self_radius := 0.0
var _dead := false
var _controls_locked := true
var _lost_time := 0.0
var _oxygen := OXYGEN_START
var _oxygen_flash := 0.0
var _oxygen_label: Label


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("wanderer")
	_self_radius = _own_hit_radius()
	_controls_locked = true
	_clear_charge()
	_free_orphan_doom_overlays()
	_build_oxygen_hud()
	call_deferred("_spawn_on_start_rock")
	call_deferred("_unlock_controls_when_ready")


func _free_orphan_doom_overlays() -> void:
	## Старые оверлеи могли висеть на root и переживать reload.
	for child in get_tree().root.get_children():
		if child is CanvasLayer and child.name == "DoomOverlay":
			child.queue_free()


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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if dock.docked:
			if not event.pressed:
				_cancel_aim_charge()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if dock.docked:
				_charging = true
				_charge = _charge_from_cursor()
				_hold_time = 0.0
				get_viewport().set_input_as_handled()
		else:
			if _charging:
				_release_push()
				get_viewport().set_input_as_handled()


func _release_push() -> void:
	var to_target := get_global_mouse_position() - global_position
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	_commit_push(to_target)


func _commit_push(to_target: Vector2) -> void:
	if not dock.docked:
		_clear_charge()
		return
	var left := dock.body
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	var rock := left as SpaceRock
	velocity = launch_velocity(to_target, _charge)
	if rock != null:
		var desired := push_desired(to_target, _charge)
		var share := rock.get_mass() / (MASS + rock.get_mass())
		rock.apply_impulse(-desired * MASS * share, global_position)
	_oxygen_double += _hold_time * OXYGEN_DOUBLE_PER_HOLD
	_clear_charge()
	undock()
	if rock != null and rock.hull:
		_begin_slip(rock)


func _begin_slip(body: Node2D) -> void:
	_end_slip()
	if body == null:
		return
	_slip_body = body
	_set_body_shape_disabled(true)


func _end_slip() -> void:
	if _slip_body == null:
		return
	_slip_body = null
	if not dock.docked:
		_set_body_shape_disabled(false)


func _release_slip_if_clear() -> void:
	if _slip_body == null:
		return
	if not is_instance_valid(_slip_body):
		_slip_body = null
		return
	var rock := _slip_body as SpaceRock
	if rock == null or _cleared_hull(rock):
		_end_slip()


func _cleared_hull(rock: SpaceRock) -> bool:
	## Круг уже снаружи контура — можно снова сталкиваться с этим корпусом.
	if rock.outline == null:
		return true
	var local := rock.to_local(global_position)
	if Geometry2D.is_point_in_polygon(local, rock.outline.points):
		return false
	var rim := rock.outline.nearest_rim(local)
	var gap: float = rim.distance
	if gap == INF:
		return true
	return gap * rock.uniform_scale() >= _self_radius + DOCK_SEPARATION


func course_is_lost() -> bool:
	## В полёте нет будущего касания ни с одним астероидом → потерялись.
	## Своя скорость может быть нулевой: камень способен догнать сам.
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as Node2D
		if rock != null and _will_meet_rock(rock):
			return false
	return true


func lost_progress() -> float:
	## 0 на теле или после гибели, 1 — в момент экрана смерти.
	if _dead or dock.docked:
		return 0.0
	return clampf(_lost_time / LOST_DOOM_DELAY, 0.0, 1.0)


func _will_meet_rock(rock: Node2D) -> bool:
	var body := rock as SpaceRock
	var hit_radius := body.get_hit_radius() if body != null else 0.0
	var to_center := rock.global_position - global_position
	var radius := _self_radius + hit_radius
	if to_center.length() <= radius:
		return true
	var rel := velocity - _velocity_at(rock, rock.global_position)
	if rel.length_squared() < 0.0001:
		return false
	var t := to_center.dot(rel) / rel.length_squared()
	if t < 0.0:
		return false
	var closest := to_center - rel * t
	return closest.length() <= radius


func _build_oxygen_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.name = "OxygenHud"
	add_child(layer)

	_oxygen_label = Label.new()
	_oxygen_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_oxygen_label.position = Vector2(20, 14)
	_oxygen_label.add_theme_font_size_override("font_size", 48)
	_oxygen_label.add_theme_color_override("font_color", OXYGEN_COLOR)
	layer.add_child(_oxygen_label)
	_refresh_oxygen_label()


func grant_oxygen(seconds: float) -> bool:
	## Полный запас не забирает баллон: касание впустую его не съедает.
	if _dead or _controls_locked or seconds <= 0.0:
		return false
	var room := OXYGEN_SECONDS - _oxygen
	if room < 1.0:
		return false
	_oxygen += minf(seconds, room)
	_oxygen_flash = 0.45
	_refresh_oxygen_label()
	return true


func _tick_oxygen(delta: float) -> bool:
	var rate := 1.0
	if _oxygen_double > 0.0:
		rate = 2.0
		_oxygen_double = maxf(0.0, _oxygen_double - delta)
	_oxygen = maxf(0.0, _oxygen - delta * rate)
	_refresh_oxygen_label()
	_tick_oxygen_flash(delta)
	if _oxygen > 0.0:
		return false
	_begin_doom(OXYGEN_DEATH_TEXT)
	return true


func _tick_oxygen_flash(delta: float) -> void:
	if _oxygen_label == null:
		return
	if _oxygen_flash > 0.0:
		_oxygen_flash = maxf(0.0, _oxygen_flash - delta)
		var t := clampf(_oxygen_flash / 0.45, 0.0, 1.0)
		_oxygen_label.add_theme_color_override("font_color", OXYGEN_COLOR.lerp(Color(0.9, 0.97, 1.0), t))
	elif _oxygen_double > 0.0:
		_oxygen_label.add_theme_color_override("font_color", OXYGEN_DOUBLE_COLOR)
	else:
		_oxygen_label.add_theme_color_override("font_color", OXYGEN_COLOR)


func _refresh_oxygen_label() -> void:
	var seconds := 0 if _oxygen <= 0.0 else ceili(_oxygen)
	_oxygen_label.text = str(seconds)


func _begin_doom(message: String = LOST_DEATH_TEXT) -> void:
	if _dead:
		return
	_dead = true
	set_physics_process(false)
	set_process_unhandled_input(false)
	call_deferred("_show_doom_and_restart", message)


func _show_doom_and_restart(message: String) -> void:
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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = message
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


func _physics_process(delta: float) -> void:
	if _dead:
		return
	if _tick_oxygen(delta):
		return
	_release_slip_if_clear()
	if dock.docked:
		_lost_time = 0.0
		if _controls_locked:
			_clear_charge()
			follow_dock()
			_face_on_surface()
			return
		if _charging:
			_hold_time += delta
			_charge = _charge_from_cursor()
		else:
			_walk_on_surface(delta)
		follow_dock()
		_face_on_surface()
		return

	_clear_charge()

	var collision := move_and_collide(velocity * delta)
	if collision != null:
		_resolve_hit(collision)
		if dock.docked or _dead:
			_lost_time = 0.0
			return

	if course_is_lost():
		_lost_time += delta
		if _lost_time >= LOST_DOOM_DELAY:
			_begin_doom()
			return
	else:
		_lost_time = 0.0

	_sprite.position = Vector2.ZERO
	if velocity.length_squared() > FACE_EPS * FACE_EPS:
		_sprite.rotation = velocity.angle() - PI / 2.0


func _screen_dir() -> Vector2:
	## Экранные оси: W вверх, S вниз, A влево, D вправо. Y экрана вниз.
	var dir := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1.0
	return dir


func _walk_on_surface(delta: float) -> void:
	var dir := _screen_dir()
	if dock.has_outline():
		if dir.length_squared() < 0.01:
			return
		_step_on_hull(dir.normalized(), delta)
		return
	_walk_rim(dir.x, delta)


func _walk_rim(axis: float, delta: float) -> void:
	if absf(axis) < 0.01:
		return
	var radius := maxf(dock.radius, 1.0)
	dock.angle += axis * (WALK_SPEED / radius) * delta
	dock.local = Vector2.from_angle(dock.angle) * dock.radius
	dock.normal_local = dock.local.normalized()


func _step_on_hull(screen_dir: Vector2, delta: float) -> void:
	var rock := dock.rock()
	if rock == null or rock.outline == null or screen_dir.length_squared() < 0.01:
		return
	var screen_delta := screen_dir.normalized() * WALK_SPEED * delta
	var local_delta := _world_delta_to_local(rock, screen_delta)
	var margin := rock.outline.fit_margin(dock.local, _hull_margin(rock))
	var next := rock.outline.slide(dock.local, local_delta, margin)
	if next.distance_squared_to(dock.local) < 0.01:
		return
	dock.local = next
	dock.hull_face = screen_dir.angle() - PI / 2.0


func _world_delta_to_local(body: Node2D, world_delta: Vector2) -> Vector2:
	return body.to_local(body.global_position + world_delta)


func _hull_margin(rock: SpaceRock) -> float:
	return _self_radius / rock.uniform_scale()


func _face_on_surface() -> void:
	if dock.has_hull():
		_sprite.position = Vector2.ZERO
		_sprite.rotation = dock.hull_face
		return
	var outward := dock.outward()
	## +PI/2 кладёт низ спрайта (ноги) на камень, рюкзак наружу.
	_sprite.rotation = outward.angle() + PI / 2.0
	var feet_gap := maxf(_self_radius - FOOT_EXTENT, 0.0)
	_sprite.position = -outward * feet_gap


func _resolve_hit(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider() as Node2D
	var normal := collision.get_normal()
	var rock := collider as SpaceRock
	var contact := collision.get_position()
	var body_vel := _velocity_at(collider, contact)
	var relative := velocity - body_vel
	var approach := -relative.dot(normal)
	if approach <= asteroid_dock_speed(rock):
		dock_to(collider, normal)
		return

	if rock == null:
		velocity = relative.bounce(normal) * RESTITUTION + body_vel
		global_position += normal * DOCK_SEPARATION
		return

	var inv_sum := 1.0 / MASS + 1.0 / rock.get_mass()
	var tangent := Vector2(-normal.y, normal.x)
	var jn := SpaceRock.normal_impulse(approach, inv_sum, RESTITUTION)
	velocity += normal * jn / MASS
	rock.apply_impulse(-normal * jn, contact)
	var slip := (velocity - _velocity_at(rock, contact)).dot(tangent)
	var radius := rock.get_hit_radius()
	var inv_t := inv_sum + (radius * radius) / rock.get_inertia()
	var jt := SpaceRock.friction_impulse(slip, inv_t, jn, HIT_FRICTION)
	velocity -= tangent * jt / MASS
	rock.apply_impulse(tangent * jt, contact)
	global_position += normal * DOCK_SEPARATION
	var shove := SpaceRock.separation_share(collision.get_depth(), rock.get_mass(), MASS)
	rock.global_position -= normal * shove


func is_aiming() -> bool:
	if _dead or _controls_locked or not dock.docked:
		return false
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)


func aim_charge() -> float:
	if _charging:
		return clampf(_charge, 0.0, 1.0)
	if is_aiming():
		return _charge_from_cursor()
	return 0.0


func charge_from_offset(to_target: Vector2) -> float:
	## 0 у персонажа, 1 на CHARGE_DIST_MAX и дальше. Ближе курсор — слабее толчок.
	return clampf(
			inverse_lerp(CHARGE_DIST_MIN, CHARGE_DIST_MAX, to_target.length()),
			0.0,
			1.0)


func aim_target() -> Vector2:
	var to_target := get_global_mouse_position() - global_position
	if to_target.length_squared() <= 0.01:
		return dock.outward()
	return to_target


func launch_velocity(to_target: Vector2, charge: float) -> Vector2:
	if not dock.docked or dock.body == null:
		return Vector2.ZERO
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	var desired := push_desired(to_target, charge)
	var rock := dock.rock()
	if rock != null:
		var share := rock.get_mass() / (MASS + rock.get_mass())
		return _velocity_at(rock, global_position) + desired * share
	return desired + _velocity_at(dock.body, global_position)


func push_desired(to_target: Vector2, charge: float) -> Vector2:
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	var speed := lerpf(PUSH_MIN, PUSH_MAX, clampf(charge, 0.0, 1.0))
	return to_target.normalized() * speed


func first_aim_hit(launch_vel: Vector2, horizon: float) -> float:
	var rock := first_aim_rock(launch_vel, horizon)
	if rock == null:
		return INF
	return _aim_hit_time(rock, launch_vel)


func first_aim_rock(launch_vel: Vector2, horizon: float) -> SpaceRock:
	## Ближайшее чужое тело на курсе. Опору, с которой толкаемся, пропускаем.
	var best := INF
	var found: SpaceRock = null
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null or rock == dock.body:
			continue
		var hit_t := _aim_hit_time(rock, launch_vel)
		if hit_t > 0.0 and hit_t <= horizon and hit_t < best:
			best = hit_t
			found = rock
	return found


func aim_relative_velocity(launch_vel: Vector2, horizon: float) -> Vector2:
	## Скорость относительно тела на курсе. Нет тела — нулевой вектор, не мировая |v|.
	var rock := first_aim_rock(launch_vel, horizon)
	if rock == null:
		return Vector2.ZERO
	return launch_vel - _body_vel_at_aim_hit(rock, launch_vel)


func aim_approach_into(rock: SpaceRock, launch_vel: Vector2) -> float:
	## Скорость входа в поверхность — тот же смысл, что approach в _resolve_hit.
	if rock == null:
		return 0.0
	var rel := launch_vel - _body_vel_at_aim_hit(rock, launch_vel)
	var hit_t := _aim_hit_time(rock, launch_vel)
	if hit_t >= INF:
		return 0.0
	var at := global_position + launch_vel * hit_t
	var center := rock.global_position + rock.get_space_velocity() * hit_t
	var away := at - center
	if away.length_squared() < 0.0001:
		return rel.length()
	return -rel.dot(away.normalized())


func asteroid_dock_speed(rock: SpaceRock) -> float:
	if rock == null:
		return DOCK_SPEED
	if rock.hull:
		return INF
	return DOCK_SPEED * minf(rock.get_mass() / MASS, 1.0)


func aim_too_fast_for_meteor(launch_vel: Vector2, horizon: float = AIM_HORIZON) -> bool:
	var rock := first_aim_rock(launch_vel, horizon)
	if rock == null or rock.hull:
		return false
	return aim_approach_into(rock, launch_vel) > asteroid_dock_speed(rock)


func dock_to(body: Node2D, normal: Vector2) -> void:
	if body == null:
		return
	dock.docked = true
	dock.body = body
	var rock := dock.rock()
	if dock.has_outline():
		var inward := -normal.rotated(-rock.global_rotation)
		dock.local = rock.outline.seat(rock.to_local(global_position), inward, _hull_margin(rock))
		dock.hull_face = 0.0
		global_position = body.to_global(dock.local)
	else:
		global_position += normal * DOCK_SEPARATION
		dock.local = body.to_local(global_position)
		dock.radius = maxf(dock.local.length(), 1.0)
		dock.angle = dock.local.angle()
		dock.local = Vector2.from_angle(dock.angle) * dock.radius
		dock.normal_local = dock.local.normalized()
	velocity = _velocity_at(body, global_position)
	_set_body_shape_disabled(true)
	_clear_charge()
	_lost_time = 0.0
	_face_on_surface()


func follow_dock() -> void:
	if not dock.follow(self):
		undock()


func undock() -> void:
	dock.clear()
	_set_body_shape_disabled(false)
	_clear_charge()


func _set_body_shape_disabled(disabled: bool) -> void:
	## Пока стоишь, корпус не выталкивает круг из контура каждый кадр.
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node != null:
		shape_node.disabled = disabled


func _body_vel_at_aim_hit(rock: SpaceRock, launch_vel: Vector2) -> Vector2:
	var hit_t := _aim_hit_time(rock, launch_vel)
	if hit_t >= INF:
		return rock.get_space_velocity()
	var at := global_position + launch_vel * hit_t
	var center := rock.global_position + rock.get_space_velocity() * hit_t
	var offset := at - center
	return rock.get_space_velocity() + rock.spin * Vector2(-offset.y, offset.x)


func _aim_hit_time(rock: SpaceRock, launch_vel: Vector2) -> float:
	var to_center := rock.global_position - global_position
	var radius := _self_radius + rock.get_hit_radius()
	var rel := launch_vel - rock.get_space_velocity()
	if rel.length_squared() < 0.0001:
		return INF
	var a := rel.length_squared()
	var b := -2.0 * to_center.dot(rel)
	var c := to_center.length_squared() - radius * radius
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return INF
	var root := sqrt(disc)
	var t_enter := (-b - root) / (2.0 * a)
	if t_enter > 0.0001:
		return t_enter
	var t_exit := (-b + root) / (2.0 * a)
	if t_exit > 0.0001:
		return t_exit
	return INF


func _charge_from_cursor() -> float:
	return charge_from_offset(get_global_mouse_position() - global_position)


func _clear_charge() -> void:
	_charging = false
	_charge = 0.0
	_hold_time = 0.0


func _cancel_aim_charge() -> void:
	## Отпустили ПКМ: заряд сгорает, прыжка нет. Нужен новый зажим ЛКМ.
	_clear_charge()


func _own_hit_radius() -> float:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not shape_node.shape is CircleShape2D:
		return 0.0
	var circle := shape_node.shape as CircleShape2D
	return circle.radius * maxf(absf(scale.x), absf(scale.y))


func _velocity_at(body: Node, at: Vector2) -> Vector2:
	return Dock.velocity_at(body, at)
