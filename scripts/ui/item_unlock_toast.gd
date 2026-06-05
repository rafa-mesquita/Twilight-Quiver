class_name ItemUnlockToast
extends CanvasLayer

# Toast de "item desbloqueado" no canto inferior direito, em TEMPO REAL assim que
# o requisito do item é satisfeito durante a partida (o HUD detecta e chama
# enqueue()). A tela de morte mostra a celebração maior — este é só o aviso
# imediato. Espelha o SkinUnlockToast, mas mostra o ÍCONE do item (32x32) no
# lugar do mini boneco.

const _FONT: FontFile = preload("res://font/Silver.ttf")

const PANEL_SIZE: Vector2 = Vector2(322, 112)
const MARGIN_RIGHT: float = 14.0
const MARGIN_BOTTOM: float = 58.0
const HIDE_SHIFT: float = 470.0
const SHOW_IN: float = 0.4
const HOLD: float = 3.2
const SHOW_OUT: float = 0.35
const ICON_BOX: Vector2 = Vector2(90, PANEL_SIZE.y - 20)

var _root: Control = null
var _panel: Panel = null
var _icon: TextureRect = null
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

	# Ícone do item à esquerda (32x32 ampliado, nearest).
	_icon = TextureRect.new()
	_icon.position = Vector2(10, 10)
	_icon.size = ICON_BOX
	_icon.custom_minimum_size = ICON_BOX
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_icon)

	# Texto à direita.
	var vbox := VBoxContainer.new()
	vbox.position = Vector2(ICON_BOX.x + 24, 0)
	vbox.size = Vector2(PANEL_SIZE.x - ICON_BOX.x - 40, PANEL_SIZE.y)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "HUD_ITEM_UNLOCK_TITLE"  # auto-traduz (Control)
	_title_label.add_theme_font_override("font", _FONT)
	_title_label.add_theme_font_size_override("font_size", 21)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35, 1.0))
	_title_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_title_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_title_label)

	_name_label = Label.new()
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.custom_minimum_size = Vector2(PANEL_SIZE.x - ICON_BOX.x - 40, 0)
	_name_label.add_theme_font_override("font", _FONT)
	_name_label.add_theme_font_size_override("font_size", 26)
	_name_label.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("outline_size", 4)
	vbox.add_child(_name_label)


# Enfileira um toast pro item (id). Mostrado assim que não houver outro em exibição.
func enqueue(item_id: String) -> void:
	if item_id.is_empty():
		return
	_queue.append(item_id)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var item_id: String = _queue.pop_front()
	_populate(item_id)
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


func _populate(item_id: String) -> void:
	var item: Dictionary = InventoryItems.ITEMS.get(item_id, {})
	_name_label.text = tr(String(item.get("name", item_id)))
	_icon.texture = load(InventoryItems.get_icon_path(item_id)) as Texture2D
