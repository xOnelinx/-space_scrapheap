class_name Wanderer
extends CharacterBody2D

## Без ранца: отталкиваешься с разной силой. В пустоте — инерция, слабая правка курса WASD и короткий импульс.
## По кромке астероида — A/D. По корпусу — WASD. Внутри корпуса — тот же шаг, без прыжка.
## Магнитные ботинки: к обломку и к астероиду цепляется при любом ударе, на любой скорости.
## С любой точки корпуса прыжок в любую сторону.
## Курс без пересечения с телами → гибель. Крутится только спрайт. Пока висит трос, этот счётчик молчит.
## ПКМ — курс до края экрана и стрелка скорости (спин опоры).
## Сила толчка — по расстоянию курсора: дальше сильнее, ближе слабее.
## Кислород кончается сам. Секунда зажатого толчка — потом 5 секунд двойного расхода.

signal pushed(desired: Vector2, charge: float)
signal dock_changed(docked: bool, body: Node2D)

const FACE_EPS := 1.0
const RESTITUTION := 0.55
const DOCK_SEPARATION := 2.0
const WALK_SPEED := 70.0
const PUSH_MIN := 10.0
const PUSH_MAX := 100.0
## За секунду удержания WASD в полёте скорость меняется меньше, чем самый слабый толчок.
const FLIGHT_NUDGE := 8.0
## Сверх обычного дыхания, только пока в полёте зажата правка курса.
const FLIGHT_OXYGEN := 3.0
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
const AIM_HORIZON := 3.0
const VOID_SPEED := 48.0
## Верх спрайта — рюкзак, он наружу от камня. Низ — шлем, им встаём на поверхность.
const FOOT_EXTENT := 12.0
const _FLIGHT_JET := preload("res://scripts/flight_jet.gd")
## Захват астероида: руки к камню. Последний кадр держится, пока стоишь.
const GRAB_FRAME_COUNT := 4
const GRAB_FRAME_TIME := 0.08
const IDLE_SPRITE := preload("res://assets/wanderer.png")
const GRAB_SPRITE := preload("res://assets/wanderer_grab.png")

@export var start_rock_path: NodePath = ^"../Bodies/StaticNear"

@onready var _sprite: Sprite2D = $Sprite

var dock := Dock.new()
var tether := Tether.new()
## Масса груза на скафандре. Список предметов снаружи.
var cargo_mass := 0.0
## 0 — толчок по курсору. Иначе доля скорости вбок. Порванный скафандр пишет сам.
var leak_bias := 0.0

var _charging := false
var _charge := 0.0
## Корпус, с которого только что прыгнули: круг ещё внутри, столкновение выключено.
var _slip_body: Node2D = null
var _hold_time := 0.0
var _oxygen_double := 0.0
var _using_flight_correction := false
var _self_radius := 0.0
var _dead := false
var _controls_locked := true
var _lost_time := 0.0
var _oxygen := OXYGEN_START
var _oxygen_flash := 0.0
var _oxygen_label: Label
var _flight_jet: Node2D
## -1 — обычный спрайт. Иначе кадр захвата, пока скиталец на астероиде.
var _grab_frame := -1
var _grab_time := 0.0


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	add_to_group("wanderer")
	_self_radius = _own_hit_radius()
	_controls_locked = true
	_clear_charge()
	var rope := TetherView.new()
	rope.name = "TetherView"
	add_child(rope)
	_free_orphan_doom_overlays()
	_build_oxygen_hud()
	_build_flight_jet()
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_E:
			_cast_harpoon()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_Q:
			tether.release()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_F:
			_toggle_hatch()
			get_viewport().set_input_as_handled()
			return
	if dock.inside:
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
				add_void_impulse(_aim_dir(), VOID_SPEED)
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
	if not dock.docked or dock.inside:
		_clear_charge()
		return
	var left := dock.body
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	var desired := push_desired(to_target, _charge)
	var charge := _charge
	var rock := left as SpaceRock
	velocity = launch_velocity(to_target, _charge)
	if rock != null:
		var share := SpaceRock.push_share(get_mass(), rock.get_mass())
		add_body_impulse(rock, -desired * get_mass() * share, global_position)
	_oxygen_double += _hold_time * OXYGEN_DOUBLE_PER_HOLD
	_clear_charge()
	undock()
	pushed.emit(desired, charge)
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
	if _using_flight_correction:
		rate += FLIGHT_OXYGEN
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
	_using_flight_correction = _flight_correction_held()
	if _tick_oxygen(delta):
		return
	_release_slip_if_clear()
	if dock.inside:
		_lost_time = 0.0
		_clear_charge()
		if not _controls_locked:
			_walk_on_surface(delta)
		follow_dock()
		_face_on_surface()
		return
	if dock.docked:
		_lost_time = 0.0
		_show_flight_jet(Vector2.ZERO)
		tether.integrate(self, delta, _reeling())
		if not dock.has_hull():
			_tick_grab(delta)
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
	_nudge_flight(delta)

	# recovery_as_collision: въезд камня в скитальца на скорости тоже контакт, не выталкивание.
	var collision := move_and_collide(velocity * delta, false, 0.08, true)
	if collision != null:
		_resolve_hit(collision)
		if _dead:
			return
		if dock.docked:
			_lost_time = 0.0
			tether.integrate(self, delta, _reeling())
			if dock.docked:
				follow_dock()
				_face_on_surface()
			return
	elif _dock_if_buried():
		_lost_time = 0.0
		return

	tether.integrate(self, delta, _reeling())

	if tether.linked():
		_lost_time = 0.0
	elif course_is_lost():
		_lost_time += delta
		if _lost_time >= LOST_DOOM_DELAY:
			_begin_doom()
			return
	else:
		_lost_time = 0.0

	_sprite.position = Vector2.ZERO
	_show_idle_sprite()
	if velocity.length_squared() > FACE_EPS * FACE_EPS:
		_sprite.rotation = velocity.angle() - PI / 2.0


func _flight_correction_held() -> bool:
	## На камне WASD — ходьба, воздух на неё не тратится.
	if _controls_locked or dock.docked:
		return false
	return _screen_dir().length_squared() > 0.01


func _nudge_flight(delta: float) -> void:
	var dir := Vector2.ZERO if _controls_locked else _screen_dir()
	## Струя — выхлоп: летит против кнопки, сам сдвиг курса — по кнопке.
	_show_flight_jet(-dir)
	_apply_flight_nudge(dir, delta)


func _build_flight_jet() -> void:
	_flight_jet = _FLIGHT_JET.new()
	_flight_jet.name = "FlightJet"
	_flight_jet.z_index = 3
	add_child(_flight_jet)


func _show_flight_jet(dir: Vector2) -> void:
	if _flight_jet != null:
		_flight_jet.set_direction(dir)


func _apply_flight_nudge(dir: Vector2, delta: float) -> void:
	## Экранные WASD, не разворот спрайта: W всегда вверх экрана.
	if dir.length_squared() < 0.01:
		return
	velocity += dir.normalized() * FLIGHT_NUDGE * delta


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
	if dock.has_shape():
		_walk_shape(dir.x, delta)
		return
	_walk_rim(dir.x, delta)


func _walk_shape(axis: float, delta: float) -> void:
	var rock := dock.rock()
	var outline := rock.outline if rock != null else null
	if outline == null or absf(axis) < 0.01 or outline.rim < 1.0:
		return
	## Положительная площадь в экранных осях — обход по часовой, как D на круге.
	var sign := 1.0 if outline.loop_is_clockwise() else -1.0
	var step := axis * sign * WALK_SPEED * delta / rock.uniform_scale()
	dock.along = fposmod(dock.along + step, outline.rim)
	var pose := outline.rim_pose(dock.along)
	dock.local = pose.point
	dock.normal_local = _ease_normal(dock.normal_local, pose.normal, delta)


func _ease_normal(current: Vector2, target: Vector2, delta: float) -> Vector2:
	if current.length_squared() < 0.01 or target.length_squared() < 0.01:
		return target
	var max_turn := deg_to_rad(220.0) * delta
	var angle := clampf(current.normalized().angle_to(target.normalized()), -max_turn, max_turn)
	return current.normalized().rotated(angle)


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
	## +PI/2 кладёт низ спрайта (шлем) на камень, рюкзак наружу.
	_sprite.rotation = outward.angle() + PI / 2.0
	var feet_gap := maxf(_self_radius - FOOT_EXTENT, 0.0)
	_sprite.position = -outward * feet_gap


func _begin_grab() -> void:
	_grab_frame = 0
	_grab_time = 0.0
	_apply_grab_frame()


func _tick_grab(delta: float) -> void:
	if _grab_frame < 0 or _grab_frame >= GRAB_FRAME_COUNT - 1:
		return
	_grab_time += delta
	var next := _grab_frame
	while _grab_time >= GRAB_FRAME_TIME and next < GRAB_FRAME_COUNT - 1:
		_grab_time -= GRAB_FRAME_TIME
		next += 1
	if next == _grab_frame:
		return
	_grab_frame = next
	_apply_grab_frame()


func _apply_grab_frame() -> void:
	_sprite.texture = GRAB_SPRITE
	_sprite.hframes = GRAB_FRAME_COUNT
	_sprite.vframes = 1
	_sprite.frame = _grab_frame


func _show_idle_sprite() -> void:
	_grab_frame = -1
	_grab_time = 0.0
	if _sprite.hframes == 1 and _sprite.texture == IDLE_SPRITE:
		return
	_sprite.texture = IDLE_SPRITE
	_sprite.hframes = 1
	_sprite.vframes = 1
	_sprite.frame = 0


func _resolve_hit(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider() as Node2D
	var normal := collision.get_normal()
	var rock := collider as SpaceRock
	if rock != null:
		## Круглый камень: нормаль из центра, чтобы кривой контакт не вдавливал внутрь.
		if not rock.hull:
			var away := global_position - rock.global_position
			if away.length_squared() > 0.0001:
				normal = away.normalized()
		dock_to(collider, normal)
		return

	var contact := collision.get_position()
	var body_vel := _velocity_at(collider, contact)
	var relative := velocity - body_vel
	velocity = relative.bounce(normal) * RESTITUTION + body_vel
	global_position += normal * DOCK_SEPARATION


func is_aiming() -> bool:
	if _dead or _controls_locked or not dock.docked or dock.inside:
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
		var share := SpaceRock.push_share(get_mass(), rock.get_mass())
		return _velocity_at(rock, global_position) + desired * share
	return desired + _velocity_at(dock.body, global_position)


func push_desired(to_target: Vector2, charge: float) -> Vector2:
	if to_target.length_squared() <= 0.01:
		to_target = dock.outward()
	var speed := lerpf(PUSH_MIN, PUSH_MAX, clampf(charge, 0.0, 1.0))
	return _with_leak(to_target.normalized() * speed)


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


func asteroid_dock_speed(_rock: SpaceRock) -> float:
	## Лёгкий камень больше не срезает порог: удар быстрее толчка тоже цепляет.
	return INF


func _dock_if_buried() -> bool:
	## Кадр без отданного контакта: круг уже внутри астероида, вылет выглядел бы отскоком.
	var buried := _buried_asteroid()
	if buried == null:
		return false
	var away := global_position - buried.global_position
	var normal := Vector2.UP if away.length_squared() < 0.0001 else away.normalized()
	dock_to(buried, normal)
	return true


func _buried_asteroid() -> SpaceRock:
	var found: SpaceRock = null
	var best := INF
	for node in get_tree().get_nodes_in_group("space_rocks"):
		var rock := node as SpaceRock
		if rock == null or rock.hull:
			continue
		var reach := _self_radius + rock.get_hit_radius()
		var dist := global_position.distance_to(rock.global_position)
		if dist < reach and dist < best:
			best = dist
			found = rock
	return found


func aim_too_fast_for_meteor(_launch_vel: Vector2, _horizon: float = AIM_HORIZON) -> bool:
	## Посадка не зависит от скорости входа: и медленный, и быстрый контакт цепляет.
	return false


func dock_to(body: Node2D, normal: Vector2) -> void:
	if body == null:
		return
	dock.docked = true
	dock.inside = false
	dock.body = body
	var rock := dock.rock()
	if dock.has_shape():
		_seat_on_shape(rock)
	elif dock.has_outline():
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
	if dock.has_hull():
		_show_idle_sprite()
	else:
		_begin_grab()
	dock_changed.emit(true, body)


func _seat_on_shape(rock: SpaceRock) -> void:
	var outline := rock.outline
	dock.along = outline.closest_rim(rock.to_local(global_position))
	var pose := outline.rim_pose(dock.along)
	dock.local = pose.point
	dock.normal_local = pose.normal
	global_position = rock.to_global(dock.local)


func follow_dock() -> void:
	if not dock.follow(self):
		undock()


func undock() -> void:
	var left := dock.body
	dock.clear()
	_set_body_shape_disabled(false)
	_clear_charge()
	_show_idle_sprite()
	dock_changed.emit(false, left)


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


func character_size() -> float:
	return maxf(_self_radius, 1.0) * 2.0


func get_mass() -> float:
	return MASS + maxf(cargo_mass, 0.0)


func add_impulse(impulse: Vector2) -> void:
	var mass := get_mass()
	if mass <= 0.0 or impulse.length_squared() < 0.0000001:
		return
	velocity += impulse / mass


func add_body_impulse(body: Node2D, impulse: Vector2, world_point: Vector2) -> void:
	var rock := body as SpaceRock
	if rock == null or impulse.length_squared() < 0.0000001:
		return
	rock.apply_impulse(impulse, world_point)


func add_void_impulse(direction: Vector2, strength: float) -> bool:
	## Короткий импульс без опоры. Топливо решает тот, кто вызывает.
	if _dead or dock.docked or dock.inside:
		return false
	if direction.length_squared() <= 0.01 or strength <= 0.0:
		return false
	var desired := direction.normalized() * strength
	add_impulse(desired * get_mass())
	return true


func enter_interior(body: SpaceRock) -> bool:
	if _dead or body == null or not body.hull or body.outline == null:
		return false
	if dock.inside and dock.body == body:
		return true
	tether.release()
	_end_slip()
	dock.docked = true
	dock.inside = true
	dock.body = body
	var local := body.to_local(global_position)
	var margin := _hull_margin(body)
	if body.outline.on_face(local, margin):
		dock.local = local
	else:
		var inward := -local
		if inward.length_squared() < 0.01:
			inward = Vector2.UP
		dock.local = body.outline.seat(local, inward.normalized(), margin)
	dock.hull_face = 0.0
	global_position = body.to_global(dock.local)
	velocity = _velocity_at(body, global_position)
	_set_body_shape_disabled(true)
	_clear_charge()
	_lost_time = 0.0
	_face_on_surface()
	_show_idle_sprite()
	dock_changed.emit(true, body)
	return true


func exit_interior() -> void:
	if not dock.inside:
		return
	var rock := dock.rock()
	var pos := global_position
	var outward := Vector2.UP
	if rock != null and rock.outline != null:
		var rim := rock.outline.nearest_rim(dock.local)
		var out_local := rim.normal
		if out_local.length_squared() < 0.01:
			out_local = Vector2.UP
		out_local = out_local.normalized()
		var gap := rim.distance + _hull_margin(rock) + DOCK_SEPARATION
		var outside_local := dock.local + out_local * gap
		if rock.outline.on_face(outside_local, 0.0) or Geometry2D.is_point_in_polygon(outside_local, rock.outline.points):
			outside_local = dock.local + out_local * (rock.outline.bound_radius + gap)
		pos = rock.to_global(outside_local)
		outward = (pos - rock.global_position).normalized()
		if outward.length_squared() < 0.01:
			outward = Vector2.UP
	var body_vel := _velocity_at(rock, pos) if rock != null else Vector2.ZERO
	undock()
	global_position = pos
	velocity = body_vel + outward * 12.0


func _with_leak(desired: Vector2) -> Vector2:
	if absf(leak_bias) < 0.0001 or desired.length_squared() <= 0.01:
		return desired
	var side := Vector2(-desired.y, desired.x)
	if side.length_squared() <= 0.0001:
		return desired
	return desired + side.normalized() * desired.length() * leak_bias


func _aim_dir() -> Vector2:
	var to_target := get_global_mouse_position() - global_position
	if to_target.length_squared() <= 0.01:
		if dock.docked:
			return dock.outward()
		if velocity.length_squared() > 1.0:
			return velocity.normalized()
		return Vector2.UP
	return to_target


func fire_harpoon(direction: Vector2) -> void:
	if dock.inside or _dead:
		return
	if tether.linked() or tether.flying():
		return
	tether.shoot(self, direction)


func _reeling() -> bool:
	return not _dead and not _controls_locked and not dock.inside and tether.linked() \
			and Input.is_physical_key_pressed(KEY_E)


func _cast_harpoon() -> void:
	if dock.inside or tether.linked() or tether.flying():
		return
	fire_harpoon(_aim_dir())


func _toggle_hatch() -> void:
	if dock.inside:
		exit_interior()
		return
	var rock := dock.rock()
	if rock != null and rock.hull:
		enter_interior(rock)


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
