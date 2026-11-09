class_name Sfx
extends Node

## Reproductor global de efectos. Vive en el grupo "sfx" y cualquier script lo alcanza
## con get_tree().get_first_node_in_group("sfx"): en los tests headless no hay nodo y
## todas las llamadas quedan en null, asi que el combate funciona igual sin sonido.
##
## Los efectos con posicion (at != Vector3.ZERO) atenuan con la distancia al jugador y se
## descartan pasado el oido maximo: un bandido que ataca a 60 m no gasta un reproductor.

const POOL_SIZE := 8
const MAX_HEAR_DISTANCE := 45.0
const MIN_DISTANCE := 4.0
const DISTANCE_FALLOFF_DB := 0.55
const WIND_NIGHT_DB := -15.0
const WIND_DAY_DB := -26.0

var _players: Array[AudioStreamPlayer] = []
var _wind: AudioStreamPlayer
var _player_ref: Node3D


func _ready() -> void:
	add_to_group("sfx")
	for i in POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Player%d" % i
		add_child(player)
		_players.append(player)
	_wind = AudioStreamPlayer.new()
	_wind.name = "Wind"
	_wind.stream = SfxBank.get_stream("wind")
	_wind.volume_db = -80.0
	add_child(_wind)
	_wind.play()


func bind_player(node: Node3D) -> void:
	_player_ref = node


## Devuelve true si el efecto sono de verdad; false si quedo fuera de oido o no habia
## reproductor libre. Asi el test puede comprobar la puerta de distancia sin oir nada.
func play(name: String, at: Vector3 = Vector3.ZERO, volume_db: float = 0.0) -> bool:
	var db := volume_db
	if at != Vector3.ZERO:
		if _player_ref == null or not is_instance_valid(_player_ref):
			return false
		var distance := at.distance_to(_player_ref.global_position)
		if distance > MAX_HEAR_DISTANCE:
			return false
		db -= clampf((distance - MIN_DISTANCE) * DISTANCE_FALLOFF_DB, 0.0, 40.0)
	var player := _free_player()
	if player == null:
		return false
	player.stream = SfxBank.get_stream(name)
	player.volume_db = db
	player.pitch_scale = randf_range(0.95, 1.06)
	player.play()
	return true


func play_local(name: String, volume_db: float = 0.0) -> bool:
	return play(name, Vector3.ZERO, volume_db)


## day_amount 1 es pleno dia y 0 noche cerrada: de noche el viento sube de volumen.
func set_ambience(day_amount: float) -> void:
	if _wind != null:
		_wind.volume_db = lerpf(WIND_NIGHT_DB, WIND_DAY_DB, clampf(day_amount, 0.0, 1.0))


func wind_volume_db() -> float:
	return _wind.volume_db if _wind != null else -80.0


func playing_count() -> int:
	var count := 0
	for player in _players:
		if player.playing:
			count += 1
	return count


func assigned_streams() -> int:
	var count := 0
	for player in _players:
		if player.stream != null:
			count += 1
	return count


func _free_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			return player
	return _players[0] if not _players.is_empty() else null
