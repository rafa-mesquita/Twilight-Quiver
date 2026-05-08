extends CanvasLayer

# Painel de controle pro dev mode no canto inferior-direito.
# Dropup: só o título visível por default; clica e o Content abre acima.

const SPAWN_OFFSET_DISTANCE: float = 60.0
const INF_LEVEL: int = 999

# Última compra aplicada — Z re-aplica pra agilizar testes (especialmente o dash
# e suas sub-melhorias). Só guarda IDs do UPGRADE_BTNS.
var _last_upgrade_id: String = ""

# Catálogo de upgrades exibidos no painel. `max` = nível máximo do upgrade
# (botão fica disabled quando atinge). `requires` = id de outro upgrade que
# precisa estar no nível 1+ pra esse botão ficar VISÍVEL (sub-níveis do dash).
# `base_text` = label original; o painel adiciona "[X/Y]" ou "[máx]" dinamicamente.
const UPGRADE_BTNS: Array = [
	{"id": "hp", "node": "UpgHpBtn", "max": INF_LEVEL, "base_text": "+1 HP"},
	{"id": "damage", "node": "UpgDamageBtn", "max": INF_LEVEL, "base_text": "+1 Dano"},
	{"id": "perfuracao", "node": "UpgPerfBtn", "max": 4, "base_text": "+1 Perfuracao"},
	{"id": "attack_speed", "node": "UpgAtkSpeedBtn", "max": INF_LEVEL, "base_text": "+1 Atk Speed"},
	{"id": "multi_arrow", "node": "UpgMultiArrowBtn", "max": 4, "base_text": "+1 Multi Arrow"},
	{"id": "chain_lightning", "node": "UpgChainBtn", "max": 4, "base_text": "+1 Cadeia de Raios"},
	{"id": "move_speed", "node": "UpgMoveSpeedBtn", "max": INF_LEVEL, "base_text": "+1 Move Speed"},
	{"id": "gold_magnet", "node": "UpgGoldMagnetBtn", "max": 4, "base_text": "+1 Chuva de Coins"},
	{"id": "life_steal", "node": "UpgLifeStealBtn", "max": 4, "base_text": "+1 Coleta de Coracao"},
	{"id": "fire_arrow", "node": "UpgFireArrowBtn", "max": 4, "base_text": "+1 Flecha de Fogo"},
	{"id": "curse_arrow", "node": "UpgCurseArrowBtn", "max": 4, "base_text": "+1 Disparo Profano"},
	{"id": "ricochet_arrow", "node": "UpgRicochetBtn", "max": 4, "base_text": "+1 Flecha Ricochete"},
	{"id": "dash", "node": "UpgDashBtn", "max": 4, "base_text": "+1 Dash"},
]


func _ready() -> void:
	# Botões do dev panel não devem capturar foco — senão Espaço/Enter
	# re-aciona o último clicado (ex: usuário aperta espaço pra dashar e
	# o botão "+1 Dash" recebe input e re-aplica o upgrade).
	_disable_focus_on_all_buttons(self)
	$Content/Scroll/VBox/EnemySection/EnemyContent/MonkeyBtn.pressed.connect(_spawn.bind("monkey"))
	$Content/Scroll/VBox/EnemySection/EnemyContent/MageBtn.pressed.connect(_spawn.bind("mage"))
	$Content/Scroll/VBox/EnemySection/EnemyContent/SummonerBtn.pressed.connect(_spawn.bind("summoner_mage"))
	$Content/Scroll/VBox/EnemySection/EnemyContent/InsectBtn.pressed.connect(_spawn.bind("insect"))
	$Content/Scroll/VBox/PlayerSection/PlayerContent/ResetHpBtn.pressed.connect(_reset_player_hp)
	$Content/Scroll/VBox/PlayerSection/PlayerContent/ClearBtn.pressed.connect(_clear_enemies)
	# Shop test buttons
	$Content/Scroll/VBox/ShopSection/ShopContent/OpenShopBtn.pressed.connect(_open_shop_directly)
	$Content/Scroll/VBox/ShopSection/ShopContent/AddGoldBtn.pressed.connect(_add_test_gold)
	$Content/Scroll/VBox/ShopSection/ShopContent/SpawnTowerBtn.pressed.connect(_spawn_tower_at_player)
	$Content/Scroll/VBox/ShopSection/ShopContent/SpawnWoodwardenBtn.pressed.connect(_spawn_woodwarden_at_player)
	# Conecta todos os botões de upgrade via UPGRADE_BTNS.
	for entry in UPGRADE_BTNS:
		var btn := _upgrade_btn(entry["node"]) as Button
		if btn != null:
			btn.pressed.connect(_apply_upgrade.bind(entry["id"]))
	$Content/Scroll/VBox/MenuBtn.pressed.connect(_back_to_menu)
	# Refresh inicial após o player estar pronto pra ler níveis atuais.
	_refresh_upgrade_buttons.call_deferred()
	# Headers das seções (já abrem/fecham seu próprio content)
	_setup_section($Content/Scroll/VBox/EnemySection/EnemyHeader,
		$Content/Scroll/VBox/EnemySection/EnemyContent, "Spawn enemy")
	_setup_section($Content/Scroll/VBox/PlayerSection/PlayerHeader,
		$Content/Scroll/VBox/PlayerSection/PlayerContent, "Player / world")
	_setup_section($Content/Scroll/VBox/ShopSection/ShopHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent, "Shop / Test")
	# Sub-seções de upgrades por categoria (ARCO/VIDA/MOV/ELEMENTAIS).
	_setup_section($Content/Scroll/VBox/ShopSection/ShopContent/ArcoSection/ArcoHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent/ArcoSection/ArcoContent, "Arco / Ataque")
	_setup_section($Content/Scroll/VBox/ShopSection/ShopContent/VidaSection/VidaHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent/VidaSection/VidaContent, "Vida / HP")
	_setup_section($Content/Scroll/VBox/ShopSection/ShopContent/MovSection/MovHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent/MovSection/MovContent, "Movimentacao")
	_setup_section($Content/Scroll/VBox/ShopSection/ShopContent/ElementaisSection/ElementaisHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent/ElementaisSection/ElementaisContent, "Elementais")
	# Toggle principal: dropup do Content inteiro.
	$MainToggle.pressed.connect(_on_main_toggle)


func _on_main_toggle() -> void:
	var content: Control = $Content
	content.visible = not content.visible
	$MainToggle.text = "DEV MODE ▼" if content.visible else "DEV MODE ▲"
	if content.visible:
		_refresh_upgrade_buttons()


func _setup_section(header: Button, content: Control, label: String) -> void:
	header.text = ("[-] " if content.visible else "[+] ") + label
	header.pressed.connect(func() -> void:
		content.visible = not content.visible
		header.text = ("[-] " if content.visible else "[+] ") + label
	)


func _spawn(type_key: String) -> void:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null or not wm.has_method("spawn_enemy_at"):
		if type_key == "insect":
			_spawn_insect_direct()
		return
	var pos := _spawn_position()
	if type_key == "insect":
		_spawn_insect_direct(pos)
		return
	wm.spawn_enemy_at(type_key, pos)


func _spawn_insect_direct(pos: Vector2 = Vector2.INF) -> void:
	var insect_scene: PackedScene = load("res://scenes/insect_enemy.tscn")
	if insect_scene == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var insect := insect_scene.instantiate()
	world.add_child(insect)
	insect.global_position = pos if pos != Vector2.INF else _spawn_position()


func _spawn_position() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return Vector2.ZERO
	var angle: float = randf() * TAU
	return player.global_position + Vector2(cos(angle), sin(angle)) * SPAWN_OFFSET_DISTANCE


func _reset_player_hp() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("reset_hp"):
		player.reset_hp()


func _clear_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()


func _back_to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _open_shop_directly() -> void:
	# Abre o shop standalone (não bloqueia o jogo). Útil pra testar UI sem terminar wave.
	var shop_scene: PackedScene = load("res://scenes/wave_shop.tscn")
	if shop_scene == null:
		return
	# Evita instâncias duplicadas se já tem um shop aberto.
	for n in get_tree().current_scene.get_children():
		if n.scene_file_path == "res://scenes/wave_shop.tscn":
			n.queue_free()
			return
	var shop = shop_scene.instantiate()
	get_tree().current_scene.add_child(shop)
	# Quando fechar, só remove (não tem wave pra continuar).
	if shop.has_signal("closed"):
		shop.closed.connect(func() -> void:
			if is_instance_valid(shop):
				shop.queue_free()
		)


func _add_test_gold() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_gold"):
		player.add_gold(50)


func _spawn_tower_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var tower_scene: PackedScene = load("res://scenes/structures/arrow_tower.tscn")
	if tower_scene == null:
		return
	var tower := tower_scene.instantiate()
	world.add_child(tower)
	tower.global_position = player.global_position + Vector2(48, 0)


func _spawn_woodwarden_at_player() -> void:
	# Increment level + spawn novo woodwarden + register pra respawnar entre rounds.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	if player.has_method("apply_upgrade"):
		player.apply_upgrade("woodwarden")
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var ww_scene: PackedScene = load("res://scenes/woodwarden.tscn")
	if ww_scene == null:
		return
	var ww := ww_scene.instantiate()
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("_apply_woodwarden_scaling_if_applicable"):
		wm._apply_woodwarden_scaling_if_applicable(ww, "res://scenes/woodwarden.tscn")
	world.add_child(ww)
	var pos: Vector2 = player.global_position + Vector2(48, 0)
	ww.global_position = pos
	if "max_hp" in ww and "hp" in ww:
		ww.hp = ww.max_hp
		if ww.has_node("HpBar"):
			ww.get_node("HpBar").set_ratio(1.0)
	if wm != null and wm.has_method("register_structure"):
		wm.register_structure("res://scenes/woodwarden.tscn", pos, ww)


func _apply_upgrade(upgrade_id: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("apply_upgrade"):
		return
	# Bloqueio defensivo: mesmo que o botão estivesse habilitado por bug,
	# não passa o limite de nível.
	for entry in UPGRADE_BTNS:
		if entry["id"] == upgrade_id:
			var current: int = 0
			if player.has_method("get_upgrade_count"):
				current = player.get_upgrade_count(upgrade_id)
			if current >= int(entry["max"]):
				return
			break
	player.apply_upgrade(upgrade_id)
	_last_upgrade_id = upgrade_id
	_refresh_upgrade_buttons()


func _unhandled_input(event: InputEvent) -> void:
	# Z (no dev mode) = re-aplica a última compra. Acelera testes — não precisa
	# voltar ao painel a cada iteração.
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_Z:
		if _last_upgrade_id != "":
			_apply_upgrade(_last_upgrade_id)
			get_viewport().set_input_as_handled()


func _disable_focus_on_all_buttons(node: Node) -> void:
	if node is BaseButton:
		(node as BaseButton).focus_mode = Control.FOCUS_NONE
	for child in node.get_children():
		_disable_focus_on_all_buttons(child)


func _upgrade_btn(node_name: String) -> Button:
	# Busca recursiva — botões foram organizados em sub-VBoxes por categoria
	# (ArcoSection/ArcoContent, VidaSection/VidaContent, etc.).
	var root: Node = $Content/Scroll/VBox/ShopSection/ShopContent
	var found: Node = root.find_child(node_name, true, false)
	return found as Button


func _refresh_upgrade_buttons() -> void:
	# Atualiza visibilidade (sub-níveis aparecem só depois do pré-requisito) +
	# disabled state (atingiu o max) + texto com "[X/Y]" ou "[máx]".
	var player := get_tree().get_first_node_in_group("player")
	for entry in UPGRADE_BTNS:
		var btn := _upgrade_btn(entry["node"])
		if btn == null:
			continue
		var current: int = 0
		if player != null and player.has_method("get_upgrade_count"):
			current = player.get_upgrade_count(entry["id"])
		# Visibilidade depende do pré-requisito (e.g., dash_cooldown precisa de dash).
		var visible: bool = true
		if entry.has("requires"):
			var req_id: String = entry["requires"]
			var req_lvl: int = 0
			if player != null and player.has_method("get_upgrade_count"):
				req_lvl = player.get_upgrade_count(req_id)
			visible = req_lvl > 0
		btn.visible = visible
		var max_level: int = int(entry["max"])
		var maxed: bool = current >= max_level
		btn.disabled = maxed
		var base_text: String = entry["base_text"]
		if max_level >= INF_LEVEL:
			btn.text = "%s [%d]" % [base_text, current]
		elif maxed:
			btn.text = "%s [max %d]" % [base_text, max_level]
		else:
			btn.text = "%s [%d/%d]" % [base_text, current, max_level]
