extends Control

const _SETTINGS_PATH: String = "user://settings.cfg"
const _RELEASE_CLIENT := preload("res://scripts/systems/release_client.gd")
const _RELEASE_NOTES_MODAL: PackedScene = preload("res://scenes/ui/release_notes_modal.tscn")
const _RELEASE_NOTES_MODAL_SCRIPT := preload("res://scripts/ui/release_notes_modal.gd")

@onready var start_button: Button = $Center/VBox/StartButton
@onready var skins_button: Button = $Center/VBox/SkinsButton
@onready var leaderboard_button: Button = $Center/VBox/LeaderboardButton
@onready var settings_button: Button = $Center/VBox/SettingsButton
@onready var dev_button: Button = $Center/VBox/DevButton
@onready var quit_button: Button = $Center/VBox/QuitButton

@onready var nickname_prompt: Control = $NicknamePrompt
@onready var nickname_input: LineEdit = $NicknamePrompt/Center/Panel/Margin/VBox/NicknameInput
@onready var nickname_ok_button: Button = $NicknamePrompt/Center/Panel/Margin/VBox/OkButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	skins_button.pressed.connect(_on_skins_pressed)
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
	# Patch notes da última versão (uma vez por versão por usuário).
	_maybe_show_release_notes()


func _maybe_show_release_notes() -> void:
	# Skip se já viu a versão local. Não bloqueia se request falhar — silencioso.
	var client: Node = _RELEASE_CLIENT.new()
	add_child(client)
	client.latest_fetched.connect(_on_release_latest_fetched)
	client.fetch_latest()


func _on_release_latest_fetched(release: Dictionary) -> void:
	if release.is_empty():
		return
	var version: String = String(release.get("version", ""))
	if version.is_empty():
		return
	var notes: String = String(release.get("notes", ""))
	if notes.is_empty():
		return
	# Compara com a última versão que o user já dispensou. Se for igual, skip.
	if _RELEASE_NOTES_MODAL_SCRIPT.load_last_seen() == version:
		return
	var modal: Control = _RELEASE_NOTES_MODAL.instantiate()
	add_child(modal)
	modal.show_release(version, notes)
	modal.closed.connect(_save_release_seen.bind(version))


func _save_release_seen(version: String) -> void:
	_RELEASE_NOTES_MODAL_SCRIPT.save_last_seen(version)


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


func _on_skins_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/skin_select.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/leaderboard.tscn")


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/settings_menu.tscn")


func _on_dev_pressed() -> void:
	GameState.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
