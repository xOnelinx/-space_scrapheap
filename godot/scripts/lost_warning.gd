class_name LostWarning
extends CanvasLayer

## В полёте без будущего касания тел растёт таймер гибели — экран темнеет к красному.

var _root: Control
var _dim: ColorRect
var _progress := 0.0


func _ready() -> void:
	add_to_group("lost_warning")
	layer = 90
	_build()
	_apply(0.0)


func show_progress(progress: float) -> void:
	_progress = progress
	_apply(progress)


func _process(_delta: float) -> void:
	_apply(_progress)


func is_shown() -> bool:
	return _root != null and _root.visible


func _apply(progress: float) -> void:
	var shown := progress > 0.001
	_root.visible = shown
	if not shown:
		return
	var t := clampf(progress, 0.0, 1.0)
	_dim.color = Color(0.12, 0.02, 0.04, lerpf(0.0, 0.38, t))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_dim = ColorRect.new()
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_dim)
