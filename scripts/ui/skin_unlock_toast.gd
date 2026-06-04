class_name SkinUnlockToast
extends CanvasLayer

# Toast minimalista de "skin desbloqueada" no canto inferior direito, mostrado em
# TEMPO REAL assim que a quest da skin é satisfeita durante a partida (o HUD faz a
# detecção e chama enqueue()). A tela de morte continua mostrando a celebração
# completa — este é só o aviso imediato.
#
# Conteúdo: mini preview animado da skin (reusa player_preview.tscn, mesmo do
# death panel) + "SKIN DESBLOQUEADA!" + nome da skin. Desliza da direita, segura
# alguns segundos e some. Múltiplos unlocks entram numa fila e aparecem em
# sequência.

const _PREVIEW_SCENE: PackedScene = preload("res://scenes/ui/player_preview.tscn")
const _FONT: FontFile = preload("res://font/Silver.ttf")

# Coordenadas no espaço nativo da HUD (mesmo da version_label: bottom-right com
# offsets em centenas). A version label ocupa ~44px no canto → ficamos acima dela.
const PANEL_SIZE: Vector2 = Vector2(430, 150)
const MARGIN_RIGHT: float = 14.0
const MARGIN_BOTTOM: float = 58.0
const HIDE_SHIFT: float = 470.0  # quanto desliza pra fora (à direita) quando oculto
const SHOW_IN: float = 0.4
const HOLD: float = 3.2
const SHOW_OUT: float = 0.35
# Framing do mini preview dentro do box recortado (ajustável no editor se precisar).
const PREVIEW_CLIP_SIZE: Vector2 = Vector2(120, PANEL_SIZE.y - 20)
const PREVIEW_SCALE: float = 2.2
const PREVIEW_FEET_Y_FACTOR: float = 0.92

var _root: Control = null
var _panel: Panel = null
var _preview: Node2D = null
var _title_label: Label = null
var _name_label: Label = null

var _queue: Array[String] = []
var _showing: bool = false


func _ready() -> void:
	layer = 6  # acima do mundo; abaixo da version label (layer 100)
	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.anchor_left = 1.0
	_root.anchor_top = 1.0
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	_root.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.offset_left = -MARGIN_RIGHT - PANEL_SIZE.x
	_root.offset_top = -MARGIN_BOTTOM - PANEL_SIZE.y
	_root.offset_right = -MARGIN_RIGHT
	_root.offset_bottom = -MARGIN_BOTTOM
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_panel = Panel.new()
	_panel.size = PANEL_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.9)
	style.border_color = Color(1.0, 0.85, 0.35, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 8
	style.content_margin_top = 8
	style.content_margin_right = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	_panel.position.x = HIDE_SHIFT  # começa escondido (deslizado pra fora)
	_root.add_child(_panel)

	# Box recortado com o mini preview à esquerda.
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(10, 10)
	clip.size = PREVIEW_CLIP_SIZE
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(clip)

	_preview = _PREVIEW_SCENE.instantiate() as Node2D
	_preview.position = Vector2(PREVIEW_CLIP_SIZE.x * 0.5, PREVIEW_CLIP_SIZE.y * PREVIEW_FEET_Y_FACTOR)
	_preview.scale = Vector2(PREVIEW_SCALE, PREVIEW_SCALE)
	clip.add_child(_preview)

	# Texto à direita.
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(PREVIEW_CLIP_SIZE.x + 24, 0)
	vbox.size = Vector2(PANEL_SIZE.x - PREVIEW_CLIP_SIZE.x - 40, PANEL_SIZE.y)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "HUD_UNLOCK_TITLE"  # auto-traduz (Control)
	_title_label.add_theme_font_override("font", _FONT)
	_title_label.add_theme_font_size_override("font_size", 28)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_title_label)

	_name_label = Label.new()
	_name_label.add_theme_font_override("font", _FONT)
	_name_label.add_theme_font_size_override("font_size", 38)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_name_label)


# Enfileira um toast pra a skin (display_name). Mostrado assim que não houver
# outro em exibição.
func enqueue(skin_name: String) -> void:
	if skin_name.is_empty():
		return
	_queue.append(skin_name)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var skin_name: String = _queue.pop_front()
	_populate(skin_name)
	_root.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_panel, "position:x", 0.0, SHOW_IN)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(HOLD)
	tw.tween_property(_root, "modulate:a", 0.0, SHOW_OUT)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_panel, "position:x", HIDE_SHIFT, SHOW_OUT)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(_show_next)


func _populate(skin_name: String) -> void:
	_name_label.text = skin_name.replace("_", " ")
	var body: AnimatedSprite2D = _preview.get_node_or_null("Body") as AnimatedSprite2D
	var skin: Node = _preview.get_node_or_null("Skin")
	if body == null or skin == null:
		return
	# Reusa as sprite_frames do player ativo (mesmas regions/anims da skin).
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var player_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if player_sprite != null and player_sprite.sprite_frames != null:
			body.sprite_frames = player_sprite.sprite_frames
	if body.sprite_frames != null and body.sprite_frames.has_animation("idle"):
		body.play("idle")
	var parts: Dictionary = SkinLoadout.get_parts_by_skin_name(skin_name)
	for slot in SkinLoadout.SLOTS:
		if skin.has_method("set_part"):
			skin.set_part(slot, parts.get(slot))
