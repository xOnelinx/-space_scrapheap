class_name LostWarning
extends CanvasLayer

## В полёте без будущего касания тел растёт таймер гибели — это его индикатор.

var _root: Control
var _dim: ColorRect
var _label: Label

@onready var _wanderer: Wanderer = $"../Wanderer"


func _ready() -> void:
	layer = 90
	_build()
	_apply(0.0)


func _process(_delta: float) -> void:
	if _wanderer == null:
		_apply(0.0)
		return
	_apply(_wanderer.lost_progress())


func is_shown() -> bool:
	return _root != null and _root.visible


func _apply(progress: float) -> void:
	var shown := progress > 0.001
	_root.visible = shown
	if not shown:
		return
	var remain := Wanderer.LOST_DOOM_DELAY * (1.0 - progress)
	_label.text = "Курс в пустоту\n%.1f" % remain
	var t := clampf(progress, 0.0, 1.0)
	_dim.color = Color(0.12, 0.02, 0.04, lerpf(0.0, 0.38, t))
	_label.add_theme_color_override(
			"font_color",
			Color(1.0, 0.86, 0.12).lerp(Color(0.95, 0.32, 0.28), t))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_label.anchor_left = 0.5
	_label.anchor_right = 0.5
	_label.offset_left = -220.0
	_label.offset_right = 220.0
	_label.offset_top = 28.0
	_label.offset_bottom = 120.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 28)
	_root.add_child(_label)
