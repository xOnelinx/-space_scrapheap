class_name GunTool
extends Node

## ЛКМ стреляет к курсору. Один выстрел на нажатие.


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"shoot"):
		return
	var host := get_parent() as Wanderer
	if host == null or not host.accepts_input():
		return
	host.fire_gun()
	var viewport := get_viewport()
	if viewport != null:
		viewport.set_input_as_handled()
