extends Node

# Cursor de MENU: mãozinha pixel-art via cursor de HARDWARE. Usado nas telas de
# menu no lugar da mira in-game (cursor.tscn) — a mira é ótima pra mirar/atirar,
# mas ruim pra clicar em botão. Troca pra "mão fechada" enquanto o jogador
# ARRASTA um item (get_viewport().gui_is_dragging, ex: drag-and-drop do
# inventário). Também restaura Input.mouse_mode = VISIBLE — a mira in-game
# esconde o mouse do OS (MOUSE_MODE_HIDDEN) e nunca restaurava.

const _HAND: String = "res://assets/Hud/cursor/menu_hand.png"
const _GRAB: String = "res://assets/Hud/cursor/menu_grab.png"
# Hotspot (px na imagem 32x32): mão apontando = ponta do dedo; mão fechada = centro.
const _HAND_HOTSPOT: Vector2 = Vector2(8, 2)
const _GRAB_HOTSPOT: Vector2 = Vector2(16, 14)

var _tex_hand: Texture2D
var _tex_grab: Texture2D
var _grabbing: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tex_hand = load(_HAND)
	_tex_grab = load(_GRAB)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_apply(false)


func _process(_delta: float) -> void:
	var vp := get_viewport()
	var dragging: bool = vp != null and vp.gui_is_dragging()
	if dragging != _grabbing:
		_apply(dragging)


func _apply(grab: bool) -> void:
	_grabbing = grab
	if grab and _tex_grab != null:
		Input.set_custom_mouse_cursor(_tex_grab, Input.CURSOR_ARROW, _GRAB_HOTSPOT)
	elif _tex_hand != null:
		Input.set_custom_mouse_cursor(_tex_hand, Input.CURSOR_ARROW, _HAND_HOTSPOT)
