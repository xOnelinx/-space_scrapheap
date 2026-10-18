extends "res://tests/scene_check.gd"

## Пробоина удваивает дыхание, бьёт видимой струёй из места удара. X тратит моток и латает одну.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot()
	if scene == null:
		return
	var wanderer := scene.get_node("Wanderer") as Wanderer
	var air := wanderer.get_node("Oxygen") as Oxygen
	wanderer._controls_locked = false
	air.open = true
	air.double_left = 0.0

	var hit := wanderer.global_position + Vector2(30.0, 0.0)
	wanderer.puncture_at(hit)
	air.seconds = 100.0
	air.tick(1.0, 0.0)
	if absf(air.seconds - 98.0) > 0.01:
		fail("Пробоина должна удваивать расход: %.2f" % air.seconds)
		return
	wanderer._publish_views()
	var jets := wanderer._leak_jets
	if jets.size() != 1 or jets[0].direction().distance_to(Vector2.RIGHT) > 0.01:
		fail("Струя должна бить из места удара")
		return

	air.tape = 1
	_press_patch(wanderer)
	if not air.holes.is_empty() or air.tape != 0:
		fail("X не залатал: пробоин %d, изоленты %d" % [air.holes.size(), air.tape])
		return
	wanderer._publish_views()
	if not wanderer._leak_jets.is_empty():
		fail("Заплатка не убрала струю")
		return

	wanderer.puncture_at(hit)
	_press_patch(wanderer)
	if air.holes.size() != 1:
		fail("Без изоленты пробоина не латается")
		return

	print("SUIT_OK")
	quit(0)


func _press_patch(wanderer: Wanderer) -> void:
	var event := InputEventAction.new()
	event.action = &"patch_suit"
	event.pressed = true
	wanderer._unhandled_input(event)
