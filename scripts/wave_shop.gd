extends CanvasLayer

# Loja pós-wave: 4 categorias, cada uma com reroll próprio.
# - Estruturas (2 cards paisagem, esq. topo): Torre + slots futuros, placement.
# - Status (2 cards paisagem, esq. base): HP, Dano, Atk Speed, Move Speed.
# - Aliados (3 cards retrato, dir. topo): Woodwarden + slots futuros, placement.
# - Upgrades (3 cards retrato, dir. base): perfuração, multi, chain, life steal,
#   gold magnet, dash + subs, fire, curse.
# Player seleciona max 1 por categoria (upgrades pode ser 1-2 com bonus em waves
# pares). Placements (estrut + aliado) entram numa fila ao apertar "Próxima Wave".

signal closed

const PRICE_TABLE: Array[int] = [3, 6, 10, 15, 20]
const TOWER_PRICE: int = 10
const WOODWARDEN_PRICE_TABLE: Array[int] = [6, 10, 14, 18, 24, 30]
const STRUCTURE_SURCHARGE_PER_OWNED: int = 3

# Pool dos cards de status (passive stats — escalonáveis ilimitadamente).
const STATUS_POOL: Array = [
	{"id": "hp", "name": "Mais HP"},
	{"id": "damage", "name": "Dano"},
	{"id": "attack_speed", "name": "Atack Speed"},
	{"id": "move_speed", "name": "Move Speed"},
]

# Pool dos cards de upgrade (gameplay-changing items, com requirements).
const UPGRADE_POOL: Array = [
	{"id": "perfuracao", "name": "Perfuracao", "max_level": 4},
	{"id": "multi_arrow", "name": "Multiplas Flechas", "max_level": 4},
	{"id": "chain_lightning", "name": "Cadeia de Raios", "max_level": 4},
	{"id": "life_steal", "name": "Coleta de Coracao"},
	{"id": "gold_magnet", "name": "Ima de Gold", "max_level": 1},
	{"id": "dash", "name": "Dash", "max_level": 1},
	{"id": "dash_cooldown", "name": "Dash CD Reduce", "requires": "dash"},
	{"id": "dash_auto_attack", "name": "Dash Auto-Atk", "max_level": 1, "requires": "dash"},
	{"id": "dash_double_arrow", "name": "Dash 2 Flechas", "max_level": 1, "requires": "dash_auto_attack"},
	{"id": "fire_arrow", "name": "Flecha de Fogo", "max_level": 4},
	{"id": "curse_arrow", "name": "Flecha de Maldição", "max_level": 4},
]

const UPGRADE_PRICE_OVERRIDES: Dictionary = {
	"dash_auto_attack": 12,
	"dash_double_arrow": 18,
}

const HP_DESCS: Array[String] = ["+15 HP maximo", "+15 HP maximo", "+15 HP maximo", "+15 HP maximo"]
const DAMAGE_DESCS: Array[String] = ["+20% dano da flecha", "+20% dano da flecha", "+20% dano da flecha", "+20% dano da flecha"]
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
const GOLD_MAGNET_DESCS: Array[String] = ["Puxa todo gold +2%\nchance de drop"]
const DASH_DESCS: Array[String] = ["Espaco = dash\n(cd 4.5s)"]
const LIFE_STEAL_DESCS: Array[String] = [
	"Inimigos: 12% drop\ncoracao cura 20% HP",
	"+5% chance, +10%\nheal por stack",
	"+5% chance, +10%\nheal por stack",
	"+5% chance, +10%\nheal por stack",
]
const DASH_COOLDOWN_DESCS: Array[String] = [
	"-0.5s no cooldown\ndo dash (min 0.5s)",
	"-0.5s no cooldown\ndo dash (min 0.5s)",
	"-0.5s no cooldown\ndo dash (min 0.5s)",
	"-0.5s no cooldown\ndo dash (min 0.5s)",
]
const DASH_AUTO_ATTACK_DESCS: Array[String] = ["Dash dispara flecha\nauto no inimigo proximo"]
const DASH_DOUBLE_ARROW_DESCS: Array[String] = ["Dash dispara 2 flechas\nem sequencia"]
const FIRE_ARROW_DESCS: Array[String] = [
	"Flecha queima inimigos\n4 dmg/s por 3s",
	"+1 dmg/s queima +\nrastro de fogo (4 dps)",
	"Skill (Q): chama em\narea (12 dps, 6s, cd 7s)",
	"Rastro do player +30%\nem queimaduras +25% area",
]
const CURSE_ARROW_DESCS: Array[String] = [
	"Flecha amaldicoada:\nslow 35% + 3 dps toxic",
	"18% chance: kill vira\naliado ate fim da horda",
	"33% chance + aliados\naplicam slow/DoT",
	"50% chance + skill (Q):\nraio roxo, cd 20s",
]

@onready var gold_label: Label = $Root/GoldLabel
@onready var continue_btn: Button = $Root/ContinueBtn
@onready var placement_hint: Label = $PlacementHint
@onready var bg_rect: ColorRect = $Bg
@onready var root_panel: Control = $Root

@onready var estrut_cards: Array[Control] = [
	$Root/EstrutCard1,
	$Root/EstrutCard2,
]
@onready var status_cards: Array[Control] = [
	$Root/StatusCard1,
	$Root/StatusCard2,
]
@onready var upg_cards: Array[Control] = [
	$Root/UpgRow/UpgCard1,
	$Root/UpgRow/UpgCard2,
	$Root/UpgRow/UpgCard3,
]
@onready var aliado_cards: Array[Control] = [
	$Root/AliadoRow/AliadoCard1,
	$Root/AliadoRow/AliadoCard2,
	$Root/AliadoRow/AliadoCard3,
]

# Bonus +1 upgrade alterna por wave: pares (2,4,6...) liberam 2 upgrades.
var max_upgrades_this_round: int = 1

# Slots
var status_slots: Array = []
var estrutura_slots: Array = []
var upg_slots: Array = []
var aliado_slots: Array = []

# Selection state
var _selected_status_idx: int = -1
var _selected_estrut_idx: int = -1
var _selected_aliado_idx: int = -1
var _selected_upgrade_idxs: Array[int] = []

# Reroll: até N por categoria. Custo escala 1, 2, 3.
const REROLL_COSTS: Array[int] = [1, 2, 3]
const MAX_REROLLS_PER_CATEGORY: int = 3
var _status_rerolls_used: int = 0
var _estrut_rerolls_used: int = 0
var _upg_rerolls_used: int = 0
var _aliado_rerolls_used: int = 0
var _status_reroll_btn: TextureButton
var _estrut_reroll_btn: TextureButton
var _upg_reroll_btn: TextureButton
var _aliado_reroll_btn: TextureButton
var _status_reroll_widget: Control
var _estrut_reroll_widget: Control
var _upg_reroll_widget: Control
var _aliado_reroll_widget: Control

const BUY_SOUND: AudioStream = preload("res://audios/effects/buy_1.mp3")

# Placement mode
const PLACEMENT_BOUNDS: Rect2 = Rect2(-80, -40, 680, 380)
const PLACEMENT_MIN_DIST: float = 80.0
const PLACEMENT_CLICK_RADIUS: float = 60.0
const PLACEMENT_SPOT_COUNT: int = 5

var _placement_active: bool = false
var _placement_ghosts: Array[Node2D] = []
# Fila de placements pendentes (estrutura primeiro, aliado depois).
var _placement_queue: Array[Dictionary] = []
var _placement_current: Dictionary = {}

const SELECTED_TINT: Color = Color(1.4, 1.25, 0.5, 1.0)

# Layout editor (modo dev pra arrastar elementos da loja).
var _layout_edit_active: bool = false
var _layout_edit_panel: Control = null
var _layout_drag_target: Control = null
var _layout_drag_offset: Vector2 = Vector2.ZERO
const LAYOUT_EDIT_HIGHLIGHT: Color = Color(1.5, 0.6, 0.6, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm and int(wm.wave_number) % 2 == 0:
		max_upgrades_this_round = 2
	continue_btn.pressed.connect(_on_continue_pressed)
	_setup_reroll_buttons()
	_setup_bonus_label()
	_refresh_gold_label()
	_roll_all_slots()
	_build_all_cards()
	_connect_card_buttons()
	_refresh_button_states()
	_setup_layout_editor()


func _process(_delta: float) -> void:
	if _placement_active and not _placement_ghosts.is_empty():
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

func _roll_all_slots() -> void:
	_roll_status_slots()
	_roll_estrutura_slots()
	_roll_upg_slots()
	_roll_aliado_slots()


func _roll_status_slots() -> void:
	# 2 rolls distintos do STATUS_POOL.
	status_slots.clear()
	var picks: Array = STATUS_POOL.duplicate()
	picks.shuffle()
	var player := _get_player()
	for i in 2:
		if i >= picks.size():
			status_slots.append({"id": "none", "name": "—", "desc": "—", "price": 0, "available": false})
			continue
		var picked: Dictionary = picks[i]
		var picked_id: String = picked["id"]
		var current_level: int = 0
		if player != null and player.has_method("get_upgrade_count"):
			current_level = player.get_upgrade_count(picked_id)
		var target_level: int = current_level + 1
		var price: int = _status_price_for(picked_id, current_level)
		status_slots.append({
			"id": picked_id,
			"name": picked["name"],
			"desc": _get_upgrade_desc(picked_id, target_level),
			"price": price,
			"available": true,
			"target_level": target_level,
		})


func _status_price_for(id: String, current_level: int) -> int:
	# HP escala 1G, 2G, 3G... — outros stats usam PRICE_TABLE.
	if id == "hp":
		return current_level + 1
	return _get_upgrade_price(id, current_level)


func _roll_estrutura_slots() -> void:
	estrutura_slots.clear()
	var surcharge: int = STRUCTURE_SURCHARGE_PER_OWNED * _total_structures_bought()
	estrutura_slots.append({
		"id": "arrow_tower",
		"name": "Torre de Flechas",
		"desc": "Atira em inimigos\nproximos. 80% dano.",
		"price": TOWER_PRICE + surcharge,
		"available": true,
		"scene": "res://scenes/structures/arrow_tower.tscn",
	})
	estrutura_slots.append({"id": "soon", "name": "Em breve", "desc": "—", "price": 0, "available": false})


func _roll_aliado_slots() -> void:
	aliado_slots.clear()
	var surcharge: int = STRUCTURE_SURCHARGE_PER_OWNED * _total_structures_bought()
	var ww_lvl: int = 0
	var p := _get_player()
	if p != null and p.has_method("get_upgrade_count"):
		ww_lvl = p.get_upgrade_count("woodwarden")
	var ww_maxed: bool = ww_lvl >= 4
	var ww_price: int = WOODWARDEN_PRICE_TABLE[mini(ww_lvl, WOODWARDEN_PRICE_TABLE.size() - 1)] + surcharge
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
	aliado_slots.append({
		"id": "woodwarden",
		"name": "Woodwarden",
		"desc": ww_desc,
		"price": ww_price,
		"available": not ww_maxed,
		"scene": "res://scenes/woodwarden.tscn",
		"is_ally": true,
	})
	aliado_slots.append({"id": "soon", "name": "Em breve", "desc": "—", "price": 0, "available": false})
	aliado_slots.append({"id": "soon", "name": "Em breve", "desc": "—", "price": 0, "available": false})


func _roll_upg_slots() -> void:
	upg_slots.clear()
	var player := _get_player()
	var already_picked_ids: Array[String] = []
	var has_fire: bool = player != null and player.has_method("get_upgrade_count") and player.get_upgrade_count("fire_arrow") > 0
	var has_curse: bool = player != null and player.has_method("get_upgrade_count") and player.get_upgrade_count("curse_arrow") > 0
	for i in 3:
		var pool: Array = []
		for u in UPGRADE_POOL:
			var id: String = u["id"]
			var max_level: int = u.get("max_level", 999)
			var current: int = 0
			if player != null and player.has_method("get_upgrade_count"):
				current = player.get_upgrade_count(id)
			if current >= max_level:
				continue
			if id in already_picked_ids:
				continue
			if id == "fire_arrow" and has_curse:
				continue
			if id == "curse_arrow" and has_fire:
				continue
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
		var price: int = _get_upgrade_price(picked_id, current_level)
		upg_slots.append({
			"id": picked_id,
			"name": picked["name"],
			"desc": _get_upgrade_desc(picked_id, target_level),
			"price": price,
			"available": true,
			"target_level": target_level,
		})


func _get_upgrade_price(id: String, player_current_level: int) -> int:
	if id in UPGRADE_PRICE_OVERRIDES:
		return int(UPGRADE_PRICE_OVERRIDES[id])
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

func _build_all_cards() -> void:
	for i in 2:
		_build_card(estrut_cards[i], estrutura_slots[i], 0)
	for i in 2:
		var tl: int = int(status_slots[i].get("target_level", 0))
		_build_card(status_cards[i], status_slots[i], tl)
	for i in 3:
		var tl2: int = int(upg_slots[i].get("target_level", 0))
		_build_card(upg_cards[i], upg_slots[i], tl2)
	for i in 3:
		_build_card(aliado_cards[i], aliado_slots[i], 0)


func _build_card(card: Control, slot: Dictionary, target_level: int) -> void:
	var available: bool = slot.get("available", false)
	var title_label: Label = card.get_node("TitleLabel")
	title_label.text = slot.get("name", "—")
	title_label.modulate = _level_tint_for_label(target_level) if (available and target_level > 0) else Color.WHITE
	card.get_node("DescLabel").text = slot.get("desc", "—")
	card.get_node("PriceLabel").text = ("%d coins" % int(slot.get("price", 0))) if available else "—"
	var stars_label: Label = card.get_node_or_null("StarsLabel")
	if stars_label != null:
		var stars_str: String = _stars_text(target_level) if (available and target_level > 0) else ""
		stars_label.text = stars_str
		stars_label.modulate = _level_tint_for_label(target_level) if (available and target_level > 0) else Color.WHITE


func _connect_card_buttons() -> void:
	for i in 2:
		_connect_button(estrut_cards[i].get_node("BuyBtn"), Callable(self, "_buy_estrutura").bind(i))
	for i in 2:
		_connect_button(status_cards[i].get_node("BuyBtn"), Callable(self, "_buy_status").bind(i))
	for i in 3:
		_connect_button(upg_cards[i].get_node("BuyBtn"), Callable(self, "_buy_upgrade").bind(i))
	for i in 3:
		_connect_button(aliado_cards[i].get_node("BuyBtn"), Callable(self, "_buy_aliado").bind(i))


func _connect_button(btn_node: Node, target: Callable) -> void:
	var btn := btn_node as Button
	if btn == null:
		return
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(target)


# ---------- Compra (toggle) ----------

func _buy_status(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = status_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_status_idx == idx:
		_selected_status_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	# Swap permitido (devolve preço do status já selecionado).
	if player.gold < _selected_total_cost() - _status_price() + price:
		return
	_selected_status_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_estrutura(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = estrutura_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_estrut_idx == idx:
		_selected_estrut_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() - _estrut_price() + price:
		return
	_selected_estrut_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_aliado(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = aliado_slots[idx]
	if not slot.get("available", false):
		return
	if _selected_aliado_idx == idx:
		_selected_aliado_idx = -1
		_refresh_button_states()
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() - _aliado_price() + price:
		return
	_selected_aliado_idx = idx
	_play_buy_sound()
	_refresh_button_states()


func _buy_upgrade(idx: int) -> void:
	if _placement_active:
		return
	var slot: Dictionary = upg_slots[idx]
	if not slot.get("available", false):
		return
	if idx in _selected_upgrade_idxs:
		_selected_upgrade_idxs.erase(idx)
		_refresh_button_states()
		return
	if _selected_upgrade_idxs.size() >= max_upgrades_this_round:
		return
	if _is_elemental_blocked_by_selection(slot.get("id", "")):
		return
	var player := _get_player()
	if player == null:
		return
	var price: int = int(slot["price"])
	if player.gold < _selected_total_cost() + price:
		return
	_selected_upgrade_idxs.append(idx)
	_play_buy_sound()
	_refresh_button_states()


func _is_elemental_blocked_by_selection(id: String) -> bool:
	if id != "fire_arrow" and id != "curse_arrow":
		return false
	var counterpart: String = "curse_arrow" if id == "fire_arrow" else "fire_arrow"
	for sel_idx in _selected_upgrade_idxs:
		if upg_slots[sel_idx].get("id", "") == counterpart:
			return true
	return false


# ---------- Selection accounting ----------

func _selected_upgrades_total_cost() -> int:
	var total: int = 0
	for i in _selected_upgrade_idxs:
		total += int(upg_slots[i].get("price", 0))
	return total


func _selected_total_cost() -> int:
	var total: int = _selected_upgrades_total_cost()
	if _selected_status_idx >= 0:
		total += int(status_slots[_selected_status_idx].get("price", 0))
	if _selected_estrut_idx >= 0:
		total += int(estrutura_slots[_selected_estrut_idx].get("price", 0))
	if _selected_aliado_idx >= 0:
		total += int(aliado_slots[_selected_aliado_idx].get("price", 0))
	return total


func _status_price() -> int:
	return int(status_slots[_selected_status_idx].get("price", 0)) if _selected_status_idx >= 0 else 0


func _estrut_price() -> int:
	return int(estrutura_slots[_selected_estrut_idx].get("price", 0)) if _selected_estrut_idx >= 0 else 0


func _aliado_price() -> int:
	return int(aliado_slots[_selected_aliado_idx].get("price", 0)) if _selected_aliado_idx >= 0 else 0


# ---------- Refresh ----------

func _refresh_button_states() -> void:
	var player := _get_player()
	var current_gold: int = player.gold if player != null else 0
	var pending_cost: int = _selected_total_cost()
	var available_gold: int = current_gold - pending_cost
	_refresh_reroll(_status_reroll_btn, _status_reroll_widget, _status_rerolls_used, available_gold)
	_refresh_reroll(_estrut_reroll_btn, _estrut_reroll_widget, _estrut_rerolls_used, available_gold)
	_refresh_reroll(_upg_reroll_btn, _upg_reroll_widget, _upg_rerolls_used, available_gold)
	_refresh_reroll(_aliado_reroll_btn, _aliado_reroll_widget, _aliado_rerolls_used, available_gold)
	_refresh_gold_label()
	# Status (single-select com swap).
	for i in 2:
		var slot: Dictionary = status_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_status_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _status_price() + price
		_apply_card_state(status_cards[i], slot, is_selected, afford_swap)
	# Estrutura (single-select com swap).
	for i in 2:
		var slot: Dictionary = estrutura_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_estrut_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _estrut_price() + price
		_apply_card_state(estrut_cards[i], slot, is_selected, afford_swap)
	# Aliado (single-select com swap).
	for i in 3:
		var slot: Dictionary = aliado_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = _selected_aliado_idx == i
		var afford_swap: bool = current_gold >= pending_cost - _aliado_price() + price
		_apply_card_state(aliado_cards[i], slot, is_selected, afford_swap)
	# Upgrades (multi-select limitado).
	var limit_reached: bool = _selected_upgrade_idxs.size() >= max_upgrades_this_round
	for i in 3:
		var slot: Dictionary = upg_slots[i]
		var price: int = int(slot.get("price", 0))
		var is_selected: bool = i in _selected_upgrade_idxs
		var blocked: bool = _is_elemental_blocked_by_selection(slot.get("id", ""))
		var can_select: bool = not limit_reached and available_gold >= price and not blocked
		_apply_card_state(upg_cards[i], slot, is_selected, can_select or is_selected)


func _refresh_reroll(btn: TextureButton, widget: Control, used: int, available_gold: int) -> void:
	if btn == null:
		return
	var maxed: bool = used >= MAX_REROLLS_PER_CATEGORY
	var cost: int = _next_reroll_cost(used)
	var disabled: bool = maxed or available_gold < cost
	btn.disabled = disabled
	_set_reroll_widget_dim(widget, disabled)
	_update_reroll_price_label(widget, cost, maxed)


func _apply_card_state(card: Control, slot: Dictionary, is_selected: bool, can_buy: bool) -> void:
	var available: bool = slot.get("available", false)
	var bg: TextureRect = card.get_node_or_null("Bg") as TextureRect
	if bg != null:
		# Mantém o tint base configurado na .tscn (ex: laranja do upgrade card)
		# e multiplica por SELECTED_TINT quando selecionado.
		if not card.has_meta("base_tint"):
			card.set_meta("base_tint", bg.modulate)
		var base_tint: Color = card.get_meta("base_tint")
		if not available:
			bg.modulate = base_tint * Color(0.5, 0.5, 0.5, 0.7)
		elif is_selected:
			bg.modulate = base_tint * SELECTED_TINT
		else:
			bg.modulate = base_tint
	var btn: Button = card.get_node_or_null("BuyBtn") as Button
	if btn != null:
		btn.disabled = not available or (not is_selected and not can_buy)


# ---------- Continue & placement queue ----------

func _on_continue_pressed() -> void:
	if _placement_active:
		_cancel_placement()
		return
	_placement_queue.clear()
	if _selected_estrut_idx >= 0:
		var sel_e: Dictionary = estrutura_slots[_selected_estrut_idx]
		if sel_e.get("available", false) and "scene" in sel_e:
			_placement_queue.append({"type": "estrutura", "slot": sel_e})
	if _selected_aliado_idx >= 0:
		var sel_a: Dictionary = aliado_slots[_selected_aliado_idx]
		if sel_a.get("available", false) and "scene" in sel_a:
			_placement_queue.append({"type": "aliado", "slot": sel_a})
	if _placement_queue.is_empty():
		_commit_status_only()
		_commit_upgrades_and_close()
		return
	_process_next_placement()


func _process_next_placement() -> void:
	if _placement_queue.is_empty():
		_commit_status_only()
		_commit_upgrades_and_close()
		return
	_placement_current = _placement_queue.pop_front()
	_enter_placement_mode(_placement_current["slot"])


func _commit_status_only() -> void:
	var player := _get_player()
	if player == null:
		return
	if _selected_status_idx >= 0:
		var slot: Dictionary = status_slots[_selected_status_idx]
		if slot.get("available", false):
			if player.spend_gold(int(slot.get("price", 0))):
				if player.has_method("apply_upgrade"):
					player.apply_upgrade(slot["id"])
		_selected_status_idx = -1


func _commit_upgrades_and_close() -> void:
	var player := _get_player()
	if player != null:
		for idx in _selected_upgrade_idxs:
			var slot: Dictionary = upg_slots[idx]
			if not player.spend_gold(int(slot.get("price", 0))):
				continue
			if player.has_method("apply_upgrade"):
				player.apply_upgrade(slot["id"])
	closed.emit()


# ---------- Placement mode ----------

func _enter_placement_mode(slot: Dictionary) -> void:
	var scene: PackedScene = load(slot["scene"])
	if scene == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
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
	bg_rect.visible = false
	root_panel.visible = false
	placement_hint.visible = true
	_set_camera_overview(true)


func _confirm_placement_at(chosen: Node2D) -> void:
	var slot: Dictionary = _placement_current["slot"]
	var player := _get_player()
	if player == null or not player.spend_gold(int(slot["price"])):
		_cancel_placement()
		return
	for g in _placement_ghosts:
		if not is_instance_valid(g):
			continue
		if g == chosen:
			g.modulate = Color(1, 1, 1, 1)
			g.process_mode = Node.PROCESS_MODE_INHERIT
		else:
			g.queue_free()
	_placement_ghosts.clear()
	if slot.get("id", "") == "woodwarden" and player.has_method("apply_upgrade"):
		player.apply_upgrade("woodwarden")
		var wm0 := get_tree().get_first_node_in_group("wave_manager")
		if wm0 != null and wm0.has_method("_apply_woodwarden_scaling_if_applicable"):
			wm0._apply_woodwarden_scaling_if_applicable(chosen, slot["scene"])
			if "max_hp" in chosen and "hp" in chosen:
				chosen.hp = chosen.max_hp
				if chosen.has_node("HpBar"):
					chosen.get_node("HpBar").set_ratio(1.0)
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("register_structure"):
		wm.register_structure(slot["scene"], chosen.global_position, chosen)
	if _placement_current.get("type", "") == "estrutura":
		_selected_estrut_idx = -1
	elif _placement_current.get("type", "") == "aliado":
		_selected_aliado_idx = -1
	_placement_current = {}
	_exit_placement_mode()
	_process_next_placement()


func _cancel_placement() -> void:
	for g in _placement_ghosts:
		if is_instance_valid(g):
			g.queue_free()
	_placement_ghosts.clear()
	_placement_queue.clear()
	_placement_current = {}
	_exit_placement_mode()
	_refresh_button_states()


func _exit_placement_mode() -> void:
	_placement_active = false
	bg_rect.visible = true
	root_panel.visible = true
	placement_hint.visible = false
	_set_camera_overview(false)


func _set_camera_overview(active: bool) -> void:
	var camera := get_viewport().get_camera_2d()
	if camera != null and camera.has_method("set_overview_mode"):
		camera.set_overview_mode(active)


# ---------- Tier visuals ----------

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


func _level_tint_for_label(level: int) -> Color:
	match level:
		1: return Color(1.0, 1.0, 1.0, 1.0)
		2: return Color(0.55, 0.85, 1.0, 1.0)
		3: return Color(0.95, 0.6, 1.0, 1.0)
		_: return Color(1.0, 0.85, 0.3, 1.0)


# ---------- Gold label ----------

func _refresh_gold_label() -> void:
	var player := _get_player()
	var g: int = player.gold if player != null else 0
	var available: int = g - _selected_total_cost()
	gold_label.text = "%d coins" % available


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


func _total_structures_bought() -> int:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null or not "owned_structures" in wm:
		return 0
	return (wm.owned_structures as Array).size()


func _play_buy_sound() -> void:
	if BUY_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = BUY_SOUND
	p.volume_db = -16.0
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


# ---------- Bonus +1 upgrade label ----------

func _setup_bonus_label() -> void:
	if max_upgrades_this_round <= 1:
		return
	var upg_header: Label = $Root/UpgHeader
	if upg_header == null:
		return
	var bonus := Label.new()
	bonus.name = "BonusUpgradeLabel"
	bonus.text = "BONUS +1!"
	var at01_font: Font = load("res://font/at01.ttf")
	if at01_font != null:
		bonus.add_theme_font_override("font", at01_font)
	bonus.add_theme_font_size_override("font_size", 22)
	bonus.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	bonus.position = Vector2(720, 4)
	bonus.size = Vector2(200, 40)
	upg_header.add_child(bonus)
	var tw := bonus.create_tween().set_loops()
	tw.tween_property(bonus, "modulate:a", 0.55, 0.6)
	tw.tween_property(bonus, "modulate:a", 1.0, 0.6)


# ---------- Reroll (4 categorias) ----------

func _setup_reroll_buttons() -> void:
	_status_reroll_widget = _attach_reroll_to("Root/StatusReroll")
	if _status_reroll_widget != null:
		_status_reroll_btn = _status_reroll_widget.get_node("IconWrap/Btn") as TextureButton
		if _status_reroll_btn != null:
			_status_reroll_btn.pressed.connect(_on_status_reroll)
	_estrut_reroll_widget = _attach_reroll_to("Root/EstrutReroll")
	if _estrut_reroll_widget != null:
		_estrut_reroll_btn = _estrut_reroll_widget.get_node("IconWrap/Btn") as TextureButton
		if _estrut_reroll_btn != null:
			_estrut_reroll_btn.pressed.connect(_on_estrut_reroll)
	_upg_reroll_widget = _attach_reroll_to("Root/UpgReroll")
	if _upg_reroll_widget != null:
		_upg_reroll_btn = _upg_reroll_widget.get_node("IconWrap/Btn") as TextureButton
		if _upg_reroll_btn != null:
			_upg_reroll_btn.pressed.connect(_on_upg_reroll)
	_aliado_reroll_widget = _attach_reroll_to("Root/AliadoReroll")
	if _aliado_reroll_widget != null:
		_aliado_reroll_btn = _aliado_reroll_widget.get_node("IconWrap/Btn") as TextureButton
		if _aliado_reroll_btn != null:
			_aliado_reroll_btn.pressed.connect(_on_aliado_reroll)


func _attach_reroll_to(anchor_path: String) -> Control:
	var anchor := get_node_or_null(anchor_path) as Control
	if anchor == null:
		return null
	var widget := _make_reroll_pair()
	widget.name = "RerollPair"
	anchor.add_child(widget)
	widget.position = Vector2.ZERO
	return widget


func _on_status_reroll() -> void:
	if _status_rerolls_used >= MAX_REROLLS_PER_CATEGORY:
		return
	var cost: int = _next_reroll_cost(_status_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_status_rerolls_used += 1
	_selected_status_idx = -1
	_play_buy_sound()
	_roll_status_slots()
	_build_all_cards()
	_refresh_button_states()


func _on_estrut_reroll() -> void:
	if _estrut_rerolls_used >= MAX_REROLLS_PER_CATEGORY:
		return
	var cost: int = _next_reroll_cost(_estrut_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_estrut_rerolls_used += 1
	_selected_estrut_idx = -1
	_play_buy_sound()
	_roll_estrutura_slots()
	_build_all_cards()
	_refresh_button_states()


func _on_upg_reroll() -> void:
	if _upg_rerolls_used >= MAX_REROLLS_PER_CATEGORY:
		return
	var cost: int = _next_reroll_cost(_upg_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_upg_rerolls_used += 1
	_selected_upgrade_idxs.clear()
	_play_buy_sound()
	_roll_upg_slots()
	_build_all_cards()
	_refresh_button_states()


func _on_aliado_reroll() -> void:
	if _aliado_rerolls_used >= MAX_REROLLS_PER_CATEGORY:
		return
	var cost: int = _next_reroll_cost(_aliado_rerolls_used)
	var player := _get_player()
	if player == null or not player.spend_gold(cost):
		return
	_aliado_rerolls_used += 1
	_selected_aliado_idx = -1
	_play_buy_sound()
	_roll_aliado_slots()
	_build_all_cards()
	_refresh_button_states()


func _next_reroll_cost(rerolls_used: int) -> int:
	var idx: int = clampi(rerolls_used, 0, REROLL_COSTS.size() - 1)
	return REROLL_COSTS[idx]


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


func _update_reroll_price_label(widget: Control, cost: int, maxed: bool) -> void:
	if widget == null or not is_instance_valid(widget):
		return
	var price: Label = widget.get_node_or_null("Price") as Label
	if price == null:
		return
	price.text = "—" if maxed else "%d" % cost


const REROLL_BUTTON_SIZE: Vector2 = Vector2(48, 48)


func _make_reroll_pair() -> HBoxContainer:
	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 6)
	pair.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon_wrap := _make_reroll_widget()
	icon_wrap.name = "IconWrap"
	pair.add_child(icon_wrap)
	var price := Label.new()
	price.name = "Price"
	price.text = "%d" % REROLL_COSTS[0]
	var at01_font: Font = load("res://font/at01.ttf")
	if at01_font != null:
		price.add_theme_font_override("font", at01_font)
	price.add_theme_font_size_override("font_size", 22)
	price.add_theme_color_override("font_color", Color(1, 0.85, 0.35, 1))
	pair.add_child(price)
	return pair


func _make_reroll_widget() -> Control:
	var tex: Texture2D = load("res://assets/Hud/new reroll.png")
	var container := Control.new()
	container.custom_minimum_size = REROLL_BUTTON_SIZE
	container.size = REROLL_BUTTON_SIZE
	container.tooltip_text = "Re-roll (1: 1 coin, 2: 2 coins, 3: 3 coins)"
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


# ---------- Layout Editor (dev) ----------
# Modo dev pra arrastar elementos da loja com mouse e exportar offsets.
# Toggle no botão "EDIT LAYOUT" (canto inferior direito). Ao ativar:
# - Cada elemento editável ganha highlight vermelho.
# - Clique e arraste move o offset_left/top.
# - "PRINT VALUES" loga todas as posições no console pra commitar na .tscn.

func _setup_layout_editor() -> void:
	_layout_edit_panel = Control.new()
	_layout_edit_panel.name = "LayoutEditorPanel"
	_layout_edit_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_layout_edit_panel.position = Vector2(-360, -180)
	_layout_edit_panel.size = Vector2(340, 160)
	_layout_edit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$Root.add_child(_layout_edit_panel)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout_edit_panel.add_child(bg)
	var at01: Font = load("res://font/at01.ttf")
	var toggle := Button.new()
	toggle.position = Vector2(10, 10)
	toggle.size = Vector2(320, 60)
	toggle.text = "EDIT LAYOUT: OFF"
	if at01 != null:
		toggle.add_theme_font_override("font", at01)
	toggle.add_theme_font_size_override("font_size", 24)
	toggle.pressed.connect(_toggle_layout_edit.bind(toggle))
	_layout_edit_panel.add_child(toggle)
	var print_btn := Button.new()
	print_btn.position = Vector2(10, 80)
	print_btn.size = Vector2(320, 60)
	print_btn.text = "PRINT VALUES"
	if at01 != null:
		print_btn.add_theme_font_override("font", at01)
	print_btn.add_theme_font_size_override("font_size", 24)
	print_btn.pressed.connect(_print_layout_values)
	_layout_edit_panel.add_child(print_btn)


func _toggle_layout_edit(toggle_btn: Button) -> void:
	_layout_edit_active = not _layout_edit_active
	toggle_btn.text = "EDIT LAYOUT: ON" if _layout_edit_active else "EDIT LAYOUT: OFF"
	for n in _editable_layout_nodes():
		if _layout_edit_active:
			(n as CanvasItem).self_modulate = LAYOUT_EDIT_HIGHLIGHT
		else:
			(n as CanvasItem).self_modulate = Color.WHITE
	# Quando edit mode tá ON, desabilita os BuyBtn-overlay dos cards pra cliques
	# de drag não acionarem compra.
	for card in _all_card_controls():
		var btn := card.get_node_or_null("BuyBtn") as Button
		if btn != null:
			btn.visible = not _layout_edit_active


func _editable_layout_nodes() -> Array:
	# Tudo que faz sentido reposicionar: headers, cards, rerolls, gold, continue.
	var nodes: Array = []
	for n_path in [
		"Root/GoldLabel",
		"Root/EstrutHeader", "Root/EstrutReroll", "Root/EstrutCard1", "Root/EstrutCard2",
		"Root/StatusHeader", "Root/StatusReroll", "Root/StatusCard1", "Root/StatusCard2",
		"Root/AliadoHeader", "Root/AliadoReroll", "Root/AliadoRow",
		"Root/UpgHeader", "Root/UpgReroll", "Root/UpgRow",
		"Root/ContinueBtn",
	]:
		var n := get_node_or_null(n_path)
		if n != null and n is Control:
			nodes.append(n)
	return nodes


func _all_card_controls() -> Array:
	var arr: Array = []
	arr.append_array(estrut_cards)
	arr.append_array(status_cards)
	arr.append_array(upg_cards)
	arr.append_array(aliado_cards)
	return arr


func _gui_input_drag(event: InputEvent) -> void:
	pass  # placeholder, drag é via _input global abaixo


func _unhandled_input(event: InputEvent) -> void:
	if not _layout_edit_active:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			# Pega o nó editável mais ao topo sob o mouse.
			var picked: Control = _pick_editable_under_mouse(mb.position)
			if picked != null:
				_layout_drag_target = picked
				_layout_drag_offset = mb.position - Vector2(picked.offset_left, picked.offset_top)
				get_viewport().set_input_as_handled()
		else:
			if _layout_drag_target != null:
				_layout_drag_target = null
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _layout_drag_target != null:
		var mm: InputEventMouseMotion = event
		var new_pos: Vector2 = mm.position - _layout_drag_offset
		var w: float = _layout_drag_target.offset_right - _layout_drag_target.offset_left
		var h: float = _layout_drag_target.offset_bottom - _layout_drag_target.offset_top
		_layout_drag_target.offset_left = new_pos.x
		_layout_drag_target.offset_top = new_pos.y
		_layout_drag_target.offset_right = new_pos.x + w
		_layout_drag_target.offset_bottom = new_pos.y + h


func _pick_editable_under_mouse(mouse_pos: Vector2) -> Control:
	# Itera ao contrário (o último adicionado é o mais "no topo" visualmente).
	var candidates: Array = _editable_layout_nodes()
	candidates.reverse()
	for n in candidates:
		var c: Control = n
		var rect := Rect2(Vector2(c.offset_left, c.offset_top), Vector2(c.offset_right - c.offset_left, c.offset_bottom - c.offset_top))
		if rect.has_point(mouse_pos):
			return c
	return null


func _print_layout_values() -> void:
	print("===== SHOP LAYOUT VALUES =====")
	for n in _editable_layout_nodes():
		var c: Control = n
		print("%s: offset_left=%d offset_top=%d offset_right=%d offset_bottom=%d" % [
			c.get_path(), int(c.offset_left), int(c.offset_top), int(c.offset_right), int(c.offset_bottom)
		])
	print("=============================")
