extends CanvasLayer

# Mostra application/config/version no canto inferior direito da tela, com um botão
# "(?)" clicável LOGO À ESQUERDA da versão que reabre o modal de patch notes em
# qualquer tela (mesmo fluxo do main_menu). O botão e a label são nós reais da cena
# (ver version_label.tscn) — não criados em código — pra renderizarem de forma
# confiável quando a cena é instanciada dentro de outra (HUD, menus, loja, etc).
# O CanvasLayer fica em layer alto (100) pra a versão e o modal ficarem acima de tudo.

const _RELEASE_CLIENT := preload("res://scripts/systems/release_client.gd")
const _RELEASE_NOTES_MODAL: PackedScene = preload("res://scenes/ui/release_notes_modal.tscn")
const _MODAL_NODE_NAME: String = "PatchNotesModalInstance"

@onready var _version_label: Label = $Row/Version
@onready var _help_button: Button = $Row/Help

var _busy: bool = false


func _ready() -> void:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	_version_label.text = v
	_help_button.pressed.connect(_on_help_pressed)


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
	# Filho deste CanvasLayer (layer 100) pra ficar acima de tudo.
	add_child(modal)
	modal.show_release(version, notes)


func _modal_open() -> bool:
	return has_node(_MODAL_NODE_NAME)
