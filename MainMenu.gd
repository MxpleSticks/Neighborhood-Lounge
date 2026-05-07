extends Control

const GAME_SCENE_PATH: String = "res://Main.tscn"
const SETTINGS_PATH: String = "user://main_menu_settings.cfg"
const SETTINGS_SECTION_AUDIO: String = "audio"
const MIN_VOLUME_LINEAR: float = 0.0
const MAX_VOLUME_LINEAR: float = 1.0
const MUTED_DB: float = -80.0

@onready var start_button: Button = $StartButton
@onready var options_button: Button = $OptionsButton
@onready var quit_button: Button = $QuitButton
@onready var volume_label: Label = $VolumeLabel
@onready var volume_slider: HSlider = $VolumeSlider
@onready var status_label: Label = $StatusLabel

var _master_bus_index: int = -1
var _options_visible: bool = false
var _master_volume_linear: float = 1.0

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_master_bus_index = AudioServer.get_bus_index("Master")
	_apply_fullscreen(true)

	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	volume_slider.value_changed.connect(_on_volume_changed)

	_disable_focus_outlines()
	_load_settings()
	_apply_options_visibility()
	_update_volume_label()
	_update_options_button_text()

func _on_start_pressed() -> void:
	status_label.text = "Loading lounge..."
	var result: Error = get_tree().change_scene_to_file(GAME_SCENE_PATH)
	if result != OK:
		status_label.text = "Could not load the game scene."
		push_error("Failed to load scene: %s (error %d)" % [GAME_SCENE_PATH, result])

func _on_options_pressed() -> void:
	_options_visible = not _options_visible
	_apply_options_visibility()
	_update_options_button_text()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(percent_value: float) -> void:
	var clamped_percent: float = clamp(percent_value, 0.0, 100.0)
	_master_volume_linear = clamped_percent / 100.0
	_apply_master_volume(_master_volume_linear)
	_update_volume_label()
	_save_settings()

func _update_options_button_text() -> void:
	options_button.text = "Close Options" if _options_visible else "Options"

func _disable_focus_outlines() -> void:
	var controls: Array[Control] = [
		start_button,
		options_button,
		quit_button,
		volume_slider
	]
	for c in controls:
		c.focus_mode = Control.FOCUS_NONE

func _apply_options_visibility() -> void:
	volume_label.visible = _options_visible
	volume_slider.visible = _options_visible

func _apply_fullscreen(enabled: bool) -> void:
	var mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _is_fullscreen_mode(mode: DisplayServer.WindowMode) -> bool:
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN

func _apply_master_volume(linear_volume: float) -> void:
	if _master_bus_index < 0:
		return

	var clamped_value: float = clamp(linear_volume, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)
	if clamped_value <= 0.001:
		AudioServer.set_bus_volume_db(_master_bus_index, MUTED_DB)
		return

	AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(clamped_value))

func _get_master_volume_linear() -> float:
	if _master_bus_index < 0:
		return 1.0

	var volume_db: float = AudioServer.get_bus_volume_db(_master_bus_index)
	if volume_db <= MUTED_DB + 0.5:
		return 0.0
	return clamp(db_to_linear(volume_db), MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)

func _update_volume_label() -> void:
	var percent: int = int(round(volume_slider.value))
	volume_label.text = "Volume: %d%%" % percent

func _load_settings() -> void:
	_master_volume_linear = _get_master_volume_linear()

	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		_master_volume_linear = float(config.get_value(SETTINGS_SECTION_AUDIO, "master_volume", _master_volume_linear))
		if _master_volume_linear > 1.0:
			_master_volume_linear = clamp(_master_volume_linear / 100.0, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)

	_master_volume_linear = clamp(_master_volume_linear, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)
	volume_slider.set_value_no_signal(_master_volume_linear * 100.0)
	_apply_fullscreen(true)
	_apply_master_volume(_master_volume_linear)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION_AUDIO, "master_volume", _master_volume_linear)
	config.save(SETTINGS_PATH)
