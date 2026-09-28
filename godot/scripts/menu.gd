class_name GameMenu
extends CanvasLayer

## Стартовое меню и пауза по Esc.
## start_immediately переживает reload сцены.

static var start_immediately := false

const _TITLE := "Космическая свалка"

var _root: Control
var _primary: Button
var _hint: Label
var _open := false
var _pause_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_build()
	if start_immediately:
		start_immediately = false
		_set_open(false)
		get_tree().paused = false
	else:
		_show_start()


static func restart(tree: SceneTree) -> void:
	start_immediately = true
	tree.paused = false
	tree.reload_current_scene()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"ui_cancel"):
		return
	if _open:
		if _pause_mode:
			_close()
	else:
		_show_pause()
	get_viewport().set_input_as_handled()


func _show_start() -> void:
	_pause_mode = false
	_primary.text = "Начать игру"
	_hint.visible = false
	_set_open(true)
	get_tree().paused = true
	_primary.grab_focus()


func _show_pause() -> void:
	_pause_mode = true
	_primary.text = "Начать заново"
	_hint.visible = true
	_set_open(true)
	get_tree().paused = true
	_primary.grab_focus()


func _close() -> void:
	_set_open(false)
	get_tree().paused = false


func _set_open(open: bool) -> void:
	_open = open
	_root.visible = open


func _on_primary() -> void:
	if _pause_mode:
		restart(get_tree())
		return
	_close()


func _on_quit() -> void:
	get_tree().quit()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(0.02, 0.02, 0.06, 0.78)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var column := _make_column()
	center.add_child(column)
	_fill_main_page(column)


func _make_column() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 18)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	return box


func _fill_main_page(column: Control) -> void:
	column.add_child(_make_title(_TITLE))
	column.add_child(_make_gap())

	_primary = _make_button("Начать игру")
	_primary.pressed.connect(_on_primary)
	column.add_child(_primary)

	var quit := _make_button("Выйти")
	quit.pressed.connect(_on_quit)
	column.add_child(quit)

	_hint = _make_hint("Esc — продолжить")
	_hint.visible = false
	column.add_child(_hint)


func _make_title(text: String) -> Label:
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = text
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 1.0))
	return title


func _make_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap


func _make_hint(text: String) -> Label:
	var hint := Label.new()
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(280, 0)
	hint.text = text
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9, 0.85))
	return hint


func _make_button(text: String, size: Vector2 = Vector2(280, 52)) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_color", Color(0.94, 0.95, 1.0))
	button.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.58, 0.68))
	button.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.18, 0.32)))
	button.add_theme_stylebox_override("hover", _button_style(Color(0.22, 0.3, 0.5)))
	button.add_theme_stylebox_override("pressed", _button_style(Color(0.1, 0.13, 0.24)))
	button.add_theme_stylebox_override("focus", _button_style(Color(0.22, 0.3, 0.5)))
	button.add_theme_stylebox_override("disabled", _button_style(Color(0.08, 0.09, 0.14)))
	return button


func _button_style(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(6)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box
