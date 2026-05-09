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
@export var hp_growth_per_wave: float = 0.12  # +12% HP por wave (até wave 3)
@export var damage_growth_per_wave: float = 0.08  # +8% dano por wave (até wave 3)
# Wave 4+: cresce mais devagar — curva acumulada não fica brutal em sessões longas.
@export var hp_growth_per_wave_late: float = 0.08
@export var damage_growth_per_wave_late: float = 0.05
# Velocidade (movimento + atk speed) escala devagar: menos impacto que HP/dano.
# 4% por wave inicial, 2% após wave 3 — a cada wave o inimigo fica um pouco
# mais rápido tanto pra andar quanto pra atacar.
@export var speed_growth_per_wave: float = 0.02
@export var speed_growth_per_wave_late: float = 0.01
# Milestone: a cada N waves, aplica um boost EXTRA em todos os scalings
# (HP, dano, velocidade) — é o "salto de patamar" pra eras mais difíceis.
@export var milestone_interval: int = 5
@export var milestone_hp_bonus: float = 0.20
@export var milestone_damage_bonus: float = 0.15
@export var milestone_speed_bonus: float = 0.08
# Wave 1 pity system: garante mínimo de N moedas pra player não ser punido por
# RNG ruim na primeira shop. Só ATIVA se naturalmente caiu menos que N — os
# faltantes spawnam no _finish_wave (ainda pegos pelo magnet de fim de wave).
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
var _coins_dropped_this_wave: int = 0  # tracker pro pity system de gold drops da wave 1
var _player_gold_at_wave_start: int = 0  # snapshot pro pity computar gold real ganho na wave

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


# Dev helper: spawna `count` inimigos distribuídos entre `num_points` spawn
# points aleatórios. Cada inimigo sai de um ponto + offset pequeno pra não
# empilhar no Marker. Útil pra testar comportamento de horda.
func spawn_burst(type_key: String, count: int, num_points: int = 3) -> void:
	if spawn_points.is_empty() or count <= 0:
		return
	var pool: Array[Marker2D] = spawn_points.duplicate()
	pool.shuffle()
	var picked: Array[Marker2D] = []
	for i in mini(num_points, pool.size()):
		picked.append(pool[i])
	for i in count:
		var marker: Marker2D = picked[i % picked.size()]
		var off := Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		spawn_enemy_at(type_key, marker.global_position + off)


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
	_check_structure_respawns(delta)
	_emit_progress()
	spawn_cooldown = maxf(spawn_cooldown - delta, 0.0)
	if spawn_cooldown > 0.0:
		return

	# Tenta spawnar um inimigo de um tipo que precisa (alive < target AND spawned < total).
	var picked_type: String = _pick_type_to_spawn()
	if picked_type != "":
		_spawn_one(picked_type)
		spawn_cooldown = _spawn_delay_for_wave()
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
	# Reseta contador de moedas dropadas — pity system da wave 1 garante mínimo no _finish_wave.
	_coins_dropped_this_wave = 0

	# Reseta HP e posição do player antes da nova wave (camera segue → player no centro).
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_method("reset_hp"):
			player.reset_hp()
		if player.has_method("reset_position"):
			player.reset_position()
		if player.has_method("reset_perf_counter"):
			player.reset_perf_counter()
	# Snapshot do gold do player no início da wave — pity pega gold REAL ganho
	# (já coletado + ainda no chão), não conta em "coin entries" do drop.
	if player != null and "gold" in player:
		_player_gold_at_wave_start = int(player.gold)
	else:
		_player_gold_at_wave_start = 0
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
	# Wave 2: ainda sem invocador (entra só na wave 3). Escala leve sobre wave 1.
	if num == 2:
		return {
			"monkey": {"alive_target": 4, "total": 11},
			"mage": {"alive_target": 3, "total": 6},
		}
	# Waves 3+: escala automática + um pouco de aleatoriedade.
	# Quanto maior o wave_number, mais inimigos vivos e mais total.
	# Ratio macaco/mago varia entre ~70/30 e ~50/50 conforme a wave avança.
	# Wave 3 leva um corte extra (curva de aprendizado pós-wave 2).
	# Wave 5 também leva um corte (introdução do macaco camper + escala ficava
	# pesada com 47-56 mobs totais).
	var reduction: float = 0.87
	if num == 3:
		reduction = 0.72
	elif num == 5:
		reduction = 0.76
	var scale: float = (1.0 + (num - 1) * 0.35) * reduction
	var monkey_alive: int = int(round(5 * scale + randf_range(-1.0, 2.0)))
	var monkey_total: int = int(round(15 * scale + randf_range(0.0, 4.0)))
	var mage_alive: int = int(round(3 * scale + randf_range(0.0, 2.0)))
	var mage_total: int = int(round(6 * scale + randf_range(0.0, 3.0)))
	# Invocadores entram a partir da wave 3. Wave 3 é a estreia (cota bem
	# reduzida, ~1 summoner). Waves 4-8 levam metade. Wave 9+ valor cheio.
	var summ_scale_mult: float = 1.0
	if num == 3:
		summ_scale_mult = 0.35
	elif num >= 4 and num <= 8:
		summ_scale_mult = 0.5
	var summ_alive: int = int(round(1 * scale * summ_scale_mult + randf_range(0.0, 1.0)))
	var summ_total: int = int(round(3 * scale * summ_scale_mult + randf_range(0.0, 2.0)))
	# Wave 3: cap em 1 summoner total e -1 macaco (curva de estreia do invocador).
	if num == 3:
		summ_alive = mini(summ_alive, 1)
		summ_total = mini(summ_total, 1)
		monkey_alive = maxi(monkey_alive - 1, 1)
		monkey_total = maxi(monkey_total - 1, monkey_alive)
	return {
		"monkey": {"alive_target": maxi(monkey_alive, 1), "total": maxi(monkey_total, monkey_alive)},
		"mage": {"alive_target": maxi(mage_alive, 1), "total": maxi(mage_total, mage_alive)},
		"summoner_mage": {"alive_target": maxi(summ_alive, 1), "total": maxi(summ_total, summ_alive)},
	}


func _spawn_delay_for_wave() -> float:
	# Wave 3 spawna mais devagar pra dar respiro depois do salto da wave 2.
	if wave_number == 3:
		return spawn_delay * 1.6
	return spawn_delay


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
	world.add_child(enemy)
	enemy.global_position = pos
	spawned_this_wave[type_key] = spawned_this_wave.get(type_key, 0) + 1


func _apply_wave_scaling(enemy: Node) -> void:
	# Curva piecewise: waves 1→3 usam taxa cheia, wave 4+ usa taxa reduzida.
	# Velocidade escala mais devagar que HP/dano (impacto direto na sobrevivência
	# do player sente mais quando inimigo fica rápido).
	# Milestone (a cada N waves): bonus único multiplicativo sobre cada stat —
	# transição de "patamar" pra deixar a curva mais interessante.
	var early_steps: float = float(mini(maxi(wave_number - 1, 0), 2))
	var late_steps: float = float(maxi(wave_number - 3, 0))
	var milestones: int = 0 if milestone_interval <= 0 else int(wave_number / milestone_interval)
	var hp_mult: float = (1.0 + early_steps * hp_growth_per_wave + late_steps * hp_growth_per_wave_late) \
		* pow(1.0 + milestone_hp_bonus, milestones)
	var dmg_mult: float = (1.0 + early_steps * damage_growth_per_wave + late_steps * damage_growth_per_wave_late) \
		* pow(1.0 + milestone_damage_bonus, milestones)
	var speed_mult: float = (1.0 + early_steps * speed_growth_per_wave + late_steps * speed_growth_per_wave_late) \
		* pow(1.0 + milestone_speed_bonus, milestones)
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
	# Movimento e velocidade de ataque (atk speed = -atk_cooldown).
	if "speed" in enemy:
		enemy.speed = enemy.speed * speed_mult
	if "attack_cooldown" in enemy and speed_mult > 0.0:
		enemy.attack_cooldown = enemy.attack_cooldown / speed_mult


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
	# Wave 1 pity: se RNG não dropou as N mínimas, completa AGORA (antes do
	# magnet sugar pro player). Wave 2+ não tem pity, RNG normal.
	_top_up_wave1_coins()
	# Suga todas as moedas restantes do mapa pro player (auto-coleta).
	_magnet_remaining_gold()


func notify_coin_dropped(amount: int = 1) -> void:
	# Chamado por GoldDrop.try_drop sempre que spawna moeda(s).
	_coins_dropped_this_wave += amount


func _top_up_wave1_coins() -> void:
	if wave_number != 1 or wave1_min_guaranteed_drops <= 0:
		return
	# Conta gold REAL ganho na wave: (gold atual do player − snapshot inicial)
	# + gold ainda espalhado pelo mapa (cada moeda vale `value`). Dessa forma o
	# pity funciona mesmo se o player picou moedas durante a wave.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var collected_this_wave: int = 0
	if player != null and "gold" in player:
		collected_this_wave = int(player.gold) - _player_gold_at_wave_start
	var ground_gold: int = 0
	for c in get_tree().get_nodes_in_group("gold"):
		if not is_instance_valid(c):
			continue
		var v: Variant = c.get("value")
		ground_gold += int(v) if v != null else 1
	var total_so_far: int = collected_this_wave + ground_gold
	var missing: int = wave1_min_guaranteed_drops - total_so_far
	if missing <= 0:
		return
	var gold_scene: PackedScene = load("res://scenes/gold.tscn") as PackedScene
	if gold_scene == null:
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	# Spawna as faltantes perto do player (vão ser sugadas pelo magnet logo a seguir).
	var center: Vector2 = player.global_position if player != null else Vector2.ZERO
	for i in missing:
		var coin: Node2D = gold_scene.instantiate()
		world.add_child(coin)
		var off := Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
		coin.global_position = center + off


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
	# Bônus de boas-vindas: após a wave 1, presenteia um upgrade aleatório
	# (do pool base, sem elementais nem sub-melhorias do dash).
	if wave_number == 1:
		await _grant_free_random_upgrade()
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


const STRUCTURE_RESPAWN_DELAY: float = 15.0


func _check_structure_respawns(delta: float) -> void:
	# Estruturas mortas voltam 15s depois durante a wave (não precisa esperar
	# acabar). Cada entry guarda `dead_for` (acumulador de tempo morto). Quando
	# atinge STRUCTURE_RESPAWN_DELAY, spawna nova instância na última posição.
	if owned_structures.is_empty():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	for entry in owned_structures:
		var inst_ref: Variant = entry.get("instance", null)
		var alive: bool = inst_ref != null and is_instance_valid(inst_ref) and (inst_ref as Node).is_inside_tree()
		if alive:
			# Vivo — atualiza posição e zera o timer (caso tenha morrido e
			# voltado por outra via, ex: respawn de fim de wave).
			if inst_ref is Node2D:
				entry["position"] = (inst_ref as Node2D).global_position
			entry["dead_for"] = 0.0
			continue
		# Morto — incrementa timer e respawna ao chegar no delay.
		var dead_for: float = float(entry.get("dead_for", 0.0)) + delta
		entry["dead_for"] = dead_for
		if dead_for < STRUCTURE_RESPAWN_DELAY:
			continue
		var pos: Vector2 = entry["position"]
		var scene: PackedScene = load(entry["scene_path"])
		if scene == null:
			continue
		var inst: Node2D = scene.instantiate()
		_apply_woodwarden_scaling_if_applicable(inst, entry["scene_path"])
		world.add_child(inst)
		inst.global_position = pos
		entry["instance"] = inst
		entry["dead_for"] = 0.0


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
			# Reseta HP no começo do round (woodwarden tank precisa entrar full
			# pro próximo round, não com o HP que sobrou do anterior).
			if "max_hp" in inst_ref and "hp" in inst_ref:
				inst_ref.hp = inst_ref.max_hp
				if (inst_ref as Node).has_node("HpBar"):
					var bar: Node = (inst_ref as Node).get_node("HpBar")
					if bar.has_method("set_ratio"):
						bar.set_ratio(1.0)
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


# Pool curado pro bônus de boas-vindas: só upgrades base do tier 1 (sem elementais
# pra não bloquear o caminho que o player quer escolher, sem sub-dash que precisa
# de pré-requisito).
const FREE_UPGRADE_POOL: Array[Dictionary] = [
	# HP saiu do pool aleatório — agora é compra dedicada na loja com preço
	# escalonado (1G, 2G, 3G, ...). Free upgrade não pode "queimar" o slot
	# barato do primeiro HP.
	{"id": "damage", "name": "Dano"},
	{"id": "perfuracao", "name": "Perfuracao"},
	{"id": "attack_speed", "name": "Atack Speed"},
	{"id": "multi_arrow", "name": "Multiplas Flechas"},
	{"id": "chain_lightning", "name": "Cadeia de Raios"},
	{"id": "move_speed", "name": "Move Speed"},
	{"id": "life_steal", "name": "Mestre da Cura"},
	{"id": "gold_magnet", "name": "Chuva de Coins"},
	{"id": "dash", "name": "Deslizando"},
	{"id": "ricochet_arrow", "name": "Flecha Ricochete"},
	{"id": "graviton", "name": "Graviton"},
	{"id": "armor", "name": "Armadura"},
	{"id": "leno", "name": "Meu amigo Leno"},
]


func _grant_free_random_upgrade() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("apply_upgrade"):
		return
	# Filtra par exclusivo: se o player já tem perfuracao, não pode ganhar
	# ricochet_arrow (e vice-versa). Defensivo — em runtime normal, free upgrade
	# rola depois da wave 1 e o player não tem upgrade ainda; mas via dev mode
	# pode chegar aqui já com algum upgrade.
	var has_perf: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("perfuracao") > 0
	var has_ric: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("ricochet_arrow") > 0
	var pool: Array[Dictionary] = []
	for entry in FREE_UPGRADE_POOL:
		var id: String = entry["id"]
		if id == "perfuracao" and has_ric:
			continue
		if id == "ricochet_arrow" and has_perf:
			continue
		pool.append(entry)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	player.apply_upgrade(pick["id"])
	await _show_free_upgrade_popup(pick["name"])


func _show_free_upgrade_popup(name_text: String) -> void:
	# Popup procedural mostrando o upgrade ganho. Click ou ENTER fecha.
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 50
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var at01_font: Font = load("res://font/ByteBounce.ttf")
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-800, -220)
	title.size = Vector2(1600, 100)
	title.text = "BONUS DE BOAS-VINDAS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	if at01_font != null:
		title.add_theme_font_override("font", at01_font)
	title.add_theme_font_size_override("font_size", 64)
	bg.add_child(title)
	var name_label := Label.new()
	name_label.set_anchors_preset(Control.PRESET_CENTER)
	name_label.position = Vector2(-800, -90)
	name_label.size = Vector2(1600, 140)
	name_label.text = "+ %s" % name_text
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	if at01_font != null:
		name_label.add_theme_font_override("font", at01_font)
	name_label.add_theme_font_size_override("font_size", 96)
	bg.add_child(name_label)
	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.position = Vector2(-200, 100)
	btn.size = Vector2(400, 64)
	btn.text = "Continuar"
	if at01_font != null:
		btn.add_theme_font_override("font", at01_font)
	btn.add_theme_font_size_override("font_size", 48)
	bg.add_child(btn)
	get_tree().current_scene.add_child(layer)
	await btn.pressed
	if is_instance_valid(layer):
		layer.queue_free()


