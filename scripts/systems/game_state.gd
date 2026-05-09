extends Node

# Singleton de estado global. Autoloaded no project.godot como "GameState".
# Carrega defaults toda vez que o jogo é aberto — não persiste entre runs.

const _SETTINGS_PATH: String = "user://settings.cfg"

# Dev mode: quando true, main.tscn não roda waves automáticas e exibe o DevPanel
# pra o desenvolvedor testar inimigos/upgrades isoladamente.
var dev_mode: bool = false


func _ready() -> void:
	_load_and_apply_display_settings()


func reset() -> void:
	dev_mode = false


# ---------- Display settings ----------

# Modos de display salvos em config (ordem do dropdown em settings_menu).
# Janela = windowed normal; Borderless = tela cheia em janela; Exclusive = tela cheia.
const DISPLAY_MODE_WINDOWED: int = 0
const DISPLAY_MODE_BORDERLESS: int = 1
const DISPLAY_MODE_FULLSCREEN: int = 2


func _load_and_apply_display_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return  # Sem arquivo: usa defaults do project.godot.
	var mode: int = int(cfg.get_value("display", "window_mode", DISPLAY_MODE_WINDOWED))
	var res_x: int = int(cfg.get_value("display", "resolution_x", 1920))
	var res_y: int = int(cfg.get_value("display", "resolution_y", 1080))
	apply_display_settings(mode, Vector2i(res_x, res_y))


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
