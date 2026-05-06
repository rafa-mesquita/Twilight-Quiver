extends CanvasLayer

# Painel de controle pro dev mode no canto inferior-direito.
# Dropup: só o título visível por default; clica e o Content abre acima.

const SPAWN_OFFSET_DISTANCE: float = 60.0


func _ready() -> void:
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
	$Content/Scroll/VBox/ShopSection/ShopContent/UpgHpBtn.pressed.connect(_apply_upgrade.bind("hp"))
	$Content/Scroll/VBox/ShopSection/ShopContent/UpgDamageBtn.pressed.connect(_apply_upgrade.bind("damage"))
	$Content/Scroll/VBox/ShopSection/ShopContent/UpgPerfBtn.pressed.connect(_apply_upgrade.bind("perfuracao"))
	$Content/Scroll/VBox/MenuBtn.pressed.connect(_back_to_menu)
	# Headers das seções (já abrem/fecham seu próprio content)
	_setup_section($Content/Scroll/VBox/EnemySection/EnemyHeader,
		$Content/Scroll/VBox/EnemySection/EnemyContent, "Spawn enemy")
	_setup_section($Content/Scroll/VBox/PlayerSection/PlayerHeader,
		$Content/Scroll/VBox/PlayerSection/PlayerContent, "Player / world")
	_setup_section($Content/Scroll/VBox/ShopSection/ShopHeader,
		$Content/Scroll/VBox/ShopSection/ShopContent, "Shop / Test")
	# Toggle principal: dropup do Content inteiro.
	$MainToggle.pressed.connect(_on_main_toggle)


func _on_main_toggle() -> void:
	var content: Control = $Content
	content.visible = not content.visible
	$MainToggle.text = "DEV MODE ▼" if content.visible else "DEV MODE ▲"


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


func _apply_upgrade(upgrade_id: String) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("apply_upgrade"):
		player.apply_upgrade(upgrade_id)
