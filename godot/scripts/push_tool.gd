class_name PushTool
extends Node

## ЛКМ готовит толчок только на опоре. ПКМ сбрасывает заряд. В пустоте мышь не толкает.


func _unhandled_input(event: InputEvent) -> void:
	var host := get_parent() as Wanderer
	if host == null or not host.accepts_input() or host.dock.inside:
		return
	if event.is_action(&"aim"):
		if host.dock.docked and event.is_action_released(&"aim"):
			host.cancel_push_charge()
		if host.dock.docked:
			_mark_handled()
		return
	if not event.is_action(&"push") or not host.dock.docked:
		return
	if event.is_action_pressed(&"push"):
		host.begin_push()
		_mark_handled()
	elif event.is_action_released(&"push") and host.is_push_charging():
		host.release_push()
		_mark_handled()


func _mark_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
