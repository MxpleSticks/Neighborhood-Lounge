extends Node

const DailyEventsScript := preload("res://daily_events.gd")
const DailyWeatherScript := preload("res://daily_weather.gd")
const MORNING_START_TIME_OF_DAY: float = 0.08

signal day_started(day_number: int)
signal recurring_day_started(day_number: int)

@onready var sun         : DirectionalLight3D = $Sun
@onready var environment : WorldEnvironment   = $WorldEnvironment
@onready var pause_menu_ui: Control = $player/CanvasLayer/PauseMenu


var day_length_seconds : float = 240.0
var time_of_day        : float = MORNING_START_TIME_OF_DAY

var day_number: int = 1
var _sky : ProceduralSkyMaterial
var _daily_events
var _daily_weather
var _events_enabled: bool = true
var _weather_enabled: bool = true
var _weather_sound_enabled: bool = true


func _ready() -> void:
	_sky = environment.environment.sky.sky_material
	_daily_events = DailyEventsScript.new()
	_daily_weather = DailyWeatherScript.new()
	time_of_day = MORNING_START_TIME_OF_DAY
	_daily_events.setup(self)
	_daily_weather.setup(self)
	if pause_menu_ui and pause_menu_ui.has_signal("events_enabled_changed"):
		pause_menu_ui.events_enabled_changed.connect(_on_events_enabled_changed)
		if pause_menu_ui.has_method("are_events_enabled"):
			_on_events_enabled_changed(pause_menu_ui.call("are_events_enabled"))
	else:
		_daily_events.set_events_enabled(_events_enabled, self)
	if pause_menu_ui and pause_menu_ui.has_signal("weather_enabled_changed"):
		pause_menu_ui.weather_enabled_changed.connect(_on_weather_enabled_changed)
		if pause_menu_ui.has_method("is_weather_enabled"):
			_on_weather_enabled_changed(pause_menu_ui.call("is_weather_enabled"))
	else:
		_daily_weather.set_weather_enabled(_weather_enabled, self)
	if pause_menu_ui and pause_menu_ui.has_signal("weather_sound_enabled_changed"):
		pause_menu_ui.weather_sound_enabled_changed.connect(_on_weather_sound_enabled_changed)
		if pause_menu_ui.has_method("is_weather_sound_enabled"):
			_on_weather_sound_enabled_changed(pause_menu_ui.call("is_weather_sound_enabled"))
	else:
		_daily_weather.set_weather_sound_enabled(_weather_sound_enabled, self)
	_apply_time_of_day_visuals()


func _process(delta: float) -> void:
	if day_length_seconds <= 0.0:
		return

	time_of_day += delta / day_length_seconds
	var completed_days: int = int(floor(time_of_day))
	if completed_days > 0:
		time_of_day = fmod(time_of_day, 1.0)
		_advance_days(completed_days)

	_apply_time_of_day_visuals()


func _advance_days(days_to_advance: int) -> void:
	for _i in range(days_to_advance):
		day_number += 1
		day_started.emit(day_number)
		if day_number > 1:
			recurring_day_started.emit(day_number)
			_daily_events.run_for_day(day_number, self)
			_daily_weather.run_for_day(day_number, self)


func _on_events_enabled_changed(is_enabled: bool) -> void:
	_events_enabled = is_enabled
	if _daily_events:
		_daily_events.set_events_enabled(_events_enabled, self)

func _on_weather_enabled_changed(is_enabled: bool) -> void:
	_weather_enabled = is_enabled
	if _daily_weather:
		_daily_weather.set_weather_enabled(_weather_enabled, self)


func _on_weather_sound_enabled_changed(is_enabled: bool) -> void:
	_weather_sound_enabled = is_enabled
	if _daily_weather:
		_daily_weather.set_weather_sound_enabled(_weather_sound_enabled, self)


func _apply_time_of_day_visuals() -> void:
	sun.rotation_degrees.x = (time_of_day * 360.0) - 90.0
	_update_light()
	_update_sky()


func _update_light() -> void:
	var sun_angle : float = sin(time_of_day * TAU)
	sun.visible      = sun_angle > -0.1
	sun.light_energy = clamp(sun_angle, 0.0, 1.0)

	var warm : float = clamp(1.0 - abs(sun_angle), 0.0, 1.0)
	sun.light_color  = Color(1.0, 1.0 - warm * 0.3, 1.0 - warm * 0.5)


func _update_sky() -> void:
	var sun_angle  : float = sin(time_of_day * TAU)
	var sky_day    : Color = Color(0.2, 0.5, 0.9)
	var sky_night  : Color = Color(0.01, 0.01, 0.05)
	var sky_dawn   : Color = Color(0.6, 0.3, 0.2)

	var t          : float = clamp(sun_angle, 0.0, 1.0)
	var dawn_factor: float = clamp(1.0 - abs(sun_angle - 0.3) * 4.0, 0.0, 1.0)
	var sky_color  : Color = sky_night.lerp(sky_day, t).lerp(sky_dawn, dawn_factor)

	_sky.sky_top_color        = sky_color
	_sky.sky_horizon_color    = sky_color.lightened(0.2)
	_sky.ground_horizon_color = sky_color.darkened(0.2)
