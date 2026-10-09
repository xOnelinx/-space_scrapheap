class_name HarpoonTool
extends Node

## E стреляет или, пока зажата, втягивает. Q снимает трос.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	var host := get_parent() as Wanderer
	if host == null or not host.accepts_input():
		return
	if event.is_action_pressed(&"harpoon"):
		host.cast_harpoon()
		_mark_handled()
	elif event.is_action_pressed(&"release_tether"):
		host.release_tether()
		_mark_handled()


func _mark_handled() -> void:
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
