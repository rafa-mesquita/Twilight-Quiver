extends CanvasLayer

# Loja pós-wave: 3 estruturas (esq) + 3 upgrades (dir).
# Player compra max 1 estrutura + 1 upgrade por round.
# Estruturas entram em placement mode (ghost segue mouse, click coloca).
# Emite "closed" quando o player clica "Próxima Wave".

signal closed

# Tabela de preço por nível atual do player → preço da próxima compra.
# 1ª = 4, 2ª = 6, 3ª = 10, 4ª = 15, 5ª+ = 20 (cap).
const PRICE_TABLE: Array[int] = [4, 6, 10, 15, 20]
const TOWER_PRICE: int = 10

const UPGRADE_CATALOG: Array = [
	{"id": "hp", "name": "Mais HP"},
	{"id": "damage", "name": "Dano"},
	{"id": "perfuracao", "name": "Perfuracao", "max_level": 4},
]

const HP_DESCS: Array[String] = [
	"+15 HP maximo",
	"+15 HP maximo",
	"+15 HP maximo",
	"+15 HP maximo",
]
const DAMAGE_DESCS: Array[String] = [
	"+20% dano da flecha",
	"+20% dano da flecha",
	"+20% dano da flecha",
	"+20% dano da flecha",
]
const PERFURACAO_DESCS: Array[String] = [
	"A cada 3 ataques flecha\natravessa, +30% dano",
	"+60% dano + hitbox maior",
	"+90% dano",
	"Todo ataque atravessa",
]

@onready var gold_label: Label = $Root/HBox/RightCol/Header/GoldLabel
@onready var continue_btn: Button = $Root/HBox/RightCol/ContinueBtn
@onready var placement_hint: Label = $PlacementHint
@onready var bg_rect: ColorRect = $Bg
@onready var root_panel: Control = $Root

@onready var struct_cards: Array[Control] = [
	$Root/HBox/LeftCol/StructList/Card1,
	$Root/HBox/LeftCol/StructList/Card2,
	$Root/HBox/LeftCol/StructList/Card3,
]
@onready var upg_cards: Array[Control] = [
	$Root/HBox/RightCol/UpgRow/Card1,
	$Root/HBox/RightCol/UpgRow/Card2,
	$Root/HBox/RightCol/UpgRow/Card3,
]

var bought_upgrade_this_round: bool = false
var bought_structure_this_round: bool = false
# Confirmação em 2 cliques: 1º click marca pending, 2º no mesmo card confirma.
# Click em outro card troca o pending — permite mudar de ideia sem comprar errado.
var _pending_upgrade_idx: int = -1
# Re-roll: 1 coin por categoria, 1× por turno.
const REROLL_COST: int = 1
var _struct_reroll_used: bool = false
var _upg_reroll_used: bool = false
var _struct_reroll_btn: TextureButton
var _upg_reroll_btn: TextureButton
var _struct_reroll_widget: Control
var _upg_reroll_widget: Control
var _confirm_dialog: ConfirmationDialog

const BUY_SOUND: AudioStream = preload("res://audios/effects/buy_1.mp3")

var struct_slots: Array = []
var upg_slots: Array = []

# Placement mode (5 spots aleatórios)
const PLACEMENT_BOUNDS: Rect2 = Rect2(-80, -40, 680, 380)  # área válida do mapa
const PLACEMENT_MIN_DIST: float = 80.0  # distância mínima entre spots
const PLACEMENT_CLICK_RADIUS: float = 60.0  # raio max do click pra selecionar spot
const PLACEMENT_SPOT_COUNT: int = 5

var _placement_active: bool = false
var _placement_ghosts: Array[Node2D] = []
var _placement_slot_idx: int = -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	continue_btn.pressed.connect(_on_continue_pressed)
	_setup_reroll_buttons()
	_setup_confirm_dialog()
	_refresh_gold_label()
	_roll_slots()
	_build_struct_cards()
	_build_upg_cards()
	_refresh_button_states()


func _process(_delta: float) -> void:
	if _placement_active and not _placement_ghosts.is_empty():
		# Highlight do ghost mais próximo do mouse — outros ficam dim.
		var mouse_world: Vector2 = _world_mouse_position()
		var nearest: Node2D = _nearest_ghost_to(mouse_world)
		for g in _placement_ghosts:
			if not is_instance_valid(g):
				continue
			if g == nearest:
				g.modulate = Color(1.3, 1.3, 1.3, 0.95)
			else:
				g.modulate = Color(1, 1, 1, 0.45)


func _input(event: InputEvent) -> void:
	if not _placement_active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Z:
			_cancel_placement()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_world: Vector2 = _world_mouse_position()
			var nearest: Node2D = _nearest_ghost_to(mouse_world)
			if nearest != null and nearest.global_position.distance_to(mouse_world) <= PLACEMENT_CLICK_RADIUS:
				_confirm_placement_at(nearest)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_placement()
			get_viewport().set_input_as_handled()


func _world_mouse_position() -> Vector2:
	# Converte screen mouse pos → world pos (considera transformação da câmera/canvas).
	return get_viewport().get_canvas_transform().affine_inverse() * get_viewport().get_mouse_position()


func _nearest_ghost_to(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_dist: float = INF
	for g in _placement_ghosts:
		if not is_instance_valid(g):
			continue
		var d: float = g.global_position.distance_to(pos)
		if d < best_dist:
			best = g
			best_dist = d
	return best


func _generate_random_positions(count: int) -> Array[Vector2]:
	# Prioriza markers definidos no editor (Map/TowerSpawnPoints / group "tower_spawn_root").
	# Pega `count` aleatórios do pool. Se não houver markers, faz fallback pra random.
	var spawn_root := get_tree().get_first_node_in_group("tower_spawn_root")
	if spawn_root != null and spawn_root.get_child_count() > 0:
		var marker_positions: Array[Vector2] = []
		for c in spawn_root.get_children():
			if c is Node2D:
				marker_positions.append((c as Node2D).global_position)
		marker_positions.shuffle()
		var picked: Array[Vector2] = []
		for i in mini(count, marker_positions.size()):
			picked.append(marker_positions[i])
		return picked
	# Fallback: gera random dentro de PLACEMENT_BOUNDS.
	var result: Array[Vector2] = []
	var attempts: int = 0
	while result.size() < count and attempts < 200:
		attempts += 1
		var p := Vector2(
			randf_range(PLACEMENT_BOUNDS.position.x, PLACEMENT_BOUNDS.position.x + PLACEMENT_BOUNDS.size.x),
			randf_range(PLACEMENT_BOUNDS.position.y, PLACEMENT_BOUNDS.position.y + PLACEMENT_BOUNDS.size.y)
		)
		var ok: bool = true
		for existing in result:
			if existing.distance_to(p) < PLACEMENT_MIN_DIST:
				ok = false
				break
		if ok:
			result.append(p)
	return result


# ---------- Roll ----------

func _roll_slots() -> void:
	_roll_struct_slots()
	_roll_upg_slots()


func _roll_struct_slots() -> void:
	struct_slots.clear()
	struct_slots.append({
		"id": "arrow_tower",
		"name": "Torre de Flechas",
		"desc": "Atira em inimigos\nproximos. 80% dano.",
		"price": TOWER_PRICE,
		"available": true,
		"scene": "res://scenes/structures/arrow_tower.tscn",
	})
	struct_slots.append({"id": "soon", "name": "Em breve", "desc": "—", "price": 0, "available": false})
	struct_slots.append({"id": "soon", "name": "Em breve", "desc": "—", "price": 0, "available": false})


func _roll_upg_slots() -> void:
	upg_slots.clear()
	var player := _get_player()
	var already_picked_ids: Array[String] = []  # evita 2 cards iguais no mesmo roll
	for i in 3:
		var pool: Array = []
		for u in UPGRADE_CATALOG:
			var id: String = u["id"]
			var max_level: int = u.get("max_level", 999)
			var current: int = 0
			if player != null and player.has_method("get_upgrade_count"):
				current = player.get_upgrade_count(id)
			if current >= max_level:
				continue
			if id in already_picked_ids:
				continue
			pool.append(u)
		if pool.is_empty():
			upg_slots.append({"id": "none", "name": "—", "desc": "—", "price": 0, "available": false})
			continue
		var picked: Dictionary = pool[randi() % pool.size()]
		already_picked_ids.append(picked["id"])
		var picked_id: String = picked["id"]
		var current_level: int = 0
		if player != null and player.has_method("get_upgrade_count"):
			current_level = player.get_upgrade_count(picked_id)
		var target_level: int = current_level + 1
		var price: int = _get_upgrade_price(current_level)
		upg_slots.append({
			"id": picked_id,
			"name": picked["name"],
			"desc": _get_upgrade_desc(picked_id, target_level),
			"price": price,
			"available": true,
			"target_level": target_level,
		})


func _get_upgrade_price(player_current_level: int) -> int:
	if player_current_level < 0:
		player_current_level = 0
	if player_current_level >= PRICE_TABLE.size():
		return PRICE_TABLE[PRICE_TABLE.size() - 1]
	return PRICE_TABLE[player_current_level]


func _get_upgrade_desc(id: String, target_level: int) -> String:
	var arr: Array
	match id:
		"hp": arr = HP_DESCS
		"damage": arr = DAMAGE_DESCS
		"perfuracao": arr = PERFURACAO_DESCS
		_: return ""
	var idx: int = clampi(target_level - 1, 0, arr.size() - 1)
	return arr[idx]


# ---------- Build cards ----------

func _build_struct_cards() -> void:
	for i in 3:
		var slot: Dictionary = struct_slots[i]
		var card: Control = struct_cards[i]
		card.get_node("VBox/TitleLabel").text = slot["name"]
		card.get_node("VBox/DescLabel").text = slot["desc"]
		card.get_node("VBox/PriceLabel").text = ("%d coins" % slot["price"]) if slot["available"] else "—"
		var btn: Button = card.get_node("VBox/BuyBtn")
		btn.text = "Comprar" if slot["available"] else "—"
		for c in btn.pressed.get_connections():
			btn.pressed.disconnect(c["callable"])
		btn.pressed.connect(_buy_structure.bind(i))


func _build_upg_cards() -> void:
	for i in 3:
		var slot: Dictionary = upg_slots[i]
		var card: Control = upg_cards[i]
		var available: bool = slot.get("available", false)
		var target_level: int = int(slot.get("target_level", 0))
		var title_label: Label = card.get_node("VBox/TitleLabel")
		title_label.text = slot["name"]
		title_label.modulate = _level_tint_for_label(target_level) if available else Color.WHITE
		# Estrelas em Label separado sem override de fonte (at01 não tem ★).
		var star_label: Label = _ensure_stars_label(card)
		var stars_str: String = _stars_text(target_level) if available else ""
		star_label.text = stars_str
		star_label.visible = stars_str != ""
		star_label.modulate = _level_tint_for_label(target_level) if available else Color.WHITE
		card.get_node("VBox/DescLabel").text = slot["desc"]
		card.get_node("VBox/PriceLabel").text = ("%d coins" % slot["price"]) if available else "—"
		# Tint do card inteiro pra reforçar o tier — sutil pra não quebrar a leitura.
		card.modulate = _level_tint_for_card(target_level) if available else Color.WHITE
		var btn: Button = card.get_node("VBox/BuyBtn")
		btn.text = "Selecionar" if available else "—"
		for c in btn.pressed.get_connections():
			btn.pressed.disconnect(c["callable"])
		btn.pressed.connect(_buy_upgrade.bind(i))


func _ensure_stars_label(card: Control) -> Label:
	# Garante que existe um StarsLabel logo abaixo do TitleLabel, usando a fonte
	# default do Godot (a at01 do projeto não tem o glifo ★).
	var vbox: VBoxContainer = card.get_node("VBox")
	var existing := vbox.get_node_or_null("StarsLabel")
	if existing != null and existing is Label:
		return existing as Label
	var star_label := Label.new()
	star_label.name = "StarsLabel"
	star_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(star_label)
	var title_idx: int = vbox.get_node("TitleLabel").get_index()
	vbox.move_child(star_label, title_idx + 1)
	return star_label


func _stars_text(level: int) -> String:
	if level <= 0:
		return ""
	var n: int = mini(level, 4)
	var s: String = ""
	for i in n:
		s += "★"
	if level > 4:
		s += " +%d" % (level - 4)
	return s


func _level_tint_for_card(level: int) -> Color:
	# Tint suave aplicado no card inteiro (multiplicativo, fica próximo do branco).
	match level:
		1: return Color(1.0, 1.0, 1.0, 1.0)
		2: return Color(0.85, 0.95, 1.15, 1.0)  # azulado
		3: return Color(1.05, 0.85, 1.15, 1.0)  # roxeado
		_: return Color(1.2, 1.05, 0.7, 1.0)    # dourado (4+)


func _level_tint_for_label(level: int) -> Color:
	# Cor do título — mais saturada pra dar destaque às estrelas.
	match level:
		1: return Color(1.0, 1.0, 1.0, 1.0)
		2: return Color(0.55, 0.85, 1.0, 1.0)
		3: return Color(0.95, 0.6, 1.0, 1.0)
		_: return Color(1.0, 0.85, 0.3, 1.0)


# ---------- Compra ----------

func _buy_structure(idx: int) -> void:
	if bought_structure_this_round or _placement_active:
		return
	var slot: Dictionary = struct_slots[idx]
	if not slot.get("available", false):
		return
	var player := _get_player()
	if player == null or player.gold < int(slot["price"]):
		return
	# Inicia placement mode (ainda não desconta gold).
	_enter_placement_mode(idx)


func _enter_placement_mode(idx: int) -> void:
	var slot: Dictionary = struct_slots[idx]
	var scene: PackedScene = load(slot["scene"])
	if scene == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	# Gera 5 posições aleatórias espalhadas e spawna um ghost em cada.
	var positions: Array[Vector2] = _generate_random_positions(PLACEMENT_SPOT_COUNT)
	_placement_ghosts.clear()
	for pos in positions:
		var ghost: Node2D = scene.instantiate()
		world.add_child(ghost)
		ghost.global_position = pos
		ghost.modulate = Color(1, 1, 1, 0.5)
		ghost.process_mode = Node.PROCESS_MODE_DISABLED
		_placement_ghosts.append(ghost)
	_placement_active = true
	_placement_slot_idx = idx
	# Esconde UI da loja durante placement.
	bg_rect.visible = false
	root_panel.visible = false
	placement_hint.visible = true
	# Câmera entra em overview pra mostrar mapa inteiro (todos os 5 spots visíveis).
	_set_camera_overview(true)


func _confirm_placement_at(chosen: Node2D) -> void:
	var slot: Dictionary = struct_slots[_placement_slot_idx]
	var player := _get_player()
	if player == null or not player.spend_gold(int(slot["price"])):
		_cancel_placement()
		return
	# Ativa a estrutura escolhida; remove os outros ghosts.
	for g in _placement_ghosts:
		if not is_instance_valid(g):
			continue
		if g == chosen:
			g.modulate = Color(1, 1, 1, 1)
			g.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			g.queue_free()
	_placement_ghosts.clear()
	bought_structure_this_round = true
	_play_buy_sound()
	# Registra a estrutura no wave_manager pra renascer na próxima wave caso
	# seja destruída pelos inimigos.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("register_structure"):
		wm.register_structure(slot["scene"], chosen.global_position)
	_exit_placement_mode()
	_refresh_gold_label()
	_refresh_button_states()


func _cancel_placement() -> void:
	for g in _placement_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_placement_ghosts.clear()
	_exit_placement_mode()


func _exit_placement_mode() -> void:
	_placement_active = false
	_placement_slot_idx = -1
	bg_rect.visible = true
	root_panel.visible = true
	placement_hint.visible = false
	# Restaura zoom da câmera (volta a seguir o player).
	_set_camera_overview(false)


func _set_camera_overview(active: bool) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("set_overview_mode"):
		camera.set_overview_mode(active)


func _buy_upgrade(idx: int) -> void:
	if bought_upgrade_this_round:
		return
	var slot: Dictionary = upg_slots[idx]
	if not slot.get("available", false):
		return
	var player := _get_player()
	if player == null or player.gold < int(slot["price"]):
		return
	# 1º click ou troca pra outro card: marca pending e espera confirmação.
	if _pending_upgrade_idx != idx:
		_pending_upgrade_idx = idx
		_refresh_button_states()
		return
	# 2º click no mesmo card: confirma a compra.
	if not player.spend_gold(int(slot["price"])):
		return
	if player.has_method("apply_upgrade"):
		player.apply_upgrade(slot["id"])
	bought_upgrade_this_round = true
	_pending_upgrade_idx = -1
	_play_buy_sound()
	_refresh_gold_label()
	_refresh_button_states()


func _refresh_button_states() -> void:
	var player := _get_player()
	var current_gold: int = player.gold if player != null else 0
	if _struct_reroll_btn != null:
		var disabled_struct: bool = _struct_reroll_used or bought_structure_this_round \
			or _placement_active or current_gold < REROLL_COST
		_struct_reroll_btn.disabled = disabled_struct
		_set_reroll_widget_dim(_struct_reroll_widget, disabled_struct)
	if _upg_reroll_btn != null:
		var disabled_upg: bool = _upg_reroll_used or bought_upgrade_this_round \
			or current_gold < REROLL_COST
		_upg_reroll_btn.disabled = disabled_upg
		_set_reroll_widget_dim(_upg_reroll_widget, disabled_upg)
	for i in 3:
		var slot: Dictionary = struct_slots[i]
		var btn: Button = struct_cards[i].get_node("VBox/BuyBtn")
		var available: bool = slot.get("available", false)
		var afford: bool = current_gold >= int(slot.get("price", 0))
		btn.disabled = not available or bought_structure_this_round or not afford
		if bought_structure_this_round:
			btn.text = "—" if available else btn.text
		elif not available:
			btn.text = "—"
		else:
			btn.text = "Comprar"
	for i in 3:
		var slot: Dictionary = upg_slots[i]
		var btn: Button = upg_cards[i].get_node("VBox/BuyBtn")
		var available: bool = slot.get("available", false)
		var afford: bool = current_gold >= int(slot.get("price", 0))
		btn.disabled = not available or bought_upgrade_this_round or not afford
		var is_pending: bool = (_pending_upgrade_idx == i) and not bought_upgrade_this_round
		if bought_upgrade_this_round:
			btn.text = "—" if available else btn.text
			btn.modulate = Color.WHITE
		elif not available:
			btn.text = "—"
			btn.modulate = Color.WHITE
		elif is_pending:
			btn.text = "Comprar"
			btn.modulate = Color(1.4, 1.25, 0.5, 1.0)  # destaque amarelo
		else:
			btn.text = "Selecionar"
			btn.modulate = Color.WHITE


func _set_reroll_widget_dim(widget: Control, dim: bool) -> void:
	if widget == null or not is_instance_valid(widget):
		return
	var icon_wrap: Node = widget.get_node_or_null("IconWrap")
	if icon_wrap != null:
		var halo := icon_wrap.get_node_or_null("Halo") as TextureRect
		var btn := icon_wrap.get_node_or_null("Btn") as TextureButton
		if halo != null:
			halo.visible = not dim
		if btn != null:
			btn.modulate = Color(0.55, 0.55, 0.55, 0.65) if dim else Color.WHITE
	var price: Label = widget.get_node_or_null("Price") as Label
	if price != null:
		price.modulate = Color(0.55, 0.55, 0.55, 0.65) if dim else Color.WHITE


func _refresh_gold_label() -> void:
	var player := _get_player()
	var g: int = player.gold if player != null else 0
	gold_label.text = "%d coins" % g


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _play_buy_sound() -> void:
	if BUY_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = BUY_SOUND
	p.volume_db = -16.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _on_continue_pressed() -> void:
	if _placement_active:
		_cancel_placement()
	# Aviso quando há um upgrade selecionado mas não comprado.
	if _pending_upgrade_idx >= 0 and not bought_upgrade_this_round:
		if _confirm_dialog != null:
			_confirm_dialog.popup_centered()
		return
	closed.emit()


func _on_confirm_continue() -> void:
	closed.emit()


func _setup_confirm_dialog() -> void:
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = "Confirmar"
	_confirm_dialog.dialog_text = "Existem upgrades selecionados.\nProsseguir sem a compra?"
	_confirm_dialog.ok_button_text = "Prosseguir"
	_confirm_dialog.get_cancel_button().text = "Voltar"
	_confirm_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_confirm_dialog)
	_confirm_dialog.confirmed.connect(_on_confirm_continue)


func _setup_reroll_buttons() -> void:
	# Estruturas: LeftHeader é um Label simples — embrulha num HBox pra encaixar
	# o ícone + custo do re-roll do lado.
	var left_col: VBoxContainer = $Root/HBox/LeftCol
	var struct_label: Label = $Root/HBox/LeftCol/LeftHeader
	var struct_hbox := HBoxContainer.new()
	struct_hbox.add_theme_constant_override("separation", 10)
	struct_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	var label_idx: int = struct_label.get_index()
	left_col.remove_child(struct_label)
	left_col.add_child(struct_hbox)
	left_col.move_child(struct_hbox, label_idx)
	struct_hbox.add_child(struct_label)
	_struct_reroll_widget = _make_reroll_pair()
	_struct_reroll_btn = _struct_reroll_widget.get_node("IconWrap/Btn") as TextureButton
	if _struct_reroll_btn != null:
		_struct_reroll_btn.pressed.connect(_on_struct_reroll)
	struct_hbox.add_child(_struct_reroll_widget)
	# Upgrades: Header já é HBox (UpgHeader + GoldLabel) — UpgHeader tinha
	# size_flags=expand que jogava o reroll pro extremo direito. Tira o expand
	# e adiciona um spacer antes do GoldLabel pra manter ele no canto.
	var right_header: HBoxContainer = $Root/HBox/RightCol/Header
	var upg_label: Label = $Root/HBox/RightCol/Header/UpgHeader
	upg_label.size_flags_horizontal = 0
	_upg_reroll_widget = _make_reroll_pair()
	_upg_reroll_btn = _upg_reroll_widget.get_node("IconWrap/Btn") as TextureButton
	if _upg_reroll_btn != null:
		_upg_reroll_btn.pressed.connect(_on_upg_reroll)
	right_header.add_child(_upg_reroll_widget)
	right_header.move_child(_upg_reroll_widget, upg_label.get_index() + 1)
	# Spacer expansivo entre o reroll e o gold label.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_header.add_child(spacer)
	var gold_node: Node = $Root/HBox/RightCol/Header/GoldLabel
	right_header.move_child(spacer, gold_node.get_index())


func _make_reroll_pair() -> HBoxContainer:
	# HBox externo: [Icon (Control), Price (Label)]
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon_wrap := _make_reroll_widget()
	icon_wrap.name = "IconWrap"
	pair.add_child(icon_wrap)
	var price := Label.new()
	price.name = "Price"
	price.text = "%d" % REROLL_COST
	var at01_font: Font = load("res://font/at01.ttf")
	if at01_font != null:
		price.add_theme_font_override("font", at01_font)
	price.add_theme_font_size_override("font_size", 22)
	price.add_theme_color_override("font_color", Color(1, 0.85, 0.35, 1))
	pair.add_child(price)
	return pair


const REROLL_BUTTON_SIZE: Vector2 = Vector2(44, 44)
const REROLL_HALO_BASE_SCALE: Vector2 = Vector2(1.35, 1.35)
const REROLL_HALO_HOVER_SCALE: Vector2 = Vector2(1.55, 1.55)


func _make_reroll_widget() -> Control:
	# Carrega texture em runtime — se faltar, cai num fallback de "↻" pra não quebrar.
	var tex: Texture2D = load("res://assets/Hud/reroll.png")
	var container := Control.new()
	container.custom_minimum_size = REROLL_BUTTON_SIZE
	container.size = REROLL_BUTTON_SIZE
	container.tooltip_text = "Re-roll (1 coin)"

	# Halo atrás do botão pra dar destaque (modulado dourado, alpha baixo).
	var halo := TextureRect.new()
	halo.name = "Halo"
	halo.texture = tex
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	halo.set_anchors_preset(Control.PRESET_FULL_RECT)
	halo.modulate = Color(1.6, 1.45, 0.85, 0.32)
	halo.pivot_offset = REROLL_BUTTON_SIZE * 0.5
	halo.scale = REROLL_HALO_BASE_SCALE
	halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(halo)

	# Botão real com a textura crisp por cima.
	var btn := TextureButton.new()
	btn.name = "Btn"
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pivot_offset = REROLL_BUTTON_SIZE * 0.5
	# Nearest neighbor pra não suavizar o pixel art.
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if halo != null:
		halo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.add_child(btn)

	btn.mouse_entered.connect(_on_reroll_hover.bind(container, true))
	btn.mouse_exited.connect(_on_reroll_hover.bind(container, false))
	return container


func _on_reroll_hover(container: Control, hovered: bool) -> void:
	if container == null or not is_instance_valid(container):
		return
	var halo := container.get_node_or_null("Halo") as TextureRect
	var btn := container.get_node_or_null("Btn") as TextureButton
	var t := create_tween().set_parallel(true)
	if halo != null:
		t.tween_property(halo, "modulate:a", 0.6 if hovered else 0.32, 0.12)
		t.tween_property(halo, "scale",
			REROLL_HALO_HOVER_SCALE if hovered else REROLL_HALO_BASE_SCALE, 0.12)
	if btn != null:
		t.tween_property(btn, "scale",
			Vector2(1.1, 1.1) if hovered else Vector2.ONE, 0.12)


func _on_struct_reroll() -> void:
	if _struct_reroll_used or bought_structure_this_round or _placement_active:
		return
	var player := _get_player()
	if player == null or not player.spend_gold(REROLL_COST):
		return
	_struct_reroll_used = true
	_play_buy_sound()
	_roll_struct_slots()
	_build_struct_cards()
	_refresh_gold_label()
	_refresh_button_states()


func _on_upg_reroll() -> void:
	if _upg_reroll_used or bought_upgrade_this_round:
		return
	var player := _get_player()
	if player == null or not player.spend_gold(REROLL_COST):
		return
	_upg_reroll_used = true
	# Reseta seleção pendente — os cards mudaram.
	_pending_upgrade_idx = -1
	_play_buy_sound()
	_roll_upg_slots()
	_build_upg_cards()
	_refresh_gold_label()
	_refresh_button_states()
