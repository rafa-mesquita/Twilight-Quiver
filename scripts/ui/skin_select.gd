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
# Sentinel slot pra tab de "Kits" (aplica skin inteira em todos os slots de uma vez).
# Não bate com nenhum slot real de SkinLoadout.SLOTS.
const _KIT_SLOT: StringName = &"_kit"
# Quantos slots distintos um display_name precisa ocupar pra ser considerado um "kit".
const _KIT_MIN_SLOTS: int = 2
# Ordem de empilhamento do thumbnail de kit (back → front). Bate com a ordem
# das camadas em scenes/ui/player_preview.tscn.
# `bow_back` é pseudo-slot — usa o `texture_back` da SkinPart do bow. Só o arco
# de TRÁS entra no thumbnail (pose idle): o arco da frente só aparece no meio do
# ataque in-game, então incluí-lo aqui mostrava dois arcos sobrepostos.
const _KIT_LAYER_ORDER: Array[StringName] = [
	&"bow_back", &"body", &"legs", &"quiver", &"shirt", &"alfaja", &"cape", &"hair"
]

# Translation keys por slot — tr() onde o label é exibido (tabs).
const _SLOT_LABELS: Dictionary = {
	&"_kit":   "PLAYER_SLOT_KITS",
	&"body":   "PLAYER_SLOT_BODY",
	&"legs":   "PLAYER_SLOT_LEGS",
	&"shirt":  "PLAYER_SLOT_SHIRT",
	&"alfaja": "PLAYER_SLOT_ALFAJA",
	&"cape":   "PLAYER_SLOT_CAPE",
	&"quiver": "PLAYER_SLOT_QUIVER",
	&"hair":   "PLAYER_SLOT_HAIR",
	&"bow":    "PLAYER_SLOT_BOW",
}

# Ordem das abas por slot (UI only). Desacoplado de SkinLoadout.SLOTS: este
# array controla SÓ a ordem/visibilidade das abas. SLOTS segue a ordem de
# dados (save/load/apply). "Kits" entra à parte (sempre primeiro). alfaja no
# fim: sem parts hoje, então a aba é pulada (invisível, sem efeito).
const _TAB_SLOT_ORDER: Array[StringName] = [
	&"body", &"hair", &"shirt", &"cape", &"legs", &"quiver", &"bow", &"alfaja"
]

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
@onready var shop_face: Node2D = $Center/Panel/Margin/VBox/Body/LeftCol/ShopFaceSection/PlayerFace
@onready var preview_section: Panel = $Center/Panel/Margin/VBox/Body/LeftCol/PreviewSection
@onready var face_section: Panel = $Center/Panel/Margin/VBox/Body/LeftCol/ShopFaceSection
@onready var stats_vbox: VBoxContainer = $StatsOverlay
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
# Badges "!" sobre os quadros de preview (boneco + rosto) quando a seleção atual
# inclui alguma peça bloqueada.
var _preview_badge: Label
var _face_badge: Label
# Requisito de unlock (no topo do quadro do boneco) da última peça selecionada.
# _locked: desafio em vermelho (ainda bloqueada). _unlocked: mesmo desafio em
# branco (o que o jogador fez pra liberar a skin já desbloqueada).
var _req_label: Label
var _last_locked_quest_key: String = ""
var _last_unlocked_quest_key: String = ""
var _inv_mode: String = "skins"
var _mode_bar: HBoxContainer = null
var _mode_skins_btn: Button = null
var _mode_equip_btn: Button = null
var _equip_panel: Control = null
# Ícone sendo arrastado (escondido durante o drag → sensação de "mover"; restaurado
# no _process se o drag terminar sem drop válido).
var _dragging_icon: Control = null
var _drag_source: String = ""
var _drag_active: bool = false
var _drop_highlighted: Control = null
# Tooltip custom de item (hover) — o tooltip default não aparece com o cursor
# custom; este é um painel próprio mostrado no mouse_entered.
var _item_tip_panel: PanelContainer = null
var _item_tip_label: RichTextLabel = null


func _ready() -> void:
	_font = load("res://font/Silver.ttf")
	save_button.pressed.connect(_on_save)
	back_button.pressed.connect(_on_back)
	_setup_save_disabled_style()
	# Badges "!" nos quadros de preview (boneco + rosto), escondidos por padrão.
	_preview_badge = _make_lock_badge(47)
	preview_section.add_child(_preview_badge)
	_face_badge = _make_lock_badge(47)
	face_section.add_child(_face_badge)
	_req_label = _make_req_label()
	preview_section.add_child(_req_label)

	_available = SkinLoadout.scan_available_parts()
	_current = SkinLoadout.load_loadout()
	_apply_to_preview()
	_refresh_shop_face()
	_play_preview_walk()
	_update_lock_indicator()

	# Stats escondidas por enquanto (estavam deslocadas; novo lugar a definir).
	# Pra reativar: descomentar _build_stats_panel() e remover o .hide().
	stats_vbox.hide()
	#_build_stats_panel()
	_build_tabs()
	_build_petal_bank_display()
	_build_mode_bar()
	_build_equip_panel()
	_set_inv_mode("skins")
	# Abre na tab de Kits se existir, senão no primeiro slot com peças.
	var first_slot: StringName = _KIT_SLOT if not _list_available_kits().is_empty() else _first_slot_with_parts()
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


# Toca a animação walk no preview. Re-chamado depois de trocar peças: set_part(body)
# reconstrói o sprite_frames do AnimatedSprite2D, o que reseta pro frame 0 PARADO.
# Sem re-tocar, o modelo fica estático após escolher um kit (ou trocar o corpo).
func _play_preview_walk() -> void:
	var preview_body: AnimatedSprite2D = preview.get_node_or_null("Body") as AnimatedSprite2D
	if preview_body != null and preview_body.sprite_frames != null and preview_body.sprite_frames.has_animation("walk"):
		preview_body.play("walk")


# Atualiza o retrato do shop (rosto) com o loadout em edição — preview ao vivo.
func _refresh_shop_face() -> void:
	if shop_face != null and shop_face.has_method("apply_loadout"):
		shop_face.apply_loadout(_current)


func _first_slot_with_parts() -> StringName:
	for slot in SkinLoadout.SLOTS:
		if (_available.get(slot, []) as Array).size() > 0:
			return slot
	return &""


# ---------- Stats panel ----------

func _build_stats_panel() -> void:
	for child in stats_vbox.get_children():
		child.queue_free()
	# Header — discreto, fora do painel (margem esquerda da tela).
	var header := Label.new()
	header.text = "PLAYER_PROGRESS_HEADER"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if _font != null:
		header.add_theme_font_override("font", _font)
	header.add_theme_font_size_override("font_size", 19)
	header.add_theme_color_override("font_color", Color(0.62, 0.55, 0.74, 1))
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
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(0.55, 0.52, 0.64, 1))
	row.add_child(name_label)
	var value_label := Label.new()
	value_label.text = _format_number(value)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if _font != null:
		value_label.add_theme_font_override("font", _font)
	value_label.add_theme_font_size_override("font_size", 18)
	value_label.add_theme_color_override("font_color", Color(0.72, 0.66, 0.82, 1))
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
	# Kit tab primeiro — atalho pra equipar uma skin inteira de uma vez.
	if not _list_available_kits().is_empty():
		var kit_label: String = tr(String(_SLOT_LABELS[_KIT_SLOT]))
		var kit_btn: Button = _make_tab_button(_KIT_SLOT, kit_label)
		tabs_container.add_child(kit_btn)
		_tab_buttons[_KIT_SLOT] = kit_btn
	for slot in _TAB_SLOT_ORDER:
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
	btn.add_theme_font_size_override("font_size", 28)
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
	if slot == _KIT_SLOT:
		_build_kit_cards()
		return
	var parts: Array = (_available.get(slot, []) as Array).duplicate()
	# Ordem: desbloqueadas primeiro, Default primeiro, depois alfabética.
	parts.sort_custom(_part_sort_lt)
	# Decisão de design 0.5.7: NÃO inserir mais "Nenhum" como opção mesmo em
	# slots removíveis. Player sempre vê uma peça equipada.
	for part in parts:
		# Pula skins hidden-locked (quest.hidden=true E ainda lockada).
		if part != null and SkinLoadout.is_hidden_locked(part):
			continue
		var card: Control = _make_card(slot, part)
		cards_grid.add_child(card)


# ---------- Kits ----------

func _list_available_kits() -> Array:
	# Retorna display_names ordenados que aparecem em >= _KIT_MIN_SLOTS slots
	# (= são kits completos). Skins hidden-locked NÃO entram na listagem.
	var counts: Dictionary = {}
	var sample: Dictionary = {}  # name -> SkinPart (pra checar lock/hidden)
	for slot in SkinLoadout.SLOTS:
		var parts_arr: Array = _available.get(slot, [])
		for p in parts_arr:
			var part: SkinPart = p
			if part == null:
				continue
			var n: String = part.display_name
			counts[n] = int(counts.get(n, 0)) + 1
			if not sample.has(n):
				sample[n] = part
	var kits: Array = []
	for n in counts.keys():
		if int(counts[n]) < _KIT_MIN_SLOTS:
			continue
		# Peça partilhada (ex: "Hawk_Skeleton" = arco+aljava comum a 2 skins) ocupa
		# >= _KIT_MIN_SLOTS mas NÃO é um kit próprio — não lista como card de kit.
		if SkinLoadout.SHARED_PART_NAMES.has(n):
			continue
		var s: SkinPart = sample[n]
		# Hidden-locked = não aparece. Locked sem hidden = aparece como card travado.
		if SkinLoadout.is_hidden_locked(s):
			continue
		kits.append(String(n))
	# Ordem: desbloqueados primeiro, Default primeiro, depois alfabética.
	kits.sort_custom(_kit_sort_lt)
	return kits


# Comparadores de ordenação: desbloqueado vem antes de bloqueado; dentro do mesmo
# grupo, "Default" primeiro e depois alfabético (case-insensitive).
func _kit_sort_lt(a: String, b: String) -> bool:
	var au: bool = SkinLoadout.is_kit_unlocked(a)
	var bu: bool = SkinLoadout.is_kit_unlocked(b)
	if au != bu:
		return au
	if a == "Default" and b != "Default":
		return true
	if b == "Default" and a != "Default":
		return false
	return a.to_lower() < b.to_lower()


func _part_sort_lt(a: SkinPart, b: SkinPart) -> bool:
	var au: bool = a == null or SkinLoadout.is_unlocked(a)
	var bu: bool = b == null or SkinLoadout.is_unlocked(b)
	if au != bu:
		return au
	var an: String = a.display_name if a != null else ""
	var bn: String = b.display_name if b != null else ""
	if an == "Default" and bn != "Default":
		return true
	if bn == "Default" and an != "Default":
		return false
	return an.to_lower() < bn.to_lower()


func _build_kit_cards() -> void:
	for kit_name in _list_available_kits():
		var card: Control = _make_kit_card(kit_name)
		cards_grid.add_child(card)


func _make_kit_card(kit_name: String) -> Control:
	var kit_parts: Dictionary = SkinLoadout.get_parts_by_skin_name(kit_name)
	# Parts efetivas mostradas no preview = peças do kit + Default nos slots
	# que o kit não cobre (mesma regra do apply em _on_kit_picked).
	var preview_parts: Dictionary = kit_parts.duplicate()
	for slot in SkinLoadout.SLOTS:
		if preview_parts.has(slot):
			continue
		var def: SkinPart = _default_part_for_slot(slot)
		if def != null:
			preview_parts[slot] = def
	# Lock do kit vem da QUEST do NOME do kit — NÃO da peça body. O body de
	# Linked/Rosa_Onyx é sobrescrito pra "Linked_Pink" (sem quest), então checar
	# pela peça desbloqueava esses kits sem cumprir o desafio.
	var is_unlocked: bool = SkinLoadout.is_kit_unlocked(kit_name)
	var is_selected: bool = _is_kit_currently_selected(kit_parts)

	var btn := Button.new()
	btn.custom_minimum_size = _CARD_SIZE
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = false  # bloqueada continua clicável (preview); só o Salvar trava
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 23)
	btn.add_theme_stylebox_override("normal", _make_card_stylebox(is_selected, false))
	btn.add_theme_stylebox_override("hover", _make_card_stylebox(is_selected, true))
	btn.add_theme_stylebox_override("pressed", _make_card_stylebox(is_selected, true))

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 6)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(vbox)

	var thumb: Control = _make_kit_thumbnail(preview_parts, not is_unlocked)
	vbox.add_child(thumb)

	var label := Label.new()
	label.text = kit_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 25)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", _card_label_color(is_unlocked, is_selected))
	vbox.add_child(label)

	if not is_unlocked:
		# Nome em vermelho (via _card_label_color) + "!" no canto + quest no tooltip.
		var quest: Dictionary = SkinLoadout.get_quest_for(kit_name)
		btn.tooltip_text = tr(String(quest.get("label", "COMMON_LOCKED")))
		btn.add_child(_make_lock_badge(33))

	btn.pressed.connect(_on_kit_picked.bind(kit_name))
	return btn


func _is_kit_currently_selected(kit_parts: Dictionary) -> bool:
	# Kit "ativo" = todos os slots batem: peças do kit nos slots que ele cobre,
	# Default (ou null em removíveis sem Default) nos slots ausentes.
	if kit_parts.is_empty():
		return false
	for slot in SkinLoadout.SLOTS:
		if kit_parts.has(slot):
			if not _is_same_part(_current.get(slot), kit_parts[slot]):
				return false
		else:
			var expected: SkinPart = _default_part_for_slot(slot)
			if expected == null and not SkinLoadout.REMOVABLE_SLOTS.has(slot):
				# Slot não-removível sem Default — ignora na comparação.
				continue
			if not _is_same_part(_current.get(slot), expected):
				return false
	return true


func _make_kit_thumbnail(parts: Dictionary, locked: bool) -> Control:
	# Container do tamanho do thumbnail com TextureRects empilhados em camadas.
	# Cada camada renderiza o frame 0 (idle) da textura do slot — visualmente
	# equivalente ao preview animado, mas estático.
	var holder := Control.new()
	holder.custom_minimum_size = _THUMBNAIL_SIZE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for slot in _KIT_LAYER_ORDER:
		# `bow_back` é pseudo-slot: usa o texture_back da SkinPart do bow.
		var part: SkinPart
		var texture: Texture2D
		if slot == &"bow_back":
			part = parts.get(&"bow")
			texture = part.texture_back if part != null else null
		else:
			part = parts.get(slot)
			texture = part.texture if part != null else null
		if texture == null:
			continue
		var layer := TextureRect.new()
		layer.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = _IDLE_FRAME_REGION
		layer.texture = atlas
		if locked:
			layer.modulate = Color(0.4, 0.4, 0.4, 1)
		holder.add_child(layer)
	return holder


func _default_part_for_slot(slot: StringName) -> SkinPart:
	# Procura uma peça com display_name == "Default" no slot. Usada como
	# fallback quando um kit não cobre todos os slots.
	for p in (_available.get(slot, []) as Array):
		var part: SkinPart = p
		if part != null and part.display_name == "Default":
			return part
	return null


func _on_kit_picked(kit_name: String) -> void:
	var kit_parts: Dictionary = SkinLoadout.get_parts_by_skin_name(kit_name)
	for slot in SkinLoadout.SLOTS:
		if kit_parts.has(slot):
			_current[slot] = kit_parts[slot]
		else:
			# Sem peça do kit pra esse slot — usa Default. Se não tem Default
			# nem é removível, mantém o atual (caso raro).
			var default_part: SkinPart = _default_part_for_slot(slot)
			if default_part != null:
				_current[slot] = default_part
			elif SkinLoadout.REMOVABLE_SLOTS.has(slot):
				_current[slot] = null
	# Guarda a quest do kit pro requisito no topo do preview: vermelho se ainda
	# bloqueado, branco (o que liberou) se já desbloqueado. Kit sem quest limpa.
	var kit_quest_key: String = String(SkinLoadout.get_quest_for(kit_name).get("label", ""))
	if not SkinLoadout.is_kit_unlocked(kit_name):
		_last_locked_quest_key = kit_quest_key
	else:
		_last_unlocked_quest_key = kit_quest_key
	_apply_to_preview()
	_refresh_shop_face()
	_play_preview_walk()
	_update_lock_indicator()
	_build_cards_for_slot(_KIT_SLOT)
	status_label.text = ""


func _make_card(slot: StringName, part: SkinPart) -> Control:
	var is_unlocked: bool = part == null or SkinLoadout.is_unlocked(part)
	var btn := Button.new()
	btn.custom_minimum_size = _CARD_SIZE
	btn.toggle_mode = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = false  # bloqueada continua clicável (preview); só o Salvar trava
	if _font != null:
		btn.add_theme_font_override("font", _font)
	btn.add_theme_font_size_override("font_size", 23)
	# Compara por texture path porque _current e _available vêm de scans diferentes —
	# instâncias de SkinPart com mesmo conteúdo são objetos distintos (== falha).
	var is_selected: bool = _is_same_part(_current.get(slot), part)
	btn.add_theme_stylebox_override("normal", _make_card_stylebox(is_selected, false))
	btn.add_theme_stylebox_override("hover", _make_card_stylebox(is_selected, true))
	btn.add_theme_stylebox_override("pressed", _make_card_stylebox(is_selected, true))

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

	# Label: sempre o nome (ou "Nenhum"); vermelho quando bloqueada.
	var label := Label.new()
	if part == null:
		label.text = _NONE_LABEL
	else:
		label.text = part.display_name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", 25)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", _card_label_color(is_unlocked, is_selected))
	vbox.add_child(label)

	if not is_unlocked and part != null:
		# Nome em vermelho + "!" no canto + quest no tooltip (hover).
		var quest: Dictionary = SkinLoadout.get_quest_for(part.display_name)
		btn.tooltip_text = tr(String(quest.get("label", "COMMON_LOCKED")))
		btn.add_child(_make_lock_badge(33))

	btn.pressed.connect(_on_card_picked.bind(slot, part))
	return btn


func _make_card_stylebox(selected: bool, hover: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	if selected:
		# Selecionado: um pouco mais claro que o default + borda amarela.
		sb.bg_color = Color(0.28, 0.20, 0.40, 1)
		sb.border_color = Color(1, 0.85, 0.35, 1)
	elif hover:
		sb.bg_color = Color(0.21, 0.15, 0.32, 1)
		sb.border_color = Color(0.7, 0.55, 0.85, 1)
	else:
		# Default = #271b3d (um pouco mais escuro).
		sb.bg_color = Color(0.152941, 0.105882, 0.239216, 1)
		sb.border_color = Color(0.35, 0.25, 0.45, 1)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_detail = 1
	return sb


func _on_card_picked(slot: StringName, part: SkinPart) -> void:
	_current[slot] = part
	# Guarda a quest da peça pro requisito no topo do preview: vermelho se ainda
	# bloqueada, branco (o que liberou) se já desbloqueada. Peça sem quest limpa.
	if part != null:
		var quest_key: String = String(SkinLoadout.get_quest_for(part.display_name).get("label", ""))
		if not SkinLoadout.is_unlocked(part):
			_last_locked_quest_key = quest_key
		else:
			_last_unlocked_quest_key = quest_key
	var skin: Node = preview.get_node("Skin")
	if skin != null and skin.has_method("set_part"):
		skin.set_part(slot, part)
	# Trocar o corpo reconstrói o sprite_frames e para a anim — re-toca o walk.
	if slot == &"body":
		_play_preview_walk()
	_refresh_shop_face()
	_update_lock_indicator()
	_build_cards_for_slot(slot)
	status_label.text = ""


# ---------- Lock state (preview tint + "!" badge + Save trava) ----------

func _card_label_color(is_unlocked: bool, is_selected: bool) -> Color:
	if not is_unlocked:
		return Color(0.95, 0.3, 0.3, 1)  # vermelho = bloqueada
	if is_selected:
		return Color(1, 0.92, 0.4, 1)
	return Color(0.92, 0.88, 1, 1)


# "!" pra marcar bloqueio — usado nos cards e nos quadros de preview.
func _make_lock_badge(font_size: int) -> Label:
	var badge := Label.new()
	badge.text = "!"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	if _font != null:
		badge.add_theme_font_override("font", _font)
	badge.add_theme_font_size_override("font_size", font_size)
	badge.add_theme_color_override("font_color", Color(1, 0.25, 0.25, 1))
	badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	badge.add_theme_constant_override("outline_size", 5)
	# Canto superior direito do pai.
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.offset_left = -float(font_size) - 10.0
	badge.offset_right = -8.0
	badge.offset_top = 2.0
	badge.offset_bottom = float(font_size) + 8.0
	return badge


# Label de requisito no TOPO do quadro do boneco (mesma faixa do "!"): mostra
# como liberar a última peça bloqueada selecionada.
func _make_req_label() -> Label:
	var lbl := Label.new()
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.visible = false
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if _font != null:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.98, 0.4, 0.4, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	# Faixa no topo, deixando o canto direito livre pro "!".
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.0
	lbl.anchor_bottom = 0.0
	lbl.offset_left = 8.0
	lbl.offset_right = -52.0
	lbl.offset_top = 6.0
	lbl.offset_bottom = 64.0
	return lbl


# Fallback (estado inicial): quest da primeira peça bloqueada da seleção.
func _first_locked_quest_key() -> String:
	for slot in SkinLoadout.SLOTS:
		var part: SkinPart = _current.get(slot)
		if part != null and not SkinLoadout.is_unlocked(part):
			return String(SkinLoadout.get_quest_for(part.display_name).get("label", ""))
	return ""


# Fallback (estado inicial): quest da primeira peça LIBERADA com desafio. Mostra
# em branco o que o jogador fez pra liberar a skin equipada ao abrir a tela.
func _first_unlocked_quest_key() -> String:
	for slot in SkinLoadout.SLOTS:
		var part: SkinPart = _current.get(slot)
		if part != null and SkinLoadout.is_unlocked(part):
			var key: String = String(SkinLoadout.get_quest_for(part.display_name).get("label", ""))
			if key != "":
				return key
	return ""


# Alguma peça da seleção atual está bloqueada?
func _selection_has_locked() -> bool:
	for slot in SkinLoadout.SLOTS:
		var part: SkinPart = _current.get(slot)
		if part != null and not SkinLoadout.is_unlocked(part):
			return true
	return false


# Reflete o estado de bloqueio: filtro vermelho leve + "!" nos quadros de preview
# e trava o botão Salvar quando a seleção inclui peça bloqueada.
func _update_lock_indicator() -> void:
	var locked: bool = _selection_has_locked()
	save_button.disabled = locked
	var tint: Color = Color(1, 0.7, 0.7, 1) if locked else Color(1, 1, 1, 1)
	if preview != null:
		preview.modulate = tint
	if shop_face != null:
		shop_face.modulate = tint
	if _preview_badge != null:
		_preview_badge.visible = locked
	if _face_badge != null:
		_face_badge.visible = locked
	# Requisito no topo do quadro do boneco: vermelho se a seleção tem peça
	# bloqueada (o que falta), branco se está liberada (o que o jogador fez).
	if _req_label != null:
		if locked:
			var req_key: String = _last_locked_quest_key
			if req_key == "":
				req_key = _first_locked_quest_key()
			_req_label.visible = req_key != ""
			if _req_label.visible:
				_req_label.text = tr(req_key) + SkinLoadout.progress_suffix_for_label(req_key)
				_req_label.add_theme_color_override("font_color", Color(0.98, 0.4, 0.4, 1))
		else:
			var req_key: String = _last_unlocked_quest_key
			if req_key == "":
				req_key = _first_unlocked_quest_key()
			_req_label.visible = req_key != ""
			if _req_label.visible:
				_req_label.text = tr(req_key)
				_req_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _setup_save_disabled_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.07, 0.1, 1)
	sb.border_color = Color(0.22, 0.18, 0.28, 1)
	sb.border_width_left = 4
	sb.border_width_top = 4
	sb.border_width_right = 4
	sb.border_width_bottom = 4
	sb.corner_detail = 1
	save_button.add_theme_stylebox_override("disabled", sb)
	save_button.add_theme_color_override("font_disabled_color", Color(0.5, 0.42, 0.55, 1))


# ---------- Save / Back ----------

func _on_save() -> void:
	if _selection_has_locked():
		return  # não salva loadout com peça bloqueada (o botão já fica disabled)
	SkinLoadout.save_loadout(_current)
	status_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55, 1))
	status_label.text = "COMMON_SAVED"


func _on_back() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)


# ---------- Inventário: modos (Skins / Equipamentos) + banco ----------

func _build_petal_bank_display() -> void:
	var holder := Control.new()
	holder.name = "PetalBankDisplay"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	holder.offset_left = -260.0
	holder.offset_top = 24.0
	holder.offset_right = -24.0
	holder.offset_bottom = 70.0
	add_child(holder)
	var icon := Sprite2D.new()
	icon.texture = load("res://assets/Hud/petals.png") as Texture2D
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(16, 22)
	icon.scale = Vector2(1.8, 1.8)
	holder.add_child(icon)
	var lbl := Label.new()
	lbl.offset_left = 40.0
	lbl.offset_right = 240.0
	lbl.offset_bottom = 46.0
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 34)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.62, 0.82, 1.0))
	lbl.text = str(PetalBank.get_total())
	holder.add_child(lbl)


func _build_mode_bar() -> void:
	var edit: Node = tabs_container.get_parent()
	_mode_bar = HBoxContainer.new()
	_mode_bar.name = "ModeBar"
	_mode_bar.add_theme_constant_override("separation", 8)
	edit.add_child(_mode_bar)
	edit.move_child(_mode_bar, 0)
	_mode_skins_btn = _make_mode_button("INVENTORY_MODE_SKINS", "skins")
	_mode_equip_btn = _make_mode_button("INVENTORY_MODE_EQUIP", "equip")
	_mode_bar.add_child(_mode_skins_btn)
	_mode_bar.add_child(_mode_equip_btn)


func _make_mode_button(key: String, mode: String) -> Button:
	var b := Button.new()
	b.text = tr(key)
	b.custom_minimum_size = Vector2(0, 56)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	if _font != null:
		b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(_set_inv_mode.bind(mode))
	return b


func _set_inv_mode(mode: String) -> void:
	_inv_mode = mode
	var is_skins: bool = mode == "skins"
	tabs_container.visible = is_skins
	cards_scroll.visible = is_skins
	if not is_skins:
		empty_label.visible = false
	if _equip_panel != null:
		_equip_panel.visible = not is_skins
		if not is_skins:
			_refresh_equip_ui()
	var on := Color(1, 0.92, 0.4, 1)
	var off := Color(0.7, 0.7, 0.85, 1)
	if _mode_skins_btn != null:
		_mode_skins_btn.add_theme_color_override("font_color", on if is_skins else off)
	if _mode_equip_btn != null:
		_mode_equip_btn.add_theme_color_override("font_color", off if is_skins else on)


# ---------- Equipamentos (slots + drag-and-drop) ----------

func _build_equip_panel() -> void:
	var edit: Node = tabs_container.get_parent()
	_equip_panel = HBoxContainer.new()
	_equip_panel.name = "EquipPanel"
	_equip_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_equip_panel.add_theme_constant_override("separation", 24)
	edit.add_child(_equip_panel)
	# Coluna VERTICAL dos 3 slots (à direita do preview da skin).
	var slots_row := VBoxContainer.new()
	slots_row.name = "SlotsRow"
	slots_row.add_theme_constant_override("separation", 14)
	slots_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_equip_panel.add_child(slots_row)
	# Área de itens possuídos à DIREITA dos slots (drop zone pra desequipar).
	var owned_panel := PanelContainer.new()
	owned_panel.name = "OwnedPanel"
	owned_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	owned_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	owned_panel.add_theme_stylebox_override("panel", _pool_stylebox(false))
	owned_panel.set_drag_forwarding(Callable(), _owned_can_drop, _owned_drop)
	_equip_panel.add_child(owned_panel)
	# Pool: LIBERADOS (fileira de cima) separados dos TRAVADOS (fileira de baixo).
	var content := VBoxContainer.new()
	content.name = "OwnedContent"
	content.add_theme_constant_override("separation", 8)
	owned_panel.add_child(content)
	content.add_child(_make_section_label("INVENTORY_UNLOCKED", Color(0.78, 0.74, 0.92, 1)))
	content.add_child(_make_owned_grid("UnlockedGrid"))
	content.add_child(HSeparator.new())
	content.add_child(_make_section_label("INVENTORY_LOCKED", Color(0.9, 0.55, 0.55, 1)))
	content.add_child(_make_owned_grid("LockedGrid"))
	_equip_panel.visible = false


func _refresh_equip_ui() -> void:
	if _equip_panel == null:
		return
	# Limpa qualquer highlight de drop preso (ex.: após soltar no pool).
	_drop_highlighted = null
	_clear_drop_highlights()
	var slots_row: Node = _equip_panel.get_node("SlotsRow")
	for c in slots_row.get_children():
		c.queue_free()
	var equipped: Array = InventoryItems.get_equipped()
	for idx in InventoryItems.MAX_SLOTS:
		var eid: String = String(equipped[idx]) if idx < equipped.size() else ""
		slots_row.add_child(_make_slot(idx, eid))
	var unlocked_grid: Node = _equip_panel.get_node("OwnedPanel/OwnedContent/UnlockedGrid")
	var locked_grid: Node = _equip_panel.get_node("OwnedPanel/OwnedContent/LockedGrid")
	for c in unlocked_grid.get_children():
		c.queue_free()
	for c in locked_grid.get_children():
		c.queue_free()
	for id in InventoryItems.all_ids():
		var sid: String = String(id)
		if InventoryItems.is_equipped(sid):
			continue
		if InventoryItems.is_unlocked(sid):
			unlocked_grid.add_child(_make_item_card(sid, true))
		else:
			locked_grid.add_child(_make_item_card(sid, false))


func _make_item_texture(id: String, box: float) -> TextureRect:
	var item: Dictionary = InventoryItems.ITEMS.get(id, {})
	var t := TextureRect.new()
	t.texture = load(String(item.get("icon", ""))) as Texture2D
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.custom_minimum_size = Vector2(box, box)
	return t


func _item_tooltip(id: String) -> String:
	var item: Dictionary = InventoryItems.ITEMS.get(id, {})
	var name_line: String = tr(String(item.get("name", id)))
	var desc: String = tr(String(item.get("desc", "")))
	# Efeito (o que o item FAZ) aparece SEMPRE, mesmo travado.
	var out: String = "[b]%s[/b]\n[color=#cdbfe6]%s[/color]" % [name_line, desc]
	if InventoryItems.is_unlocked(id):
		return out
	# Travado: secao "como liberar" com requisitos coloridos (verde=feito, vermelho=falta).
	var ut: String = String(item.get("unlock", {}).get("type", ""))
	out += "\n\n[color=#c9a6ff]%s[/color]" % tr("ITEM_UNLOCK_HOW")
	if ut == "shop":
		out += "\n[color=#bfd4e8]%s[/color]" % tr("ITEM_UNLOCK_SHOP")
		return out
	for req in InventoryItems.get_unlock_reqs(id):
		var met: bool = bool(req.get("met", false))
		var col: String = "#8de88d" if met else "#ff8a8a"
		var mark: String = "·" if met else "▸"
		out += "\n[color=%s]%s %s[/color]" % [col, mark, tr(String(req.get("label", "")))]
	return out


func _ensure_item_tip() -> void:
	if _item_tip_panel != null:
		return
	_item_tip_panel = PanelContainer.new()
	_item_tip_panel.name = "ItemTooltip"
	_item_tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_item_tip_panel.z_index = 300
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.06, 0.12, 0.97)
	sb.border_color = Color(0.6, 0.45, 0.8, 1)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_item_tip_panel.add_theme_stylebox_override("panel", sb)
	_item_tip_panel.custom_minimum_size = Vector2(340, 0)
	_item_tip_label = RichTextLabel.new()
	_item_tip_label.bbcode_enabled = true
	_item_tip_label.fit_content = true
	_item_tip_label.scroll_active = false
	_item_tip_label.custom_minimum_size = Vector2(312, 0)
	if _font != null:
		_item_tip_label.add_theme_font_override("normal_font", _font)
		_item_tip_label.add_theme_font_override("bold_font", _font)
	_item_tip_label.add_theme_font_size_override("normal_font_size", 20)
	_item_tip_label.add_theme_font_size_override("bold_font_size", 25)
	_item_tip_label.add_theme_color_override("default_color", Color(0.92, 0.86, 1, 1))
	_item_tip_panel.add_child(_item_tip_label)
	add_child(_item_tip_panel)
	_item_tip_panel.visible = false


func _show_item_tooltip(id: String) -> void:
	_ensure_item_tip()
	_item_tip_label.text = _item_tooltip(id)
	_item_tip_panel.visible = true
	_position_item_tip()


func _hide_item_tooltip() -> void:
	if _item_tip_panel != null:
		_item_tip_panel.visible = false


func _position_item_tip() -> void:
	if _item_tip_panel == null or not _item_tip_panel.visible:
		return
	var mp: Vector2 = get_global_mouse_position()
	var sz: Vector2 = _item_tip_panel.size
	var vp: Vector2 = get_viewport_rect().size
	var pos: Vector2 = mp + Vector2(22, 18)
	pos.x = clampf(pos.x, 8.0, maxf(8.0, vp.x - sz.x - 8.0))
	pos.y = clampf(pos.y, 8.0, maxf(8.0, vp.y - sz.y - 8.0))
	_item_tip_panel.global_position = pos


func _make_item_card(id: String, unlocked: bool) -> Control:
	# Card do item: ícone + nome embaixo. Espalha pela largura (size flags expand).
	# Liberado = arrastável (equipar). Travado = ícone escurecido + "!" + nome vermelho.
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 4)
	var icon_wrap := Control.new()
	icon_wrap.custom_minimum_size = Vector2(88, 88)
	icon_wrap.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	icon_wrap.mouse_entered.connect(_show_item_tooltip.bind(id))
	icon_wrap.mouse_exited.connect(_hide_item_tooltip)
	var t := _make_item_texture(id, 88.0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		t.modulate = Color(0.5, 0.32, 0.36, 0.9)
	icon_wrap.add_child(t)
	if unlocked:
		icon_wrap.set_drag_forwarding(_get_item_drag_data.bind(id, "owned", icon_wrap), Callable(), Callable())
	else:
		icon_wrap.add_child(_make_lock_badge(28))
	card.add_child(icon_wrap)
	var name_lbl := Label.new()
	name_lbl.text = tr(String(InventoryItems.ITEMS.get(id, {}).get("name", id)))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(110, 0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", _card_label_color(unlocked, false))
	card.add_child(name_lbl)
	return card


func _make_slot(idx: int, equipped_id: String) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(104, 104)
	slot.add_theme_stylebox_override("panel", _slot_stylebox(false))
	slot.set_drag_forwarding(Callable(), _slot_can_drop, _slot_drop)
	if equipped_id != "":
		var t := _make_item_texture(equipped_id, 88.0)
		t.mouse_filter = Control.MOUSE_FILTER_STOP
		t.mouse_entered.connect(_show_item_tooltip.bind(equipped_id))
		t.mouse_exited.connect(_hide_item_tooltip)
		t.set_drag_forwarding(_get_item_drag_data.bind(equipped_id, "slot", t), Callable(), Callable())
		slot.add_child(t)
	return slot


func _make_drag_preview(id: String) -> Control:
	# Preview do mesmo tamanho do ícone (88), CENTRADO no cursor (filho deslocado
	# -metade) — senão o Godot ancora o canto superior-esquerdo no cursor.
	var root := Control.new()
	var box: float = 88.0
	var t := _make_item_texture(id, box)
	t.size = Vector2(box, box)
	t.position = Vector2(-box / 2.0, -box / 2.0)
	root.add_child(t)
	return root


func _get_item_drag_data(_at: Vector2, id: String, source: String, ctrl: Control) -> Variant:
	MenuAudio.play_click()  # som padrão ao PEGAR o item
	_hide_item_tooltip()  # esconde o tooltip enquanto arrasta
	set_drag_preview(_make_drag_preview(id))
	# Esconde o ícone de origem enquanto arrasta (parece que MOVE, não duplica).
	if is_instance_valid(ctrl):
		ctrl.modulate.a = 0.0
		_dragging_icon = ctrl
	_drag_source = source
	_drag_active = true
	return {"id": id, "source": source}


func _process(_delta: float) -> void:
	# Restaura o ícone escondido quando o drag termina sem drop válido (drop
	# válido rebuilda a UI e o ícone antigo é liberado).
	if _drag_active and not get_viewport().gui_is_dragging():
		_drag_active = false
		if _dragging_icon != null and is_instance_valid(_dragging_icon):
			_dragging_icon.modulate.a = 1.0
		_dragging_icon = null
		_drag_source = ""
		_clear_drop_highlights()
		_drop_highlighted = null
	elif _drag_active:
		_update_drop_highlight()
	_position_item_tip()


func _slot_can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and String(data.get("source", "")) == "owned"


func _slot_drop(_at: Vector2, data: Variant) -> void:
	if data is Dictionary and String(data.get("source", "")) == "owned":
		InventoryItems.toggle_equipped(String(data.get("id", "")))
		MenuAudio.play_drop()  # som ao SOLTAR no slot
		_refresh_equip_ui()


func _owned_can_drop(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and String(data.get("source", "")) == "slot"


func _owned_drop(_at: Vector2, data: Variant) -> void:
	if data is Dictionary and String(data.get("source", "")) == "slot":
		InventoryItems.toggle_equipped(String(data.get("id", "")))
		# Sem som ao desequipar (soltar "pra fora" do slot) — só toca ao soltar
		# DENTRO de um slot (em _slot_drop).
		_refresh_equip_ui()


# ---------- Inventário: secoes + highlight de drop ----------

func _make_section_label(key: String, col: Color) -> Label:
	var l := Label.new()
	l.text = tr(key)
	if _font != null:
		l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", col)
	return l


func _make_owned_grid(grid_name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = grid_name
	g.columns = 6
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g


func _slot_stylebox(highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	if highlight:
		sb.bg_color = Color(0.45, 0.9, 0.55, 0.15)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.55, 0.95, 0.62, 0.7)
	else:
		sb.bg_color = Color(0.10, 0.09, 0.14, 0.9)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.45, 0.42, 0.6, 1)
	return sb


func _pool_stylebox(highlight: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12.0
	sb.content_margin_top = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_bottom = 12.0
	if highlight:
		sb.bg_color = Color(0.45, 0.9, 0.55, 0.12)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.55, 0.95, 0.62, 0.65)
	else:
		sb.bg_color = Color(0.08, 0.07, 0.11, 0.6)
		sb.set_border_width_all(0)
	return sb


func _set_slots_highlight(on: bool) -> void:
	if _equip_panel == null:
		return
	var slots_row := _equip_panel.get_node_or_null("SlotsRow")
	if slots_row == null:
		return
	for c in slots_row.get_children():
		var pc := c as PanelContainer
		if pc != null:
			pc.add_theme_stylebox_override("panel", _slot_stylebox(on))


func _set_pool_highlight(on: bool) -> void:
	if _equip_panel == null:
		return
	var pool := _equip_panel.get_node_or_null("OwnedPanel") as PanelContainer
	if pool != null:
		pool.add_theme_stylebox_override("panel", _pool_stylebox(on))


func _clear_drop_highlights() -> void:
	_set_slots_highlight(false)
	_set_pool_highlight(false)


# So acende o destino que esta SOB o mouse e que aceita o drop (por-hover).
func _update_drop_highlight() -> void:
	var target: Control = _drop_target_under_mouse()
	if target == _drop_highlighted:
		return
	if _drop_highlighted != null and is_instance_valid(_drop_highlighted):
		_set_target_green(_drop_highlighted, false)
	_drop_highlighted = target
	if target != null:
		_set_target_green(target, true)


func _drop_target_under_mouse() -> Control:
	if _equip_panel == null:
		return null
	var mp: Vector2 = get_global_mouse_position()
	if _drag_source == "owned":
		var sr := _equip_panel.get_node_or_null("SlotsRow")
		if sr != null:
			for c in sr.get_children():
				var pc := c as PanelContainer
				if pc != null and pc.get_global_rect().has_point(mp):
					return pc
	elif _drag_source == "slot":
		var pool := _equip_panel.get_node_or_null("OwnedPanel") as Control
		if pool != null and pool.get_global_rect().has_point(mp):
			return pool
	return null


func _set_target_green(node: Control, on: bool) -> void:
	var pc := node as PanelContainer
	if pc == null:
		return
	if node.name == "OwnedPanel":
		pc.add_theme_stylebox_override("panel", _pool_stylebox(on))
	else:
		pc.add_theme_stylebox_override("panel", _slot_stylebox(on))
