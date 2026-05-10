class_name LocaleManager
extends RefCounted

# Helper estático pra ler/salvar locale do user://settings.cfg.
# Aplica via TranslationServer.set_locale() no startup (game_state.gd).

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "locale"
const _KEY: String = "code"

const SUPPORTED_LOCALES: Array[Dictionary] = [
	{"code": "pt_BR", "label": "Português"},
	{"code": "en",    "label": "English"},
	{"code": "es",    "label": "Español"},
	{"code": "fr",    "label": "Français"},
]
const DEFAULT_LOCALE: String = "pt_BR"


static func get_saved_locale() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return DEFAULT_LOCALE
	return str(cfg.get_value(_SECTION, _KEY, DEFAULT_LOCALE))


static func save_locale(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	cfg.set_value(_SECTION, _KEY, code)
	cfg.save(_SETTINGS_PATH)


static func apply_locale(code: String) -> void:
	TranslationServer.set_locale(code)
