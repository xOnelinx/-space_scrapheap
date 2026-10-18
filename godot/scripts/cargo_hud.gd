extends CanvasLayer

## Значок груза справа сверху: сколько груз прибавил к своей массе скитальца, в процентах.

const ICON := preload("res://assets/cargo.png")
const COLOR := Color(0.82, 0.84, 0.9)
const MARGIN := Vector2(20, 14)

var _shown := -1
var _label: Label

@onready var _host := get_parent() as Wanderer


func _ready() -> void:
	layer = 40
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.offset_left = -MARGIN.x
	row.offset_right = -MARGIN.x
	row.offset_top = MARGIN.y
	row.add_theme_constant_override("separation", 12)
	add_child(row)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 48)
	_label.add_theme_color_override("font_color", COLOR)
	row.add_child(_label)

	var icon := TextureRect.new()
	icon.texture = ICON
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(60, 60)
	row.add_child(icon)
	_refresh()


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	var extra := roundi((_host.get_mass() / Wanderer.MASS - 1.0) * 100.0)
	if extra != _shown:
		_shown = extra
		_label.text = "+%d%%" % extra
