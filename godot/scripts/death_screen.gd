class_name DeathScreen
extends CanvasLayer

## Затемнение и текст гибели. Клик мыши после короткой паузы перезапускает сцену.

const LOST_TEXT := "Вы умерли.\nБесконечно скитаясь в космосе.\n\nНажмите мышь — начать снова"
const OXYGEN_TEXT := "В космосе нет кислорода, как и в ваших легких\n\nНажмите мышь — начать снова"
const INPUT_GRACE := 0.35

var message := LOST_TEXT

var _root: Control
var _dim: ColorRect


static func clear_orphans(tree: SceneTree) -> void:
	## Старые оверлеи могли висеть на root и переживать reload.
	for child in tree.root.get_children():
		if child is CanvasLayer and child.name == "DoomOverlay":
			child.queue_free()


static func open(tree: SceneTree, text: String) -> void:
	var screen := DeathScreen.new()
	screen.name = "DoomOverlay"
	screen.layer = 100
	screen.message = text
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child.call_deferred(screen)


func _ready() -> void:
	_build()
	_arm()


func _arm() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await get_tree().create_timer(INPUT_GRACE).timeout
	if not is_inside_tree():
		return
	var restarting := false
	var do_restart := func() -> void:
		if restarting:
			return
		restarting = true
		if is_instance_valid(self):
			queue_free()
		GameMenu.restart(get_tree())
	var on_click := func(event: InputEvent) -> void:
		# Рестарт по отпусканию: зажатие не переносится в новую игру как заряд толчка.
		if event is InputEventMouseButton \
				and event.button_index == MOUSE_BUTTON_LEFT \
				and not event.pressed:
			do_restart.call()
	_dim.gui_input.connect(on_click)
	_root.gui_input.connect(on_click)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.color = Color(0.02, 0.02, 0.06, 0.72)
	_root.add_child(_dim)

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
	_root.add_child(label)
