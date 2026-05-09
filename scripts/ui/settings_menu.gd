extends Control

# Menu de configuração: modo de janela + resolução. Persiste em user://settings.cfg
# (seção [display]). game_state.gd aplica essas configs no startup.

const _SETTINGS_PATH: String = "user://settings.cfg"
const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"

const _RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]

# Itens do dropdown de modo de janela. Ordem MUST bater com os constantes
# DISPLAY_MODE_* em game_state.gd (0=Janela, 1=Borderless, 2=Tela cheia).
const _DISPLAY_MODE_ITEMS: Array[String] = [
	"Janela",
	"Tela cheia em janela",
	"Tela cheia",
]

@onready var display_mode_dropdown: Button = $Center/Panel/Margin/VBox/DisplayModeRow/DisplayModeDropdown
@onready var resolution_dropdown: Button = $Center/Panel/Margin/VBox/ResolutionRow/ResolutionDropdown
@onready var apply_button: Button = $Center/Panel/Margin/VBox/ApplyButton
@onready var back_button: Button = $Center/Panel/Margin/VBox/BackButton


func _ready() -> void:
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)
	display_mode_dropdown.item_selected.connect(_on_display_mode_changed)
	_populate_dropdowns()
	_load_current_settings()
	_update_resolution_enabled()


func _populate_dropdowns() -> void:
	display_mode_dropdown.clear_items()
	for label in _DISPLAY_MODE_ITEMS:
		display_mode_dropdown.add_item(label)
	resolution_dropdown.clear_items()
	for res in _RESOLUTIONS:
		resolution_dropdown.add_item("%dx%d" % [res.x, res.y])


func _load_current_settings() -> void:
	var cfg := ConfigFile.new()
	var mode: int = GameState.DISPLAY_MODE_WINDOWED
	var res_x: int = 1920
	var res_y: int = 1080
	if cfg.load(_SETTINGS_PATH) == OK:
		mode = int(cfg.get_value("display", "window_mode", GameState.DISPLAY_MODE_WINDOWED))
		res_x = int(cfg.get_value("display", "resolution_x", 1920))
		res_y = int(cfg.get_value("display", "resolution_y", 1080))
	display_mode_dropdown.select(clamp(mode, 0, _DISPLAY_MODE_ITEMS.size() - 1))
	# Seleciona o item da resolução atual (cai no native 1920x1080 se não bater).
	var selected_idx: int = 2
	for i in range(_RESOLUTIONS.size()):
		if _RESOLUTIONS[i].x == res_x and _RESOLUTIONS[i].y == res_y:
			selected_idx = i
			break
	resolution_dropdown.select(selected_idx)


func _on_display_mode_changed(_index: int) -> void:
	_update_resolution_enabled()


func _update_resolution_enabled() -> void:
	# Resolução só faz sentido em modo Janela. Nos outros, monitor define.
	resolution_dropdown.disabled = display_mode_dropdown.get_selected() != GameState.DISPLAY_MODE_WINDOWED


func _on_apply_pressed() -> void:
	var mode: int = display_mode_dropdown.get_selected()
	var idx: int = max(0, resolution_dropdown.get_selected())
	var res: Vector2i = _RESOLUTIONS[idx]
	# Persiste.
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("display", "window_mode", mode)
	cfg.set_value("display", "resolution_x", res.x)
	cfg.set_value("display", "resolution_y", res.y)
	cfg.save(_SETTINGS_PATH)
	# Aplica imediatamente.
	GameState.apply_display_settings(mode, res)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
