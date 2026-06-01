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
				_req_label.text = tr(req_key)
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
