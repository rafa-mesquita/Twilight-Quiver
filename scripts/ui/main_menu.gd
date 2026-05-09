extends Control

const _SETTINGS_PATH: String = "user://settings.cfg"

@onready var start_button: Button = $Center/VBox/StartButton
@onready var leaderboard_button: Button = $Center/VBox/LeaderboardButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var dev_button: Button = $Center/VBox/DevButton
@onready var quit_button: Button = $Center/VBox/QuitButton

@onready var nickname_prompt: Control = $NicknamePrompt
@onready var nickname_input: LineEdit = $NicknamePrompt/Center/Panel/Margin/VBox/NicknameInput
@onready var nickname_ok_button: Button = $NicknamePrompt/Center/Panel/Margin/VBox/OkButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	dev_button.pressed.connect(_on_dev_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	nickname_ok_button.pressed.connect(_on_nickname_ok)
	nickname_input.text_submitted.connect(_on_nickname_submitted)
	# DevMode só aparece em build de debug.
	dev_button.visible = OS.is_debug_build()
	# Primeira vez? Pede o nick antes de liberar o menu.
	if _load_nickname().is_empty():
		_show_nickname_prompt()
	else:
		nickname_prompt.visible = false
		start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _show_nickname_prompt() -> void:
	nickname_prompt.visible = true
	nickname_input.text = ""
	nickname_input.grab_focus()


func _on_nickname_submitted(_text: String) -> void:
	_on_nickname_ok()


func _on_nickname_ok() -> void:
	var nick: String = nickname_input.text.strip_edges()
	if nick.is_empty():
		return
	if nick.length() > 24:
		nick = nick.substr(0, 24)
	_save_nickname(nick)
	nickname_prompt.visible = false
	start_button.grab_focus()


func _load_nickname() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value("player", "nickname", ""))


func _save_nickname(nick: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("player", "nickname", nick)
	cfg.save(_SETTINGS_PATH)


func _on_start_pressed() -> void:
	GameState.dev_mode = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")


func _on_dev_pressed() -> void:
	GameState.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
