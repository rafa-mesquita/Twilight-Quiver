extends Label

# Lê application/config/version do project.godot e exibe como "vX.Y.Z" no canto.
# Instanciar como filho de um CanvasLayer (ver version_label.tscn) pra ficar
# fixo no viewport independente do tipo de cena pai (Control ou CanvasLayer).
#
# Ao lado da versão, cria um botão "?" (via código, pra não mexer no .tscn) que
# abre o modal de patch notes em qualquer tela — mesmo fluxo do main_menu.

const _RELEASE_CLIENT := preload("res://scripts/systems/release_client.gd")
const _RELEASE_NOTES_MODAL: PackedScene = preload("res://scenes/ui/release_notes_modal.tscn")
const _MODAL_NODE_NAME: String = "PatchNotesModalInstance"

var _busy: bool = false


func _ready() -> void:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	text = "%s" % v if v != "" else ""
	# Abre espaço à direita pro botão "?".
	offset_right = -48.0
	_add_help_button()


func _add_help_button() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var btn := Button.new()
	btn.name = "PatchNotesHelpButton"
	btn.process_mode = Node.PROCESS_MODE_ALWAYS  # clicável mesmo pausado
	btn.flat = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "?"
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -44.0
	btn.offset_top = -46.0
	btn.offset_right = -8.0
	btn.offset_bottom = -6.0
	btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var f: Font = load("res://font/Silver.ttf")
	if f != null:
		btn.add_theme_font_override("font", f)
	btn.add_theme_font_size_override("font_size", 30)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.95))
	btn.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	btn.add_theme_constant_override("outline_size", 4)
	btn.pressed.connect(_on_help_pressed)
	parent.add_child(btn)


func _on_help_pressed() -> void:
	if _busy or _modal_open():
		return
	_busy = true
	var client: Node = _RELEASE_CLIENT.new()
	add_child(client)
	client.latest_fetched.connect(_on_latest_fetched)
	client.fetch_latest()


func _on_latest_fetched(release: Dictionary) -> void:
	_busy = false
	var version: String = String(release.get("version", ""))
	var notes: String = String(release.get("notes", ""))
	if version.is_empty() or notes.is_empty():
		return  # fetch falhou — silencioso
	if _modal_open():
		return
	var modal: Control = _RELEASE_NOTES_MODAL.instantiate()
	modal.name = _MODAL_NODE_NAME
	modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Adiciona no CanvasLayer pai (layer alto) pra ficar acima de tudo.
	get_parent().add_child(modal)
	modal.show_release(version, notes)


func _modal_open() -> bool:
	var p := get_parent()
	return p != null and p.has_node(_MODAL_NODE_NAME)
