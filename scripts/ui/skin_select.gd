extends Control

# Tela "Player": preview animado + abas por slot + grid de cards de skin +
# painel de stats persistentes (progresso entre runs).
#
# - SkinLoadout.scan_available_parts() lê PNGs de assets/player/<slot>/.
# - Cards lockados mostram a quest.label (ex: "Alcance a raid 10").
# - Cards com quest.hidden=true são escondidos enquanto não desbloqueados.
# - Stats panel mostra max_wave_reached, enemies_killed_total, dmg_dealt_total,
#   runs_completed (não mostra runs_no_damage por design).

const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const _NONE_LABEL: String = "COMMON_NONE"
const _IDLE_FRAME_REGION: Rect2 = Rect2(0, 0, 32, 32)

# Translation keys por slot — tr() onde o label é exibido (tabs).
const _SLOT_LABELS: Dictionary = {
	&"body":   "PLAYER_SLOT_BODY",
	&"legs":   "PLAYER_SLOT_LEGS",
	&"shirt":  "PLAYER_SLOT_SHIRT",
	&"alfaja": "PLAYER_SLOT_ALFAJA",
	&"cape":   "PLAYER_SLOT_CAPE",
	&"quiver": "PLAYER_SLOT_QUIVER",
	&"hair":   "PLAYER_SLOT_HAIR",
	&"bow":    "PLAYER_SLOT_BOW",
}

# Stats exibidos no painel de progresso (ordem importa). Cada entry = chave do
# stat + translation key do label. runs_no_damage NÃO entra aqui (decisão de design).
const _STAT_DISPLAY: Array = [
	{"key": &"max_wave_reached",     "label": "PLAYER_STAT_MAX_WAVE"},
	{"key": &"enemies_killed_total", "label": "PLAYER_STAT_KILLS"},
	{"key": &"dmg_dealt_total",      "label": "PLAYER_STAT_DAMAGE"},
	{"key": &"runs_completed",       "label": "PLAYER_STAT_RUNS"},
]

const _CARD_SIZE: Vector2 = Vector2(160, 200)
const _THUMBNAIL_SIZE: Vector2 = Vector2(140, 140)
const _TAB_BUTTON_SIZE: Vector2 = Vector2(0, 52)

@onready var preview: Node2D = $Center/Panel/Margin/VBox/Body/LeftCol/PreviewSection/PlayerPreview
@onready var stats_vbox: VBoxContainer = $Center/Panel/Margin/VBox/Body/LeftCol/StatsPanel/Margin/VBox
@onready var tabs_container: HBoxContainer = $Center/Panel/Margin/VBox/Body/EditSection/Tabs
@onready var empty_label: Label = $Center/Panel/Margin/VBox/Body/EditSection/EmptyLabel
@onready var cards_scroll: ScrollContainer = $Center/Panel/Margin/VBox/Body/EditSection/CardsScroll
@onready var cards_grid: GridContainer = $Center/Panel/Margin/VBox/Body/EditSection/CardsScroll/CardsGrid
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var save_button: Button = $Center/Panel/Margin/VBox/Buttons/SaveButton
@onready var back_button: Button = $Center/Panel/Margin/VBox/Buttons/BackButton

var _font: Font
var _available: Dictionary = {}
var _current: Dictionary = {}
var _active_slot: StringName = &""
var _tab_buttons: Dictionary = {}


func _ready() -> void:
	_font = load("res://font/ByteBounce.ttf")
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)

	_available = SkinLoadout.scan_available_parts()
	_current = SkinLoadout.load_loadout()
	_apply_to_preview()
	var preview_body: AnimatedSprite2D = preview.get_node("Body")
	if preview_body != null and preview_body.sprite_frames != null and preview_body.sprite_frames.has_animation("walk"):
		preview_body.play("walk")

	_build_stats_panel()
	_build_tabs()
	var first_slot: StringName = _first_slot_with_parts()
	if first_slot != &"":
		_set_active_slot(first_slot)
	else:
		empty_label.visible = true
		cards_scroll.visible = false


func _apply_to_preview() -> void:
	var skin: Node = preview.get_node("Skin")
	if skin == null or not skin.has_method("set_part"):
		return
	for slot in SkinLoadout.SLOTS:
		var part: SkinPart = _current.get(slot)
		skin.set_part(slot, part)


func _first_slot_with_parts() -> StringName:
	for slot in SkinLoadout.SLOTS:
		if (_available.get(slot, []) as Array).size() > 0:
			return slot
	return &""


# ---------- Stats panel ----------

func _build_stats_panel() -> void:
	for child in stats_vbox.get_children():
		child.queue_free()
	# Header
	var header := Label.new()
	header.text = "PLAYER_PROGRESS_HEADER"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _font != null:
		header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 26)
	header.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	stats_vbox.add_child(header)
	# Linhas
	for entry in _STAT_DISPLAY:
		var row: HBoxContainer = _make_stat_row(tr(String(entry.label)), int(SkinLoadout.get_stat(entry.key)))
		stats_vbox.add_child(row)


func _make_stat_row(label_text: String, value: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_label := Label.new()
	name_label.text = label_text + ":"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font != null:
		name_label.add_theme_font_override("font", _font)
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.95, 1))
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = _format_number(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _font != null:
		value_label.add_theme_font_override("font", _font)
	value_label.add_theme_font_size_override("font_size", 22)
	value_label.add_theme_color_override("font_color", Color(1, 0.92, 0.55, 1))
	row.add_child(value_label)
	return row


func _is_same_part(a: SkinPart, b: SkinPart) -> bool:
	# Considera "Nenhum" (null) igual a "Nenhum".
	if a == null and b == null:
		return true
	if a == null or b == null:
		return false
	if a.texture == null or b.texture == null:
		return false
	return a.texture.resource_path == b.texture.resource_path


func _format_number(n: int) -> String:
	# Adiciona separador de milhar (ex: 12345 → "12.345"). Sem locale fancy.
	var s: String = str(n)
	var neg: bool = s.begins_with("-")
	if neg:
		s = s.substr(1)
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count == 3 and i > 0:
			out = "." + out
			count = 0
	return ("-" + out) if neg else out


# ---------- Tabs ----------

func _build_tabs() -> void:
	for child in tabs_container.get_children():
		child.queue_free()
	_tab_buttons.clear()
	for slot in SkinLoadout.SLOTS:
		if (_available.get(slot, []) as Array).is_empty():
			continue
		var label: String = tr(String(_SLOT_LABELS.get(slot, String(slot))))
		var btn: Button = _make_tab_button(slot, label)
		tabs_container.add_child(btn)
		_tab_buttons[slot] = btn


func _make_tab_button(slot: StringName, label: String) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = _TAB_BUTTON_SIZE
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(_set_active_slot.bind(slot))
	return btn


func _set_active_slot(slot: StringName) -> void:
	_active_slot = slot
	_refresh_tab_highlights()
	_build_cards_for_slot(slot)


func _refresh_tab_highlights() -> void:
	for slot in _tab_buttons.keys():
		var btn: Button = _tab_buttons[slot]
		if slot == _active_slot:
			btn.add_theme_color_override("font_color", Color(1, 0.92, 0.4, 1))
			btn.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.6, 1))
		else:
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85, 1))
			btn.add_theme_color_override("font_hover_color", Color(0.95, 0.85, 1, 1))


# ---------- Cards ----------

func _build_cards_for_slot(slot: StringName) -> void:
	for child in cards_grid.get_children():
		child.queue_free()
	var parts: Array = (_available.get(slot, []) as Array).duplicate()
	if SkinLoadout.REMOVABLE_SLOTS.has(slot):
		parts.insert(0, null)  # "Nenhum" card primeiro
	for part in parts:
		# Pula skins hidden-locked (quest.hidden=true E ainda lockada).
		if part != null and SkinLoadout.is_hidden_locked(part):
			continue
		var card: Control = _make_card(slot, part)
		cards_grid.add_child(card)


func _make_card(slot: StringName, part: SkinPart) -> Control:
	var is_unlocked: bool = part == null or SkinLoadout.is_unlocked(part)
	var btn := Button.new()
	btn.custom_minimum_size = _CARD_SIZE
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = not is_unlocked
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 20)
	# Compara por texture path porque _current e _available vêm de scans diferentes —
	# instâncias de SkinPart com mesmo conteúdo são objetos distintos (== falha).
	var is_selected: bool = _is_same_part(_current.get(slot), part)
	btn.add_theme_stylebox_override("normal", _make_card_stylebox(is_selected, false))
	btn.add_theme_stylebox_override("hover", _make_card_stylebox(is_selected, true))
	btn.add_theme_stylebox_override("pressed", _make_card_stylebox(is_selected, true))
	btn.add_theme_stylebox_override("disabled", _make_card_stylebox(false, false))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var thumb_rect := TextureRect.new()
	thumb_rect.custom_minimum_size = _THUMBNAIL_SIZE
	thumb_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	thumb_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	thumb_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if part != null and part.texture != null:
		var thumb := AtlasTexture.new()
		thumb.atlas = part.texture
		thumb.region = _IDLE_FRAME_REGION
		thumb_rect.texture = thumb
	if not is_unlocked:
		thumb_rect.modulate = Color(0.4, 0.4, 0.4, 1)
	vbox.add_child(thumb_rect)

	# Label: display_name, "Nenhum", ou quest.label se lockada.
	var label := Label.new()
	if part == null:
		label.text = _NONE_LABEL
	elif not is_unlocked:
		var quest: Dictionary = SkinLoadout.get_quest_for(part.display_name)
		# quest.label é translation key — Label auto-traduz no assignment.
		label.text = String(quest.get("label", "COMMON_LOCKED"))
	else:
		label.text = part.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		label.add_theme_font_override("font", _font)
	# Label menor pra caber descrição de quest.
	label.add_theme_font_size_override("font_size", 18 if not is_unlocked and part != null else 22)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var label_color: Color
	if not is_unlocked:
		label_color = Color(0.95, 0.5, 0.5, 1)
	elif is_selected:
		label_color = Color(1, 0.92, 0.4, 1)
	else:
		label_color = Color(0.92, 0.88, 1, 1)
	label.add_theme_color_override("font_color", label_color)
	vbox.add_child(label)

	if is_unlocked:
		btn.pressed.connect(_on_card_picked.bind(slot, part))
	return btn


func _make_card_stylebox(selected: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if selected:
		sb.bg_color = Color(0.20, 0.14, 0.30, 1)
		sb.border_color = Color(1, 0.85, 0.35, 1)
	elif hover:
		sb.bg_color = Color(0.15, 0.10, 0.20, 1)
		sb.border_color = Color(0.7, 0.55, 0.85, 1)
	else:
		sb.bg_color = Color(0.10, 0.08, 0.14, 1)
		sb.border_color = Color(0.35, 0.25, 0.45, 1)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_detail = 1
	return sb


func _on_card_picked(slot: StringName, part: SkinPart) -> void:
	_current[slot] = part
	var skin: Node = preview.get_node("Skin")
	if skin != null and skin.has_method("set_part"):
		skin.set_part(slot, part)
	_build_cards_for_slot(slot)
	status_label.text = ""


# ---------- Save / Back ----------

func _on_save() -> void:
	SkinLoadout.save_loadout(_current)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1))
	status_label.text = "COMMON_SAVED"


func _on_back() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
