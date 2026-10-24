extends "res://tests/scene_check.gd"

## Посадка на старте звучит в шлеме. Гибель от кислорода гасит фон.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := await boot(4)
	if scene == null:
		return
	var wanderer: Wanderer = scene.get_node("Wanderer")
	var suit := wanderer.get_node("SuitAudio") as SuitAudio
	if suit.last_cue != "dock":
		fail("Старт не дал посадку, cue=%s" % suit.last_cue)
		return
	if not suit.bed_on:
		fail("Фон шлема не запрошен")
		return
	var air := wanderer.get_node("Oxygen") as Oxygen
	air.seconds = 0.0
	air.tick(0.1, 0.0)
	if suit.last_cue != "death":
		fail("Гибель без звука, cue=%s" % suit.last_cue)
		return
	if suit.bed_on:
		fail("Фон шлема не погас")
		return
	print("AUDIO_OK")
	quit(0)
