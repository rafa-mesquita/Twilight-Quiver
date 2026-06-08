extends Node

# Singleton de estado global. Autoloaded no project.godot como "GameState".
# Carrega defaults toda vez que o jogo é aberto — não persiste entre runs.

const _SETTINGS_PATH: String = "user://settings.cfg"

# Dev mode: quando true, main.tscn não roda waves automáticas e exibe o DevPanel
# pra o desenvolvedor testar inimigos/upgrades isoladamente.
var dev_mode: bool = false

# Dev godmode: player ignora todo dano enquanto true (checado em player.take_damage).
# Persiste entre scene reloads (útil pra testar runs longas sem morrer).
var dev_godmode: bool = false

# Dev: força o Relógio de Reset a dropar SEMPRE (chance 100%, ignora o gate de
# "ter skill ativa"). Pra testar o pickup/SFX/reset sem depender do RNG de 4%.
# Checado em ClockDrop.try_drop. Toggle no dev_panel.
var dev_clock_always_drop: bool = false

# Força a carta "Último Desejo" a aparecer no próximo roll do shop, ignorando
# weight e wave 5+. Resetado pelo wave_shop ao consumir o flag. Setado pelo
# dev_panel pra testar a feature sem depender de RNG.
var dev_force_joker_next_shop: bool = false

# Força a carta "Roleta Elemental" a aparecer no próximo roll do shop, ignorando
# weight. Resetado pelo wave_shop ao consumir o flag. Setado pelo dev_panel.
var dev_force_roulette_next_shop: bool = false

# Snapshot de upgrades pra "renascer com os mesmos" (botão do dev panel).
# Mapa upgrade_id → nível alvo. Aplicado pelo dev_panel após o player carregar
# na nova run (cena recarregada), depois limpado. Vazio = sem respawn pendente.
var pending_respawn_upgrades: Dictionary = {}

# Overlay de FPS (criado lazy quando _ensure_fps_overlay roda a primeira vez).
var _fps_overlay: CanvasLayer = null
var _fps_label: Label = null
var _show_fps: bool = false


func _ready() -> void:
	LocaleManager.apply_locale(LocaleManager.get_saved_locale())
	_load_and_apply_display_settings()
	_load_and_apply_audio_settings()
	_load_and_apply_video_settings()
	_load_and_apply_hud_settings()


func _process(_delta: float) -> void:
	if _show_fps and _fps_label != null:
		_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func reset() -> void:
	dev_mode = false


# ---------- Display settings ----------

# Modos de display salvos em config (ordem do dropdown em settings_menu).
# Janela = windowed normal; Borderless = tela cheia em janela; Exclusive = tela cheia.
const DISPLAY_MODE_WINDOWED: int = 0
const DISPLAY_MODE_BORDERLESS: int = 1
const DISPLAY_MODE_FULLSCREEN: int = 2
# Ultrawide: false = pillarbox 16:9 (aspect KEEP, padrão justo). true = preenche a tela
# (aspect EXPAND, mostra mais do mundo na horizontal — pra monitores ultrawide).
const DEFAULT_ULTRAWIDE: bool = false


func _load_and_apply_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return  # Sem arquivo: usa defaults do project.godot.
	var mode: int = int(cfg.get_value("display", "window_mode", DISPLAY_MODE_WINDOWED))
	var res_x: int = int(cfg.get_value("display", "resolution_x", 1920))
	var res_y: int = int(cfg.get_value("display", "resolution_y", 1080))
	apply_display_settings(mode, Vector2i(res_x, res_y))
	apply_ultrawide(bool(cfg.get_value("display", "ultrawide_expand", DEFAULT_ULTRAWIDE)))


func apply_display_settings(mode: int, resolution: Vector2i) -> void:
	match mode:
		DISPLAY_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		DISPLAY_MODE_BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_size(resolution)
			# Recentra a janela na tela após resize.
			var screen_size: Vector2i = DisplayServer.screen_get_size()
			var window_pos: Vector2i = (screen_size - resolution) / 2
			DisplayServer.window_set_position(window_pos)


# Ultrawide: EXPAND preenche a tela mostrando mais do mundo na horizontal; KEEP mantém
# 16:9 com barras laterais (pillarbox). Aplicado no root Window (stretch mode = viewport).
func apply_ultrawide(expand: bool) -> void:
	var root := get_tree().root
	if root != null:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND if expand else Window.CONTENT_SCALE_ASPECT_KEEP


# ---------- Audio settings ----------

# Bus indices (devem bater com default_bus_layout.tres).
const _BUS_MASTER: int = 0
const _BUS_MUSIC: int = 1
const _BUS_SFX: int = 2

const DEFAULT_MASTER_VOLUME: int = 80
const DEFAULT_MUSIC_VOLUME: int = 60
const DEFAULT_SFX_VOLUME: int = 80


func _load_and_apply_audio_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)  # OK falha não tem problema — usa defaults.
	var master: int = int(cfg.get_value("audio", "master_volume", DEFAULT_MASTER_VOLUME))
	var music: int = int(cfg.get_value("audio", "music_volume", DEFAULT_MUSIC_VOLUME))
	var sfx: int = int(cfg.get_value("audio", "sfx_volume", DEFAULT_SFX_VOLUME))
	apply_audio_settings(master, music, sfx)


func apply_audio_settings(master: int, music: int, sfx: int) -> void:
	AudioServer.set_bus_volume_db(_BUS_MASTER, _volume_to_db(master))
	AudioServer.set_bus_volume_db(_BUS_MUSIC, _volume_to_db(music))
	AudioServer.set_bus_volume_db(_BUS_SFX, _volume_to_db(sfx))


func _volume_to_db(volume_0_100: int) -> float:
	# 0 = mute total (-80dB); >0 mapeia linearmente (0-100 -> 0.0-1.0) via linear_to_db.
	var v: int = clamp(volume_0_100, 0, 100)
	if v <= 0:
		return -80.0
	return linear_to_db(float(v) / 100.0)


# ---------- Video settings ----------

const DEFAULT_VSYNC: bool = true
const DEFAULT_FPS_CAP: int = 0  # 0 = sem limite
const DEFAULT_SHOW_FPS: bool = false


func _load_and_apply_video_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	var vsync: bool = bool(cfg.get_value("video", "vsync", DEFAULT_VSYNC))
	var fps_cap: int = int(cfg.get_value("video", "fps_cap", DEFAULT_FPS_CAP))
	var show_fps: bool = bool(cfg.get_value("video", "show_fps", DEFAULT_SHOW_FPS))
	apply_video_settings(vsync, fps_cap, show_fps)


func apply_video_settings(vsync: bool, fps_cap: int, show_fps: bool) -> void:
	if vsync:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max(0, fps_cap)
	_show_fps = show_fps
	_ensure_fps_overlay()
	if _fps_overlay != null:
		_fps_overlay.visible = show_fps


# ---------- HUD settings (esconder informações de tempo) ----------

const DEFAULT_HIDE_RUN_TIMER: bool = false
const DEFAULT_HIDE_TIME_INFO: bool = false

# Esconde o cronômetro live no HUD durante a run. Lido todo frame pelo HUD.
var hide_run_timer: bool = false
# Esconde os tempos de round/run mostrados entre rounds (tela "Wave Limpa") e na
# tela de morte. Lido na hora de montar esses textos.
var hide_time_info: bool = false


func _load_and_apply_hud_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	var hide_timer: bool = bool(cfg.get_value("hud", "hide_run_timer", DEFAULT_HIDE_RUN_TIMER))
	var hide_info: bool = bool(cfg.get_value("hud", "hide_time_info", DEFAULT_HIDE_TIME_INFO))
	apply_hud_settings(hide_timer, hide_info)


func apply_hud_settings(hide_timer: bool, hide_info: bool) -> void:
	hide_run_timer = hide_timer
	hide_time_info = hide_info


func _ensure_fps_overlay() -> void:
	if _fps_overlay != null:
		return
	_fps_overlay = CanvasLayer.new()
	_fps_overlay.layer = 100
	_fps_overlay.name = "FPSOverlay"
	add_child(_fps_overlay)
	_fps_label = Label.new()
	_fps_label.text = "FPS: 0"
	_fps_label.position = Vector2(12, 8)
	_fps_label.add_theme_color_override("font_color", Color(1, 1, 0.4, 1))
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.add_theme_font_size_override("font_size", 25)
	# Carrega fonte do projeto se disponível (falha silenciosa em testes).
	var fnt: FontFile = load("res://font/Silver.ttf") as FontFile
	if fnt != null:
		_fps_label.add_theme_font_override("font", fnt)
	_fps_overlay.add_child(_fps_label)
	_fps_overlay.visible = false
