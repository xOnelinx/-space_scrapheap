extends Sprite2D

## Фон заливает вид камеры: мир открытый, картинка не уезжает.


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	global_position = cam.get_screen_center_position() - get_viewport_rect().size * 0.5
