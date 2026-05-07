extends Control

signal menu_closed
signal beer_tracker_visibility_changed(is_visible: bool)
signal events_enabled_changed(is_enabled: bool)
signal weather_enabled_changed(is_enabled: bool)
signal weather_sound_enabled_changed(is_enabled: bool)
signal drink_sfx_volume_changed(linear_volume: float)

const MAIN_MENU_SCENE_PATH: String = "res://MainMenu.tscn"
const SETTINGS_PATH: String = "user://main_menu_settings.cfg"
const SETTINGS_SECTION_AUDIO: String = "audio"
const SETTINGS_SECTION_UI: String = "ui"
const SETTINGS_KEY_SHOW_BEER_TRACKER: String = "show_beer_tracker"
const SETTINGS_KEY_EVENTS_ENABLED: String = "events_enabled"
const SETTINGS_KEY_WEATHER_ENABLED: String = "weather_enabled"
const SETTINGS_KEY_WEATHER_SOUND_ENABLED: String = "weather_sound_enabled"
const SETTINGS_KEY_DRINK_SFX_VOLUME: String = "drink_sfx_volume"
const MIN_VOLUME_LINEAR: float = 0.0
const MAX_VOLUME_LINEAR: float = 1.0
const MUTED_DB: float = -80.0

@onready var continue_button: Button = $CenterContainer/MenuVBox/ContinueButton
@onready var main_menu_button: Button = $CenterContainer/MenuVBox/MainMenuButton
@onready var options_button: Button = $CenterContainer/MenuVBox/OptionsButton
@onready var quit_button: Button = $CenterContainer/MenuVBox/QuitButton
@onready var options_box: VBoxContainer = $CenterContainer/MenuVBox/OptionsBox
@onready var volume_slider: HSlider = $CenterContainer/MenuVBox/OptionsBox/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $CenterContainer/MenuVBox/OptionsBox/VolumeRow/VolumeValueLabel
@onready var drink_sfx_slider: HSlider = $CenterContainer/MenuVBox/OptionsBox/DrinkSfxRow/DrinkSfxSlider
@onready var drink_sfx_value_label: Label = $CenterContainer/MenuVBox/OptionsBox/DrinkSfxRow/DrinkSfxValueLabel
@onready var beer_tracker_toggle: CheckButton = $CenterContainer/MenuVBox/OptionsBox/BeerTrackerToggle
@onready var events_toggle: CheckButton = $CenterContainer/MenuVBox/OptionsBox/EventsToggle
@onready var weather_toggle: CheckButton = $CenterContainer/MenuVBox/OptionsBox/WeatherToggle
@onready var weather_sound_toggle: CheckButton = $CenterContainer/MenuVBox/OptionsBox/WeatherSoundToggle

var _master_bus_index: int = -1
var _show_beer_tracker_ui: bool = true
var _events_enabled: bool = true
var _weather_enabled: bool = true
var _weather_sound_enabled: bool = true
var _drink_sfx_volume_linear: float = 1.0

func _ready() -> void:
	visible = false
	_master_bus_index = AudioServer.get_bus_index("Master")
	_apply_fullscreen(true)

	continue_button.pressed.connect(_on_continue_pressed)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	volume_slider.value_changed.connect(_on_volume_changed)
	drink_sfx_slider.value_changed.connect(_on_drink_sfx_changed)
	beer_tracker_toggle.toggled.connect(_on_beer_tracker_toggled)
	events_toggle.toggled.connect(_on_events_toggled)
	weather_toggle.toggled.connect(_on_weather_toggled)
	weather_sound_toggle.toggled.connect(_on_weather_sound_toggled)

	_disable_focus_outlines()
	_load_settings()
	_set_options_visible(false)
	_update_volume_label()
	_update_drink_sfx_label()

func open_menu() -> void:
	visible = true

func close_menu() -> void:
	visible = false
	_set_options_visible(false)
	menu_closed.emit()

func is_menu_open() -> bool:
	return visible

func _on_continue_pressed() -> void:
	close_menu()

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)

func _on_options_pressed() -> void:
	_set_options_visible(not options_box.visible)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_volume_changed(value: float) -> void:
	_apply_master_volume(value)
	_update_volume_label()
	_save_settings()

func _on_drink_sfx_changed(percent_value: float) -> void:
	var clamped_percent: float = clamp(percent_value, 0.0, 100.0)
	_drink_sfx_volume_linear = clamped_percent / 100.0
	_update_drink_sfx_label()
	_save_settings()
	drink_sfx_volume_changed.emit(_drink_sfx_volume_linear)

func _on_beer_tracker_toggled(is_pressed: bool) -> void:
	_show_beer_tracker_ui = is_pressed
	_save_settings()
	beer_tracker_visibility_changed.emit(_show_beer_tracker_ui)

func is_beer_tracker_ui_enabled() -> bool:
	return _show_beer_tracker_ui

func _on_events_toggled(is_pressed: bool) -> void:
	_events_enabled = is_pressed
	_save_settings()
	events_enabled_changed.emit(_events_enabled)

func are_events_enabled() -> bool:
	return _events_enabled

func _on_weather_toggled(is_pressed: bool) -> void:
	_weather_enabled = is_pressed
	_save_settings()
	weather_enabled_changed.emit(_weather_enabled)

func is_weather_enabled() -> bool:
	return _weather_enabled

func _on_weather_sound_toggled(is_pressed: bool) -> void:
	_weather_sound_enabled = is_pressed
	_save_settings()
	weather_sound_enabled_changed.emit(_weather_sound_enabled)

func is_weather_sound_enabled() -> bool:
	return _weather_sound_enabled

func get_drink_sfx_volume_linear() -> float:
	return _drink_sfx_volume_linear

func _set_options_visible(visible_state: bool) -> void:
	options_box.visible = visible_state
	options_button.text = "Close Options" if visible_state else "Options"

func _disable_focus_outlines() -> void:
	var controls: Array[Control] = [
		continue_button,
		main_menu_button,
		options_button,
		quit_button,
		volume_slider,
		drink_sfx_slider,
		beer_tracker_toggle,
		events_toggle,
		weather_toggle,
		weather_sound_toggle
	]
	for c in controls:
		c.focus_mode = Control.FOCUS_NONE

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
	var percent: int = int(round(volume_slider.value * 100.0))
	volume_value_label.text = "%d%%" % percent

func _update_drink_sfx_label() -> void:
	var percent: int = int(round(drink_sfx_slider.value))
	drink_sfx_value_label.text = "%d%%" % percent

func _load_settings() -> void:
	var master_volume: float = _get_master_volume_linear()

	var config: ConfigFile = ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		master_volume = float(config.get_value(SETTINGS_SECTION_AUDIO, "master_volume", master_volume))
		_drink_sfx_volume_linear = float(config.get_value(SETTINGS_SECTION_AUDIO, SETTINGS_KEY_DRINK_SFX_VOLUME, _drink_sfx_volume_linear))
		if _drink_sfx_volume_linear > 1.0:
			_drink_sfx_volume_linear = clamp(_drink_sfx_volume_linear / 100.0, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)
		_show_beer_tracker_ui = bool(config.get_value(SETTINGS_SECTION_UI, SETTINGS_KEY_SHOW_BEER_TRACKER, _show_beer_tracker_ui))
		_events_enabled = bool(config.get_value(SETTINGS_SECTION_UI, SETTINGS_KEY_EVENTS_ENABLED, _events_enabled))
		_weather_enabled = bool(config.get_value(SETTINGS_SECTION_UI, SETTINGS_KEY_WEATHER_ENABLED, _weather_enabled))
		_weather_sound_enabled = bool(config.get_value(SETTINGS_SECTION_UI, SETTINGS_KEY_WEATHER_SOUND_ENABLED, _weather_sound_enabled))

	_drink_sfx_volume_linear = clamp(_drink_sfx_volume_linear, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR)
	volume_slider.set_value_no_signal(clamp(master_volume, MIN_VOLUME_LINEAR, MAX_VOLUME_LINEAR))
	drink_sfx_slider.set_value_no_signal(_drink_sfx_volume_linear * 100.0)
	beer_tracker_toggle.set_pressed_no_signal(_show_beer_tracker_ui)
	events_toggle.set_pressed_no_signal(_events_enabled)
	weather_toggle.set_pressed_no_signal(_weather_enabled)
	weather_sound_toggle.set_pressed_no_signal(_weather_sound_enabled)
	_apply_fullscreen(true)
	_apply_master_volume(volume_slider.value)
	beer_tracker_visibility_changed.emit(_show_beer_tracker_ui)
	events_enabled_changed.emit(_events_enabled)
	weather_enabled_changed.emit(_weather_enabled)
	weather_sound_enabled_changed.emit(_weather_sound_enabled)
	drink_sfx_volume_changed.emit(_drink_sfx_volume_linear)

func _save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value(SETTINGS_SECTION_AUDIO, "master_volume", volume_slider.value)
	config.set_value(SETTINGS_SECTION_AUDIO, SETTINGS_KEY_DRINK_SFX_VOLUME, _drink_sfx_volume_linear)
	config.set_value(SETTINGS_SECTION_UI, SETTINGS_KEY_SHOW_BEER_TRACKER, _show_beer_tracker_ui)
	config.set_value(SETTINGS_SECTION_UI, SETTINGS_KEY_EVENTS_ENABLED, _events_enabled)
	config.set_value(SETTINGS_SECTION_UI, SETTINGS_KEY_WEATHER_ENABLED, _weather_enabled)
	config.set_value(SETTINGS_SECTION_UI, SETTINGS_KEY_WEATHER_SOUND_ENABLED, _weather_sound_enabled)
	config.save(SETTINGS_PATH)
