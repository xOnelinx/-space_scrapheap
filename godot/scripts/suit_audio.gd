class_name SuitAudio
extends Node

## Звук шлема. Мир молчит: плееры не в пространстве, только то, что слышно в скафандре.

const VOL_HIT := 0.55
const VOL_BED := 0.12
const VOL_JET := 0.4
const VOL_BREATH := 0.22
const VOL_LEAK := 0.3

const PUSH := preload("res://assets/sfx/forceField_000.ogg")
const DOCK := preload("res://assets/sfx/impactMetal_000.ogg")
const SHOT := preload("res://assets/sfx/lowFrequency_explosion_001.ogg")
const HIT := preload("res://assets/sfx/impactMetal_003.ogg")
const CANISTER := preload("res://assets/sfx/forceField_002.ogg")
const DEATH := preload("res://assets/sfx/lowFrequency_explosion_000.ogg")
const JET := preload("res://assets/sfx/thrusterFire_000.ogg")
## shortcut: нет записи дыхания, заменить файлом, когда будет
const BREATH := preload("res://assets/sfx/spaceEngineSmall_000.ogg")
const LEAK := preload("res://assets/sfx/spaceEngineLow_002.ogg")
const BED := preload("res://assets/sfx/computerNoise_000.ogg")

var last_cue := ""
var bed_on := false

var _silent := false
var _oneshot: AudioStreamPlayer
var _bed: AudioStreamPlayer
var _jet: AudioStreamPlayer
var _breath: AudioStreamPlayer
var _leak: AudioStreamPlayer


func _ready() -> void:
	_oneshot = _add_player(VOL_HIT)
	_bed = _add_loop(BED, VOL_BED)
	_jet = _add_loop(JET, VOL_JET)
	_breath = _add_loop(BREATH, VOL_BREATH)
	_leak = _add_loop(LEAK, VOL_LEAK)
	bed_on = true
	_bed.play()


func play_push() -> void:
	_play(PUSH, "push")


func play_dock() -> void:
	_play(DOCK, "dock")


func play_shot() -> void:
	_play(SHOT, "shot")


func play_hit() -> void:
	_play(HIT, "hit")


func play_canister() -> void:
	_play(CANISTER, "canister")


func play_death() -> void:
	_silent = true
	bed_on = false
	_bed.stop()
	_jet.stop()
	_breath.stop()
	_leak.stop()
	_play(DEATH, "death")


func sync(jet: bool, breath: bool, leak: bool) -> void:
	if _silent:
		return
	_set_loop(_jet, jet)
	_set_loop(_breath, breath)
	_set_loop(_leak, leak)


func _play(stream: AudioStream, cue: String) -> void:
	if _silent and cue != "death":
		return
	last_cue = cue
	_oneshot.stream = stream
	_oneshot.play()


func _set_loop(player: AudioStreamPlayer, on: bool) -> void:
	if on == player.playing:
		return
	if on:
		player.play()
	else:
		player.stop()


func _add_player(volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.volume_db = linear_to_db(volume)
	add_child(player)
	return player


func _add_loop(stream: AudioStreamOggVorbis, volume: float) -> AudioStreamPlayer:
	var copy := stream.duplicate() as AudioStreamOggVorbis
	copy.loop = true
	var player := _add_player(volume)
	player.stream = copy
	return player
