class_name RunBuildModal
extends Control

# Modal "Build da Run" — mostra os upgrades (texto, agrupados) + itens equipados
# (ícones) de uma run do leaderboard. Construído todo em código pra ser
# instanciável de qualquer tela (leaderboard, ou a cena de teste do dev).
#
# Uso:
#   var m := RunBuildModal.new()
#   add_child(m)
#   m.open({
#     "nickname": "rafa", "wave": 24, "score": 12340,
#     "time_ms": 312000, "time_to_w21_ms": 312000,
#     "build": { "upgrades": {"attack_speed": 4, ...}, "items": ["sanguinario", ...] }
#   })
#
# Run antiga sem build (chave "build" ausente/vazia) → mostra "build não
# registrada".

const _FONT_PATH: String = "res://font/Silver.ttf"
const _GOLD := Color(1, 0.85, 0.45, 1)
const _TEXT := Color(0.9, 0.85, 1, 1)
const _DIM := Color(0.6, 0.58, 0.7, 1)

# Categorias na ordem de exibição. Cada uma: title key + lista de (id, name_key).
# Nomes reusam as keys da loja (SHOP_*) — nada novo no CSV pros upgrades.
const _CATEGORIES: Array = [
	{
		"title": "LEADERBOARD_BUILD_CAT_ELEMENTAL",
		"entries": [
			["fire_arrow", "SHOP_UPG_FIRE_ARROW"],
			["curse_arrow", "SHOP_UPG_CURSE_ARROW"],
			["ice_arrow", "SHOP_UPG_ICE_ARROW"],
			["stone_arrow", "SHOP_UPG_STONE_ARROW"],
			["tide_arrow", "SHOP_UPG_TIDE_ARROW"],
		],
	},
	{
		"title": "LEADERBOARD_BUILD_CAT_STANDARD",
		"entries": [
			["perfuracao", "SHOP_UPG_PERFURACAO"],
			["multi_arrow", "SHOP_UPG_MULTI_ARROW"],
			["double_arrows", "SHOP_UPG_DOUBLE_ARROWS"],
			["chain_lightning", "SHOP_UPG_CHAIN_LIGHTNING"],
			["life_steal", "SHOP_UPG_LIFE_STEAL"],
			["gold_magnet", "SHOP_UPG_GOLD_MAGNET"],
			["dash", "SHOP_UPG_DASH"],
			["esquivando", "SHOP_UPG_ESQUIVANDO"],
			["fenda", "SHOP_UPG_FENDA"],
			["adrenalina", "SHOP_UPG_ADRENALINA"],
			["ricochet_arrow", "SHOP_UPG_RICOCHET"],
			["graviton", "SHOP_UPG_GRAVITON"],
			["boomerang", "SHOP_UPG_BOOMERANG"],
			["critical_chance", "SHOP_UPG_CRITICAL_CHANCE"],
			["tiger_claws", "SHOP_UPG_TIGER_CLAWS"],
		],
	},
	{
		"title": "LEADERBOARD_BUILD_CAT_STATUS",
		"entries": [
			["hp", "SHOP_STAT_HP"],
			["damage", "SHOP_STAT_DAMAGE"],
			["attack_speed", "SHOP_STAT_ATTACK_SPEED"],
			["move_speed", "SHOP_STAT_MOVE_SPEED"],
			["armor", "SHOP_STAT_ARMOR"],
		],
	},
	{
		"title": "LEADERBOARD_BUILD_CAT_ALLIES",
		"entries": [
			["claudio_druida", "SHOP_ALLY_CLAUDIO_DRUIDA"],
			["leno", "SHOP_ALLY_LENO"],
			["capivara_joe", "SHOP_ALLY_CAPIVARA"],
			["ting", "SHOP_ALLY_TING"],
			["mini_mago", "SHOP_ALLY_MINI_MAGO"],
			["arbusto", "SHOP_ALLY_ARBUSTO"],
		],
	},
]

const _PANEL_W: float = 380.0
const _PANEL_MARGIN: float = 24.0

var _font: Font = null
var _content: VBoxContainer = null
var _panel: PanelContainer = null


func _ready() -> void:
	_font = load(_FONT_PATH)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# IGNORE no root: cliques fora do painel atravessam pro leaderboard atrás —
	# o painel é lateral e NÃO escurece/cobre a tela. Fecha pelo X (ou ESC).
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Painel lateral à DIREITA, altura cheia (com margens), sem cobrir o leaderboard.
	# Posicionado pelo tamanho do VIEWPORT (via _layout_panel), NÃO por âncoras do
	# parent — o parent ainda tem tamanho 0 no _ready, o que jogava o painel pra fora
	# da tela (x negativo) e fazia o "ver build" parecer não abrir.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.09, 0.15, 0.98)
	sb.border_color = _GOLD
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_panel = panel
	# Reposiciona quando a janela muda de tamanho.
	get_viewport().size_changed.connect(_layout_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Barra superior com botão X (fechar) à direita.
	var topbar := HBoxContainer.new()
	topbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topbar.add_child(spacer)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(40, 40)
	if _font != null:
		close_btn.add_theme_font_override("font", _font)
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.add_theme_color_override("font_color", _GOLD)
	close_btn.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	close_btn.pressed.connect(_close)
	topbar.add_child(close_btn)
	vbox.add_child(topbar)

	# Scroll preenche a altura restante do painel → conteúdo nunca corta na tela.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(348, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	_layout_panel()


## Posiciona o painel encostado na direita, altura cheia, com base no viewport.
func _layout_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var h: float = maxf(0.0, vp.y - 2.0 * _PANEL_MARGIN)
	_panel.custom_minimum_size = Vector2(_PANEL_W, h)
	_panel.size = Vector2(_PANEL_W, h)
	_panel.position = Vector2(vp.x - _PANEL_W - _PANEL_MARGIN, _PANEL_MARGIN)


# ───────────────────────── API ─────────────────────────

func open(row: Dictionary) -> void:
	# Garante o posicionamento correto agora que o layout já assentou (open é
	# chamado via call_deferred, depois do _ready e do primeiro layout).
	_layout_panel()
	for c in _content.get_children():
		c.queue_free()

	# Cabeçalho.
	_add_title(str(row.get("nickname", "?")))
	var t21: int = int(row.get("time_to_w21_ms", -1))
	var time_str: String = _format_time(int(row.get("time_ms", 0)))
	if t21 > 0:
		time_str = _format_time(t21)
	_add_subtitle("Wave %d · %s · %d pts" % [int(row.get("wave", 0)), time_str, int(row.get("score", 0))])
	_add_separator()

	var build: Dictionary = row.get("build", {}) if typeof(row.get("build")) == TYPE_DICTIONARY else {}
	var upgrades: Dictionary = build.get("upgrades", {}) if typeof(build.get("upgrades")) == TYPE_DICTIONARY else {}
	var items: Array = build.get("items", []) if typeof(build.get("items")) == TYPE_ARRAY else []

	if upgrades.is_empty() and items.is_empty():
		_add_none_label()
		return

	# Categorias de upgrade (texto).
	for cat in _CATEGORIES:
		var rows: Array = []
		for entry in cat["entries"]:
			var id: String = entry[0]
			var lvl: int = int(upgrades.get(id, 0))
			if lvl > 0:
				rows.append([entry[1], lvl])
		if rows.is_empty():
			continue
		_add_category_title(tr(cat["title"]))
		for r in rows:
			_add_upgrade_row(tr(r[0]), int(r[1]))

	# Itens (ícones).
	if not items.is_empty():
		_add_category_title(tr("LEADERBOARD_BUILD_CAT_ITEMS"))
		_add_item_icons(items)


# ───────────────────────── builders ─────────────────────────

func _add_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(l, 30, _GOLD)
	_content.add_child(l)


func _add_subtitle(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_style(l, 20, _DIM)
	_content.add_child(l)


func _add_separator() -> void:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 12)
	_content.add_child(s)


func _add_category_title(text: String) -> void:
	var l := Label.new()
	l.text = text
	_style(l, 22, _GOLD)
	l.add_theme_constant_override("line_spacing", 8)
	_content.add_child(l)


func _add_upgrade_row(name_text: String, lvl: int) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_l := Label.new()
	name_l.text = name_text
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style(name_l, 22, _TEXT)
	var lvl_l := Label.new()
	lvl_l.text = "Lv.%d" % lvl
	lvl_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style(lvl_l, 22, _GOLD)
	row.add_child(name_l)
	row.add_child(lvl_l)
	_content.add_child(row)


func _add_item_icons(items: Array) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for id_v in items:
		var id: String = str(id_v)
		if not InventoryItems.ITEMS.has(id):
			continue
		var data: Dictionary = InventoryItems.ITEMS[id]
		var tex_rect := TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(48, 48)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_path: String = str(data.get("icon", ""))
		if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
			tex_rect.texture = load(icon_path)
		tex_rect.tooltip_text = tr(str(data.get("name", id)))
		flow.add_child(tex_rect)
	_content.add_child(flow)


func _add_none_label() -> void:
	var l := Label.new()
	l.text = tr("LEADERBOARD_BUILD_NONE")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_style(l, 22, _DIM)
	_content.add_child(l)


func _style(l: Label, size: int, color: Color) -> void:
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)


func _format_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	return "%d:%02d" % [total_sec / 60, total_sec % 60]


func _close() -> void:
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()
