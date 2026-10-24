extends Sprite2D

## Фон заливает вид камеры: мир открытый, картинка не уезжает.


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	## Текстура уже размером с экран. Крутить её с камерой достаточно, увеличивать не нужно:
	## иначе при входе в кусок фон прыгает и пиксели растут.
	var rotating := not cam.ignore_rotation
	centered = true
	scale = Vector2.ONE
	global_rotation = cam.global_rotation if rotating else 0.0
	global_position = cam.get_screen_center_position()
