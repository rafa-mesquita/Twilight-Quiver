extends Control

# Loja de Pétalas (loja meta, fora do jogo). Gasta o PetalBank persistente em
# skins + itens equipáveis. v1: skin World Cup + itens Adaga/Arco (tipo "shop").
# Tela construída em código. Ver spec 2026-06-05-p4-loja-petalas-meta-design.md.

const _FONT_PATH: String = "res://font/Silver.ttf"
const _PETAL_ICON: String = "res://assets/Hud/petals.png"
# Ordem de camadas do thumbnail de skin (mesma do skin_select).
const _KIT_LAYER_ORDER: Array[StringName] = [
	&"bow_back", &"body", &"legs", &"quiver", &"shirt", &"alfaja", &"cape", &"hair"
]
const _IDLE_REGION: Rect2 = Rect2(0, 0, 32, 32)
const _THUMB_SIZE: Vector2 = Vector2(150, 150)

# Catálogo da loja. kind: "skin" | "item". id: nome do kit / id do item.
const CATALOG: Array[Dictionary] = [
	{"kind": "skin", "id": "World_Cup", "price": 120},
	{"kind": "item", "id": "midnight_dagger", "price": 200},
	{"kind": "item", "id": "golden_bow", "price": 200},
]

var _font: Font
var _bank_label: Label = null
var _cards_row: HBoxContainer = null
var _confirm_modal: Control = null


func _ready() -> void:
	_font = load(_FONT_PATH)
	_build_background()
	_build_header()
	_build_cards()
	_build_back_button()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_header() -> void:
	# Título centralizado no topo.
	var title := Label.new()
	title.text = tr("LOJA_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 28.0
	title.offset_bottom = 90.0
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	add_child(title)
	# Saldo do banco (canto superior direito): ícone + total.
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -280.0
	holder.offset_top = 30.0
	holder.offset_right = -30.0
	holder.offset_bottom = 80.0
	add_child(holder)
	var icon := Sprite2D.new()
	icon.texture = load(_PETAL_ICON) as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(18, 24)
	icon.scale = Vector2(2.0, 2.0)
	holder.add_child(icon)
	_bank_label = Label.new()
	_bank_label.offset_left = 46.0
	_bank_label.offset_right = 250.0
	_bank_label.offset_bottom = 50.0
	_bank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bank_label.add_theme_font_override("font", _font)
	_bank_label.add_theme_font_size_override("font_size", 38)
	_bank_label.add_theme_color_override("font_color", Color(1.0, 0.62, 0.82, 1.0))
	holder.add_child(_bank_label)
	_refresh_bank()


func _build_cards() -> void:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_cards_row = HBoxContainer.new()
	_cards_row.add_theme_constant_override("separation", 36)
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_cards_row)
	_rebuild_cards()


func _rebuild_cards() -> void:
	for c in _cards_row.get_children():
		c.queue_free()
	for entry in CATALOG:
		_cards_row.add_child(_make_card(entry))


func _make_card(entry: Dictionary) -> Control:
	var kind: String = String(entry["kind"])
	var id: String = String(entry["id"])
	var price: int = int(entry["price"])
	var owned: bool = _is_owned(entry)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(240, 360)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.09, 0.15, 0.95)
	sb.border_color = Color(0.65, 0.5, 0.85, 1.0) if not owned else Color(0.5, 0.85, 0.55, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	card.add_child(vb)

	# Thumbnail.
	var thumb: Control = _make_skin_thumb(id) if kind == "skin" else _make_item_thumb(id)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(thumb)

	# Nome.
	var name_lbl := Label.new()
	name_lbl.text = _display_name(entry)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 26)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 1.0, 1.0))
	vb.add_child(name_lbl)

	# Descrição curta (itens).
	if kind == "item":
		var desc := Label.new()
		desc.text = tr(String(InventoryItems.ITEMS.get(id, {}).get("desc", "")))
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_override("font", _font)
		desc.add_theme_font_size_override("font_size", 17)
		desc.add_theme_color_override("font_color", Color(0.78, 0.72, 0.88, 1.0))
		vb.add_child(desc)

	# Empurra a linha de preço/compra pro rodapé do card.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	if owned:
		var owned_lbl := Label.new()
		owned_lbl.text = tr("LOJA_OWNED")
		owned_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		owned_lbl.add_theme_font_override("font", _font)
		owned_lbl.add_theme_font_size_override("font_size", 26)
		owned_lbl.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6, 1.0))
		vb.add_child(owned_lbl)
	else:
		var can_afford: bool = PetalBank.get_total() >= price
		var buy := Button.new()
		buy.text = "%s   %d" % [tr("LOJA_BUY"), price]
		buy.focus_mode = Control.FOCUS_NONE
		buy.add_theme_font_override("font", _font)
		buy.add_theme_font_size_override("font_size", 24)
		buy.disabled = not can_afford
		buy.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
		buy.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.55, 1.0))
		if can_afford:
			buy.pressed.connect(_on_buy_pressed.bind(entry))
		vb.add_child(buy)
		if not can_afford:
			var hint := Label.new()
			hint.text = tr("LOJA_INSUFFICIENT")
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.add_theme_font_override("font", _font)
			hint.add_theme_font_size_override("font_size", 15)
			hint.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45, 1.0))
			vb.add_child(hint)
	return card


func _make_skin_thumb(skin_name: String) -> Control:
	var parts: Dictionary = SkinLoadout.get_parts_by_skin_name(skin_name)
	var holder := Control.new()
	holder.custom_minimum_size = _THUMB_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot in _KIT_LAYER_ORDER:
		var tex: Texture2D
		if slot == &"bow_back":
			var bp: SkinPart = parts.get(&"bow")
			tex = bp.texture_back if bp != null else null
		else:
			var pp: SkinPart = parts.get(slot)
			tex = pp.texture if pp != null else null
		if tex == null:
			continue
		var layer := TextureRect.new()
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = _IDLE_REGION
		layer.texture = atlas
		holder.add_child(layer)
	return holder


func _make_item_thumb(id: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = _THUMB_SIZE
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := TextureRect.new()
	t.texture = load(InventoryItems.get_icon_path(id)) as Texture2D
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(t)
	return holder


func _display_name(entry: Dictionary) -> String:
	if String(entry["kind"]) == "item":
		return tr(String(InventoryItems.ITEMS.get(String(entry["id"]), {}).get("name", entry["id"])))
	return String(entry["id"]).replace("_", " ")


func _is_owned(entry: Dictionary) -> bool:
	if String(entry["kind"]) == "item":
		return InventoryItems.is_purchased(String(entry["id"]))
	return SkinLoadout.is_skin_purchased(String(entry["id"]))


func _on_buy_pressed(entry: Dictionary) -> void:
	MenuAudio.play_click()
	_open_confirm(entry)


func _refresh_bank() -> void:
	if _bank_label != null:
		_bank_label.text = str(PetalBank.get_total())


# ---------- Modal de confirmação ----------

func _open_confirm(entry: Dictionary) -> void:
	if _confirm_modal != null:
		_confirm_modal.queue_free()
	var price: int = int(entry["price"])
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_confirm_modal = overlay

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.09, 0.16, 1.0)
	sb.border_color = Color(0.65, 0.5, 0.85, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 28.0
	sb.content_margin_right = 28.0
	sb.content_margin_top = 24.0
	sb.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", sb)
	overlay.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vb)

	var q := Label.new()
	q.text = tr("LOJA_CONFIRM") % [_display_name(entry), price]
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(460, 0)
	q.add_theme_font_override("font", _font)
	q.add_theme_font_size_override("font_size", 28)
	q.add_theme_color_override("font_color", Color(0.95, 0.88, 1.0, 1.0))
	vb.add_child(q)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(_modal_button(tr("COMMON_CANCEL"), Color(0.85, 0.7, 0.75, 1.0), _close_confirm))
	row.add_child(_modal_button(tr("COMMON_CONFIRM"), Color(0.55, 0.9, 0.6, 1.0), _confirm_purchase.bind(entry)))


func _modal_button(label: String, col: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(180, 56)
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 26)
	b.add_theme_color_override("font_color", col)
	b.pressed.connect(cb)
	return b


func _close_confirm() -> void:
	MenuAudio.play_click()
	if _confirm_modal != null:
		_confirm_modal.queue_free()
		_confirm_modal = null


func _confirm_purchase(entry: Dictionary) -> void:
	var price: int = int(entry["price"])
	if PetalBank.spend(price):
		if String(entry["kind"]) == "item":
			InventoryItems.mark_purchased(String(entry["id"]))
		else:
			SkinLoadout.mark_skin_purchased(String(entry["id"]))
		MenuAudio.play_drop()  # som de compra
	if _confirm_modal != null:
		_confirm_modal.queue_free()
		_confirm_modal = null
	_refresh_bank()
	_rebuild_cards()


# ---------- Voltar ----------

func _build_back_button() -> void:
	var back := Button.new()
	back.text = tr("COMMON_BACK")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(220, 64)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.offset_left = 40.0
	back.offset_top = -100.0
	back.offset_right = 260.0
	back.offset_bottom = -36.0
	back.add_theme_font_override("font", _font)
	back.add_theme_font_size_override("font_size", 28)
	back.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0, 1.0))
	back.pressed.connect(_on_back_pressed)
	add_child(back)


func _on_back_pressed() -> void:
	MenuAudio.play_click()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")
