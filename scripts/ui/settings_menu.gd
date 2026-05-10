extends Control

# Menu de configurações: Display + Audio + Video + Idioma. Persiste em
# user://settings.cfg em seções separadas. game_state.gd aplica essas configs
# no startup (e expõe helpers pra reaplicar quando o usuário clica Aplicar).
#
# Pode ser usado standalone (cena rodando direto, ex: do main menu) ou como
# overlay no meio do jogo (a partir do menu de pausa). Em modo overlay:
#  - Voltar emite signal `closed` em vez de change_scene
#  - Cursor + VersionLabel são removidos (HUD já tem os deles)

signal closed

# Setado pelo opener antes de adicionar à árvore. Quando true, comportamento
# de Voltar muda pra emitir signal em vez de trocar de cena.
@export var as_overlay: bool = false

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
# Strings são translation keys — TranslationServer auto-resolve via
# CustomSelect.text assignment (Control auto_translate_mode = INHERIT).
const _DISPLAY_MODE_ITEMS: Array[String] = [
	"SETTINGS_DISPLAY_MODE_WINDOWED",
	"SETTINGS_DISPLAY_MODE_BORDERLESS",
	"SETTINGS_DISPLAY_MODE_FULLSCREEN",
]

# FPS cap dropdown. Index 3 = "Sem limite" (0).
const _FPS_CAP_ITEMS: Array[String] = ["60", "120", "144", "SETTINGS_FPS_UNLIMITED"]
const _FPS_CAP_VALUES: Array[int] = [60, 120, 144, 0]

# --- Display ---
@onready var display_mode_dropdown: Button = $Center/Panel/Margin/Scroll/VBox/DisplayModeRow/DisplayModeDropdown
@onready var resolution_dropdown: Button = $Center/Panel/Margin/Scroll/VBox/ResolutionRow/ResolutionDropdown

# --- Audio ---
@onready var master_slider: HSlider = $Center/Panel/Margin/Scroll/VBox/MasterRow/MasterSlider
@onready var master_value: Label = $Center/Panel/Margin/Scroll/VBox/MasterRow/MasterValue
@onready var music_slider: HSlider = $Center/Panel/Margin/Scroll/VBox/MusicRow/MusicSlider
@onready var music_value: Label = $Center/Panel/Margin/Scroll/VBox/MusicRow/MusicValue
@onready var sfx_slider: HSlider = $Center/Panel/Margin/Scroll/VBox/SfxRow/SfxSlider
@onready var sfx_value: Label = $Center/Panel/Margin/Scroll/VBox/SfxRow/SfxValue

# --- Video ---
@onready var vsync_check: CheckBox = $Center/Panel/Margin/Scroll/VBox/VsyncRow/VsyncCheck
@onready var fps_cap_dropdown: Button = $Center/Panel/Margin/Scroll/VBox/FpsCapRow/FpsCapDropdown
@onready var show_fps_check: CheckBox = $Center/Panel/Margin/Scroll/VBox/ShowFpsRow/ShowFpsCheck

# --- Locale ---
@onready var locale_dropdown: Button = $Center/Panel/Margin/Scroll/VBox/LocaleRow/LocaleDropdown

# --- Buttons ---
@onready var apply_button: Button = $Center/Panel/Margin/Scroll/VBox/ApplyButton
@onready var back_button: Button = $Center/Panel/Margin/Scroll/VBox/BackButton


func _ready() -> void:
	if as_overlay:
		# Em overlay, removemos o cursor e o version label próprios — o HUD
		# do jogo já está renderizando os dele atrás.
		var c := get_node_or_null("Cursor")
		if c != null:
			c.queue_free()
		var v := get_node_or_null("VersionLabel")
		if v != null:
			v.queue_free()
	apply_button.pressed.connect(_on_apply_pressed)
	back_button.pressed.connect(_on_back_pressed)
	display_mode_dropdown.item_selected.connect(_on_display_mode_changed)
	# Sliders aplicam som imediato pra usuário ouvir o efeito; persiste no Aplicar.
	master_slider.value_changed.connect(_on_master_changed)
	music_slider.value_changed.connect(_on_music_changed)
	sfx_slider.value_changed.connect(_on_sfx_changed)
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
	fps_cap_dropdown.clear_items()
	for label in _FPS_CAP_ITEMS:
		fps_cap_dropdown.add_item(label)
	locale_dropdown.clear_items()
	for entry in LocaleManager.SUPPORTED_LOCALES:
		locale_dropdown.add_item(str(entry["label"]))


func _load_current_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)  # OK falha = usa defaults.

	# Display
	var mode: int = int(cfg.get_value("display", "window_mode", GameState.DISPLAY_MODE_WINDOWED))
	var res_x: int = int(cfg.get_value("display", "resolution_x", 1920))
	var res_y: int = int(cfg.get_value("display", "resolution_y", 1080))
	display_mode_dropdown.select(clamp(mode, 0, _DISPLAY_MODE_ITEMS.size() - 1))
	var selected_idx: int = 2
	for i in range(_RESOLUTIONS.size()):
		if _RESOLUTIONS[i].x == res_x and _RESOLUTIONS[i].y == res_y:
			selected_idx = i
			break
	resolution_dropdown.select(selected_idx)

	# Audio
	var master: int = int(cfg.get_value("audio", "master_volume", GameState.DEFAULT_MASTER_VOLUME))
	var music: int = int(cfg.get_value("audio", "music_volume", GameState.DEFAULT_MUSIC_VOLUME))
	var sfx: int = int(cfg.get_value("audio", "sfx_volume", GameState.DEFAULT_SFX_VOLUME))
	master_slider.value = master
	music_slider.value = music
	sfx_slider.value = sfx
	master_value.text = str(master)
	music_value.text = str(music)
	sfx_value.text = str(sfx)

	# Video
	var vsync: bool = bool(cfg.get_value("video", "vsync", GameState.DEFAULT_VSYNC))
	var fps_cap: int = int(cfg.get_value("video", "fps_cap", GameState.DEFAULT_FPS_CAP))
	var show_fps: bool = bool(cfg.get_value("video", "show_fps", GameState.DEFAULT_SHOW_FPS))
	vsync_check.button_pressed = vsync
	show_fps_check.button_pressed = show_fps
	var fps_idx: int = _FPS_CAP_VALUES.find(fps_cap)
	if fps_idx < 0:
		fps_idx = _FPS_CAP_VALUES.find(0)  # fallback "Sem limite"
	fps_cap_dropdown.select(fps_idx)

	# Locale
	var current_locale: String = LocaleManager.get_saved_locale()
	var locale_idx: int = 0
	for i in range(LocaleManager.SUPPORTED_LOCALES.size()):
		if str(LocaleManager.SUPPORTED_LOCALES[i]["code"]) == current_locale:
			locale_idx = i
			break
	locale_dropdown.select(locale_idx)


func _on_display_mode_changed(_index: int) -> void:
	_update_resolution_enabled()


func _update_resolution_enabled() -> void:
	# Resolução só faz sentido em modo Janela. Nos outros, monitor define.
	resolution_dropdown.disabled = display_mode_dropdown.get_selected() != GameState.DISPLAY_MODE_WINDOWED


func _on_master_changed(value: float) -> void:
	master_value.text = str(int(value))
	# Aplica imediato pro usuário escutar (persiste só no Aplicar).
	GameState.apply_audio_settings(int(master_slider.value), int(music_slider.value), int(sfx_slider.value))


func _on_music_changed(value: float) -> void:
	music_value.text = str(int(value))
	GameState.apply_audio_settings(int(master_slider.value), int(music_slider.value), int(sfx_slider.value))


func _on_sfx_changed(value: float) -> void:
	sfx_value.text = str(int(value))
	GameState.apply_audio_settings(int(master_slider.value), int(music_slider.value), int(sfx_slider.value))


func _on_apply_pressed() -> void:
	# --- Display ---
	var mode: int = display_mode_dropdown.get_selected()
	var idx: int = max(0, resolution_dropdown.get_selected())
	var res: Vector2i = _RESOLUTIONS[idx]

	# --- Audio ---
	var master: int = int(master_slider.value)
	var music: int = int(music_slider.value)
	var sfx: int = int(sfx_slider.value)

	# --- Video ---
	var vsync: bool = vsync_check.button_pressed
	var fps_idx: int = max(0, fps_cap_dropdown.get_selected())
	var fps_cap: int = _FPS_CAP_VALUES[fps_idx]
	var show_fps: bool = show_fps_check.button_pressed

	# --- Locale ---
	var loc_idx: int = max(0, locale_dropdown.get_selected())
	var locale_code: String = str(LocaleManager.SUPPORTED_LOCALES[loc_idx]["code"])

	# Persiste tudo.
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value("display", "window_mode", mode)
	cfg.set_value("display", "resolution_x", res.x)
	cfg.set_value("display", "resolution_y", res.y)
	cfg.set_value("audio", "master_volume", master)
	cfg.set_value("audio", "music_volume", music)
	cfg.set_value("audio", "sfx_volume", sfx)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("video", "fps_cap", fps_cap)
	cfg.set_value("video", "show_fps", show_fps)
	cfg.save(_SETTINGS_PATH)
	# Locale: LocaleManager cuida da seção [locale].
	LocaleManager.save_locale(locale_code)
	LocaleManager.apply_locale(locale_code)

	# Aplica imediatamente.
	GameState.apply_display_settings(mode, res)
	GameState.apply_audio_settings(master, music, sfx)
	GameState.apply_video_settings(vsync, fps_cap, show_fps)


func _on_back_pressed() -> void:
	closed.emit()
	if not as_overlay:
		get_tree().change_scene_to_file(_MAIN_MENU_PATH)
