class_name Oxygen
extends Node

## Запас воздуха на скафандре. Чем платить за толчок и правку курса, решает тот, кто зовёт tick.
## Пока open == false, баллон не забирается: ввод закрыт или скиталец уже погиб.

signal depleted
signal changed(seconds: float)

const CAPACITY := 1800.0
const START := 200.0
const DOUBLE_PER_HOLD := 5.0
const COLOR_IDLE := Color(0.4, 0.78, 1.0)
const COLOR_DOUBLE := Color(1.0, 0.62, 0.28)
const FLASH_TIME := 0.45

var seconds := START
var double_left := 0.0
var open := false

var _flash := 0.0
var _empty := false
var _label: Label


func _ready() -> void:
	add_to_group("oxygen")
	_build_hud()


func grant(amount: float) -> bool:
	## Полный запас не забирает баллон: касание впустую его не съедает.
	if not open or _empty or amount <= 0.0:
		return false
	var room := CAPACITY - seconds
	if room < 1.0:
		return false
	seconds += minf(amount, room)
	_flash = FLASH_TIME
	_refresh()
	changed.emit(seconds)
	return true


func note_hold(hold_seconds: float) -> void:
	if hold_seconds <= 0.0:
		return
	double_left += hold_seconds * DOUBLE_PER_HOLD


func tick(delta: float, extra_rate: float) -> bool:
	if _empty:
		return true
	var rate := 1.0
	if double_left > 0.0:
		rate = 2.0
		double_left = maxf(0.0, double_left - delta)
	if extra_rate > 0.0:
		rate += extra_rate
	seconds = maxf(0.0, seconds - delta * rate)
	_refresh()
	_tick_flash(delta)
	changed.emit(seconds)
	if seconds > 0.0:
		return false
	_empty = true
	open = false
	depleted.emit()
	return true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.name = "OxygenHud"
	add_child(layer)

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.position = Vector2(20, 14)
	_label.add_theme_font_size_override("font_size", 48)
	_label.add_theme_color_override("font_color", COLOR_IDLE)
	layer.add_child(_label)
	_refresh()


func _tick_flash(delta: float) -> void:
	if _label == null:
		return
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
		var t := clampf(_flash / FLASH_TIME, 0.0, 1.0)
		_label.add_theme_color_override("font_color", COLOR_IDLE.lerp(Color(0.9, 0.97, 1.0), t))
	elif double_left > 0.0:
		_label.add_theme_color_override("font_color", COLOR_DOUBLE)
	else:
		_label.add_theme_color_override("font_color", COLOR_IDLE)


func _refresh() -> void:
	if _label == null:
		return
	var shown := 0 if seconds <= 0.0 else ceili(seconds)
	_label.text = str(shown)
