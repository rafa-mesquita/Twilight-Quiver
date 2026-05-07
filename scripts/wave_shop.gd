extends CanvasLayer

# Loja pós-wave: 3 estruturas (esq) + 3 upgrades (dir).
# Player compra max 1 estrutura + 1 upgrade por round.
# Estruturas entram em placement mode (ghost segue mouse, click coloca).
# Emite "closed" quando o player clica "Próxima Wave".

signal closed

# Tabela de preço por nível atual do player → preço da próxima compra.
# 1ª = 4, 2ª = 6, 3ª = 10, 4ª = 15, 5ª+ = 20 (cap).
const PRICE_TABLE: Array[int] = [3, 6, 10, 15, 20]
const TOWER_PRICE: int = 10
# Woodwarden: 1ª compra = 6 coins. Cada compra "uppa" o aliado e aumenta custo.
# Tabela de preços por nível atual do player → custo da próxima compra.
const WOODWARDEN_PRICE_TABLE: Array[int] = [6, 10, 14, 18, 24, 30]

const UPGRADE_CATALOG: Array = [
	{"id": "hp", "name": "Mais HP"},
	{"id": "damage", "name": "Dano"},
	{"id": "perfuracao", "name": "Perfuracao", "max_level": 4},
	{"id": "attack_speed", "name": "Atack Speed"},
	{"id": "multi_arrow", "name": "Multiplas Flechas", "max_level": 4},
	{"id": "chain_lightning", "name": "Cadeia de Raios", "max_level": 4},
	{"id": "move_speed", "name": "Move Speed"},
	{"id": "life_steal", "name": "Life Steal"},
	{"id": "gold_magnet", "name": "Ima de Gold", "max_level": 1},
	{"id": "dash", "name": "Dash", "max_level": 1},
	# Sub-melhorias do dash — só aparecem no roll quando pré-requisito atendido.
	{"id": "dash_cooldown", "name": "Dash CD Reduce", "requires": "dash"},
	{"id": "dash_auto_attack", "name": "Dash Auto-Atk", "max_level": 1, "requires": "dash"},
	{"id": "dash_double_arrow", "name": "Dash 2 Flechas", "max_level": 1, "requires": "dash_auto_attack"},
	{"id": "fire_arrow", "name": "Flecha de Fogo", "max_level": 4},
	{"id": "curse_arrow", "name": "Flecha de Maldição", "max_level": 4},
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
const ATTACK_SPEED_DESCS: Array[String] = [
	"+30% velocidade de\nataque",
	"+30% velocidade de\nataque",
	"+30% velocidade de\nataque",
	"+30% velocidade de\nataque",
]
const MULTI_ARROW_DESCS: Array[String] = [
	"+2 flechas a 30°\n(50% dano)",
	"Flechas extras agora\n80% do dano",
	"+2 flechas (5 total)\nem leque",
	"10 flechas em todas\nas direcoes",
]
const CHAIN_LIGHTNING_DESCS: Array[String] = [
	"30% dano no inimigo\nmais proximo",
	"50% dano em 2 inimigos\n+30% chance no 3º",
	"60% dano em 4\ninimigos",
	"100% dano em todos\nda area",
]
const MOVE_SPEED_DESCS: Array[String] = [
	"+17% velocidade de\nmovimento",
	"+17% velocidade de\nmovimento",
	"+17% velocidade de\nmovimento",
	"+17% velocidade de\nmovimento",
]
const GOLD_MAGNET_DESCS: Array[String] = [
	"Puxa todo gold +2%\nchance de drop",
]
const DASH_DESCS: Array[String] = [
	"Espaco = dash\n(cd 4.5s)",
]
const LIFE_STEAL_DESCS: Array[String] = [
	"Inimigos: 12% drop\ncoracao cura 20% HP",
	"+5% chance, +10%\nheal por stack",
	"+5% chance, +10%\nheal por stack",
	"+5% chance, +10%\nheal por stack",
]
const DASH_COOLDOWN_DESCS: Array[String] = [
	"-0.3s no cooldown\ndo dash (min 0.5s)",
	"-0.3s no cooldown\ndo dash (min 0.5s)",
	"-0.3s no cooldown\ndo dash (min 0.5s)",
	"-0.3s no cooldown\ndo dash (min 0.5s)",
]
const DASH_AUTO_ATTACK_DESCS: Array[String] = [
	"Dash dispara flecha\nauto no inimigo proximo",
]
const DASH_DOUBLE_ARROW_DESCS: Array[String] = [
	"Dash dispara 2 flechas\nem sequencia",
]
const FIRE_ARROW_DESCS: Array[String] = [
	"Flecha queima inimigos\n5 dmg/s por 3s",
	"+1 dmg/s queima +\nrastro de fogo (4 dps)",
	"Skill (Q): chama em\narea (12 dps, 6s, cd 7s)",
	"Rastro do player +30%\nem queimaduras +25% area",
]
const CURSE_ARROW_DESCS: Array[String] = [
	"Flecha amaldicoada:\nslow 35% + 4 dps toxic",
	"18% chance: kill vira\naliado ate fim da horda",
	"33% chance + aliados\naplicam slow/DoT",
	"50% chance + skill (Q):\nraio roxo, cd 3s",
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

# Bônus +1 upgrade alterna por wave: rounds pares (2,4,6...) liberam 2 upgrades,
# rounds ímpares (1,3,5...) só 1. Lê wave_manager.wave_number em _ready.
var max_upgrades_this_round: int = 1
# Seleção: click marca, click de novo desmarca. A compra acontece
# no "Próxima Wave" — commita upgrades selecionados + entra em placement
# se houver estrutura selecionada. Estrutura é seleção única (toggle),
# upgrades é multi (limite max_upgrades_this_round).
var _selected_upgrade_idxs: Array[int] = []
var _selected_structure_idx: int = -1
# Re-roll: até 2 por categoria. 1º roll = 1 coin, 2º roll = 2 coins.
const REROLL_COSTS: Array[int] = [1, 2]
const MAX_REROLLS_PER_CATEGORY: int = 2
var _struct_rerolls_used: int = 0
var _upg_rerolls_used: int = 0
var _struct_reroll_btn: TextureButton
var _upg_reroll_btn: TextureButton
var _struct_reroll_widget: Control
var _upg_reroll_widget: Control

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
	# Bônus de +1 upgrade alterna a cada wave: par = 2 compras, ímpar = 1.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm and int(wm.wave_number) % 2 == 0:
		max_upgrades_this_round = 2
	continue_btn.pressed.connect(_on_continue_pressed)
	_setup_reroll_buttons()
	_setup_bonus_label()
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
	# Aliado: Woodwarden — preço progressivo, cada compra "uppa" stats. Max 4.
	var ww_lvl: int = 0
	var p := _get_player()
	if p != null and p.has_method("get_upgrade_count"):
		ww_lvl = p.get_upgrade_count("woodwarden")
	var ww_maxed: bool = ww_lvl >= 4
	var ww_price: int = WOODWARDEN_PRICE_TABLE[mini(ww_lvl, WOODWARDEN_PRICE_TABLE.size() - 1)]
	var ww_desc: String
	if ww_maxed:
		ww_desc = "Max (4/4) atingido"
	else:
		match ww_lvl:
			0: ww_desc = "Aliado tank: 200hp\n50dmg+stun"
			1: ww_desc = "Lv2: +1 aliado, ataques\ncuram aliados 25%"
			2: ww_desc = "Lv3: +1 aliado, +25hp\n+5 dano em todos"
			3: ww_desc = "Lv4 max: +1 aliado\n+25hp +5 dano"
			_: ww_desc = ""
	struct_slots.append({
		"id": "woodwarden",
		"name": "Woodwarden",
		"desc": ww_desc,
		"price": ww_price,
		"available": not ww_maxed,
		"scene": "res://scenes/woodwarden.tscn",
		"is_ally": true,
	})
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
			# Pré-requisito: upgrade só entra no pool se o requires está com lvl > 0.
			# Ex: dash_auto_attack só aparece após comprar dash.
			var requires: String = u.get("requires", "")
			if requires != "":
				var req_lvl: int = 0
				if player != null and player.has_method("get_upgrade_count"):
					req_lvl = player.get_upgrade_count(requires)
				if req_lvl <= 0:
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
		"attack_speed": arr = ATTACK_SPEED_DESCS
		"multi_arrow": arr = MULTI_ARROW_DESCS
		"chain_lightning": arr = CHAIN_LIGHTNING_DESCS
		"move_speed": arr = MOVE_SPEED_DESCS
		"gold_magnet": arr = GOLD_MAGNET_DESCS
		"dash": arr = DASH_DESCS
		"life_steal": arr = LIFE_STEAL_DESCS
		"fire_arrow": arr = FIRE_ARROW_DESCS
		"curse_arrow": arr = CURSE_ARROW_DESCS
		"dash_cooldown": arr = DASH_COOLDOWN_DESCS
		"dash_auto_attack": arr = DASH_AUTO_ATTACK_DESCS
		"dash_double_arrow": arr = DASH_DOUBLE_ARROW_DESCS
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
	if _placement_active:
		return
	var slot: Dictionary = struct_slots[idx]
	if not slot.get("available", false):
		return
	# Toggle: clicar de novo no mesmo card desmarca.
	if _selected_structure_idx == idx:
		_selected_structure_idx = -1
		_refresh_button_states()
		return
	# Verifica gold considerando todas as seleções pendentes (estrutura + upgrades).
	var player := _get_player()
	if player == null:
		return
	var struct_price: int = int(slot["price"])
	if player.gold < _selected_upgrades_total_cost() + struct_price:
		return
	_selected_structure_idx = idx
	_play_buy_sound()
	_refresh_button_states()


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
	# Aliado (Woodwarden): conta como upgrade — incrementa woodwarden_level
	# do player ANTES de registrar/spawnar pra que o scaling do wave_manager
	# pegue o nível novo (ex: 1ª compra → spawn lv1, 2ª → spawn lv2).
	if slot.get("id", "") == "woodwarden" and player.has_method("apply_upgrade"):
		player.apply_upgrade("woodwarden")
		# Aplica scaling no ghost recém-ativado também (já está spawnado).
		var wm0 := get_tree().get_first_node_in_group("wave_manager")
		if wm0 != null and wm0.has_method("_apply_woodwarden_scaling_if_applicable"):
			wm0._apply_woodwarden_scaling_if_applicable(chosen, slot["scene"])
			# Ajusta hp atual ao novo max_hp (foi instanciado com valor base).
			if "max_hp" in chosen and "hp" in chosen:
				chosen.hp = chosen.max_hp
				if chosen.has_node("HpBar"):
					chosen.get_node("HpBar").set_ratio(1.0)
	# Registra a estrutura no wave_manager pra renascer na próxima wave caso
	# seja destruída pelos inimigos.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("register_structure"):
		wm.register_structure(slot["scene"], chosen.global_position, chosen)
	_exit_placement_mode()
	# Após colocar a estrutura, finaliza o flow do Continue: aplica upgrades
	# selecionados e fecha o shop.
	_commit_upgrades_and_close()


func _cancel_placement() -> void:
	for g in _placement_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_placement_ghosts.clear()
	_exit_placement_mode()
	# Cancelar = volta pra shop com a estrutura ainda selecionada — usuário
	# pode reescolher um spot via Continue de novo, ou desmarcar pelo card.
	_refresh_button_states()


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


func _is_upgrade_limit_reached() -> bool:
	return _selected_upgrade_idxs.size() >= max_upgrades_this_round


func _selected_upgrades_total_cost() -> int:
	var total: int = 0
	for i in _selected_upgrade_idxs:
		total += int(upg_slots[i].get("price", 0))
	return total


func _selected_total_cost_with_structure() -> int:
	var total: int = _selected_upgrades_total_cost()
	if _selected_structure_idx >= 0:
		total += int(struct_slots[_selected_structure_idx].get("price", 0))
	return total


func _buy_upgrade(idx: int) -> void:
	var slot: Dictionary = upg_slots[idx]
	if not slot.get("available", false):
		return
	# Toggle: já selecionado → desmarca.
	if idx in _selected_upgrade_idxs:
		_selected_upgrade_idxs.erase(idx)
		_refresh_button_states()
		return
	# Limite de seleções por round (1 ou 2 dependendo da wave).
	if _is_upgrade_limit_reached():
		return
	var player := _get_player()
	if player == null:
		return
	# Verifica gold considerando todas as seleções pendentes (struct + upgrades).
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost_with_structure() + price:
		return
	_selected_upgrade_idxs.append(idx)
	_play_buy_sound()
	_refresh_button_states()


func _commit_upgrades_and_close() -> void:
	# Cobra e aplica todos os upgrades selecionados em sequência. Som único.
	# Som de compra já tocou ao SELECIONAR; commit é silencioso pra não duplicar.
	var player := _get_player()
	if player != null:
		for idx in _selected_upgrade_idxs:
			var slot: Dictionary = upg_slots[idx]
			if not player.spend_gold(int(slot.get("price", 0))):
				continue
			if player.has_method("apply_upgrade"):
				player.apply_upgrade(slot["id"])
	closed.emit()


const SELECTED_TINT: Color = Color(1.4, 1.25, 0.5, 1.0)


func _refresh_button_states() -> void:
	var player := _get_player()
	var current_gold: int = player.gold if player != null else 0
	# Gold "comprometido" pelas seleções pendentes — o que sobra é o gold que
	# pode ser usado pra novas seleções/rerolls sem estourar.
	var pending_cost: int = _selected_total_cost_with_structure()
	var available_gold: int = current_gold - pending_cost
	if _struct_reroll_btn != null:
		var struct_max: bool = _struct_rerolls_used >= MAX_REROLLS_PER_CATEGORY
		var struct_cost: int = _next_reroll_cost(_struct_rerolls_used)
		# Reroll de struct: liberado mesmo com estrutura selecionada (vai trocar o pool).
		var disabled_struct: bool = struct_max or _placement_active \
			or available_gold < struct_cost
		_struct_reroll_btn.disabled = disabled_struct
		_set_reroll_widget_dim(_struct_reroll_widget, disabled_struct)
		_update_reroll_price_label(_struct_reroll_widget, struct_cost, struct_max)
	if _upg_reroll_btn != null:
		var upg_max: bool = _upg_rerolls_used >= MAX_REROLLS_PER_CATEGORY
		var upg_cost: int = _next_reroll_cost(_upg_rerolls_used)
		var disabled_upg: bool = upg_max or available_gold < upg_cost
		_upg_reroll_btn.disabled = disabled_upg
		_set_reroll_widget_dim(_upg_reroll_widget, disabled_upg)
		_update_reroll_price_label(_upg_reroll_widget, upg_cost, upg_max)
	# Estruturas: toggle. Selecionada = amarelo + "Selecionado". Outras só
	# desabilitam se não der pra trocar pra elas (= sem gold suficiente).
	for i in 3:
		var slot: Dictionary = struct_slots[i]
		var btn: Button = struct_cards[i].get_node("VBox/BuyBtn")
		var available: bool = slot.get("available", false)
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_structure_idx == i
		# Pode trocar a seleção se a outra estrutura cabe no gold (devolvendo a já selecionada).
		var afford_swap: bool = current_gold >= pending_cost - _selected_struct_price() + price
		btn.disabled = not available or (not is_selected and not afford_swap)
		if not available:
			btn.text = "—"
			btn.modulate = Color.WHITE
		elif is_selected:
			btn.text = "Selecionado"
			btn.modulate = SELECTED_TINT
		else:
			btn.text = "Selecionar"
			btn.modulate = Color.WHITE
	# Upgrades: multi-seleção até max_upgrades_this_round. Selecionado = amarelo.
	var limit_reached: bool = _is_upgrade_limit_reached()
	for i in 3:
		var slot: Dictionary = upg_slots[i]
		var btn: Button = upg_cards[i].get_node("VBox/BuyBtn")
		var available: bool = slot.get("available", false)
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = i in _selected_upgrade_idxs
		# Pode adicionar essa nova seleção? cabem no gold + ainda dentro do limite.
		var can_select: bool = not limit_reached and available_gold >= price
		btn.disabled = not available or (not is_selected and not can_select)
		if not available:
			btn.text = "—"
			btn.modulate = Color.WHITE
		elif is_selected:
			btn.text = "Selecionado"
			btn.modulate = SELECTED_TINT
		else:
			btn.text = "Selecionar"
			btn.modulate = Color.WHITE


func _selected_struct_price() -> int:
	if _selected_structure_idx < 0:
		return 0
	return int(struct_slots[_selected_structure_idx].get("price", 0))


func _set_reroll_widget_dim(widget: Control, dim: bool) -> void:
	if widget == null or not is_instance_valid(widget):
		return
	var icon_wrap: Node = widget.get_node_or_null("IconWrap")
	if icon_wrap != null:
		var btn := icon_wrap.get_node_or_null("Btn") as TextureButton
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
		# Safety: shop UI fica escondida durante placement, mas se de alguma
		# forma o botão for clicado, cancela e mantém aberto.
		_cancel_placement()
		return
	# Estrutura selecionada → entra em placement. Após confirmar o spot,
	# os upgrades são commitados e o shop fecha (_commit_upgrades_and_close).
	if _selected_structure_idx >= 0:
		_enter_placement_mode(_selected_structure_idx)
		return
	# Sem estrutura: só commita upgrades selecionados (se houver) e fecha.
	_commit_upgrades_and_close()


func _setup_bonus_label() -> void:
	# Quando o bônus de +1 upgrade rola, mostra um label dourado pulsando
	# ao lado do UpgHeader pra player saber que pode comprar 2.
	if max_upgrades_this_round <= 1:
		return
	var right_header: HBoxContainer = $Root/HBox/RightCol/Header
	var upg_label: Label = $Root/HBox/RightCol/Header/UpgHeader
	var bonus := Label.new()
	bonus.name = "BonusUpgradeLabel"
	bonus.text = "BONUS +1!"
	var at01_font: Font = load("res://font/at01.ttf")
	if at01_font != null:
		bonus.add_theme_font_override("font", at01_font)
	bonus.add_theme_font_size_override("font_size", 22)
	bonus.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	right_header.add_child(bonus)
	right_header.move_child(bonus, upg_label.get_index() + 1)
	# Pulse leve pra chamar atenção.
	var tw := bonus.create_tween().set_loops()
	tw.tween_property(bonus, "modulate:a", 0.55, 0.6)
	tw.tween_property(bonus, "modulate:a", 1.0, 0.6)


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
	# Texto inicial = primeiro custo; _refresh_button_states sobrescreve dinamicamente.
	price.text = "%d" % REROLL_COSTS[0]
	var at01_font: Font = load("res://font/at01.ttf")
	if at01_font != null:
		price.add_theme_font_override("font", at01_font)
	price.add_theme_font_size_override("font_size", 22)
	price.add_theme_color_override("font_color", Color(1, 0.85, 0.35, 1))
	pair.add_child(price)
	return pair


const REROLL_BUTTON_SIZE: Vector2 = Vector2(64, 64)  # 32×32 sprite × 2× nearest pra ficar crisp


func _make_reroll_widget() -> Control:
	var tex: Texture2D = load("res://assets/Hud/new reroll.png")
	var container := Control.new()
	container.custom_minimum_size = REROLL_BUTTON_SIZE
	container.size = REROLL_BUTTON_SIZE
	container.tooltip_text = "Re-roll (1º: 1 coin, 2º: 2 coins)"

	# Botão flat — sem halo, sem hover tween (user tirou o efeito).
	var btn := TextureButton.new()
	btn.name = "Btn"
	btn.texture_normal = tex
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pivot_offset = REROLL_BUTTON_SIZE * 0.5
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	container.add_child(btn)
	return container


func _next_reroll_cost(rerolls_used: int) -> int:
	# Cap em REROLL_COSTS — se já usou todos os rolls, retorna o último (botão
	# fica disabled de qualquer forma).
	var idx: int = clampi(rerolls_used, 0, REROLL_COSTS.size() - 1)
	return REROLL_COSTS[idx]


func _update_reroll_price_label(widget: Control, cost: int, maxed: bool) -> void:
	if widget == null or not is_instance_valid(widget):
		return
	var price: Label = widget.get_node_or_null("Price") as Label
	if price == null:
		return
	price.text = "—" if maxed else "%d" % cost


func _on_struct_reroll() -> void:
	if _struct_rerolls_used >= MAX_REROLLS_PER_CATEGORY or _placement_active:
		return
	var cost: int = _next_reroll_cost(_struct_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_struct_rerolls_used += 1
	# Reseta seleção de estrutura — slots mudaram.
	_selected_structure_idx = -1
	_play_buy_sound()
	_roll_struct_slots()
	_build_struct_cards()
	_refresh_gold_label()
	_refresh_button_states()


func _on_upg_reroll() -> void:
	if _upg_rerolls_used >= MAX_REROLLS_PER_CATEGORY or _is_upgrade_limit_reached():
		return
	var cost: int = _next_reroll_cost(_upg_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_upg_rerolls_used += 1
	# Reseta seleções de upgrade — os cards mudaram, índices não fazem mais sentido.
	_selected_upgrade_idxs.clear()
	_play_buy_sound()
	_roll_upg_slots()
	_build_upg_cards()
	_refresh_gold_label()
	_refresh_button_states()
