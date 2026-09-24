extends Node2D

## Звёзды в мировых координатах: дрейф влево + wrap вокруг вида камеры.

const STAR_COUNT := 200
const SPEED_PX := 30.0
const MARGIN := 40.0

@export var star_texture: Texture2D


func _ready() -> void:
	if star_texture == null:
		push_error("StarField: не задана текстура звезды")
		return
	var view := get_viewport_rect().size
	for i in STAR_COUNT:
		var star := Sprite2D.new()
		star.texture = star_texture
		star.centered = false
		star.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		star.position = Vector2(randf() * view.x, randf() * view.y)
		add_child(star)


func _process(delta: float) -> void:
	var view := get_viewport_rect().size
	var cam := get_viewport().get_camera_2d()
	var center := view * 0.5
	if cam != null:
		center = cam.get_screen_center_position()

	var half := view * 0.5
	var min_p := center - half - Vector2(MARGIN, MARGIN)
	var max_p := center + half + Vector2(MARGIN, MARGIN)
	var span := max_p - min_p

	for star in get_children():
		star.position.x -= SPEED_PX * delta
		if star.position.x < min_p.x:
			star.position.x += span.x
			star.position.y = min_p.y + randf() * span.y
		elif star.position.x > max_p.x:
			star.position.x -= span.x
		if star.position.y < min_p.y:
			star.position.y += span.y
		elif star.position.y > max_p.y:
			star.position.y -= span.y
