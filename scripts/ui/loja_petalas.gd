extends Control

# Loja de Pétalas (loja meta, fora do jogo). Gasta o PetalBank persistente em
# skins + itens equipáveis. Layout C (loja de jogo): sidebar de categorias + grid
# + painel de detalhe à direita. Ver spec 2026-06-05-p4-loja-petalas-meta-design.md.

const _FONT_PATH: String = "res://font/Silver.ttf"
const _PETAL_ICON: String = "res://assets/Hud/petals.png"
const _KIT_LAYER_ORDER: Array[StringName] = [
	&"bow_back", &"body", &"legs", &"quiver", &"shirt", &"alfaja", &"cape", &"hair"
]
const _IDLE_REGION: Rect2 = Rect2(0, 0, 32, 32)

# Catálogo: cat ("skins"|"itens"), kind ("skin"|"item"), id, price, desc (key opcional).
const CATALOG: Array[Dictionary] = [
	{"cat": "skins", "kind": "skin", "id": "World_Cup", "price": 350, "desc": "LOJA_DESC_WORLD_CUP"},
	{"cat": "skins", "kind": "part", "id": "Red_Hair", "slot": "hair", "price": 150, "name_key": "LOJA_NAME_RED_HAIR", "desc": "LOJA_DESC_RED_HAIR"},
	{"cat": "itens", "kind": "item", "id": "midnight_dagger", "price": 750},
	{"cat": "itens", "kind": "item", "id": "golden_bow", "price": 750},
	{"cat": "itens", "kind": "item", "id": "cajado_crepusculo", "price": 400},
	{"cat": "itens", "kind": "item", "id": "sanguinario", "price": 660},
	{"cat": "itens", "kind": "item", "id": "chamado_da_matilha", "price": 200},
	{"cat": "itens", "kind": "item", "id": "primavera_eterna", "price": 50},
]
const CATEGORIES: Array[Dictionary] = [
	{"key": "skins", "label": "LOJA_CAT_SKINS"},
	{"key": "itens", "label": "LOJA_CAT_ITEMS"},
]
# Mesmo som de compra da loja in-game (wave_shop).
const BUY_SOUND: AudioStream = preload("res://audios/effects/buy_1.mp3")

const _ACCENT: Color = Color(1.0, 0.82, 0.4, 1.0)
const _MUTED: Color = Color(0.66, 0.58, 0.8, 1.0)
const _TEXT: Color = Color(0.92, 0.86, 1.0, 1.0)

var _font: Font
var _category: String = "skins"
var _selected: Dictionary = {}
var _parts_cache: Dictionary = {}  # id -> parts (cache do scan, evita re-varredura)

var _bank_label: Label = null
var _cat_box: VBoxContainer = null
var _grid: GridContainer = null
var _detail_box: VBoxContainer = null
var _confirm_modal: Control = null


func _ready() -> void:
	_font = load(_FONT_PATH)
	_build_ui()
	_set_category("skins")


# ---------- Construção da tela ----------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Frame centralizado, tamanho parecido com o Inventário (1440x820).
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(1440, 820)
	frame.add_theme_stylebox_override("panel", _sb(Color(0.10, 0.08, 0.15, 0.96), Color(0.42, 0.32, 0.6, 1.0), 12))
	center.add_child(frame)

	var pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 22)
	frame.add_child(pad)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 14)
	pad.add_child(root_vb)

	# --- Topo: título + saldo ---
	var top := HBoxContainer.new()
	root_vb.add_child(top)
	var title := Label.new()
	title.text = tr("LOJA_TITLE")
	title.add_theme_font_override("font", _font)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", _TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var bank := HBoxContainer.new()
	bank.add_theme_constant_override("separation", 8)
	bank.alignment = BoxContainer.ALIGNMENT_END
	top.add_child(bank)
	var picon := TextureRect.new()
	picon.texture = load(_PETAL_ICON) as Texture2D
	picon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picon.custom_minimum_size = Vector2(34, 34)
	picon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bank.add_child(picon)
	_bank_label = _mk_label("", 36, Color(1.0, 0.62, 0.82, 1.0))
	bank.add_child(_bank_label)

	var sep := HSeparator.new()
	root_vb.add_child(sep)

	# --- Corpo: sidebar | grid | detalhe ---
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(body)

	# Sidebar.
	_cat_box = VBoxContainer.new()
	_cat_box.add_theme_constant_override("separation", 6)
	_cat_box.custom_minimum_size = Vector2(200, 0)
	body.add_child(_cat_box)
	for cat in CATEGORIES:
		_cat_box.add_child(_make_cat_button(cat))

	body.add_child(_vsep())

	# Grid (com scroll pra quando crescer).
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	# CenterContainer centra o grid na largura disponível (o scroll força a largura
	# total com h-scroll desabilitado), deixando o grid equidistante das bordas em
	# vez de colado à esquerda com um vazião à direita.
	var grid_center := CenterContainer.new()
	grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid_center)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 14)
	grid_center.add_child(_grid)

	body.add_child(_vsep())

	# Painel de detalhe.
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(360, 0)
	detail_panel.add_theme_stylebox_override("panel", _sb(Color(0.08, 0.06, 0.12, 0.9), Color(0.4, 0.3, 0.58, 1.0), 10))
	body.add_child(detail_panel)
	var dpad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		dpad.add_theme_constant_override("margin_" + s, 18)
	detail_panel.add_child(dpad)
	_detail_box = VBoxContainer.new()
	_detail_box.add_theme_constant_override("separation", 12)
	dpad.add_child(_detail_box)

	# --- Voltar ---
	var back := Button.new()
	back.text = tr("COMMON_BACK")
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(200, 56)
	back.add_theme_font_override("font", _font)
	back.add_theme_font_size_override("font_size", 26)
	back.add_theme_color_override("font_color", _TEXT)
	back.pressed.connect(_on_back_pressed)
	var back_row := HBoxContainer.new()
	back_row.add_child(back)
	root_vb.add_child(back_row)

	_refresh_bank()


func _make_cat_button(cat: Dictionary) -> Button:
	var b := Button.new()
	b.text = tr(String(cat["label"]))
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 56)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 28)
	b.set_meta("cat_key", String(cat["key"]))
	b.pressed.connect(_set_category.bind(String(cat["key"])))
	return b


# ---------- Categoria / grid ----------

func _set_category(key: String) -> void:
	_category = key
	# Destaque do botão ativo.
	for c in _cat_box.get_children():
		var btn := c as Button
		if btn == null:
			continue
		var active: bool = String(btn.get_meta("cat_key", "")) == key
		btn.add_theme_color_override("font_color", _ACCENT if active else _MUTED)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1.0, 0.82, 0.4, 0.10) if active else Color(0, 0, 0, 0)
		sb.border_width_left = 3 if active else 0
		sb.border_color = _ACCENT
		sb.content_margin_left = 12.0
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
	# Seleciona o primeiro da categoria (o _select reconstroi o grid).
	var items := _catalog_for(key)
	_select(items[0] if not items.is_empty() else {})


func _catalog_for(key: String) -> Array:
	var out: Array = []
	for e in CATALOG:
		if String(e["cat"]) == key:
			out.append(e)
	# Ordena do mais barato pro mais caro (também define qual fica pré-selecionado).
	out.sort_custom(func(a, b): return int(a.get("price", 0)) < int(b.get("price", 0)))
	return out


func _rebuild_grid() -> void:
	for c in _grid.get_children():
		c.queue_free()
	for e in _catalog_for(_category):
		_grid.add_child(_make_grid_card(e))


func _make_grid_card(entry: Dictionary) -> Control:
	var id: String = String(entry["id"])
	var is_sel: bool = not _selected.is_empty() and String(_selected.get("id", "")) == id
	var owned: bool = _is_owned(entry)
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.custom_minimum_size = Vector2(150, 170)
	var border := _ACCENT if is_sel else (Color(0.45, 0.78, 0.5, 1.0) if owned else Color(0.4, 0.32, 0.56, 1.0))
	var sb := _sb(Color(0.13, 0.10, 0.18, 0.95), border, 8)
	card.add_theme_stylebox_override("normal", sb)
	card.add_theme_stylebox_override("hover", _sb(Color(0.17, 0.13, 0.23, 0.97), border, 8))
	card.add_theme_stylebox_override("pressed", sb)
	card.pressed.connect(_select.bind(entry))

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 8; vb.offset_top = 8; vb.offset_right = -8; vb.offset_bottom = -8
	card.add_child(vb)
	var thumb := _make_thumb(entry, 78.0)
	thumb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(thumb)
	var nm := _mk_label(_display_name(entry), 17, _TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(nm)
	if owned:
		vb.add_child(_mk_label(tr("LOJA_OWNED"), 14, Color(0.55, 0.9, 0.6, 1.0)))
	else:
		vb.add_child(_mk_label(str(int(entry["price"])), 16, Color(1.0, 0.62, 0.82, 1.0)))
	return card


# ---------- Seleção / painel de detalhe ----------

func _select(entry: Dictionary) -> void:
	_selected = entry
	_rebuild_grid()
	_refresh_detail()


func _refresh_detail() -> void:
	for c in _detail_box.get_children():
		c.queue_free()
	if _selected.is_empty():
		return
	var entry: Dictionary = _selected
	var price: int = int(entry["price"])
	var owned: bool = _is_owned(entry)

	var big := _make_thumb(entry, 170.0)
	big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_detail_box.add_child(big)

	var nm := _mk_label(_display_name(entry), 30, _TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_box.add_child(nm)

	var price_row := HBoxContainer.new()
	price_row.alignment = BoxContainer.ALIGNMENT_CENTER
	price_row.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.texture = load(_PETAL_ICON) as Texture2D
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.custom_minimum_size = Vector2(26, 26)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price_row.add_child(pic)
	price_row.add_child(_mk_label(str(price), 28, Color(1.0, 0.62, 0.82, 1.0)))
	_detail_box.add_child(price_row)

	# Descrição (abaixo do preço, ocupando o espaço).
	var desc := _mk_label(_description(entry), 19, _MUTED)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_detail_box.add_child(desc)

	# Rodapé: estado de compra.
	if owned:
		var ol := _mk_label(tr("LOJA_OWNED"), 26, Color(0.55, 0.9, 0.6, 1.0))
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_detail_box.add_child(ol)
	else:
		var can_afford: bool = PetalBank.get_total() >= price
		var buy := Button.new()
		buy.text = tr("LOJA_BUY")
		buy.focus_mode = Control.FOCUS_NONE
		buy.custom_minimum_size = Vector2(0, 58)
		buy.add_theme_font_override("font", _font)
		buy.add_theme_font_size_override("font_size", 28)
		buy.disabled = not can_afford
		buy.add_theme_color_override("font_color", Color(0.2, 0.7, 0.3, 1.0))
		buy.add_theme_color_override("font_hover_color", Color(0.3, 0.9, 0.4, 1.0))
		buy.add_theme_color_override("font_disabled_color", Color(0.5, 0.45, 0.55, 1.0))
		if can_afford:
			buy.pressed.connect(_on_buy_pressed.bind(entry))
		_detail_box.add_child(buy)
		if not can_afford:
			var hint := _mk_label(tr("LOJA_INSUFFICIENT"), 16, Color(0.95, 0.45, 0.45, 1.0))
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_detail_box.add_child(hint)


# ---------- Thumbnails ----------

func _make_thumb(entry: Dictionary, box: float) -> Control:
	if String(entry["kind"]) == "item":
		return _make_item_thumb(String(entry["id"]), box)
	return _thumb_from_parts(_parts_for(entry), box)


# Parts pro thumbnail de skin/peca, cacheadas por id (o scan eh caro).
func _parts_for(entry: Dictionary) -> Dictionary:
	var id: String = String(entry["id"])
	if _parts_cache.has(id):
		return _parts_cache[id]
	var parts: Dictionary
	if String(entry["kind"]) == "part":
		parts = SkinLoadout.get_parts_by_skin_name("Default").duplicate()
		var sp: SkinPart = SkinLoadout.find_part(StringName(String(entry["slot"])), id)
		if sp != null:
			parts[StringName(String(entry["slot"]))] = sp
	else:
		parts = SkinLoadout.get_parts_by_skin_name(id)
	_parts_cache[id] = parts
	return parts


func _thumb_from_parts(parts: Dictionary, box: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
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


func _make_item_thumb(id: String, box: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(box, box)
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


# ---------- Dados ----------

func _display_name(entry: Dictionary) -> String:
	if entry.has("name_key"):
		return tr(String(entry["name_key"]))
	if String(entry["kind"]) == "item":
		return tr(String(InventoryItems.ITEMS.get(String(entry["id"]), {}).get("name", entry["id"])))
	return String(entry["id"]).replace("_", " ")


func _description(entry: Dictionary) -> String:
	if entry.has("desc"):
		return tr(String(entry["desc"]))
	if String(entry["kind"]) == "item":
		return tr(String(InventoryItems.ITEMS.get(String(entry["id"]), {}).get("desc", "")))
	return ""


func _is_owned(entry: Dictionary) -> bool:
	if String(entry["kind"]) == "item":
		return InventoryItems.is_purchased(String(entry["id"]))
	return SkinLoadout.is_skin_purchased(String(entry["id"]))


func _refresh_bank() -> void:
	if _bank_label != null:
		_bank_label.text = str(PetalBank.get_total())


# ---------- Compra ----------

func _on_buy_pressed(entry: Dictionary) -> void:
	MenuAudio.play_click()
	_open_confirm(entry)


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
	panel.add_theme_stylebox_override("panel", _sb(Color(0.12, 0.09, 0.16, 1.0), Color(0.6, 0.46, 0.8, 1.0), 10))
	overlay.add_child(panel)
	var pad := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + s, 26)
	panel.add_child(pad)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	pad.add_child(vb)
	var q := _mk_label(tr("LOJA_CONFIRM") % [_display_name(entry), price], 28, _TEXT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(460, 0)
	vb.add_child(q)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	row.add_child(_modal_button(tr("COMMON_CANCEL"), Color(0.85, 0.7, 0.75, 1.0), _close_confirm))
	row.add_child(_modal_button(tr("COMMON_CONFIRM"), Color(0.4, 0.85, 0.5, 1.0), _confirm_purchase.bind(entry)))


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
		_play_buy_sound()  # mesmo som da loja in-game
	if _confirm_modal != null:
		_confirm_modal.queue_free()
		_confirm_modal = null
	_refresh_bank()
	_rebuild_grid()
	_refresh_detail()


func _on_back_pressed() -> void:
	MenuAudio.play_click()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# Som de compra (buy_1.mp3) — idêntico ao da loja in-game (wave_shop._play_buy_sound).
func _play_buy_sound() -> void:
	if BUY_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = BUY_SOUND
	p.volume_db = -16.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------- Helpers ----------

func _mk_label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l


func _sb(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(radius)
	return sb


func _vsep() -> VSeparator:
	return VSeparator.new()
