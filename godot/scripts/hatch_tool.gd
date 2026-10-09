class_name HatchTool
extends Node

## F открывает и закрывает люк корпуса.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var host := get_parent() as Wanderer
	if host == null or not host.accepts_input():
		return
	if not event.is_action_pressed(&"hatch"):
		return
	host.toggle_hatch()
	_mark_handled()


func _mark_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
