extends Node2D

# Wave manager: spawn de hordas a partir dos N spawn points mais longe do player.
# Cada wave tem uma config (tipo de inimigo → alive_target + total). Inimigos são
# escolhidos aleatoriamente dentre os tipos que ainda têm cota disponível, e
# spawnados em pontos aleatórios dos N mais longes (offscreen porque a câmera
# segue o player).

@export var monkey_scene: PackedScene
@export var mage_scene: PackedScene
@export var summoner_mage_scene: PackedScene
@export var spawn_delay: float = 0.5
@export var inter_wave_delay: float = 2.0
@export var pre_cleared_hold: float = 2.0  # tempo segurando 100% antes da tela "Wave Limpa"
@export var spawn_points_path: NodePath
@export var farthest_count: int = 3  # quantos spawn points ativos por wave (top N mais longe do player)
# Scaling por wave: cada wave acima da 1ª aumenta HP e dano dos inimigos linearmente.
@export var hp_growth_per_wave: float = 0.12  # +12% HP por wave
@export var damage_growth_per_wave: float = 0.08  # +8% dano por wave
# Wave 1: primeira impressão. Garante mínimo de N gold drops pra player ter coins
# pra primeira shop. Setado nos N primeiros spawns via guaranteed_gold_drop=true.
@export var wave1_min_guaranteed_drops: int = 4

var wave_number: int = 0
var spawn_points: Array[Marker2D] = []
var spawn_cooldown: float = 0.0
var wave_active: bool = false
var stopped: bool = false

# Per-wave state
var wave_config: Dictionary = {}  # {type_key: {"alive_target": int, "total": int}}
var spawned_this_wave: Dictionary = {}  # {type_key: int}
var total_to_spawn_this_wave: int = 0
var last_progress_killed: int = -1  # cache pra evitar spam de update na HUD
var _guaranteed_drops_remaining: int = 0  # contagem regressiva de spawns flagados pra dropar gold (wave 1)

# Registro de tipos: associa uma chave de string a (PackedScene, group_name).
# Pra adicionar um novo tipo de inimigo: registra aqui + adiciona group no script dele.
var type_registry: Dictionary = {}

# Estruturas que o player já comprou. Cada entrada: {scene_path: String, position: Vector2}.
# Usado pra renascer torres destruídas no início da próxima wave.
var owned_structures: Array = []


func _ready() -> void:
	add_to_group("wave_manager")
	# HUD e Cursor são instanciados em runtime (não estão no main.tscn) pra editor
	# do mapa ficar limpo — sem CanvasLayers cobrindo a view de edição.
	_instantiate_overlays()
	_collect_spawn_points()
	type_registry = {
		"monkey": {"scene": monkey_scene, "group": "monkey"},
		"mage": {"scene": mage_scene, "group": "mage"},
		"summoner_mage": {"scene": summoner_mage_scene, "group": "summoner_mage"},
	}
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("died"):
		player.died.connect(_on_player_died)
	# Dev mode: não dispara waves automáticas — DevPanel controla spawn manual.
	if _is_dev_mode():
		stopped = true
		_spawn_dev_panel.call_deferred()
		return
	_start_next_wave.call_deferred()


func _instantiate_overlays() -> void:
	var hud_scene: PackedScene = load("res://scenes/hud.tscn")
	if hud_scene != null:
		add_child(hud_scene.instantiate())
	var cursor_scene: PackedScene = load("res://scenes/cursor.tscn")
	if cursor_scene != null:
		add_child(cursor_scene.instantiate())


func _spawn_dev_panel() -> void:
	var panel_scene: PackedScene = load("res://scenes/dev_panel.tscn")
	if panel_scene != null:
		var panel := panel_scene.instantiate()
		get_tree().current_scene.add_child(panel)
	# HUD editor lateral esquerdo pra ajustar HUD ao vivo.
	var editor_scene: PackedScene = load("res://scenes/hud_editor.tscn")
	if editor_scene != null:
		var editor := editor_scene.instantiate()
		get_tree().current_scene.add_child(editor)


func _is_dev_mode() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and "dev_mode" in gs:
		return bool(gs.dev_mode)
	return false


func spawn_enemy_at(type_key: String, pos: Vector2) -> Node:
	# Usado pelo DevPanel pra spawnar inimigos de qualquer tipo registrado.
	var info: Dictionary = type_registry.get(type_key, {})
	if info.is_empty() or info["scene"] == null:
		return null
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	var enemy: Node2D = info["scene"].instantiate()
	world.add_child(enemy)
	enemy.global_position = pos
	return enemy


func _collect_spawn_points() -> void:
	spawn_points.clear()
	var container := get_node_or_null(spawn_points_path)
	if container == null:
		return
	for child in container.get_children():
		if child is Marker2D:
			spawn_points.append(child)


func _process(delta: float) -> void:
	if stopped or not wave_active:
		return
	_emit_progress()
	spawn_cooldown = maxf(spawn_cooldown - delta, 0.0)
	if spawn_cooldown > 0.0:
		return

	# Tenta spawnar um inimigo de um tipo que precisa (alive < target AND spawned < total).
	var picked_type: String = _pick_type_to_spawn()
	if picked_type != "":
		_spawn_one(picked_type)
		spawn_cooldown = spawn_delay
		return

	# Nenhum tipo precisando spawnar — wave acaba quando todos os inimigos morrerem.
	if _total_alive() == 0:
		_finish_wave()


func _start_next_wave() -> void:
	if stopped:
		return
	wave_number += 1
	wave_config = _build_wave_config(wave_number)
	spawned_this_wave.clear()
	for k: String in wave_config.keys():
		spawned_this_wave[k] = 0
	total_to_spawn_this_wave = _calc_total_to_spawn()
	last_progress_killed = -1
	spawn_cooldown = 0.0
	# Wave 1: primeiros N spawns dropam gold garantido. Wave 2+ usa só chance normal.
	_guaranteed_drops_remaining = wave1_min_guaranteed_drops if wave_number == 1 else 0

	# Reseta HP e posição do player antes da nova wave (camera segue → player no centro).
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_method("reset_hp"):
			player.reset_hp()
		if player.has_method("reset_position"):
			player.reset_position()
		if player.has_method("reset_perf_counter"):
			player.reset_perf_counter()
	# Renasce torres/aliados destruídos na wave anterior na mesma posição.
	_respawn_owned_structures()

	# Intro "Raid X" antes de spawnar nada.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("play_raid_intro"):
		await hud.play_raid_intro(wave_number)
	if stopped:
		return
	wave_active = true
	_emit_progress()


func _calc_total_to_spawn() -> int:
	var t: int = 0
	for k: String in wave_config.keys():
		t += int(wave_config[k]["total"])
	return t


func _emit_progress() -> void:
	var killed: int = _killed_count()
	if killed == last_progress_killed:
		return
	last_progress_killed = killed
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("update_wave_progress"):
		hud.update_wave_progress(killed, total_to_spawn_this_wave, wave_number)


func _killed_count() -> int:
	var spawned_total: int = 0
	for k: String in wave_config.keys():
		spawned_total += int(spawned_this_wave.get(k, 0))
	return spawned_total - _total_alive()


func _build_wave_config(num: int) -> Dictionary:
	# Wave 1: introdutória — sem invocador, poucos macacos.
	if num == 1:
		return {
			"monkey": {"alive_target": 3, "total": 8},
			"mage": {"alive_target": 2, "total": 4},
		}
	# Wave 2: invocador entra com cota mínima, escala leve sobre wave 1.
	# -5% aplicado nos totals (monkey 12→11; outros mantêm via arredondamento).
	if num == 2:
		return {
			"monkey": {"alive_target": 4, "total": 11},
			"mage": {"alive_target": 3, "total": 6},
			"summoner_mage": {"alive_target": 1, "total": 2},
		}
	# Waves 3+: escala automática + um pouco de aleatoriedade.
	# Quanto maior o wave_number, mais inimigos vivos e mais total.
	# Ratio macaco/mago varia entre ~70/30 e ~50/50 conforme a wave avança.
	# `WAVE_3PLUS_REDUCTION` reduz contagem em 13% do scale linear (afeta o número
	# de inimigos sem mexer na escala de stats).
	const WAVE_3PLUS_REDUCTION: float = 0.87
	var scale: float = (1.0 + (num - 1) * 0.35) * WAVE_3PLUS_REDUCTION
	var monkey_alive: int = int(round(5 * scale + randf_range(-1.0, 2.0)))
	var monkey_total: int = int(round(15 * scale + randf_range(0.0, 4.0)))
	var mage_alive: int = int(round(3 * scale + randf_range(0.0, 2.0)))
	var mage_total: int = int(round(6 * scale + randf_range(0.0, 3.0)))
	# Invocadores entram com força a partir da wave 2.
	var summ_alive: int = int(round(1 * scale + randf_range(0.0, 1.0)))
	var summ_total: int = int(round(3 * scale + randf_range(0.0, 2.0)))
	return {
		"monkey": {"alive_target": maxi(monkey_alive, 1), "total": maxi(monkey_total, monkey_alive)},
		"mage": {"alive_target": maxi(mage_alive, 1), "total": maxi(mage_total, mage_alive)},
		"summoner_mage": {"alive_target": maxi(summ_alive, 1), "total": maxi(summ_total, summ_alive)},
	}


func _pick_type_to_spawn() -> String:
	# Lista os tipos que ainda têm cota disponível (precisam de mais spawn).
	var candidates: Array[String] = []
	for type_key: String in wave_config.keys():
		var cfg: Dictionary = wave_config[type_key]
		var spawned: int = spawned_this_wave.get(type_key, 0)
		var alive: int = _alive_count_of(type_key)
		if spawned < cfg["total"] and alive < cfg["alive_target"]:
			candidates.append(type_key)
	if candidates.is_empty():
		return ""
	return candidates[randi() % candidates.size()]


func _alive_count_of(type_key: String) -> int:
	var info: Dictionary = type_registry.get(type_key, {})
	if info.is_empty():
		return 0
	return get_tree().get_nodes_in_group(info["group"]).size()


func _total_alive() -> int:
	return get_tree().get_nodes_in_group("enemy").size()


func _spawn_one(type_key: String) -> void:
	var info: Dictionary = type_registry.get(type_key, {})
	if info.is_empty() or info["scene"] == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	var pos: Vector2 = _pick_random_far_spawn_point()
	var enemy: Node2D = info["scene"].instantiate()
	# Aplica scaling de wave ANTES de add_child pra _ready do inimigo já usar max_hp escalado.
	_apply_wave_scaling(enemy)
	# Wave 1: marca os primeiros N spawns pra dropar gold garantido (mínimo de
	# moedas pro player ter o que comprar na 1ª shop).
	if _guaranteed_drops_remaining > 0 and "guaranteed_gold_drop" in enemy:
		enemy.guaranteed_gold_drop = true
		_guaranteed_drops_remaining -= 1
	world.add_child(enemy)
	enemy.global_position = pos
	spawned_this_wave[type_key] = spawned_this_wave.get(type_key, 0) + 1


func _apply_wave_scaling(enemy: Node) -> void:
	var hp_mult: float = 1.0 + maxf(wave_number - 1, 0) * hp_growth_per_wave
	var dmg_mult: float = 1.0 + maxf(wave_number - 1, 0) * damage_growth_per_wave
	if "max_hp" in enemy:
		enemy.max_hp = enemy.max_hp * hp_mult
	# Inimigos melee guardam dano em "damage" direto. Ranged (mage/insect) usam
	# "damage_mult" pra aplicar no projectile na hora do disparo.
	if "damage" in enemy:
		enemy.damage = enemy.damage * dmg_mult
	if "damage_mult" in enemy:
		enemy.damage_mult = dmg_mult
	if "hp_mult" in enemy:
		enemy.hp_mult = hp_mult


func _pick_random_far_spawn_point() -> Vector2:
	# Pega os N spawn points mais longe do player, escolhe um deles aleatoriamente.
	if spawn_points.is_empty():
		return Vector2.ZERO
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return spawn_points[randi() % spawn_points.size()].global_position

	var sorted: Array[Marker2D] = spawn_points.duplicate()
	sorted.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		var da: float = a.global_position.distance_squared_to(player.global_position)
		var db: float = b.global_position.distance_squared_to(player.global_position)
		return da > db
	)
	var top_n: int = mini(farthest_count, sorted.size())
	return sorted[randi() % top_n].global_position


func _finish_wave() -> void:
	wave_active = false
	# Garante que a barra mostra 100% antes da tela de "Wave Limpa".
	_emit_progress()
	# Maldição: aliados convertidos pela curse só duram até o fim da horda/turno.
	_cleanup_curse_allies()
	# Suga todas as moedas restantes do mapa pro player (auto-coleta).
	_magnet_remaining_gold()


func _cleanup_curse_allies() -> void:
	# Remove aliados convertidos pela Maldição. "Até final da horda" (lv2) e
	# "até final do turno" (lv3+) são equivalentes neste jogo (1 horda = 1 turno).
	for ally in get_tree().get_nodes_in_group("curse_ally"):
		if is_instance_valid(ally):
			ally.queue_free()
	# Mostra HUD em 100% por alguns segundos pro player ver o progresso completo.
	if pre_cleared_hold > 0.0:
		await get_tree().create_timer(pre_cleared_hold).timeout
	if stopped:
		return
	# Tela "Wave X Limpa" + botão "Continuar". Aguarda o player clicar.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("play_wave_cleared"):
		await hud.play_wave_cleared(wave_number)
	if stopped:
		return
	# Loja pós-wave: 1 estrutura + 1 upgrade max.
	await _open_shop()
	if stopped:
		return
	# Pequeno delay e próxima wave (que vai disparar o intro).
	if inter_wave_delay > 0.0:
		await get_tree().create_timer(inter_wave_delay).timeout
	_start_next_wave()


func _magnet_remaining_gold() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return
	var get_player_pos: Callable = func() -> Vector2:
		return player.global_position if is_instance_valid(player) else Vector2.ZERO
	for coin in get_tree().get_nodes_in_group("gold"):
		if not is_instance_valid(coin):
			continue
		if coin.has_method("magnet_to_player"):
			coin.magnet_to_player(get_player_pos)
	# Mesmo magnet pros corações de Life Steal — sweep de pickups no fim da wave.
	for heart in get_tree().get_nodes_in_group("heart"):
		if not is_instance_valid(heart):
			continue
		if heart.has_method("magnet_to_player"):
			heart.magnet_to_player(get_player_pos)


func _open_shop() -> void:
	var shop_scene: PackedScene = load("res://scenes/wave_shop.tscn")
	if shop_scene == null:
		return
	var shop = shop_scene.instantiate()
	get_tree().current_scene.add_child(shop)
	if shop.has_signal("closed"):
		await shop.closed
	if is_instance_valid(shop):
		shop.queue_free()


func _on_player_died() -> void:
	stopped = true
	wave_active = false


# Chamado pelo wave_shop quando o player confirma o placement de uma estrutura.
# Salva pra renascer entre waves se for destruída. Aceita ref do node atual
# pra rastrear se ainda tá vivo (estruturas móveis tipo woodwarden movem do
# spawn original — não dá pra checar só por proximidade de posição).
func register_structure(scene_path: String, pos: Vector2, instance: Node2D = null) -> void:
	owned_structures.append({
		"scene_path": scene_path,
		"position": pos,
		"instance": instance,
	})


func _respawn_owned_structures() -> void:
	if owned_structures.is_empty():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	# Pra cada entry, verifica se a instância registrada ainda existe. Se sim,
	# atualiza a posição salva (pra o respawn futuro acontecer onde ela morreu).
	# Se não, spawna uma nova na última posição conhecida.
	for entry in owned_structures:
		var inst_ref: Variant = entry.get("instance", null)
		if inst_ref != null and is_instance_valid(inst_ref) and (inst_ref as Node).is_inside_tree():
			# Vivo — atualiza posição pra próxima respawn ser na última posição dele.
			if inst_ref is Node2D:
				entry["position"] = (inst_ref as Node2D).global_position
			continue
		# Morto/freed — respawna na última posição conhecida.
		var pos: Vector2 = entry["position"]
		var scene: PackedScene = load(entry["scene_path"])
		if scene == null:
			continue
		var inst: Node2D = scene.instantiate()
		_apply_woodwarden_scaling_if_applicable(inst, entry["scene_path"])
		world.add_child(inst)
		inst.global_position = pos
		entry["instance"] = inst


# Aplica HP/dmg scalonado por nível do woodwarden_level do player. Cada compra
# aumenta os stats do aliado quando ele é spawnado (ou re-spawnado a cada round).
func _apply_woodwarden_scaling_if_applicable(inst: Node2D, scene_path: String) -> void:
	if not scene_path.ends_with("woodwarden.tscn"):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	var lvl: int = int(player.get_upgrade_count("woodwarden"))
	if lvl <= 1:
		return
	# +25 HP, +5 dmg por level acima de 1.
	if "max_hp" in inst:
		inst.max_hp = inst.max_hp + 25.0 * float(lvl - 1)
	if "damage" in inst:
		inst.damage = inst.damage + 5.0 * float(lvl - 1)


