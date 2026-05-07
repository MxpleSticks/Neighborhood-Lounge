extends RefCounted

const WINDY_WEATHER_ID: String = "windy"
const RAIN_WEATHER_ID: String = "rain"

const NORMAL_DAY_WEATHER_ID: String = "normal"

const WIND_AUDIO_NODE_PATH: NodePath = ^"Wind"
const RAIN_NODE_PATH: NodePath = ^"Weather/Rain"
const RAIN_SOUND_NODE_PATHS: Array[NodePath] = [
	^"Weather/RainSound",
	^"Weather/RainSound2",
	^"Weather/RainSound3",
	^"Weather/RainSound4",
]
const WORLD_ENVIRONMENT_NODE_PATH: NodePath = ^"WorldEnvironment"

const NORMAL_WIND_VOLUME_DB: float = -1.0
const WINDY_WIND_VOLUME_DB: float = 7.0
const RAIN_SOUND_VOLUME_DB: float = -9.0
const MUTED_DB: float = -80.0
const RAIN_VISUAL_FADE_SEC: float = 1.5
const RAIN_AUDIO_FADE_SEC: float = 1.5

var weather_patterns: Array[String] = [
	NORMAL_DAY_WEATHER_ID,
	WINDY_WEATHER_ID,
	RAIN_WEATHER_ID,
]

var _last_weather_id: String = ""
var _active_weather_id: String = ""
var _weather_enabled: bool = true
var _weather_sound_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _rain_audio_schedule_gen: int = 0
var _rain_effects_active: bool = false

var _rain_vfx_tween: Tween
var _rain_audio_tween: Tween
var _rain_transition_tween: Tween


func setup(world_root: Node) -> void:
	_rng.randomize()
	_active_weather_id = ""
	_apply_weather("", world_root)


func run_for_day(_day_number: int, world_root: Node) -> void:
	_active_weather_id = _choose_weather()
	if _weather_enabled:
		_apply_weather(_active_weather_id, world_root)
	else:
		_apply_weather("", world_root)
	_last_weather_id = _active_weather_id


func set_weather_enabled(is_enabled: bool, world_root: Node) -> void:
	_weather_enabled = is_enabled
	if _weather_enabled:
		_apply_weather(_active_weather_id, world_root)
	else:
		_apply_weather("", world_root)


func set_weather_sound_enabled(is_enabled: bool, world_root: Node) -> void:
	_weather_sound_enabled = is_enabled
	if not _weather_enabled:
		return
	_sync_active_weather_audio(world_root)


func _choose_weather() -> String:
	if weather_patterns.is_empty():
		return ""

	var candidate_weather_id: String = weather_patterns[_rng.randi_range(0, weather_patterns.size() - 1)]

	if candidate_weather_id == _last_weather_id:
		return ""
	return candidate_weather_id


func _apply_weather(weather_id: String, world_root: Node) -> void:
	_invalidate_rain_audio_schedule()
	_kill_all_rain_tweens()

	var want_rain: bool = weather_id == RAIN_WEATHER_ID and _weather_enabled

	match weather_id:
		WINDY_WEATHER_ID:
			_set_wind_volume(world_root, _wind_volume_for(WINDY_WEATHER_ID))
		RAIN_WEATHER_ID:
			_set_wind_volume(world_root, _wind_volume_for(RAIN_WEATHER_ID))
		_:
			_set_wind_volume(world_root, _wind_volume_for(""))

	if want_rain:
		_rain_effects_active = true
		_set_fog(world_root, true)
		_rain_vfx_fade_in(world_root)
		_schedule_rain_audio(world_root)
	else:
		if _rain_effects_active:
			_rain_transition_fade_out(world_root)
		else:
			_finalize_rain_cleared(world_root)


func _wind_volume_for(weather_id: String) -> float:
	if not _weather_sound_enabled:
		return NORMAL_WIND_VOLUME_DB
	if weather_id == WINDY_WEATHER_ID:
		return WINDY_WIND_VOLUME_DB
	return NORMAL_WIND_VOLUME_DB


func _sync_active_weather_audio(world_root: Node) -> void:
	match _active_weather_id:
		WINDY_WEATHER_ID:
			_set_wind_volume(world_root, _wind_volume_for(WINDY_WEATHER_ID))
			_kill_rain_audio_tween()
			_hard_stop_rain_audio(world_root)
		RAIN_WEATHER_ID:
			_set_wind_volume(world_root, _wind_volume_for(RAIN_WEATHER_ID))
			if _weather_sound_enabled:
				_rain_audio_fade_in(world_root)
			else:
				_fade_out_rain_audio_only(world_root)
		_:
			_set_wind_volume(world_root, NORMAL_WIND_VOLUME_DB)
			_kill_rain_audio_tween()
			_hard_stop_rain_audio(world_root)


func _set_wind_volume(world_root: Node, volume_db: float) -> void:
	var wind_player := world_root.get_node_or_null(WIND_AUDIO_NODE_PATH)
	if wind_player and wind_player is AudioStreamPlayer:
		(wind_player as AudioStreamPlayer).volume_db = volume_db


func _get_rain_particles(world_root: Node) -> GPUParticles3D:
	var node := world_root.get_node_or_null(RAIN_NODE_PATH)
	if node is GPUParticles3D:
		return node as GPUParticles3D
	return null


func _set_fog(world_root: Node, is_active: bool) -> void:
	var world_env := world_root.get_node_or_null(WORLD_ENVIRONMENT_NODE_PATH)
	if world_env and world_env is WorldEnvironment:
		var env := (world_env as WorldEnvironment).environment
		if env:
			env.volumetric_fog_enabled = false
			env.fog_enabled = is_active


func _invalidate_rain_audio_schedule() -> void:
	_rain_audio_schedule_gen += 1


func _kill_all_rain_tweens() -> void:
	_kill_rain_vfx_tween()
	_kill_rain_audio_tween()
	_kill_rain_transition_tween()


func _kill_rain_vfx_tween() -> void:
	if _rain_vfx_tween != null and is_instance_valid(_rain_vfx_tween):
		_rain_vfx_tween.kill()
	_rain_vfx_tween = null


func _kill_rain_audio_tween() -> void:
	if _rain_audio_tween != null and is_instance_valid(_rain_audio_tween):
		_rain_audio_tween.kill()
	_rain_audio_tween = null


func _kill_rain_transition_tween() -> void:
	if _rain_transition_tween != null and is_instance_valid(_rain_transition_tween):
		_rain_transition_tween.kill()
	_rain_transition_tween = null


func _schedule_rain_audio(world_root: Node) -> void:
	if not _weather_sound_enabled:
		return
	if not _weather_enabled or _active_weather_id != RAIN_WEATHER_ID:
		return
	_rain_audio_fade_in(world_root)


func _rain_vfx_fade_in(world_root: Node) -> void:
	var particles := _get_rain_particles(world_root)
	if particles == null:
		return
	_kill_rain_vfx_tween()
	particles.visible = true
	particles.amount_ratio = 0.0
	var tw: Tween = world_root.create_tween()
	_rain_vfx_tween = tw
	tw.tween_property(particles, "amount_ratio", 1.0, RAIN_VISUAL_FADE_SEC)


func _rain_audio_fade_in(world_root: Node) -> void:
	if not _weather_sound_enabled:
		return
	if _active_weather_id != RAIN_WEATHER_ID or not _weather_enabled:
		return
	_kill_rain_audio_tween()
	var tw: Tween = world_root.create_tween()
	tw.set_parallel(true)
	_rain_audio_tween = tw
	for sound_path in RAIN_SOUND_NODE_PATHS:
		var player := world_root.get_node_or_null(sound_path)
		if player is AudioStreamPlayer3D:
			var asp3d := player as AudioStreamPlayer3D
			asp3d.volume_db = MUTED_DB
			if not asp3d.playing:
				asp3d.play()
			tw.tween_property(asp3d, "volume_db", RAIN_SOUND_VOLUME_DB, RAIN_AUDIO_FADE_SEC)


func _fade_out_rain_audio_only(world_root: Node) -> void:
	_kill_rain_audio_tween()
	var tw: Tween = world_root.create_tween()
	tw.set_parallel(true)
	_rain_audio_tween = tw
	for sound_path in RAIN_SOUND_NODE_PATHS:
		var player := world_root.get_node_or_null(sound_path)
		if player is AudioStreamPlayer3D:
			var asp3d := player as AudioStreamPlayer3D
			tw.tween_property(asp3d, "volume_db", MUTED_DB, RAIN_AUDIO_FADE_SEC * 0.5)
	tw.finished.connect(func () -> void:
		_hard_stop_rain_audio(world_root)
		_rain_audio_tween = null
	)


func _rain_transition_fade_out(world_root: Node) -> void:
	_kill_rain_vfx_tween()
	_kill_rain_audio_tween()
	_kill_rain_transition_tween()

	var particles := _get_rain_particles(world_root)
	var rain_players: Array[AudioStreamPlayer3D] = []
	for sound_path in RAIN_SOUND_NODE_PATHS:
		var player := world_root.get_node_or_null(sound_path)
		if player is AudioStreamPlayer3D:
			rain_players.append(player as AudioStreamPlayer3D)

	var start_ratio: float = particles.amount_ratio if particles != null else 0.0
	var start_volumes: Array[float] = []
	for asp3d in rain_players:
		start_volumes.append(asp3d.volume_db)

	var tw: Tween = world_root.create_tween()
	tw.set_trans(Tween.TRANS_QUAD)
	tw.set_ease(Tween.EASE_IN)
	_rain_transition_tween = tw
	var out_duration: float = maxf(RAIN_VISUAL_FADE_SEC, RAIN_AUDIO_FADE_SEC)
	tw.tween_method(
		_rain_transition_step.bind(particles, rain_players, start_ratio, start_volumes),
		0.0,
		1.0,
		out_duration
	)
	tw.finished.connect(func () -> void:
		_rain_transition_tween = null
		_rain_effects_active = false
		_finalize_rain_cleared(world_root)
	)


func _rain_transition_step(
	particles: Variant,
	rain_players: Array[AudioStreamPlayer3D],
	start_ratio: float,
	start_volumes: Array[float],
	weight: float
) -> void:
	var u: float = clampf(weight, 0.0, 1.0)
	if particles is GPUParticles3D:
		(particles as GPUParticles3D).amount_ratio = lerpf(start_ratio, 0.0, u)
	for i in range(rain_players.size()):
		rain_players[i].volume_db = lerpf(start_volumes[i], MUTED_DB, u)


func _hard_stop_rain_audio(world_root: Node) -> void:
	for sound_path in RAIN_SOUND_NODE_PATHS:
		var player := world_root.get_node_or_null(sound_path)
		if player is AudioStreamPlayer3D:
			var asp3d := player as AudioStreamPlayer3D
			asp3d.stop()
			asp3d.volume_db = RAIN_SOUND_VOLUME_DB


func _finalize_rain_cleared(world_root: Node) -> void:
	var particles := _get_rain_particles(world_root)
	if particles != null:
		particles.amount_ratio = 1.0
		particles.visible = false
	_hard_stop_rain_audio(world_root)
	_set_fog(world_root, false)
