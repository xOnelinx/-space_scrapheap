extends "res://tests/scene_check.gd"

## Пробоина удваивает дыхание и кренит толчок. X тратит моток и латает одну.


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

	air.seconds = 100.0
	air.punctures = 1
	air.tick(1.0, 0.0)
	if absf(air.seconds - 98.0) > 0.01:
		fail("Пробоина должна удваивать расход: %.2f" % air.seconds)
		return
	wanderer._breathe(0.0)
	if absf(wanderer.leak_bias - Wanderer.LEAK_PER_PUNCTURE) > 0.0001:
		fail("Пробоина не кренит толчок: %.3f" % wanderer.leak_bias)
		return

	air.tape = 1
	_press_patch(wanderer)
	if air.punctures != 0 or air.tape != 0:
		fail("X не залатал: пробоин %d, изоленты %d" % [air.punctures, air.tape])
		return
	wanderer._breathe(0.0)
	if wanderer.leak_bias != 0.0:
		fail("Заплатка не сняла крен")
		return

	air.puncture()
	_press_patch(wanderer)
	if air.punctures != 1:
		fail("Без изоленты пробоина не латается")
		return

	print("SUIT_OK")
	quit(0)


func _press_patch(wanderer: Wanderer) -> void:
	var event := InputEventAction.new()
	event.action = &"patch_suit"
	event.pressed = true
	wanderer._unhandled_input(event)
