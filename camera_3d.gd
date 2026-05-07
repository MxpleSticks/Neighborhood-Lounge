extends Camera3D


const SETTINGS_PATH: String = "user://main_menu_settings.cfg"
const SETTINGS_SECTION_AUDIO: String = "audio"
const SETTINGS_SECTION_UI: String = "ui"
const SETTINGS_KEY_SHOW_BEER_TRACKER: String = "show_beer_tracker"
const SETTINGS_SECTION_STATS: String = "stats"
const SETTINGS_KEY_BEER_SIP_COUNT: String = "beer_sip_count"
const SETTINGS_KEY_DRINK_SFX_VOLUME: String = "drink_sfx_volume"
const MUTED_DB: float = -80.0

var max_pitch_up : float = 60.0
var max_pitch_down : float = 50.0
var max_yaw : float = 60.0
var sensitivity : float = 0.06
var smoothing : float = 12.0
var breathe_speed : float = 0.3
var breathe_amount : float = 0.004
var sway_amount : float = 0.0015

const ZOOM_IN_FOV_DELTA: float = 25.0
const ZOOM_FOV_SMOOTHING: float = 12.0

@export var bottle_hold_offset : Vector3 = Vector3(0.0, -0.1, -0.4)

@export var bottle_hold_rotation_degrees : Vector3 = Vector3(65.0, 0.0, 0.0)

var _pitch : float = 0.0
var _yaw : float = 0.0
var _smooth_pitch : float = 0.0
var _smooth_yaw : float = 0.0
var _breathe_time : float = 0.0
var _origin : Vector3
var _origin_yaw : float = 0.0
var _default_fov: float = 75.0
var _is_zooming_in: bool = false

var is_drinking : bool = false
var hovered_bottle : Node3D = null
var hovered_radio : Node3D = null
var _held_bottle : Node3D = null
var _held_bottle_scale : Vector3 = Vector3.ONE
var _sip_count: int = 0
var _show_beer_tracker_ui: bool = true
var _drink_sfx_volume_linear: float = 1.0

@onready var raycast = $RayCast3D
@onready var drink_sound = $DrinkSound
@onready var hover_ui = get_node_or_null("../CanvasLayer/ColorRect/Hover")
@onready var hand_anim = get_node_or_null("../CanvasLayer/ColorRect/AnimatedSprite2D")
@onready var radio_playlist_ui = get_node_or_null("../CanvasLayer/RadioPlaylistUI")
@onready var pause_menu_ui = get_node_or_null("../CanvasLayer/PauseMenu")
@onready var beer_tracker_ui = get_node_or_null("../CanvasLayer/BeerTrackerUI")
@onready var beer_counter_label = get_node_or_null("../CanvasLayer/BeerTrackerUI/BeerCounterLabel")

func _ready() -> void:
	_origin = position
	_pitch = rotation_degrees.x
	_yaw = rotation_degrees.y
	_smooth_pitch = _pitch
	_smooth_yaw = _yaw
	_origin_yaw = _yaw
	_default_fov = fov
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

	print("--- Script Initialized ---")
	if raycast == null: print("ERROR: RayCast3D not found!")
	if hover_ui == null: print("ERROR: Hover UI not found! Check path.")
	if hand_anim == null: print("ERROR: Hand Animation not found! Check path.")
	if radio_playlist_ui == null: print("ERROR: Radio Playlist UI not found! Check path.")
	if pause_menu_ui == null: print("ERROR: Pause Menu UI not found! Check path.")
	if beer_tracker_ui == null: print("ERROR: Beer Tracker UI not found! Check path.")
	if beer_counter_label == null: print("ERROR: Beer Counter Label not found! Check path.")

	if hover_ui: hover_ui.visible = false
	_update_hand_ui_center()
	_load_ui_settings()
	_update_beer_counter_label()
	_apply_beer_tracker_visibility()
	_apply_drink_sfx_volume()
	if radio_playlist_ui and radio_playlist_ui.has_signal("menu_closed"):
		radio_playlist_ui.menu_closed.connect(_on_radio_menu_closed)
	if pause_menu_ui and pause_menu_ui.has_signal("menu_closed"):
		pause_menu_ui.menu_closed.connect(_on_pause_menu_closed)
	if pause_menu_ui and pause_menu_ui.has_signal("beer_tracker_visibility_changed"):
		pause_menu_ui.beer_tracker_visibility_changed.connect(_on_beer_tracker_visibility_changed)
		if pause_menu_ui.has_method("is_beer_tracker_ui_enabled"):
			_on_beer_tracker_visibility_changed(pause_menu_ui.call("is_beer_tracker_ui_enabled"))
	if pause_menu_ui and pause_menu_ui.has_signal("drink_sfx_volume_changed"):
		pause_menu_ui.drink_sfx_volume_changed.connect(_on_drink_sfx_volume_changed)
		if pause_menu_ui.has_method("get_drink_sfx_volume_linear"):
			_on_drink_sfx_volume_changed(pause_menu_ui.call("get_drink_sfx_volume_linear"))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_is_zooming_in = event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if _is_pause_menu_open():
		if event.is_action_pressed("ui_cancel"):
			pause_menu_ui.call("close_menu")
		return

	if _is_radio_menu_open():
		if event.is_action_pressed("ui_cancel"):
			radio_playlist_ui.call("close_menu")
		return

	if event.is_action_pressed("ui_cancel"):
		_open_pause_menu()
		return

	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseMotion:
		_pitch -= event.relative.y * sensitivity
		_yaw -= event.relative.x * sensitivity
		_pitch = clamp(_pitch, -max_pitch_down, max_pitch_up)
		_yaw = clamp(_yaw, _origin_yaw - max_yaw, _origin_yaw + max_yaw)

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if hovered_bottle != null and not is_drinking:
			print("Clicked the bottle! Starting sequence...")
			_drink_sequence(hovered_bottle)
		elif hovered_radio != null and not is_drinking:
			_on_radio_pressed(hovered_radio)

func _process(delta: float) -> void:
	if _is_pause_menu_open() or _is_radio_menu_open():
		_is_zooming_in = false

	_update_hand_ui_center()
	_update_look(delta)
	_update_zoom(delta)
	_update_breathe(delta)
	_update_held_bottle()
	_handle_raycast()

func _update_hand_ui_center() -> void:
	var center := get_viewport().get_visible_rect().size * 0.5
	if hover_ui:
		hover_ui.position = center
	if hand_anim:
		hand_anim.position = center

func _update_look(delta: float) -> void:
	var t : float = clamp(smoothing * delta, 0.0, 1.0)
	_smooth_pitch = lerp(_smooth_pitch, _pitch, t)
	_smooth_yaw = lerp(_smooth_yaw, _yaw, t)
	rotation_degrees = Vector3(_smooth_pitch, _smooth_yaw, 0.0)

func _update_zoom(delta: float) -> void:
	var target_fov: float = _default_fov - ZOOM_IN_FOV_DELTA if _is_zooming_in else _default_fov
	var t: float = clamp(ZOOM_FOV_SMOOTHING * delta, 0.0, 1.0)
	fov = lerp(fov, target_fov, t)

func _update_breathe(delta: float) -> void:
	_breathe_time += delta * breathe_speed * TAU
	var bob_y : float = sin(_breathe_time) * breathe_amount
	var bob_x : float = sin(_breathe_time * 0.5) * sway_amount
	position = _origin + Vector3(bob_x, bob_y, 0.0)

func _update_held_bottle() -> void:
	if _held_bottle == null:
		return
	var hold_pos := to_global(bottle_hold_offset)

	var hold_rot_offset := Basis.from_euler(Vector3(
		deg_to_rad(bottle_hold_rotation_degrees.x),
		deg_to_rad(bottle_hold_rotation_degrees.y),
		deg_to_rad(bottle_hold_rotation_degrees.z)
	))
	var hold_basis := (global_transform.basis * hold_rot_offset).orthonormalized().scaled(_held_bottle_scale)
	_held_bottle.global_transform = Transform3D(hold_basis, hold_pos)

func _handle_raycast() -> void:
	if _is_pause_menu_open() or _is_radio_menu_open():
		hovered_bottle = null
		hovered_radio = null
		if hover_ui:
			hover_ui.visible = false
		return

	if is_drinking:
		return

	hovered_bottle = null
	hovered_radio = null

	if raycast.is_colliding():
		var collider = raycast.get_collider()

		var interact_node: Node = collider
		while interact_node:
			if interact_node.is_in_group("bottle") and interact_node is Node3D:
				hovered_bottle = interact_node as Node3D
				if hover_ui:
					hover_ui.visible = true
				return
			if interact_node.is_in_group("radio") and interact_node is Node3D:
				hovered_radio = interact_node as Node3D
				if hover_ui:
					hover_ui.visible = true
				return
			interact_node = interact_node.get_parent()

	if hover_ui:
		hover_ui.visible = false

func _on_radio_pressed(radio: Node3D) -> void:
	if radio_playlist_ui and radio_playlist_ui.has_method("open_menu"):
		if hover_ui:
			hover_ui.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		radio_playlist_ui.call("open_menu")

func _drink_sequence(bottle: Node3D) -> void:
	is_drinking = true
	if hover_ui: hover_ui.visible = false


	if hand_anim:
		hand_anim.visible = true
		if hand_anim.sprite_frames and hand_anim.sprite_frames.has_animation("Grab"):
			hand_anim.sprite_frames.set_animation_loop("Grab", false)
		hand_anim.play("Grab")

	var original_transform = bottle.global_transform
	bottle.visible = true

	await get_tree().create_timer(0.4).timeout

	if hand_anim and hand_anim.visible:
		hand_anim.stop()
		hand_anim.visible = false

	_held_bottle = bottle
	_held_bottle_scale = bottle.global_basis.get_scale()
	_update_held_bottle()

	if drink_sound:
		drink_sound.play()
		await drink_sound.finished
	else:
		await get_tree().create_timer(1.0).timeout

	_held_bottle = null
	bottle.global_transform = original_transform

	_sip_count += 1
	_update_beer_counter_label()
	_save_beer_tracker_stats()

	is_drinking = false

func _load_ui_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_show_beer_tracker_ui = bool(config.get_value(SETTINGS_SECTION_UI, SETTINGS_KEY_SHOW_BEER_TRACKER, _show_beer_tracker_ui))
		_sip_count = max(int(config.get_value(SETTINGS_SECTION_STATS, SETTINGS_KEY_BEER_SIP_COUNT, _sip_count)), 0)
		_drink_sfx_volume_linear = float(config.get_value(SETTINGS_SECTION_AUDIO, SETTINGS_KEY_DRINK_SFX_VOLUME, _drink_sfx_volume_linear))
		if _drink_sfx_volume_linear > 1.0:
			_drink_sfx_volume_linear = clamp(_drink_sfx_volume_linear / 100.0, 0.0, 1.0)
	_drink_sfx_volume_linear = clamp(_drink_sfx_volume_linear, 0.0, 1.0)

func _save_beer_tracker_stats() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION_STATS, SETTINGS_KEY_BEER_SIP_COUNT, _sip_count)
	config.save(SETTINGS_PATH)

func _on_beer_tracker_visibility_changed(is_visible: bool) -> void:
	_show_beer_tracker_ui = is_visible
	_apply_beer_tracker_visibility()

func _apply_beer_tracker_visibility() -> void:
	if beer_tracker_ui:
		beer_tracker_ui.visible = _show_beer_tracker_ui

func _update_beer_counter_label() -> void:
	if beer_counter_label:
		beer_counter_label.text = str(_sip_count)

func _on_drink_sfx_volume_changed(linear_volume: float) -> void:
	_drink_sfx_volume_linear = clamp(linear_volume, 0.0, 1.0)
	_apply_drink_sfx_volume()

func _apply_drink_sfx_volume() -> void:
	if drink_sound == null:
		return
	if _drink_sfx_volume_linear <= 0.001:
		drink_sound.volume_db = MUTED_DB
		return
	drink_sound.volume_db = linear_to_db(_drink_sfx_volume_linear)

func _is_radio_menu_open() -> bool:
	if radio_playlist_ui == null:
		return false
	if not radio_playlist_ui.has_method("is_menu_open"):
		return false
	return radio_playlist_ui.call("is_menu_open")

func _is_pause_menu_open() -> bool:
	if pause_menu_ui == null:
		return false
	if not pause_menu_ui.has_method("is_menu_open"):
		return false
	return pause_menu_ui.call("is_menu_open")

func _open_pause_menu() -> void:
	if pause_menu_ui and pause_menu_ui.has_method("open_menu"):
		if hover_ui:
			hover_ui.visible = false
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		pause_menu_ui.call("open_menu")

func _on_radio_menu_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _on_pause_menu_closed() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
