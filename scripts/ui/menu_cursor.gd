extends Node

# Cursor de MENU: mãozinha pixel-art via cursor de HARDWARE. Usado nas telas de
# menu no lugar da mira in-game (cursor.tscn) — a mira é ótima pra mirar/atirar,
# mas ruim pra clicar em botão. Também restaura Input.mouse_mode = VISIBLE — a
# mira in-game esconde o mouse do OS (MOUSE_MODE_HIDDEN) e nunca restaurava.
#
# Mão fechada ao ARRASTAR: durante o drag-and-drop nativo do Godot, o engine
# troca a *shape* do cursor (DRAG / CAN_DROP / FORBIDDEN) — por isso mapeamos a
# mão fechada em TODAS essas shapes. Se mapeássemos só a ARROW, ao arrastar
# aparecia o "bloqueado" (FORBIDDEN) ou o cursor padrão do Windows.

const _HAND: String = "res://assets/Hud/cursor/menu_hand.png"
const _GRAB: String = "res://assets/Hud/cursor/menu_grab.png"
# Hotspot (px na imagem 32x32): mão apontando = ponta do dedo; mão fechada = centro.
const _HAND_HOTSPOT: Vector2 = Vector2(8, 2)
const _GRAB_HOTSPOT: Vector2 = Vector2(16, 14)


func _ready() -> void:
	var tex_hand: Texture2D = load(_HAND)
	var tex_grab: Texture2D = load(_GRAB)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Normal: mãozinha apontando (ARROW e POINTING_HAND, caso algum Control use).
	Input.set_custom_mouse_cursor(tex_hand, Input.CURSOR_ARROW, _HAND_HOTSPOT)
	Input.set_custom_mouse_cursor(tex_hand, Input.CURSOR_POINTING_HAND, _HAND_HOTSPOT)
	# Arrastando: o Godot troca pra essas shapes — todas viram mão fechada.
	for shape in [Input.CURSOR_DRAG, Input.CURSOR_CAN_DROP, Input.CURSOR_FORBIDDEN]:
		Input.set_custom_mouse_cursor(tex_grab, shape, _GRAB_HOTSPOT)
