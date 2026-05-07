extends Control

signal menu_closed

const SAVE_PATH: String = "user://radio_playlist.cfg"
const SEEK_STEP: float = 5.0

@export var music_player_path: NodePath = NodePath("../../../RadioAudio3D")

var playlist: Array[String] = []
var current_index: int = -1

var shuffle: bool = false
var repeat_song: bool = false
var loop_playlist: bool = true

@onready var music_player = get_node_or_null(music_player_path)
@onready var song_list: ItemList = $PanelContainer/MarginContainer/VBoxContainer/SongList
@onready var status_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatusLabel
@onready var previous_button: Button = $PanelContainer/MarginContainer/VBoxContainer/PlaybackRow/PreviousButton
@onready var seek_back_button: Button = $PanelContainer/MarginContainer/VBoxContainer/PlaybackRow/SeekBackButton
@onready var pause_resume_button: Button = $PanelContainer/MarginContainer/VBoxContainer/PlaybackRow/PauseResumeButton
@onready var seek_forward_button: Button = $PanelContainer/MarginContainer/VBoxContainer/PlaybackRow/SeekForwardButton
@onready var next_button: Button = $PanelContainer/MarginContainer/VBoxContainer/PlaybackRow/NextButton
@onready var shuffle_toggle: CheckButton = $PanelContainer/MarginContainer/VBoxContainer/ToggleRow/ShuffleToggle
@onready var repeat_song_toggle: CheckButton = $PanelContainer/MarginContainer/VBoxContainer/ToggleRow/RepeatSongToggle
@onready var loop_playlist_toggle: CheckButton = $PanelContainer/MarginContainer/VBoxContainer/ToggleRow/LoopPlaylistToggle
@onready var volume_slider: HSlider = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $PanelContainer/MarginContainer/VBoxContainer/VolumeRow/VolumeValueLabel
@onready var file_dialog: FileDialog = $MusicFileDialog

func _ready() -> void:
	visible = false
	if not music_player: music_player = get_node_or_null("MusicPlayer")
	
	
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.clear_filters()
	file_dialog.add_filter("*.mp3,*.ogg,*.wav", "Audio Files")
	
	previous_button.pressed.connect(func(): _change_track(-1))
	next_button.pressed.connect(func(): _change_track(1))
	seek_back_button.pressed.connect(func(): _seek_by(-SEEK_STEP))
	seek_forward_button.pressed.connect(func(): _seek_by(SEEK_STEP))
	pause_resume_button.pressed.connect(_toggle_pause)
	$PanelContainer/MarginContainer/VBoxContainer/ButtonRow/AddSongsButton.pressed.connect(func(): file_dialog.popup_centered_ratio(0.85))
	$PanelContainer/MarginContainer/VBoxContainer/ButtonRow/RemoveSongButton.pressed.connect(_remove_selected_song)
	$PanelContainer/MarginContainer/VBoxContainer/ButtonRow/CloseButton.pressed.connect(close_menu)
	file_dialog.files_selected.connect(_add_files)
	volume_slider.value_changed.connect(_apply_volume)
	
	
	shuffle_toggle.toggled.connect(func(v): shuffle = v; _save_state())
	repeat_song_toggle.toggled.connect(func(v): repeat_song = v; _save_state())
	loop_playlist_toggle.toggled.connect(func(v): loop_playlist = v; _save_state())
	
	if music_player and music_player.has_signal("finished"):
		music_player.finished.connect(_on_track_finished)
		
	_load_state()
	_update_ui("Ready." if playlist.size() > 0 else "Playlist is empty.")
	
	if current_index >= 0 and current_index < playlist.size():
		_play_track(current_index)

func open_menu() -> void:
	visible = true
	_update_ui()

func close_menu() -> void:
	visible = false
	file_dialog.hide()
	menu_closed.emit()

func is_menu_open() -> bool:
	return visible


func _change_track(direction: int) -> void:
	if playlist.is_empty(): return
	
	var next_idx = 0
	if shuffle and playlist.size() > 1:
		next_idx = randi() % playlist.size()
		while next_idx == current_index: # Prevent immediate repeat in shuffle
			next_idx = randi() % playlist.size()
	else:
		next_idx = current_index + direction
		if next_idx >= playlist.size():
			next_idx = 0 if loop_playlist else -1
		elif next_idx < 0:
			next_idx = playlist.size() - 1 if loop_playlist else -1
			
	if next_idx == -1:
		_stop_playback("Playlist ended.")
	else:
		_play_track(next_idx)

func _play_track(idx: int) -> void:
	if playlist.is_empty() or not music_player: return
	
	current_index = clamp(idx, 0, playlist.size() - 1)
	var path = playlist[current_index]
	var stream = _load_stream(path)
	
	if stream:
		music_player.stream = stream
		music_player.play()
		music_player.stream_paused = false
		_update_ui("Now playing: " + path.get_file())
		_save_state()
	else:
		_update_ui("Failed to load: " + path.get_file())

func _on_track_finished() -> void:
	if repeat_song:
		_play_track(current_index)
	else:
		_change_track(1)

func _toggle_pause() -> void:
	if playlist.is_empty() or not music_player: return
	
	if not music_player.playing and current_index == -1:
		_change_track(1) # Start playlist if stopped
	else:
		music_player.stream_paused = not music_player.stream_paused
		_update_ui("Paused" if music_player.stream_paused else "Resumed")

func _seek_by(offset: float) -> void:
	if music_player and music_player.playing:
		var length = music_player.stream.get_length() if music_player.stream else 0.0
		var new_pos = clamp(music_player.get_playback_position() + offset, 0.0, length)
		music_player.seek(new_pos)
		_update_ui("Seek: %.1fs" % new_pos)

func _stop_playback(msg: String) -> void:
	if music_player:
		music_player.stop()
		music_player.stream = null
	current_index = -1
	_update_ui(msg)


func _add_files(paths: PackedStringArray) -> void:
	var added = 0
	for path in paths:
		if not path in playlist and _load_stream(path) != null:
			playlist.append(path)
			added += 1
	
	_update_ui("Added %d songs." % added)
	_save_state()
	if current_index == -1 and added > 0:
		_change_track(1)

func _remove_selected_song() -> void:
	var selected = song_list.get_selected_items()
	if selected.is_empty(): return
	
	var idx = selected[0]
	playlist.remove_at(idx)
	
	if idx == current_index:
		_stop_playback("Song removed.") if playlist.is_empty() else _change_track(0)
	elif idx < current_index:
		current_index -= 1
		
	_update_ui("Song removed.")
	_save_state()

func _load_stream(path: String) -> AudioStream:
	var ext = path.get_extension().to_lower()
	if ext == "mp3": return AudioStreamMP3.load_from_file(path)
	if ext == "ogg": return AudioStreamOggVorbis.load_from_file(path)
	if ext == "wav": return AudioStreamWAV.load_from_file(path)
	return null


func _update_ui(status_msg: String = "") -> void:
	song_list.clear()
	for i in range(playlist.size()):
		song_list.add_item("%d. %s" % [i + 1, playlist[i].get_file()])
		
	if current_index >= 0 and current_index < song_list.item_count:
		song_list.select(current_index)
		song_list.ensure_current_is_visible()
		
	var has_songs = not playlist.is_empty()
	for btn in [previous_button, next_button, seek_back_button, seek_forward_button, pause_resume_button]:
		btn.disabled = not has_songs
	$PanelContainer/MarginContainer/VBoxContainer/ButtonRow/RemoveSongButton.disabled = not has_songs
	
	if music_player:
		pause_resume_button.text = "Resume" if music_player.stream_paused else "Pause"
		
	if status_msg != "":
		status_label.text = status_msg

func _apply_volume(val: float) -> void:
	if music_player:
		music_player.volume_db = linear_to_db(val) if val > 0.001 else -80.0
	volume_value_label.text = str(int(val * 100)) + "%"
	_save_state()

func _load_state() -> void:
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		var loaded_playlist = config.get_value("data", "playlist", [])
		playlist.assign(loaded_playlist)
		current_index = config.get_value("data", "current_index", -1)
		shuffle = config.get_value("data", "shuffle", false)
		repeat_song = config.get_value("data", "repeat_song", false)
		loop_playlist = config.get_value("data", "loop", true)
		volume_slider.value = config.get_value("data", "volume", 0.1)
		
	shuffle_toggle.set_pressed_no_signal(shuffle)
	repeat_song_toggle.set_pressed_no_signal(repeat_song)
	loop_playlist_toggle.set_pressed_no_signal(loop_playlist)
	_apply_volume(volume_slider.value)

func _save_state() -> void:
	var config = ConfigFile.new()
	config.set_value("data", "playlist", playlist)
	config.set_value("data", "current_index", current_index)
	config.set_value("data", "shuffle", shuffle)
	config.set_value("data", "repeat_song", repeat_song)
	config.set_value("data", "loop", loop_playlist)
	config.set_value("data", "volume", volume_slider.value)
	config.save(SAVE_PATH)
