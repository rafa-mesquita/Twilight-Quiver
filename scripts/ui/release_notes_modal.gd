extends Control

# Modal de patch notes — fetch da API /api/releases, mostra notes da última
# versão em markdown convertido pra BBCode (RichTextLabel).
# Aparece UMA VEZ por versão por usuário (last_seen_version em settings.cfg).

signal closed

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "release_notes"
const _KEY_LAST_SEEN: String = "last_seen_version"

@onready var version_label: Label = $Center/Panel/Margin/VBox/VersionLabel
@onready var notes_text: RichTextLabel = $Center/Panel/Margin/VBox/Scroll/Notes
@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton


func _ready() -> void:
	close_button.pressed.connect(_on_close)
	# Esc também fecha.
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_close()


func show_release(version: String, notes_md: String) -> void:
	version_label.text = version
	notes_text.text = _markdown_to_bbcode(notes_md)


# ---------- Persistência de "última versão vista" ----------

static func load_last_seen() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value(_SECTION, _KEY_LAST_SEEN, ""))


static func save_last_seen(version: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)  # ok se não existir; cfg começa vazio
	cfg.set_value(_SECTION, _KEY_LAST_SEEN, version)
	cfg.save(_SETTINGS_PATH)


# ---------- Markdown → BBCode (subset suficiente pra patch notes) ----------

func _markdown_to_bbcode(md: String) -> String:
	# Conversão simples: ## headers, **bold**, *italic*, - bullets, `code`.
	# Não tenta cobrir markdown completo — só o que aparece em release notes.
	var s: String = md
	# Headers: ## ou ### → bold dourado.
	var re_h := RegEx.new()
	re_h.compile("(?m)^#{2,3}\\s+(.+)$")
	s = re_h.sub(s, "[b][color=#ffd366]$1[/color][/b]", true)
	# **bold**
	var re_b := RegEx.new()
	re_b.compile("\\*\\*(.+?)\\*\\*")
	s = re_b.sub(s, "[b]$1[/b]", true)
	# *italic* (apenas se não for parte de **).
	var re_i := RegEx.new()
	re_i.compile("(?<!\\*)\\*([^\\*\\n]+?)\\*(?!\\*)")
	s = re_i.sub(s, "[i]$1[/i]", true)
	# - item → bullet
	var re_li := RegEx.new()
	re_li.compile("(?m)^-\\s+(.+)$")
	s = re_li.sub(s, "  • $1", true)
	# `code` inline
	var re_code := RegEx.new()
	re_code.compile("`([^`\\n]+?)`")
	s = re_code.sub(s, "[code]$1[/code]", true)
	return s


func _on_close() -> void:
	closed.emit()
	queue_free()
