extends CanvasLayer

# Painel TAB: enquanto TAB está segurado, mostra o breakdown de dano causado
# pelo player na wave atual, agrupado por fonte (flecha, multi, ricochete,
# DoTs, aliados, etc.) e ordenado por valor decrescente.
#
# Autoload pra funcionar em qualquer cena — durante gameplay (HUD layer 50) e
# durante o WaveShop (layer 50). Esse layer fica em 100, acima dos dois, então
# o painel sobrepõe HUD/shop quando aberto. Lê wave_damage_by_source do player.
#
# O dict é resetado pelo wave_manager no início de cada wave, então no shop o
# painel mostra os dados da wave que acabou.

const PANEL_LAYER: int = 100
const PANEL_BG_COLOR := Color(0.08, 0.06, 0.12, 0.94)
const PANEL_BORDER_COLOR := Color(0.55, 0.4, 0.7, 1)
const TITLE_COLOR := Color(0.95, 0.85, 1, 1)
const ROW_COLOR := Color(0.85, 0.85, 0.95, 1)
const VALUE_COLOR := Color(1, 0.85, 0.35, 1)
const TOTAL_COLOR := Color(1, 0.7, 0.85, 1)
const FONT_PATH: String = "res://font/ByteBounce.ttf"

# Mapeia source_id (interno) → translation key (label exibida ao jogador).
# IDs sem entrada aqui caem em fallback exibindo o próprio id.
const SOURCE_LABELS: Dictionary = {
	"arrow_base": "DMG_PANEL_ARROW",
	"multi_arrow": "DMG_PANEL_MULTI_ARROW",
	"double_arrows": "DMG_PANEL_DOUBLE_ARROWS",
	"perfuracao": "DMG_PANEL_PERFURACAO",
	"ricochet": "DMG_PANEL_RICOCHET",
	"fire_arrow": "DMG_PANEL_FIRE_DOT",
	"fire_skill": "DMG_PANEL_FIRE_SKILL",
	"curse_arrow": "DMG_PANEL_CURSE_DOT",
	"curse_skill": "DMG_PANEL_CURSE_SKILL",
	"ice_arrow": "DMG_PANEL_ICE_DOT",
	"chain_lightning": "DMG_PANEL_CHAIN",
	"chain_lightning_skill": "DMG_PANEL_CHAIN_SKILL",
	"graviton": "DMG_PANEL_GRAVITON",
	"boomerang": "DMG_PANEL_BOOMERANG",
	"arrow_tower": "DMG_PANEL_TOWER",
	"ting_turret": "DMG_PANEL_TING",
	"woodwarden": "DMG_PANEL_WOODWARDEN",
	"leno": "DMG_PANEL_LENO",
	"capivara_joe": "DMG_PANEL_CAPIVARA",
	"curse_ally": "DMG_PANEL_CURSE_ALLY",
}

var _panel: PanelContainer = null
var _vbox: VBoxContainer = null
var _title: Label = null
var _total_label: Label = null
var _font: Font = null


func _ready() -> void:
	layer = PANEL_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = load(FONT_PATH) as Font
	_build_ui()
	_panel.visible = false


func _process(_delta: float) -> void:
	# Só ativa se a action existir (cenas sem input mapeado simplesmente ignoram).
	if not InputMap.has_action("damage_panel"):
		return
	var holding: bool = Input.is_action_pressed("damage_panel")
	if holding:
		if not _panel.visible:
			_panel.visible = true
		_refresh()
	elif _panel.visible:
		_panel.visible = false


func _build_ui() -> void:
	var root_ctrl := Control.new()
	root_ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_ctrl)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.offset_left = -260
	_panel.offset_right = 260
	_panel.offset_top = 90
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	_panel.add_theme_stylebox_override("panel", style)
	root_ctrl.add_child(_panel)

	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", 6)
	_panel.add_child(_vbox)

	_title = Label.new()
	_title.add_theme_color_override("font_color", TITLE_COLOR)
	_title.add_theme_font_size_override("font_size", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		_title.add_theme_font_override("font", _font)
	_title.text = "DMG_PANEL_TITLE"
	_vbox.add_child(_title)

	_total_label = Label.new()
	_total_label.add_theme_color_override("font_color", TOTAL_COLOR)
	_total_label.add_theme_font_size_override("font_size", 20)
	_total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		_total_label.add_theme_font_override("font", _font)
	_vbox.add_child(_total_label)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	_vbox.add_child(sep)


func _refresh() -> void:
	# Remove linhas antigas (mantém os 3 primeiros nós: título, total, separador).
	for i in range(_vbox.get_child_count() - 1, 2, -1):
		_vbox.get_child(i).queue_free()

	var p := get_tree().get_first_node_in_group("player")
	if p == null or not ("wave_damage_by_source" in p):
		_total_label.text = tr("DMG_PANEL_EMPTY")
		return

	var dict: Dictionary = p.wave_damage_by_source
	var entries: Array = []
	var total: float = 0.0
	for k in dict.keys():
		var amount: float = float(dict[k])
		if amount <= 0.0:
			continue
		entries.append([str(k), amount])
		total += amount
	entries.sort_custom(func(a, b): return a[1] > b[1])

	_total_label.text = tr("DMG_PANEL_TOTAL") % int(round(total))

	if entries.is_empty():
		var lbl := Label.new()
		lbl.text = tr("DMG_PANEL_EMPTY")
		lbl.add_theme_color_override("font_color", ROW_COLOR)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if _font != null:
			lbl.add_theme_font_override("font", _font)
		_vbox.add_child(lbl)
		return

	for entry in entries:
		var sid: String = entry[0]
		var amount: float = entry[1]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)

		var name_lbl := Label.new()
		var key: String = SOURCE_LABELS.get(sid, "")
		name_lbl.text = tr(key) if not key.is_empty() else sid
		name_lbl.add_theme_color_override("font_color", ROW_COLOR)
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _font != null:
			name_lbl.add_theme_font_override("font", _font)
		row.add_child(name_lbl)

		var val_lbl := Label.new()
		val_lbl.text = str(int(round(amount)))
		val_lbl.add_theme_color_override("font_color", VALUE_COLOR)
		val_lbl.add_theme_font_size_override("font_size", 22)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if _font != null:
			val_lbl.add_theme_font_override("font", _font)
		row.add_child(val_lbl)

		_vbox.add_child(row)
