extends Node2D

# Wave manager: spawn de hordas a partir dos N spawn points mais longe do player.
# Cada wave tem uma config (tipo de inimigo → alive_target + total). Inimigos são
# escolhidos aleatoriamente dentre os tipos que ainda têm cota disponível, e
# spawnados em pontos aleatórios dos N mais longes (offscreen porque a câmera
# segue o player).

@export var monkey_scene: PackedScene
@export var mage_scene: PackedScene
@export var summoner_mage_scene: PackedScene
@export var stone_cube_scene: PackedScene
@export var fire_mage_scene: PackedScene
@export var ice_mage_scene: PackedScene
@export var electric_mage_scene: PackedScene
@export var mage_monkey_scene: PackedScene
@export var duskrose_scene: PackedScene
@export var rose_monster_scene: PackedScene
# Rosa decorativa do mapa da Duskrose (wave 14). 3 variantes (A/B/C) cada uma
# com seu próprio shadow/scale/alinhamento — wave_manager sorteia uma das 3
# scene files pra cada rosa spawnada, preservando as customizações específicas
# de cada cena.
@export var decorative_rose_scene: PackedScene  # A (variant Random)
@export var decorative_rose_b_scene: PackedScene  # B (variant locked frame 6)
@export var decorative_rose_c_scene: PackedScene  # C (variant locked frame 7)
# Map editável só pra wave 14 — cópia inteira do Map original que você
# customiza no editor (adiciona rosas posicionadas, muda grama, ajusta tiles,
# etc.) sem afetar o Map das outras waves. Na wave 14, wave_manager esconde
# o Map original (via group "map") e instancia este aqui no lugar.
@export var wave14_map_scene: PackedScene
const DUSKROSE_DECORATIVE_ROSE_COUNT: int = 40
# Nodes do main.tscn no grupo "hide_wave14" são escondidos durante a wave 14
# e restaurados no _finish_wave. Permite "remover" árvores/gramas/props que
# não combinam com o cenário da Duskrose sem deletar do main.
const WAVE14_HIDE_GROUP: String = "hide_wave14"
@export var dark_ball_scene: PackedScene
@export var spawn_delay: float = 0.5
@export var inter_wave_delay: float = 2.0
@export var pre_cleared_hold: float = 2.0  # tempo segurando 100% antes da tela "Wave Limpa"
# Hold extra após morte do boss: tempo pras moedas dropadas pelo boss caírem,
# pular e o player ver/coletar antes do magnet sugar e do shop abrir.
@export var boss_kill_hold: float = 2.0
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
# Pity system de gold por wave: garante que o player ganhe pelo menos N moedas
# em qualquer round. Se naturalmente o RNG dropou menos que N, os faltantes
# spawnam no _finish_wave (são sugados pelo magnet de fim de wave). Aplica em
# TODAS as waves — sem isso, sequências de drop ruins matam a economia mid-run.
@export var wave1_min_guaranteed_drops: int = 4
# Wave 14 (boss redux): mesmo setup da wave 7 (boss + horda de magos no centro),
# porém com multiplicador extra em cima do scaling natural pra ficar 2,5×–3×
# mais forte que a wave 7. 1.75× sobre o natural da wave 14 dá ~2.85× HP e
# ~2.53× dmg comparado ao boss da wave 7 — dentro do range pedido.
@export var boss_redux_wave: int = 14
@export var boss_redux_extra_mult: float = 1.75
# Wave 21 (boss duplo): Gorilla (Mage Monkey) no centro + Duskrose no topo, na
# arena da Duskrose. Reusa a maquinaria de boss da wave 14 via _uses_duskrose_arena.
@export var boss_dual_wave: int = 21
# Trilha da wave 21: sequência de 2 faixas em loop (faixa 1 → faixa 2 → faixa 1…).
@export var boss_dual_music_1: AudioStream = preload("res://audios/musics/Boss 21 wave.mp3")
@export var boss_dual_music_2: AudioStream = preload("res://audios/musics/Boss Wve 21 - 2.mp3")
# Música das waves de boss (wave 7 e boss_redux_wave). Restaura a track default
# nas outras waves. Default music = stream original do node Music no main.tscn,
# capturado no _ready (não precisa hardcoded aqui).
@export var boss_music: AudioStream = preload("res://audios/musics/monkey mage wave.mp3")
# Música da wave 14 (Duskrose) — jazz tranquilo, classe.
@export var duskrose_music: AudioStream = preload("res://assets/enemies/duskrose/Duskrose Duel.mp3")
# Trilha alternativa pras waves 4-5-6 e 12-13. Loop forçado em runtime.
@export var corrupted_void_music: AudioStream = preload("res://audios/musics/Level 4 - 5 -6/Corrupted Void Gate.mp3")
# Boss redux dropa MAIS gold pra compensar a perda dos drops dos minions
# (que ficam zerados nas waves de boss). 2.45× sobre o base 9-12 → 22-29 coins
# (nerf -30% do antigo 3.5× pra compensar o free-upgrade pós-boss 14).
const BOSS_REDUX_GOLD_MULT: float = 2.45
# Wave 21 (boss duplo): cada boss dropa ~60% do boss solo da wave 14 (são dois,
# então a soma fica generosa sem dobrar). Tunável.
const BOSS_DUAL_GOLD_MULT: float = 1.5
# Tempo (s) que a camera fica parada no boss depois do overlay preto sumir,
# antes de começar o pan pro player. Dá tempo do jogador ver o boss em defense
# + a horda ao redor antes do round começar.
const BOSS_INTRO_HOLD_ON_BOSS: float = 2.5
# Wave 21: tempo parado em cada boss no cinematic de intro + duração do pan
# entre eles. Tunável.
const BOSS_DUAL_INTRO_HOLD_DUSK: float = 1.5    # Duskrose (1º foco)
const BOSS_DUAL_INTRO_HOLD_GORILLA: float = 1.0  # Gorilla (2º foco)
const BOSS_DUAL_INTRO_PAN: float = 1.6
# Duração do pan suave da camera boss → player. Movimento dramático.
const BOSS_INTRO_PAN_DURATION: float = 2.0

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
var _boss_died_this_wave: bool = false  # setado por notify_boss_died → atrasa o magnet/cleanup
# Stream original do node Music (default track) capturado no _ready pra
# restaurar depois das waves de boss.
var _default_music: AudioStream = null
# Sequenciador de música da wave 21 (2 faixas em loop). _dual_music_active diz
# se o handler do sinal `finished` está conectado.
var _dual_music_active: bool = false
var _dual_music_index: int = 0
# Wave 7 (boss) overrides: spawn fixo do player numa extremidade, magos nas
# outras 3, boss no centro. Setado em _start_next_wave quando wave_number == 7.
var _wave7_player_spawn: Vector2 = Vector2.ZERO
var _wave7_enemy_spawns: Array[Vector2] = []
var _wave7_boss_center: Vector2 = Vector2.ZERO
var _wave7_enemy_spawn_idx: int = 0

# Registro de tipos: associa uma chave de string a (PackedScene, group_name).
# Pra adicionar um novo tipo de inimigo: registra aqui + adiciona group no script dele.
var type_registry: Dictionary = {}

# Estruturas que o player já comprou. Cada entrada: {scene_path: String, position: Vector2}.
# Usado pra renascer torres destruídas no início da próxima wave.
var owned_structures: Array = []

# Free tower grant: na wave 8 (primeira shop de estruturas), o player ganha uma
# arrow_tower de graça pra colocar antes do shop normal abrir. Flag impede
# re-entrega caso o shop reabra na mesma wave.
const FREE_TOWER_WAVE: int = 8
const FREE_TOWER_SCENE: String = "res://scenes/world/structures/arrow_tower.tscn"
var _free_tower_delivered: bool = false


func _ready() -> void:
	add_to_group("wave_manager")
	# HUD e Cursor são instanciados em runtime (não estão no main.tscn) pra editor
	# do mapa ficar limpo — sem CanvasLayers cobrindo a view de edição.
	_instantiate_overlays()
	_collect_spawn_points()
	# Captura a stream default do node Music pra restaurar nas waves não-boss.
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node != null:
		_default_music = music_node.stream
	type_registry = {
		"monkey": {"scene": monkey_scene, "group": "monkey"},
		"mage": {"scene": mage_scene, "group": "mage"},
		"summoner_mage": {"scene": summoner_mage_scene, "group": "summoner_mage"},
		"stone_cube": {"scene": stone_cube_scene, "group": "stone_cube"},
		"fire_mage": {"scene": fire_mage_scene, "group": "fire_mage"},
		"ice_mage": {"scene": ice_mage_scene, "group": "ice_mage"},
		"electric_mage": {"scene": electric_mage_scene, "group": "electric_mage"},
		"mage_monkey": {"scene": mage_monkey_scene, "group": "mage_monkey"},
		"duskrose": {"scene": duskrose_scene, "group": "duskrose"},
		"rose_monster": {"scene": rose_monster_scene, "group": "rose_monster"},
		"dark_ball": {"scene": dark_ball_scene, "group": "dark_ball"},
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
	var hud_scene: PackedScene = load("res://scenes/ui/hud.tscn")
	if hud_scene != null:
		add_child(hud_scene.instantiate())
	var cursor_scene: PackedScene = load("res://scenes/player/cursor.tscn")
	if cursor_scene != null:
		add_child(cursor_scene.instantiate())


func _spawn_dev_panel() -> void:
	var panel_scene: PackedScene = load("res://scenes/ui/dev_panel.tscn")
	if panel_scene != null:
		var panel := panel_scene.instantiate()
		get_tree().current_scene.add_child(panel)


func _is_dev_mode() -> bool:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and "dev_mode" in gs:
		return bool(gs.dev_mode)
	return false


func spawn_enemy_at(type_key: String, pos: Vector2) -> Node:
	# Usado pelo DevPanel pra spawnar inimigos de qualquer tipo registrado.
	var info: Dictionary = type_registry.get(type_key, {})
	if info.is_empty() or info["scene"] == null:
		push_warning("spawn_enemy_at: tipo '%s' sem PackedScene atribuída no main.tscn (recarregue a cena se acabou de adicionar o tipo)." % type_key)
		return null
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return null
	var enemy: Node2D = info["scene"].instantiate()
	world.add_child(enemy)
	enemy.global_position = pos
	_pause_if_time_frozen(enemy)
	return enemy


# Dev helper: salta direto pra wave N — limpa enemies vivos, reseta tracking
# e dispara _start_next_wave com wave_number = N - 1 (o increment interno
# leva pra N). Funciona mesmo no dev mode (que normalmente fica `stopped`).
func dev_finish_wave() -> void:
	# Mata todos os enemies vivos e força _finish_wave (vai pro shop).
	if not wave_active:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	# _process detecta killed == total e chama _finish_wave naturalmente,
	# mas pra acelerar, força aqui (clamp do counter pra não dar negativo).
	_finish_wave()


func dev_start_wave(target_wave: int) -> void:
	if target_wave < 1:
		return
	# Limpa horda atual sem trigger de drops/morte real (usa free direto).
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e):
			e.queue_free()
	wave_number = target_wave - 1
	wave_active = false
	stopped = false
	# Reseta flag da torre grátis se voltando pra antes da entrega — permite
	# re-testar o fluxo wave 7 → finalize → torre grátis múltiplas vezes.
	if target_wave <= FREE_TOWER_WAVE:
		_free_tower_delivered = false
	_start_next_wave.call_deferred()


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
	_update_last_enemies_indicator()
	_apply_insect_decay(delta)
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


# === Indicador dos últimos inimigos ===
# Quando restam <= 2 inimigos vivos NA FASE FINAL da wave (todos já spawnados),
# delega pro HUD desenhar setas na borda da tela apontando pros inimigos
# off-screen — mesmo padrão do TowerAlertIndicator.
const _LAST_ENEMY_MARKER_THRESHOLD: int = 2


func _update_last_enemies_indicator() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("update_last_enemies_indicator"):
		return
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	var count: int = enemies.size()
	var show: bool = _all_enemies_spawned() and count > 0 and count <= _LAST_ENEMY_MARKER_THRESHOLD
	if show:
		hud.update_last_enemies_indicator(enemies)
	else:
		hud.update_last_enemies_indicator([])


func _all_enemies_spawned() -> bool:
	if wave_config.is_empty():
		return false
	for k: String in wave_config.keys():
		if int(spawned_this_wave.get(k, 0)) < int(wave_config[k]["total"]):
			return false
	return true


func _apply_insect_decay(delta: float) -> void:
	# Anti-softlock: quando só sobram insetos (todos já spawnados), eles tomam
	# decay até morrer. O inseto foge e ignora colisão de parede → pode sair do
	# mapa e ficar intargetável, travando o fim da wave (só fecha em alive == 0).
	if not _all_enemies_spawned():
		return
	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		return
	for e in enemies:
		if is_instance_valid(e) and not (e as Node).is_in_group("insect"):
			return  # ainda há inimigo não-inseto vivo → não decai
	for e in enemies:
		if is_instance_valid(e) and e.has_method("apply_decay"):
			e.apply_decay(delta)


func _start_next_wave() -> void:
	if stopped:
		return
	# Cleanup defensivo de corações órfãos: o sweep sequencial em _finish_wave
	# pode travar (heart ativo nunca alcança o player → fila bloqueada). Sem
	# isso os corações sobravam pra próxima wave e o player ganhava cura grátis.
	_cleanup_remaining_hearts()
	wave_number += 1
	# Telemetria: emite run_start na wave 1, wave_reached em waves >= 2.
	if wave_number == 1 and Engine.has_singleton("Telemetry") == false:
		# Telemetry é autoload, não Engine singleton — só guard contra null.
		pass
	if has_node("/root/Telemetry"):
		var t: Node = get_node("/root/Telemetry")
		if wave_number == 1:
			t.start_run()
			t.track("run_start", {})
		else:
			t.track("wave_reached", {"wave": wave_number})
	wave_config = _build_wave_config(wave_number)
	spawned_this_wave.clear()
	for k: String in wave_config.keys():
		spawned_this_wave[k] = 0
	total_to_spawn_this_wave = _calc_total_to_spawn()
	last_progress_killed = -1
	spawn_cooldown = 0.0
	# Reseta contador de moedas dropadas — pity system da wave 1 garante mínimo no _finish_wave.
	_coins_dropped_this_wave = 0
	_boss_died_this_wave = false
	# Sputnik: zera o flag de disparo manual no início da wave (desafio "round sem flecha").
	var _p_no_arrow := get_tree().get_first_node_in_group("player")
	if _p_no_arrow != null and "fired_arrow_this_wave" in _p_no_arrow:
		_p_no_arrow.fired_arrow_this_wave = false

	# Wave 7 (boss) e wave 14 (boss redux): pré-calcula posições — 1 spawn point
	# pro player, os 3 restantes pros magos, e centroide dos 4 pro boss. Faz
	# isso ANTES do reset_position pra ele saber pra onde mandar o player.
	if _is_boss_wave(wave_number):
		_prepare_wave7_spawn_assignments()
	# Reseta HP e posição do player antes da nova wave (camera segue → player no centro).
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		if player.has_method("reset_hp"):
			player.reset_hp()
		if player.has_method("reset_position"):
			player.reset_position()
		# Wave 7 e wave 14 (boss redux): override da posição padrão pra extremidade
		# aleatória do mapa.
		if _is_boss_wave(wave_number) and player is Node2D:
			(player as Node2D).global_position = _wave7_player_spawn
			# Reposiciona claudios vivos pra perto do novo player_spawn. Sem isso,
			# eles ficam fora da arena (especialmente wave 14, mapa diferente).
			if player.has_method("reposition_claudio_druidas_near_player"):
				player.reposition_claudio_druidas_near_player()
		if player.has_method("reset_perf_counter"):
			player.reset_perf_counter()
		if player.has_method("reset_ricochet_counter"):
			player.reset_ricochet_counter()
		if player.has_method("reset_graviton_counter"):
			player.reset_graviton_counter()
		if player.has_method("reset_claudio_druidas_hp"):
			player.reset_claudio_druidas_hp()
		if player.has_method("reset_all_cooldowns"):
			player.reset_all_cooldowns()
		# Zera contador de magos mortos da wave — base do scaling de atk speed
		# da torreta do Ting (+1% por mago morto). Cada turno começa do zero.
		if player.has_method("reset_mages_killed_this_wave"):
			player.reset_mages_killed_this_wave()
		# Zera breakdown de dano por fonte da wave (lido pelo painel TAB).
		if player.has_method("reset_wave_damage_breakdown"):
			player.reset_wave_damage_breakdown()
	# Snapshot do gold do player no início da wave — pity pega gold REAL ganho
	# (já coletado + ainda no chão), não conta em "coin entries" do drop.
	if player != null and "gold" in player:
		_player_gold_at_wave_start = int(player.gold)
	else:
		_player_gold_at_wave_start = 0
	# Renasce torres/aliados destruídos na wave anterior na mesma posição.
	# Wave 14 (Duskrose): luta acontece em arena temática; estruturas compradas
	# ficam "estocadas" e voltam automaticamente no próximo round.
	if _uses_duskrose_arena(wave_number):
		_clear_alive_structures_for_boss_wave()
	else:
		_respawn_owned_structures()

	# Música da wave: boss / corrupted void / default — escolhida pelo número
	# da wave (ver _music_for_wave). Wave 21: sequência de 2 faixas em loop.
	_stop_dual_music_sequence()
	if wave_number == boss_dual_wave:
		_start_dual_music_sequence()
	else:
		_swap_music_to(_music_for_wave(wave_number))
	# Wave de boss: cinematic especial — boss + horda inicial são pré-spawnados,
	# camera trava no boss, cinematic toca, camera pan pro player.
	var hud := get_tree().get_first_node_in_group("hud")
	if _is_boss_wave(wave_number):
		_prespawn_boss_wave_entities()
		await _play_boss_intro_cinematic(hud)
	else:
		# Outras waves: intro padrão.
		if hud != null and hud.has_method("play_raid_intro"):
			await hud.play_raid_intro(wave_number)
	if stopped:
		return
	wave_active = true
	_spawn_capivara_starter_mushrooms()
	_spawn_stone_cube_allies()
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
	# Wave 7: BOSS — Mage Monkey. Spawna 1 boss + horda inicial densa de magos
	# pra dar shield robusto ao boss desde o começo. Quando todos morrem, boss
	# fica vulnerável 12s e invoca nova horda própria. Wave acaba quando o
	# boss morre (que mata os minions junto).
	if num == 7:
		return {
			"mage_monkey": {"alive_target": 1, "total": 1},
			"mage": {"alive_target": 5, "total": 8},
			"summoner_mage": {"alive_target": 2, "total": 3},
			"fire_mage": {"alive_target": 2, "total": 3},
			"ice_mage": {"alive_target": 1, "total": 2},
			"electric_mage": {"alive_target": 1, "total": 2},
		}
	# Wave 14: DUSKROSE — boss novo. Anda no topo do mapa horizontalmente e
	# invoca Rose Monsters dinamicamente. Setup temático: SÓ boss inicial,
	# sem rose_monsters pré-spawnados — o boss precisa invocar a 1ª horda
	# através do sistema de pesos táticos (0 roses vivas → summon priorizado).
	# Boss escala HP via override fixo no _apply_wave_scaling.
	if num == boss_redux_wave:
		return {
			"duskrose": {"alive_target": 1, "total": 1},
		}
	# Wave 21: BOSS DUPLO — Gorilla (Mage Monkey) no centro + Duskrose no topo.
	# Gorilla mantém o escudo (invulnerável enquanto tiver mago vivo); horda
	# inicial pequena pra abrir ele ser viável sob pressão da Duskrose. Duskrose
	# invoca Rose Monsters dinamicamente (config só o boss inicial dela).
	if num == boss_dual_wave:
		return {
			"mage_monkey": {"alive_target": 1, "total": 1},
			"duskrose": {"alive_target": 1, "total": 1},
			"mage": {"alive_target": 6, "total": 8},
		}
	# Waves 3+: escala automática + um pouco de aleatoriedade.
	# Quanto maior o wave_number, mais inimigos vivos e mais total.
	# Ratio macaco/mago varia entre ~70/30 e ~50/50 conforme a wave avança.
	# Wave 3 leva um corte extra (curva de aprendizado pós-wave 2).
	# Wave 5 também leva um corte (introdução do stone cube).
	# Wave 6 também leva um corte (respiro antes do boss da wave 7) — estava
	# sendo a wave mais punitiva da curva inicial.
	var reduction: float = 0.87
	if num == 3:
		reduction = 0.62
	elif num == 4:
		reduction = 0.74
	elif num == 5:
		reduction = 0.66
	elif num == 6:
		reduction = 0.62
	elif num == 10 or num == 11:
		# Wave 10 acumula: milestone scaling (+20% HP / +15% dmg / +8% spd),
		# estreia do electric mage, fire/ice subindo de 2/3 pra 3/4, e stone
		# cubes voltando depois de respiro. Reduz horda de monkey/mage nas
		# 10-11 pra absorver o stack. Wave 11 herda o mesmo alívio (sem stone
		# cubes mas com milestone scaling ainda ativo).
		reduction = 0.78
	elif num == 15 or num == 16:
		# Pós-boss da Duskrose (wave 14): player chega sem heal nem upgrade,
		# e a curva natural já tá em scale ~5+. Aliviar 15-16 evita que o
		# pico pós-boss seja punitivo demais antes da wave 19+ (pace acelerado).
		reduction = 0.68
	var scale: float = (1.0 + (num - 1) * 0.35) * reduction
	var monkey_alive: int = int(round(5 * scale + randf_range(-1.0, 2.0)))
	var monkey_total: int = int(round(15 * scale + randf_range(0.0, 4.0)))
	var mage_alive: int = int(round(3 * scale + randf_range(0.0, 2.0)))
	var mage_total: int = int(round(6 * scale + randf_range(0.0, 3.0)))
	# Wave 8+: reduz cota de mages normais — slot foi tomado pelos elementais
	# (fire/ice/electric) que agora entram em quantidade maior.
	if num >= 8:
		mage_alive = int(round(float(mage_alive) * 0.6))
		mage_total = int(round(float(mage_total) * 0.6))
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
	# Stone cube spawn pattern:
	#   Wave 5: estreia, 1 cubo.
	#   Wave 6: pula (respiro antes do boss).
	#   Wave 7: pula (boss).
	#   Wave 8, 10, 12...: a cada 2 waves pares. Count escala progressivamente
	#   (+1 por wave) e alive_target fica baixo (2-3) pra dispersar os spawns
	#   ao longo do tempo da wave.
	#   Wave 9, 11, 13...: pula.
	var stone_alive: int = 0
	var stone_total: int = 0
	if num == 5:
		stone_total = 1
		stone_alive = 1
	elif num >= 8 and num % 2 == 0:
		# step_count: wave 8 = 0, wave 10 = 1, wave 12 = 2, ...
		var step_count: int = (num - 8) / 2
		# Total cresce 1 por wave e tem 1 de variância (3-4, 4-5, 5-6, ...).
		stone_total = randi_range(3 + step_count, 4 + step_count)
		# Alive baixo (2-3) pra dispersar — cubos são tanks lentos, não spawnam
		# todos juntos: trickle conforme os anteriores morrem.
		stone_alive = mini(2 + step_count / 2, stone_total)
	# Fire mage / Ice mage: estreiam na wave 8 (logo após o primeiro boss da
	# wave 7), conta cresce devagar. Mesma curva pra ambos pra balanço fica
	# parecido — fire = pressão de campo no chão (DoT), ice = atraso de
	# posicionamento (slow AoE). Cada um adiciona uma camada de stress.
	# Electric mage: estreia na wave 10 (mais tarde — segundo elemental "premium").
	var fire_alive: int = 0
	var fire_total: int = 0
	var ice_alive: int = 0
	var ice_total: int = 0
	var elec_alive: int = 0
	var elec_total: int = 0
	if num >= 8:
		# Quantidade aumentada — elementais agora pesam mais na composição.
		# Wave 8 entra com 2 alive / 3 total (era 1/1). Cresce até cap 4/6.
		var elem_step: int = (num - 8) / 2
		fire_alive = mini(2 + elem_step, 4)
		fire_total = mini(3 + elem_step, 6)
		ice_alive = mini(2 + elem_step, 4)
		ice_total = mini(3 + elem_step, 6)
	if num >= 10:
		var elec_step: int = (num - 10) / 2
		elec_alive = mini(2 + elec_step, 4)
		elec_total = mini(3 + elec_step, 6)
		# Debut suavizado: nas waves 10-11 (estreia), entra com 1 alive / 2 total
		# pra não empilhar com o milestone scaling + outros elementais. Volta ao
		# count normal (2/3) na wave 12 e escala dali pra frente.
		if num == 10 or num == 11:
			elec_alive = 1
			elec_total = 2
	# Dark Ball cadência:
	#   Wave 6: estreia (20% dos macacos).
	#   Wave 9, 12, 15, 18...: a cada 3 waves (também 20%).
	#   Wave 7/14 (boss): pula via configs hardcoded.
	# Aplicado proporcionalmente em alive_target E total — a soma macaco + dark
	# ball bate com a quota original de monkey.
	var dark_alive: int = 0
	var dark_total: int = 0
	var dark_ball_wave: bool = (num == 6 or (num >= 9 and num % 3 == 0)) and not _is_boss_wave(num)
	if dark_ball_wave and monkey_total > 0:
		var dark_pct: float = 0.20
		dark_alive = int(round(float(monkey_alive) * dark_pct))
		dark_total = int(round(float(monkey_total) * dark_pct))
		monkey_alive = maxi(monkey_alive - dark_alive, 1)
		monkey_total = maxi(monkey_total - dark_total, monkey_alive)
	var cfg: Dictionary = {
		"monkey": {"alive_target": maxi(monkey_alive, 1), "total": maxi(monkey_total, monkey_alive)},
		"mage": {"alive_target": maxi(mage_alive, 1), "total": maxi(mage_total, mage_alive)},
		"summoner_mage": {"alive_target": maxi(summ_alive, 1), "total": maxi(summ_total, summ_alive)},
	}
	if dark_total > 0:
		cfg["dark_ball"] = {"alive_target": maxi(dark_alive, 1), "total": maxi(dark_total, dark_alive)}
	if stone_total > 0:
		cfg["stone_cube"] = {"alive_target": maxi(stone_alive, 1), "total": maxi(stone_total, stone_alive)}
	if fire_total > 0:
		cfg["fire_mage"] = {"alive_target": maxi(fire_alive, 1), "total": maxi(fire_total, fire_alive)}
	if ice_total > 0:
		cfg["ice_mage"] = {"alive_target": maxi(ice_alive, 1), "total": maxi(ice_total, ice_alive)}
	if elec_total > 0:
		cfg["electric_mage"] = {"alive_target": maxi(elec_alive, 1), "total": maxi(elec_total, elec_alive)}
	# Wave 19+: pace acelerado — dobra alive_target e total de TODOS os tipos
	# (mais inimigos ao mesmo tempo, mais inimigos no total). Combinado com o
	# spawn_delay reduzido em _spawn_delay_for_wave, o mapa enche mais rápido
	# e força o player a dar conta do volume.
	if num >= 19:
		for type_key in cfg.keys():
			var entry: Dictionary = cfg[type_key]
			entry["alive_target"] = int(entry["alive_target"]) * 2
			entry["total"] = int(entry["total"]) * 2
	return cfg


func _spawn_delay_for_wave() -> float:
	# Wave 3 spawna mais devagar pra dar respiro depois do salto da wave 2.
	if wave_number == 3:
		return spawn_delay * 1.6
	# Wave 19+: spawn delay caí pela metade pra completar a vibe de "pico de
	# pressão" — inimigos chegam dobrados (alive_target × 2) e mais rápido.
	if wave_number >= 19:
		return spawn_delay * 0.5
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
	var pos: Vector2 = _pick_spawn_for(type_key)
	var enemy: Node2D = info["scene"].instantiate()
	# Waves de boss (7 e 14): minions iniciais (todas variações de mago) NÃO
	# dropam gold nem heart — único drop da wave vem do próprio boss.
	# Diferença entre 7 e 14:
	#   Wave 7: minions PULAM scaling (trash mobs com stats base, shield).
	#   Wave 14: minions ESCALAM normalmente (natural + boss_redux_extra_mult)
	#            — versões fortes, mas sem drops pra a recompensa ficar no boss.
	if _is_boss_wave(wave_number) and type_key != "mage_monkey" and type_key != "duskrose":
		if "gold_drop_chance" in enemy:
			enemy.gold_drop_chance = 0.0
		if "heart_scene" in enemy:
			enemy.heart_scene = null
	# Scaling: pula só pra minions da wave 7. Resto (incluindo minions da
	# wave 14 e boss em qualquer wave) leva scaling normal.
	if wave_number != 7 or type_key == "mage_monkey":
		_apply_wave_scaling(enemy)
		# Override pro boss da wave 7: HP "limpo" exatos 3000 (sem frac de
		# hp_mult). Wave 14 (boss_redux) continua escalando em cima do scaling
		# normal pra ficar mais forte.
		if wave_number == 7 and type_key == "mage_monkey" and "max_hp" in enemy:
			enemy.max_hp = 3000.0
		# Override pro boss da wave 14 (Duskrose): HP fixo 8500 (buff geral pra
		# acompanhar o ritmo encurtado de poderes 3-5s).
		if wave_number == boss_redux_wave and type_key == "duskrose" and "max_hp" in enemy:
			enemy.max_hp = 8500.0
	# Wave 14 boss (redux): drops escalam pra compensar a perda de drops dos
	# minions + a dificuldade extra. Multiplicador maior que o normal de
	# scaling porque tem ~16-18 minions a menos contribuindo gold.
	if wave_number == boss_redux_wave and (type_key == "mage_monkey" or type_key == "duskrose") and BOSS_REDUX_GOLD_MULT > 1.0:
		if "gold_drop_min" in enemy:
			enemy.gold_drop_min = int(round(float(enemy.gold_drop_min) * BOSS_REDUX_GOLD_MULT))
		if "gold_drop_max" in enemy:
			enemy.gold_drop_max = int(round(float(enemy.gold_drop_max) * BOSS_REDUX_GOLD_MULT))
		# Pivot da pool ponderada também escala — sem isso, a faixa rara
		# (24-30 no base) sobreescreveria a comum em wave 14.
		if "gold_drop_pivot" in enemy:
			enemy.gold_drop_pivot = int(round(float(enemy.gold_drop_pivot) * BOSS_REDUX_GOLD_MULT))
	world.add_child(enemy)
	enemy.global_position = pos
	_pause_if_time_frozen(enemy)
	spawned_this_wave[type_key] = spawned_this_wave.get(type_key, 0) + 1


func _pause_if_time_frozen(enemy: Node) -> void:
	# Se o player ativou Time Freeze (Fica Frio L4), o inimigo recém-spawnado
	# também é pausado — senão ele se infiltra na luta enquanto todo o resto
	# está congelado.
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("apply_freeze_pause_if_active"):
		player.apply_freeze_pause_if_active(enemy)


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
	# Wave 14 (boss redux): multiplicador extra em cima do scaling natural pra
	# wave inteira ficar 2,5×–3× mais forte que a wave 7 (boss + minions).
	if wave_number == boss_redux_wave and boss_redux_extra_mult > 1.0:
		hp_mult *= boss_redux_extra_mult
		dmg_mult *= boss_redux_extra_mult
		speed_mult *= boss_redux_extra_mult
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


func get_farthest_spawn_points_from_player(count: int) -> Array[Vector2]:
	# Helper público: retorna os N spawn points mais longes do player no
	# momento atual. Usado pelo boss pra escolher onde invocar minions.
	var result: Array[Vector2] = []
	if spawn_points.is_empty():
		return result
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		# Sem player vivo — pega os primeiros N pontos disponíveis.
		for i in mini(count, spawn_points.size()):
			result.append(spawn_points[i].global_position)
		return result
	var sorted: Array[Marker2D] = spawn_points.duplicate()
	sorted.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		var da: float = a.global_position.distance_squared_to(player.global_position)
		var db: float = b.global_position.distance_squared_to(player.global_position)
		return da > db
	)
	var take: int = mini(count, sorted.size())
	for i in take:
		result.append(sorted[i].global_position)
	return result


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


func _pick_spawn_for(type_key: String) -> Vector2:
	# Wave 7 (boss) e wave 14 (boss redux): boss vai sempre pro centro; magos
	# rodam pelos 3 spawn points reservados (não o do player). Outras waves:
	# comportamento padrão.
	if _is_boss_wave(wave_number):
		if type_key == "mage_monkey" or type_key == "duskrose":
			return _wave7_boss_center
		if not _wave7_enemy_spawns.is_empty():
			var pos: Vector2 = _wave7_enemy_spawns[_wave7_enemy_spawn_idx % _wave7_enemy_spawns.size()]
			_wave7_enemy_spawn_idx += 1
			return pos
	return _pick_random_far_spawn_point()


func _is_boss_wave(num: int) -> bool:
	return num == 7 or num == boss_redux_wave or num == boss_dual_wave


# Waves que rodam na arena temática da Duskrose (swap de mapa, sem estruturas).
func _uses_duskrose_arena(num: int) -> bool:
	return num == boss_redux_wave or num == boss_dual_wave


# Wave 21 (boss duplo): moedas dropadas pelos bosses ficam travadas (não expiram
# nem são coletáveis) até o último boss morrer. O magnet de fim de wave
# (_magnet_remaining_gold, em _finish_wave) libera todas de uma vez — chuva de
# moedas. Lido pelo gold.gd no _ready de cada moeda.
func boss_coins_locked() -> bool:
	return wave_number == boss_dual_wave and wave_active


func is_boss_wave_now() -> bool:
	return _is_boss_wave(wave_number)


func _prepare_wave7_spawn_assignments() -> void:
	# Sorteia 1 spawn point pro player. Magos vão SÓ pros 2 mais longes do
	# ponto do player (não os 3 restantes — o spawn intermediário ficaria
	# perto demais do player). Centroide dos 4 = posição do boss no centro.
	if spawn_points.is_empty():
		_wave7_player_spawn = Vector2.ZERO
		_wave7_enemy_spawns = []
		_wave7_boss_center = Vector2.ZERO
		_wave7_enemy_spawn_idx = 0
		return
	var pool: Array[Marker2D] = spawn_points.duplicate()
	pool.shuffle()
	_wave7_player_spawn = pool[0].global_position
	# Ordena os spawn points restantes pela distância (do mais longe pro mais perto)
	# e pega os 2 mais longes pra spawn dos magos.
	var rest: Array[Marker2D] = []
	for i in range(1, pool.size()):
		rest.append(pool[i])
	rest.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
		var da: float = a.global_position.distance_squared_to(_wave7_player_spawn)
		var db: float = b.global_position.distance_squared_to(_wave7_player_spawn)
		return da > db
	)
	_wave7_enemy_spawns = []
	var keep: int = mini(2, rest.size())
	for i in keep:
		_wave7_enemy_spawns.append(rest[i].global_position)
	_wave7_enemy_spawn_idx = 0
	# Centroide considera TODOS os spawn points (inclui o do player) pra ficar
	# bem no meio geométrico do mapa.
	var sum: Vector2 = Vector2.ZERO
	for p in spawn_points:
		sum += p.global_position
	_wave7_boss_center = sum / float(spawn_points.size())
	# Wave 14 (Duskrose): force player no meio-inferior do mapa. Boss patrulha
	# o topo, então player começa embaixo-centro pra ter espaço de manobra e
	# distância da boss. X = centro do mapa, Y = baseado nos spawn SW/SE.
	if wave_number == boss_redux_wave:
		var south_y: float = 320.0  # default fallback se não houver SW/SE
		var south_count: int = 0
		var south_y_sum: float = 0.0
		for p in spawn_points:
			# Pega Y dos spawn points "south" (mais abaixo na metade inferior do mapa).
			if p.global_position.y > _wave7_boss_center.y:
				south_y_sum += p.global_position.y
				south_count += 1
		if south_count > 0:
			south_y = south_y_sum / float(south_count)
		_wave7_player_spawn = Vector2(_wave7_boss_center.x, south_y)
	# Wave 21 (boss duplo): player num spawn point REAL no canto inferior-ESQUERDO
	# (markers ficam DENTRO da área jogável — o player nasce dentro, sem ser
	# chutado pela wall invisível). Pega o mais à esquerda entre os da metade SUL.
	if wave_number == boss_dual_wave:
		var pl_sp: Marker2D = null
		for p in spawn_points:
			if p.global_position.y <= _wave7_boss_center.y:
				continue  # só os do sul (metade inferior)
			if pl_sp == null or p.global_position.x < pl_sp.global_position.x:
				pl_sp = p
		# Fallback: nenhum no sul → o mais à esquerda geral.
		if pl_sp == null:
			for p in spawn_points:
				if pl_sp == null or p.global_position.x < pl_sp.global_position.x:
					pl_sp = p
		if pl_sp != null:
			_wave7_player_spawn = pl_sp.global_position
		# Magos da 1ª horda no lado OPOSTO ao player: recomputa os 2 spawn points
		# mais LONGES da posição final do player (o cálculo geral acima usou um
		# ponto aleatório, podendo cair perto do player).
		var rest21: Array[Marker2D] = []
		for p in spawn_points:
			if p == pl_sp:
				continue
			rest21.append(p)
		rest21.sort_custom(func(a: Marker2D, b: Marker2D) -> bool:
			return a.global_position.distance_squared_to(_wave7_player_spawn) > b.global_position.distance_squared_to(_wave7_player_spawn)
		)
		_wave7_enemy_spawns = []
		for i in mini(2, rest21.size()):
			_wave7_enemy_spawns.append(rest21[i].global_position)
		_wave7_enemy_spawn_idx = 0


func _finish_wave() -> void:
	wave_active = false
	# Garante que a barra mostra 100% antes da tela de "Wave Limpa".
	_emit_progress()
	# Unlocks de skin amarrados à conclusão de wave:
	#  - Hawk: passar das waves 1-3 SEM dano → no fim da wave 3, se o dano
	#    acumulado da run for 0, marca a flag (record_run persiste no death).
	#  - Destiny: concluir a Raid 21 (os 2 bosses mortos) → reporta "raid21".
	var _p_fw := get_tree().get_first_node_in_group("player")
	if _p_fw != null:
		if wave_number == 3 and "stats_damage_taken" in _p_fw and float(_p_fw.stats_damage_taken) <= 0.0 and "stats_flawless_through_w3" in _p_fw:
			_p_fw.stats_flawless_through_w3 = true
		if wave_number == boss_dual_wave and _p_fw.has_method("notify_boss_killed"):
			_p_fw.notify_boss_killed("raid21")
		# Sputnik: passou da wave sem disparo manual de flecha → unlock (qualquer wave >= 1).
		if wave_number >= 1 and "fired_arrow_this_wave" in _p_fw and not _p_fw.fired_arrow_this_wave and "stats_no_arrow_round" in _p_fw:
			_p_fw.stats_no_arrow_round = true
		# Pétalas (meta-moeda): recompensa por concluir a wave. Faixa fixa por
		# round (escassa); boss dropa mais. Voa pra carteira (HUD anima).
		if _p_fw.has_method("add_petals"):
			var prange: Vector2i = Vector2i(1, 2)
			if _is_boss_wave(wave_number):
				prange = Vector2i(4, 5)
			elif wave_number <= 5:
				prange = Vector2i(1, 2)
			elif wave_number <= 10:
				prange = Vector2i(2, 3)
			else:
				prange = Vector2i(3, 4)
			var rolled: int = randi_range(prange.x, prange.y)
			var p_origin: Vector2 = (_p_fw as Node2D).global_position if _p_fw is Node2D else Vector2.INF
			_p_fw.add_petals(rolled, p_origin)
		# Dividendo Arcano (item): +N gold no fim de cada round.
		var _gpr: int = InventoryItems.equipped_gold_per_round()
		if _gpr > 0 and _p_fw.has_method("add_gold"):
			_p_fw.add_gold(_gpr)
		# Conta wave limpa (unlock do item Estou com Sorte).
		if "stats_waves_cleared" in _p_fw:
			_p_fw.stats_waves_cleared += 1
	# Pós-boss: segura tudo (cleanup, magnet, tela "Wave Limpa") por
	# `boss_kill_hold` segundos pras moedas dropadas pelo boss ficarem visíveis,
	# saltarem e o player ter tempo de coletar/ver a animação.
	if _boss_died_this_wave and boss_kill_hold > 0.0:
		await get_tree().create_timer(boss_kill_hold).timeout
		if stopped:
			return
	# Maldição: aliados convertidos pela curse só duram até o fim da horda/turno.
	_cleanup_curse_allies()
	# Cogumelos da Capivara Joe não persistem entre raids — limpa o que ficou no
	# chão (buff e damage variants).
	_cleanup_capivara_mushrooms()
	# Torretas do Mecânico Ting também duram só o round — limpa as ativas no fim
	# da wave pra cada raid começar limpo (o Ting volta a buildar normal).
	_cleanup_ting_turrets()
	# Wave 14 (Duskrose): limpa as rosas decorativas espalhadas pelo mapa.
	_cleanup_duskrose_decoration()
	# Pity de gold: se a wave rendeu menos que o mínimo garantido, completa
	# AGORA (antes do magnet sugar pro player). Aplica em qualquer wave.
	_top_up_min_coins()
	# Suga todas as moedas restantes do mapa pro player (auto-coleta).
	_magnet_remaining_gold()


func notify_boss_died() -> void:
	# Chamado pelo boss em _die() — sinaliza pro _finish_wave segurar 2s extras
	# antes do magnet/cleanup, dando tempo das moedas caírem e serem coletadas.
	_boss_died_this_wave = true


func notify_coin_dropped(amount: int = 1) -> void:
	# Chamado por GoldDrop.try_drop sempre que spawna moeda(s).
	_coins_dropped_this_wave += amount


func _top_up_min_coins() -> void:
	if wave1_min_guaranteed_drops <= 0:
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
	var gold_scene: PackedScene = load("res://scenes/pickups/gold.tscn") as PackedScene
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


const CAPIVARA_MUSHROOM_SCENE: PackedScene = preload("res://scenes/allies/capivara_mushroom.tscn")
const CAPIVARA_STARTER_BUFF_COUNT: int = 3
const CAPIVARA_STARTER_DAMAGE_COUNT: int = 2
# Bounds onde os cogumelos starter podem nascer (mesmo retângulo de wander da
# Capivara Joe — mantém o espalhamento dentro do mapa jogável).
const CAPIVARA_STARTER_BOUNDS: Rect2 = Rect2(5, 8, 510, 284)

# Disparo de Pedra L3: 3 Stone Cubes aliados no início de cada round.
const STONE_CUBE_ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/stone_cube_enemy.tscn")
const STONE_ALLY_COUNT: int = 2
const STONE_ALLY_HP: float = 160.0  # > cubo original (90)
const STONE_ALLY_DAMAGE: float = 40.0  # > cubo original (25)
const STONE_ALLY_SPAWN_RADIUS: float = 44.0  # nascem em volta do player


func _cleanup_capivara_mushrooms() -> void:
	# Limpa TODOS os cogumelos no fim do round (buff e damage variants). Não
	# persistem entre raids — o início da próxima wave gera um set novo via
	# _spawn_capivara_starter_mushrooms.
	for m in get_tree().get_nodes_in_group("capivara_mushroom"):
		if is_instance_valid(m):
			m.queue_free()


func _cleanup_remaining_hearts() -> void:
	# Limpa todos os corações no chão antes da próxima wave começar. Chamado
	# em _start_next_wave (não no _finish_wave) pra dar tempo do sweep
	# sequencial em _magnet_remaining_gold puxar o que conseguir antes — só os
	# que sobrarem (sweep travado, fora de raio, etc) são removidos aqui.
	for h in get_tree().get_nodes_in_group("heart"):
		if is_instance_valid(h):
			h.queue_free()


func _cleanup_ting_turrets() -> void:
	# Torretas dropadas pelo Ting expiram no próprio lifetime, mas se o turno
	# acaba antes (ex: matar o boss/inimigo final rápido) sobram torretas
	# atirando no vazio entre waves. Mata todas pra cada raid começar limpo.
	for t in get_tree().get_nodes_in_group("ting_turret"):
		if is_instance_valid(t):
			t.queue_free()


func _cleanup_duskrose_decoration() -> void:
	# Rosas decorativas + wave14_map + props extras (group "duskrose_decoration")
	# são limpos no fim da wave pra não vazarem pras próximas (shop / wave 15+).
	for r in get_tree().get_nodes_in_group("duskrose_decoration"):
		if is_instance_valid(r):
			r.queue_free()
	# Restaura visibilidade do Map original, dos props decorativos do Entities
	# (árvores/casas/cercas/etc.) e dos props no group "hide_wave14".
	_set_main_map_hidden(false)
	_set_main_entities_props_hidden(false)
	_set_wave14_props_hidden(false)


func _spawn_capivara_starter_mushrooms() -> void:
	# Se o player tem Capivara Joe, gera o set inicial da wave: 3 buff sempre +
	# 2 damage se a Capivara já tiver liberado a variante de dano (L2+).
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	var lvl: int = int(player.get_upgrade_count("capivara_joe"))
	if lvl < 1:
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	if world == null:
		return
	for i in CAPIVARA_STARTER_BUFF_COUNT:
		_spawn_starter_mushroom(world, false)
	if lvl >= 2:
		for i in CAPIVARA_STARTER_DAMAGE_COUNT:
			_spawn_starter_mushroom(world, true)


func _spawn_starter_mushroom(world: Node, is_damage: bool) -> void:
	var mush: Node2D = CAPIVARA_MUSHROOM_SCENE.instantiate()
	if "is_damage_variant" in mush:
		mush.is_damage_variant = is_damage
	world.add_child(mush)
	var b: Rect2 = CAPIVARA_STARTER_BOUNDS
	mush.global_position = Vector2(
		randf_range(b.position.x, b.position.x + b.size.x),
		randf_range(b.position.y, b.position.y + b.size.y)
	)


func _spawn_stone_cube_allies() -> void:
	# Disparo de Pedra L3: começa o round com 3 Stone Cubes aliados perto do
	# player. Não decaem e não renascem no round; somem no cleanup de curse_ally
	# no fim da wave (3 frescos no round seguinte, inclusive boss).
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	if int(player.get_upgrade_count("stone_arrow")) < 3:
		return
	if not (player is Node2D):
		return
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	if world == null:
		return
	var center: Vector2 = (player as Node2D).global_position
	for i in STONE_ALLY_COUNT:
		var ang: float = TAU * float(i) / float(STONE_ALLY_COUNT)
		_spawn_stone_cube_ally(world, center + Vector2(cos(ang), sin(ang)) * STONE_ALLY_SPAWN_RADIUS)


func _spawn_stone_cube_ally(world: Node, pos: Vector2) -> void:
	var cube: Node = STONE_CUBE_ENEMY_SCENE.instantiate()
	# Stats maiores que o cubo original. Setados ANTES do add_child pra o _ready
	# (hp = max_hp) já usar o HP novo.
	if "max_hp" in cube:
		cube.max_hp = STONE_ALLY_HP
	if "damage" in cube:
		cube.damage = STONE_ALLY_DAMAGE
	world.add_child(cube)
	if cube is Node2D:
		(cube as Node2D).global_position = pos
	# Vira aliado SEM decay, SEM tint roxo e SEM penalty de boss (forte e
	# permanente no round). Fica no grupo curse_ally → limpo no fim da wave.
	CurseAllyHelper.convert_to_ally(cube, false, false, false)


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
	# do pool completo (todos os 12 upgrades, todos os 4 pets, todos os 5 status).
	if wave_number == 1:
		await _grant_free_random_upgrade()
		if stopped:
			return
	# Pet grátis após wave 3 (antes do shop pra wave 4). Mostra popup do card.
	if wave_number == 3:
		await _grant_free_random_pet()
		if stopped:
			return
	# Pós-boss da Duskrose (wave 14): presenteia +1 level em um upgrade que o
	# player JÁ TEM. Recompensa que reforça a build atual em vez de diluir com
	# algo novo. Compensa o nerf de gold do boss.
	if wave_number == boss_redux_wave:
		await _grant_free_owned_upgrade()
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
	# Corações sobrando: sweep SEQUENCIAL — só puxa o próximo quando o anterior
	# é coletado (tree_exited). Cada coração se move devagar até o player, então
	# o jogador pode interceptar andando ao encontro pra acelerar. Sem isso, com
	# Life Steal L4 + várias mortes de fim de round o player curava 100% no
	# instante da transição (fountain).
	# Limite de raio: hearts muito longe somem em vez de virem voando do canto
	# do mapa (parecia bug). Raio = MAGNET_END_WAVE_RADIUS no heart.gd (260px).
	const END_WAVE_RADIUS_SQ: float = 260.0 * 260.0
	var hearts: Array = []
	for h in get_tree().get_nodes_in_group("heart"):
		if not is_instance_valid(h):
			continue
		if not (h as Node).has_method("magnet_to_player"):
			continue
		if (h as Node2D).global_position.distance_squared_to(player.global_position) > END_WAVE_RADIUS_SQ:
			(h as Node).queue_free()
			continue
		hearts.append(h)
	_magnet_next_heart_sequential(hearts, 0, get_player_pos)


func _magnet_next_heart_sequential(hearts: Array, idx: int, target_callable: Callable) -> void:
	if idx >= hearts.size():
		return
	var h: Node = hearts[idx]
	if not is_instance_valid(h):
		_magnet_next_heart_sequential(hearts, idx + 1, target_callable)
		return
	# Quando o coração sair da árvore (pickup ou queue_free externo), inicia o
	# próximo após um pequeno respiro visual.
	h.tree_exited.connect(func() -> void:
		var t := get_tree().create_timer(0.18)
		t.timeout.connect(func() -> void:
			_magnet_next_heart_sequential(hearts, idx + 1, target_callable)))
	h.magnet_to_player(target_callable)


func _open_shop() -> void:
	var shop_scene: PackedScene = load("res://scenes/ui/wave_shop.tscn")
	if shop_scene == null:
		return
	var shop = shop_scene.instantiate()
	# Free tower grant: na transição pra wave FREE_TOWER_WAVE (= 8), o shop é
	# aberto APÓS o _finish_wave() da wave anterior (= 7). Nesse momento
	# wave_number ainda é 7. Por isso checamos `wave_number == FREE_TOWER_WAVE - 1`.
	# O player coloca a arrow_tower grátis ANTES da UI do shop aparecer.
	if wave_number == FREE_TOWER_WAVE - 1 and not _free_tower_delivered:
		shop.set("pending_free_tower_scene", FREE_TOWER_SCENE)
		_free_tower_delivered = true
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
# pra rastrear se ainda tá vivo (estruturas móveis tipo claudio_druida movem do
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
	# Wave 14 (Duskrose) e wave 21 (boss duplo): estruturas não existem na arena,
	# então não respawnam.
	if _uses_duskrose_arena(wave_number):
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
		_apply_claudio_druida_scaling_if_applicable(inst, entry["scene_path"])
		world.add_child(inst)
		inst.global_position = pos
		entry["instance"] = inst
		entry["dead_for"] = 0.0


func _clear_alive_structures_for_boss_wave() -> void:
	# Wave 14 (Duskrose): free qualquer instância viva mas preserva a entry
	# (scene_path + position) pra respawnar normal no round seguinte. Sem isso,
	# torres/aliados ficariam na arena do boss em posições do mapa original.
	for entry in owned_structures:
		var inst_ref: Variant = entry.get("instance", null)
		if inst_ref != null and is_instance_valid(inst_ref) and inst_ref is Node:
			(inst_ref as Node).queue_free()
		entry["instance"] = null
		entry["dead_for"] = 0.0
	# Catch-all: free qualquer nó no grupo "structure" que ainda esteja vivo
	# (mesmo que não esteja em owned_structures, ex: bug de tracking).
	for n in get_tree().get_nodes_in_group("structure"):
		if is_instance_valid(n):
			(n as Node).queue_free()


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
			# Reseta HP no começo do round (claudio_druida tank precisa entrar full
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
		_apply_claudio_druida_scaling_if_applicable(inst, entry["scene_path"])
		world.add_child(inst)
		inst.global_position = pos
		entry["instance"] = inst


# Aplica HP/dmg scalonado por nível do claudio_druida_level do player. Cada compra
# aumenta os stats do aliado quando ele é spawnado (ou re-spawnado a cada round).
func _apply_claudio_druida_scaling_if_applicable(inst: Node2D, scene_path: String) -> void:
	if not scene_path.ends_with("claudio_druida.tscn"):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	var lvl: int = int(player.get_upgrade_count("claudio_druida"))
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
	# Pool completo: todos os status, upgrades e pets podem cair como free
	# (respeita pares exclusivos em runtime via _player_has_exclusive_counterpart).
	# `name` aqui é uma translation key — _show_free_upgrade_popup chama tr() nela.
	{"id": "hp", "name": "SHOP_HP_TITLE"},
	{"id": "damage", "name": "SHOP_UPG_DAMAGE"},
	{"id": "perfuracao", "name": "SHOP_UPG_PERFURACAO"},
	{"id": "attack_speed", "name": "SHOP_UPG_ATTACK_SPEED"},
	{"id": "multi_arrow", "name": "SHOP_UPG_MULTI_ARROW"},
	{"id": "double_arrows", "name": "SHOP_UPG_DOUBLE_ARROWS"},
	{"id": "chain_lightning", "name": "SHOP_UPG_CHAIN_LIGHTNING"},
	{"id": "move_speed", "name": "SHOP_UPG_MOVE_SPEED"},
	{"id": "life_steal", "name": "SHOP_UPG_LIFE_STEAL"},
	{"id": "gold_magnet", "name": "SHOP_UPG_GOLD_MAGNET"},
	{"id": "dash", "name": "SHOP_UPG_DASH"},
	{"id": "esquivando", "name": "SHOP_UPG_ESQUIVANDO"},
	{"id": "fenda", "name": "SHOP_UPG_FENDA"},
	{"id": "ricochet_arrow", "name": "SHOP_UPG_RICOCHET"},
	{"id": "graviton", "name": "SHOP_UPG_GRAVITON"},
	{"id": "armor", "name": "SHOP_UPG_ARMOR"},
	{"id": "fire_arrow", "name": "SHOP_UPG_FIRE_ARROW"},
	{"id": "curse_arrow", "name": "SHOP_UPG_CURSE_ARROW"},
	{"id": "ice_arrow", "name": "SHOP_UPG_ICE_ARROW"},
	{"id": "boomerang", "name": "SHOP_UPG_BOOMERANG"},
	{"id": "critical_chance", "name": "SHOP_UPG_CRITICAL_CHANCE"},
	{"id": "tiger_claws", "name": "SHOP_UPG_TIGER_CLAWS"},
	{"id": "claudio_druida", "name": "SHOP_ALLY_CLAUDIO_DRUIDA"},
	{"id": "leno", "name": "SHOP_ALLY_LENO"},
	{"id": "capivara_joe", "name": "SHOP_ALLY_CAPIVARA"},
	{"id": "ting", "name": "SHOP_ALLY_TING"},
	{"id": "mini_mago", "name": "SHOP_ALLY_MINI_MAGO"},
	{"id": "arbusto", "name": "SHOP_ALLY_ARBUSTO"},
]


signal _elemental_choice_picked(id: String)
# Elementais sorteados pela escolha do Mestre Elemental (item do inventário).
const _ELEMENTAL_IDS: Array[String] = ["fire_arrow", "curse_arrow", "chain_lightning", "ice_arrow", "stone_arrow", "tide_arrow"]


func _grant_elemental_choice(player: Node) -> void:
	# Sorteia 3 elementais distintos e deixa o player escolher 1 (aplica no L1).
	var pool: Array = _ELEMENTAL_IDS.duplicate()
	pool.shuffle()
	var three: Array = pool.slice(0, 3)
	var chosen: String = await _show_elemental_choice_popup(three)
	if chosen != "" and player.has_method("apply_upgrade"):
		player.apply_upgrade(chosen)


func _show_elemental_choice_popup(ids: Array) -> String:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 50
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.82)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var font: Font = load("res://font/Silver.ttf")
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-800, -320)
	title.size = Vector2(1600, 100)
	title.text = tr("HUD_ELEMENTAL_CHOICE_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	if font != null:
		title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 56)
	bg.add_child(title)
	var card_w: float = 260.0
	var card_h: float = 322.0
	var sep: float = 44.0
	var total_w: float = card_w * 3.0 + sep * 2.0
	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_CENTER)
	hb.add_theme_constant_override("separation", int(sep))
	hb.position = Vector2(-total_w / 2.0, -card_h / 2.0)
	hb.size = Vector2(total_w, card_h)
	bg.add_child(hb)
	for eid in ids:
		var seid: String = String(eid)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(card_w, card_h)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.pivot_offset = Vector2(card_w, card_h) * 0.5  # escala a partir do centro
		var tex := TextureRect.new()
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.texture = _reward_load_card_texture(seid, "upgrade", 1)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)
		# Hover: cresce um pouco (feedback visual).
		btn.mouse_entered.connect(func() -> void:
			if is_instance_valid(btn):
				btn.scale = Vector2(1.08, 1.08))
		btn.mouse_exited.connect(func() -> void:
			if is_instance_valid(btn):
				btn.scale = Vector2.ONE)
		# Escolher: som de compra + resolve.
		btn.pressed.connect(func() -> void:
			_play_buy_sfx()
			_elemental_choice_picked.emit(seid))
		hb.add_child(btn)
	get_tree().current_scene.add_child(layer)
	var chosen: String = await _elemental_choice_picked
	if is_instance_valid(layer):
		layer.queue_free()
	return chosen


func _play_buy_sfx() -> void:
	# SFX de compra (mesmo do shop). Tocado no current_scene pra sobreviver ao
	# queue_free do popup (senão o som corta).
	var p := AudioStreamPlayer.new()
	p.bus = &"SFX"
	p.stream = load("res://audios/effects/buy_1.mp3") as AudioStream
	p.volume_db = -16.0  # mesmo volume do shop (_play_buy_sound)
	get_tree().current_scene.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


func _grant_free_random_upgrade() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("apply_upgrade"):
		return
	# Mestre Elemental (item do inventário): substitui o presente de boas-vindas
	# por uma ESCOLHA de 1 entre 3 elementais aleatórios.
	if InventoryItems.has_welcome_elemental_choice():
		await _grant_elemental_choice(player)
		return
	# Filtra pares exclusivos:
	#  - perfuracao ↔ ricochet_arrow (perfura e ricocheia não combinam)
	#  - multi_arrow ↔ double_arrows (volley triplo vs disparo duplo, exclusivos)
	#  - dash ↔ esquivando (mesma categoria movimentação, mesmo slot de espaço)
	# Defensivo — em runtime normal, free upgrade rola depois da wave 1 e o player
	# ainda não tem upgrade; via dev mode pode chegar aqui com algum upgrade.
	var has_perf: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("perfuracao") > 0
	var has_ric: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("ricochet_arrow") > 0
	var has_multi: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("multi_arrow") > 0
	var has_double: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("double_arrows") > 0
	var has_dash: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("dash") > 0
	var has_esq: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("esquivando") > 0
	var has_fenda: bool = player.has_method("get_upgrade_count") and player.get_upgrade_count("fenda") > 0
	var pool: Array[Dictionary] = []
	for entry in FREE_UPGRADE_POOL:
		var id: String = entry["id"]
		# Itens de status (Adaga = +1 Dano, Arco Dourado = +1 Vel. Ataque) já dão
		# o status no L1 no início da run. O upgrade de boas-vindas NÃO pode ser
		# esse status (seria L2) — geral: pula qualquer upgrade que o player já tem.
		if player.has_method("get_upgrade_count") and int(player.get_upgrade_count(id)) > 0:
			continue
		if id == "perfuracao" and has_ric:
			continue
		if id == "ricochet_arrow" and has_perf:
			continue
		if id == "multi_arrow" and has_double:
			continue
		if id == "double_arrows" and has_multi:
			continue
		# Mobilidade: dash / esquivando / fenda são mutuamente exclusivos.
		if id == "dash" and (has_esq or has_fenda):
			continue
		if id == "esquivando" and (has_dash or has_fenda):
			continue
		if id == "fenda" and (has_dash or has_esq):
			continue
		pool.append(entry)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	player.apply_upgrade(pick["id"])
	var lvl: int = 1
	if player.has_method("get_upgrade_count"):
		lvl = int(player.get_upgrade_count(pick["id"]))
	await _show_card_reward_popup(pick["id"], lvl, "HUD_FREE_UPGRADE_TITLE", pick["name"])


# IDs cujos cards moram em pastas diferentes (subfolder ou nome PT). Mantido em
# sync com wave_shop.CARD_PATH_OVERRIDES — qualquer mudança lá precisa refletir
# aqui pra o popup de free reward achar a mesma arte que o shop.
const FREE_REWARD_CARD_PATHS: Dictionary = {
	"leno": "res://assets/Hud/shop/aliado/Leno/Leno Card.png",
	"claudio_druida": "res://assets/Hud/shop/aliado/claudio_druida/claudio_druida card.png",
	"ting": "res://assets/Hud/shop/aliado/ting/ting card.png",
	"capivara_joe": "res://assets/Hud/shop/aliado/capivara joe/capivara joe card.png",
	"mini_mago": "res://assets/Hud/shop/aliado/mini mago/mini mago card.png",
	"arbusto": "res://assets/Hud/shop/aliado/abursto carrara/arbusto.png",
	"graviton": "res://assets/Hud/shop/upgrade/graviton/graviton card-Sheet.png",
	"ricochet_arrow": "res://assets/Hud/shop/upgrade/ricochete.png",
	"gold_magnet": "res://assets/Hud/shop/upgrade/coin master.png",
	"life_steal": "res://assets/Hud/shop/upgrade/life steal.png",
	"fire_arrow": "res://assets/Hud/shop/upgrade/fire_arrow2.png",
	"ice_arrow": "res://assets/Hud/shop/upgrade/ice arrow/sangue frio card design-Sheet.png",
	"stone_arrow": "res://assets/Hud/shop/upgrade/disparo do pedra/disparo de pedra card-Sheet.png",
	"tide_arrow": "res://assets/Hud/shop/upgrade/furia da maré/furia da maré.png",
	"boomerang": "res://assets/Hud/shop/upgrade/boomerang/boomerang card design.png",
	"critical_chance": "res://assets/Hud/shop/upgrade/flechas criticas/felchas criticas card design.png",
	"tiger_claws": "res://assets/Hud/shop/upgrade/garras de tigre/garras de tigre hud-Sheet.png",
	"dash": "res://assets/Hud/shop/upgrade/deslizando.png",
	"esquivando": "res://assets/Hud/shop/upgrade/deslizando.png",
	"fenda": "res://assets/Hud/shop/upgrade/deslizando.png",
	"double_arrows": "res://assets/Hud/shop/upgrade/multi_arrow.png",
}
const FREE_REWARD_STATUS_SHEET: String = "res://assets/Hud/shop/status/HP - atck speed - Move speed - Atck Dmg.png"
const FREE_REWARD_STATUS_ROWS: Dictionary = {"hp": 0, "attack_speed": 1, "move_speed": 2, "damage": 3}
const FREE_REWARD_ALIADO_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto"]
const FREE_REWARD_STATUS_IDS: Array[String] = ["hp", "damage", "attack_speed", "move_speed", "armor"]


func _grant_free_owned_upgrade() -> void:
	# Sorteia entre os upgrades que o player JÁ TEM (level >= 1) e ainda não
	# maxou (< 4). Aplica +1 level. Se nenhum candidato (todos maxados ou nada
	# possuído), sai silenciosamente. Mesmo popup de card do _grant_free_random_upgrade.
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("apply_upgrade") or not player.has_method("get_upgrade_count"):
		return
	var pool: Array[Dictionary] = []
	for entry in FREE_UPGRADE_POOL:
		var id: String = entry["id"]
		var cur: int = int(player.get_upgrade_count(id))
		if cur <= 0:
			continue
		if cur >= 4:
			continue
		# No Limite/itens: nao sobe upgrade que so veio do item (sem investimento do
		# player alem do baseline). Ex: gold_magnet L2 do No Limite nao vira L3.
		if cur <= InventoryItems.start_granted_amount(id):
			continue
		pool.append(entry)
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	player.apply_upgrade(pick["id"])
	var lvl: int = int(player.get_upgrade_count(pick["id"]))
	await _show_card_reward_popup(pick["id"], lvl, "HUD_FREE_UPGRADE_TITLE", pick["name"])


func _grant_free_random_pet() -> void:
	# Sorteia entre os pets ainda não maxados (4 = max). Espelha a lógica antiga
	# de wave_shop._grant_free_random_pet — agora roda em wave_manager pra usar
	# o popup com card art ANTES do shop abrir.
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("apply_upgrade"):
		return
	var pets: Array[String] = []
	if player.has_method("get_upgrade_count"):
		for pid in FREE_REWARD_ALIADO_IDS:
			if int(player.get_upgrade_count(pid)) < 4:
				pets.append(pid)
	else:
		pets = FREE_REWARD_ALIADO_IDS.duplicate()
	if pets.is_empty():
		return
	var pick: String = pets[randi() % pets.size()]
	player.apply_upgrade(pick)
	var lvl: int = 1
	if player.has_method("get_upgrade_count"):
		lvl = int(player.get_upgrade_count(pick))
	var name_key: String = "SHOP_ALLY_CLAUDIO_DRUIDA"
	for entry in FREE_UPGRADE_POOL:
		if entry["id"] == pick:
			name_key = entry["name"]
			break
	await _show_card_reward_popup(pick, lvl, "HUD_FREE_PET_TITLE", name_key)


func _show_card_reward_popup(slot_id: String, target_level: int, title_key: String, name_key: String) -> void:
	# Popup procedural mostrando o card do upgrade/ally ganho com animação de
	# scale-up (overshoot pra dar sensação de "PRESENTE!"). Click no botão fecha.
	var category: String = _reward_detect_category(slot_id)
	var card_tex: Texture2D = _reward_load_card_texture(slot_id, category, target_level)
	var is_landscape: bool = (category == "status" or category == "estrutura")
	var card_size: Vector2 = Vector2(520, 136) if is_landscape else Vector2(304, 376)

	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.layer = 50
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bg)
	var at01_font: Font = load("res://font/Silver.ttf")

	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-800, -360)
	title.size = Vector2(1600, 100)
	title.text = tr(title_key)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	if at01_font != null:
		title.add_theme_font_override("font", at01_font)
	title.add_theme_font_size_override("font_size", 69)
	bg.add_child(title)

	# Card art centrado. Pivot no meio pro scale animar do centro.
	var card := TextureRect.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.position = -card_size * 0.5
	card.position.y += -20  # leve subida pra dar espaço pro name+btn embaixo
	card.size = card_size
	card.texture = card_tex
	card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	card.pivot_offset = card_size * 0.5
	card.scale = Vector2(0.1, 0.1)
	card.modulate.a = 0.0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(card)

	var name_label := Label.new()
	name_label.set_anchors_preset(Control.PRESET_CENTER)
	var name_y: float = card_size.y * 0.5 + 0  # card termina aqui (já offsetado -20)
	name_label.position = Vector2(-800, name_y)
	name_label.size = Vector2(1600, 80)
	name_label.text = "+ %s" % tr(name_key)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color.WHITE)
	if at01_font != null:
		name_label.add_theme_font_override("font", at01_font)
	name_label.add_theme_font_size_override("font_size", 69)
	name_label.modulate.a = 0.0
	bg.add_child(name_label)

	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_CENTER)
	btn.position = Vector2(-200, name_y + 90)
	btn.size = Vector2(400, 64)
	btn.text = tr("COMMON_CONTINUE")
	if at01_font != null:
		btn.add_theme_font_override("font", at01_font)
	btn.add_theme_font_size_override("font_size", 52)
	btn.modulate.a = 0.0
	btn.disabled = true  # evita click acidental durante animação
	bg.add_child(btn)

	get_tree().current_scene.add_child(layer)

	# Animação: card cresce com overshoot, depois name + btn aparecem.
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.08)
	tw.tween_property(card, "scale", Vector2.ONE, 0.45)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain()
	tw.tween_property(name_label, "modulate:a", 1.0, 0.22)
	tw.parallel().tween_property(btn, "modulate:a", 1.0, 0.22)
	tw.chain()
	tw.tween_callback(func() -> void:
		if is_instance_valid(btn):
			btn.disabled = false
	)

	await btn.pressed
	if is_instance_valid(layer):
		layer.queue_free()


func _reward_detect_category(slot_id: String) -> String:
	if FREE_REWARD_ALIADO_IDS.has(slot_id):
		return "aliado"
	if FREE_REWARD_STATUS_IDS.has(slot_id):
		return "status"
	return "upgrade"


func _reward_load_card_texture(slot_id: String, category: String, target_level: int) -> Texture2D:
	# Status usa sheet combinado (1 PNG com várias linhas = ids, várias colunas = níveis).
	if category == "status" and FREE_REWARD_STATUS_ROWS.has(slot_id):
		var sheet_tex: Texture2D = load(FREE_REWARD_STATUS_SHEET) as Texture2D
		if sheet_tex != null:
			var atlas_s := AtlasTexture.new()
			atlas_s.atlas = sheet_tex
			var fw_s: int = 65
			var fh_s: int = 17
			var cols_s: int = maxi(1, int(sheet_tex.get_width() / fw_s))
			var col_s: int = clampi(target_level - 1, 0, cols_s - 1)
			var row_s: int = int(FREE_REWARD_STATUS_ROWS[slot_id])
			atlas_s.region = Rect2(col_s * fw_s, row_s * fh_s, fw_s, fh_s)
			return atlas_s
	# Override path (assets fora do padrão `<category>/<id>.png`).
	var path: String = ""
	if FREE_REWARD_CARD_PATHS.has(slot_id):
		path = FREE_REWARD_CARD_PATHS[slot_id]
	else:
		path = "res://assets/Hud/shop/%s/%s.png" % [category, slot_id]
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	# Atlas pro frame do nível atual (col=level-1, 1 row só pra upgrade/aliado).
	var fw: int = 38
	var fh: int = 47
	if category == "status" or category == "estrutura":
		fw = 65
		fh = 17
	var frame_count: int = maxi(1, int(tex.get_width() / fw))
	var frame_idx: int = clampi(target_level - 1, 0, frame_count - 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(frame_idx * fw, 0, fw, fh)
	return atlas


# ---------- Boss intro cinematic (waves 7 e 14) ----------

func _music_for_wave(num: int) -> AudioStream:
	# Seleção da música por wave:
	#   7              → boss_music (cinematic do mage monkey)
	#   14             → duskrose_music (jazz tranquilo da Duskrose)
	#   4, 5, 6, 12, 13 → corrupted_void_music (Level 4-5-6 / Level 12-13)
	#   resto          → default (stream original do node Music)
	if num == 7:
		return boss_music
	if num == boss_redux_wave:
		return duskrose_music
	if num == 4 or num == 5 or num == 6 or num == 12 or num == 13:
		return corrupted_void_music
	return _default_music


func _swap_music_to(stream: AudioStream) -> void:
	# Troca a stream do node Music e re-toca. No-op se já está nessa stream.
	# Força loop em runtime pra mp3 (a .import default não preserva o loop).
	if stream == null:
		return
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node == null or music_node.stream == stream:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	music_node.stream = stream
	music_node.play()


func _start_dual_music_sequence() -> void:
	# Wave 21: toca faixa 1 inteira → faixa 2 inteira → faixa 1… em loop. Cada
	# faixa SEM loop nativo; o encadeamento é via o sinal `finished` do player.
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node == null:
		return
	if boss_dual_music_1 == null or boss_dual_music_2 == null:
		_swap_music_to(_default_music)
		return
	if boss_dual_music_1 is AudioStreamMP3:
		(boss_dual_music_1 as AudioStreamMP3).loop = false
	if boss_dual_music_2 is AudioStreamMP3:
		(boss_dual_music_2 as AudioStreamMP3).loop = false
	_dual_music_index = 0
	_dual_music_active = true
	if not music_node.finished.is_connected(_on_dual_music_finished):
		music_node.finished.connect(_on_dual_music_finished)
	music_node.stream = boss_dual_music_1
	music_node.play()


func _on_dual_music_finished() -> void:
	if not _dual_music_active:
		return
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node == null:
		return
	# Alterna 0 → 1 → 0 → … em loop.
	_dual_music_index = (_dual_music_index + 1) % 2
	music_node.stream = boss_dual_music_2 if _dual_music_index == 1 else boss_dual_music_1
	music_node.play()


func _stop_dual_music_sequence() -> void:
	if not _dual_music_active:
		return
	_dual_music_active = false
	var music_node := get_tree().get_first_node_in_group("music") as AudioStreamPlayer
	if music_node != null and music_node.finished.is_connected(_on_dual_music_finished):
		music_node.finished.disconnect(_on_dual_music_finished)


# Pré-spawna boss + horda inicial ANTES da cinematic (pra quando o overlay
# preto fadeia o mundo já tem todos posicionados). Boss vem com flag pra
# pular a animação de pop-in (a cinematic já é a entrada visual).
func _prespawn_boss_wave_entities() -> void:
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	# Itera o wave_config e spawna tudo de uma vez, marcando spawned_this_wave
	# pra o loop normal do _process não tentar spawnar de novo.
	for type_key: String in wave_config.keys():
		var info: Dictionary = type_registry.get(type_key, {})
		if info.is_empty() or info["scene"] == null:
			continue
		var total: int = int(wave_config[type_key]["total"])
		for i in total:
			var enemy: Node2D = info["scene"].instantiate()
			# Boss pula a animação de entrada — cinematic toma o lugar.
			if (type_key == "mage_monkey" or type_key == "duskrose") and "skip_entrance_animation" in enemy:
				enemy.skip_entrance_animation = true
			# Wave 21: a Duskrose não invoca dark balls (requisito do design).
			if wave_number == boss_dual_wave and type_key == "duskrose" and "dark_ball_summon_enabled" in enemy:
				enemy.dark_ball_summon_enabled = false
			# Aplica regras de drop/scaling iguais ao _spawn_one normal.
			if _is_boss_wave(wave_number) and type_key != "mage_monkey" and type_key != "duskrose":
				if "gold_drop_chance" in enemy:
					enemy.gold_drop_chance = 0.0
				if "heart_scene" in enemy:
					enemy.heart_scene = null
			if wave_number != 7 or type_key == "mage_monkey":
				_apply_wave_scaling(enemy)
				# Override pro boss Duskrose (wave 14): HP fixo 8500.
				if wave_number == boss_redux_wave and type_key == "duskrose" and "max_hp" in enemy:
					enemy.max_hp = 8500.0
				# Wave 21 (boss duplo): força DOBRADA — players chegam muito fortes
				# nesse round. HP Gorilla 12000 / Duskrose 16000 + dano 2x (melee e
				# projétil) nos DOIS bosses. Tropas dobradas via wave_config (8 mages).
				if wave_number == boss_dual_wave and "max_hp" in enemy:
					if type_key == "mage_monkey":
						enemy.max_hp = 12000.0
					elif type_key == "duskrose":
						enemy.max_hp = 16000.0
					if type_key == "mage_monkey" or type_key == "duskrose":
						if "damage" in enemy:
							enemy.damage *= 2.0
						if "damage_mult" in enemy:
							enemy.damage_mult *= 2.0
			# Gold dos bosses por wave (valores FINAIS, fixos):
			# - Wave 7 (Gorilla solo): 20-30 (pool ponderada mantida, pivot 23).
			# - Wave 14 (Duskrose solo): 40-60.
			# - Wave 21 (duplo): TOTAL combinado 70-100 — moedas travadas ate os 2
			#   morrerem e caem juntas. Split: Gorilla 30-45 + Duskrose 40-55.
			if wave_number == 7 and type_key == "mage_monkey":
				if "gold_drop_min" in enemy:
					enemy.gold_drop_min = 20
				if "gold_drop_max" in enemy:
					enemy.gold_drop_max = 30
			elif wave_number == boss_redux_wave and type_key == "duskrose":
				if "gold_drop_min" in enemy:
					enemy.gold_drop_min = 40
				if "gold_drop_max" in enemy:
					enemy.gold_drop_max = 60
			elif wave_number == boss_dual_wave:
				if type_key == "mage_monkey":
					if "gold_drop_min" in enemy:
						enemy.gold_drop_min = 30
					if "gold_drop_max" in enemy:
						enemy.gold_drop_max = 45
					if "gold_drop_pivot" in enemy:
						enemy.gold_drop_pivot = 45
				elif type_key == "duskrose":
					if "gold_drop_min" in enemy:
						enemy.gold_drop_min = 40
					if "gold_drop_max" in enemy:
						enemy.gold_drop_max = 55
			world.add_child(enemy)
			enemy.global_position = _pick_spawn_for(type_key)
			_pause_if_time_frozen(enemy)
			spawned_this_wave[type_key] = spawned_this_wave.get(type_key, 0) + 1
	# Wave 14 (Duskrose): troca o Map (esconde original + instancia o wave14_map
	# editável que já tem as rosas posicionadas estaticamente no .tscn),
	# esconde props decorativos de Entities (árvores/casas/cercas/postes/poços
	# do main.tscn que sobrepunham), e esconde props marcados (group
	# "hide_wave14") — tudo antes da cinematic pra player ver o ambiente
	# temático quando o overlay preto sumir.
	if _uses_duskrose_arena(wave_number):
		_set_main_map_hidden(true)
		_set_main_entities_props_hidden(true)
		_spawn_wave14_map(world)
		_set_wave14_props_hidden(true)


func _spawn_duskrose_decorative_roses(world: Node) -> void:
	# Spawna DUSKROSE_DECORATIVE_ROSE_COUNT rosas em posições aleatórias pelo
	# mapa. Cada instância usa uma das 3 scene files (A/B/C) sorteada — cada
	# scene tem seu próprio shadow/scale/alinhamento configurado no editor.
	# Tag "duskrose_decoration" pra cleanup automático no _finish_wave.
	# Monta o pool de scenes disponíveis (skipa nulls pra robustez).
	var pool: Array[PackedScene] = []
	if decorative_rose_scene != null:
		pool.append(decorative_rose_scene)
	if decorative_rose_b_scene != null:
		pool.append(decorative_rose_b_scene)
	if decorative_rose_c_scene != null:
		pool.append(decorative_rose_c_scene)
	if pool.is_empty():
		return
	# Área de spawn: largura inteira do mapa, evita o topo (patrulha da Duskrose
	# em y=40) e exclusão em raio em torno do spawn do player.
	var x_min: float = 20.0
	var x_max: float = 500.0
	var y_min: float = 60.0
	var y_max: float = 290.0
	var player_spawn: Vector2 = _wave7_player_spawn
	var exclusion_radius_sq: float = 40.0 * 40.0
	for i in DUSKROSE_DECORATIVE_ROSE_COUNT:
		var pos: Vector2 = Vector2.ZERO
		# Re-rola posição se cair no raio do player (até 5 tentativas).
		for attempt in 5:
			pos = Vector2(randf_range(x_min, x_max), randf_range(y_min, y_max))
			if pos.distance_squared_to(player_spawn) > exclusion_radius_sq:
				break
		# Sorteia 1 das 3 scenes pra essa instância — preserva customizações
		# (shadow, scale, alinhamento) específicas de cada cena.
		var scene: PackedScene = pool.pick_random()
		var rose: Node2D = scene.instantiate()
		rose.add_to_group("duskrose_decoration")
		world.add_child(rose)
		rose.global_position = pos


func _spawn_wave14_map(world: Node) -> void:
	# Carrega o Map editável da wave 14 (cópia do Map original) e adiciona ao
	# main scene root. Tudo dentro dele — grass, ground tiles, rosas que você
	# arrastou no editor, props extras — entra no mapa só pra wave 14.
	# Cleanup via group "duskrose_decoration".
	if wave14_map_scene == null:
		return
	var map_node: Node = wave14_map_scene.instantiate()
	if map_node == null:
		return
	map_node.add_to_group("duskrose_decoration")
	var main_root: Node = get_tree().current_scene
	if main_root == null:
		main_root = world
	main_root.add_child(map_node)
	# Move logo após o Map original pra ficar no mesmo Z-ordering (renderiza
	# atrás do Entities/player/enemies, igual o Map). Sem isso, o Wave14Map
	# entra como último filho e renderiza POR CIMA do player.
	var main_map: Node = get_tree().get_first_node_in_group("map")
	if main_map != null and main_map.get_parent() == main_root:
		main_root.move_child(map_node, main_map.get_index() + 1)


func _set_main_map_hidden(hide: bool) -> void:
	# Esconde/mostra o Map original (group "map") do main.tscn. Wave 14 esconde
	# pra dar lugar ao wave14_map editável. Cleanup no _finish_wave restaura.
	# IMPORTANTE: também alterna process_mode pra desligar a FÍSICA dos
	# Boundaries (StaticBody2D filhos). Sem isso, hide só esconde visualmente
	# mas as paredes do main continuam ativas e sobrepostas com as do wave14_map.
	var main_map: Node = get_tree().get_first_node_in_group("map")
	if main_map == null or not is_instance_valid(main_map):
		return
	if main_map is CanvasItem:
		(main_map as CanvasItem).visible = not hide
	main_map.process_mode = Node.PROCESS_MODE_DISABLED if hide else Node.PROCESS_MODE_INHERIT


# Scenes de props decorativos que ficam direto em Entities no main.tscn (não
# em Map). São escondidos durante a wave 14 pra o wave14_map ficar "limpo"
# sem árvores/casas/cercas/postes/poços do mapa original sobrepondo.
const _MAIN_DECORATIVE_PROP_SCENES: Array[String] = [
	"res://scenes/world/props/arvore.tscn",
	"res://scenes/world/props/arvore_2.tscn",
	"res://scenes/world/props/casa.tscn",
	"res://scenes/world/props/cerca.tscn",
	"res://scenes/world/props/cerca_cima.tscn",
	"res://scenes/world/props/cerca_cima_end.tscn",
	"res://scenes/world/props/poco.tscn",
	"res://scenes/world/props/poste.tscn",
]


func _set_main_entities_props_hidden(hide: bool) -> void:
	# Esconde/restaura props decorativos do main.tscn que estão como filhos
	# diretos de Entities (árvores, casas, cercas, postes, poços). Toggle visual
	# E process_mode pra desligar a física dos StaticBody2D filhos (cercas têm
	# collision; sem isso o player esbarra em paredes invisíveis na wave 14).
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		return
	for child in world.get_children():
		if not (child is CanvasItem):
			continue
		var path: String = (child as Node).scene_file_path
		if path in _MAIN_DECORATIVE_PROP_SCENES:
			(child as CanvasItem).visible = not hide
			(child as Node).process_mode = Node.PROCESS_MODE_DISABLED if hide else Node.PROCESS_MODE_INHERIT


func _set_wave14_props_hidden(hide: bool) -> void:
	# Esconde/mostra nodes do main.tscn marcados com group "hide_wave14".
	# Permite "remover" árvores/gramas/props que não combinam com o cenário da
	# Duskrose sem deletar nada — basta o usuário adicionar o group no Inspector
	# (Node → Groups → hide_wave14) dos props que ele quer sumir só na wave 14.
	for n in get_tree().get_nodes_in_group(WAVE14_HIDE_GROUP):
		if n is CanvasItem and is_instance_valid(n):
			(n as CanvasItem).visible = not hide


# Orquestra a cinematic: trava camera no boss, chama play_boss_intro na HUD,
# depois pan suave da camera pra o player. Boss já está em defense (porque
# minions foram pré-spawnados antes da cinematic).
func _play_boss_intro_cinematic(hud: Node) -> void:
	var camera := get_tree().get_first_node_in_group("camera")
	if camera == null:
		camera = _find_camera_fallback()
	var player := get_tree().get_first_node_in_group("player") as Node2D
	# Congela player + enemies pré-spawnados durante a cinematic (não andam,
	# não atiram). Quando o pan voltar todos estão em pose estática.
	_freeze_entities(true)
	# Wave 21: cinematic de 2 alvos (Duskrose → Gorilla → player).
	if wave_number == boss_dual_wave:
		await _play_dual_boss_intro_cinematic(hud, camera, player)
		return
	# Trava camera no centro do boss durante a cinematic. Usa a posição REAL
	# da boss (após call_deferred do snap_to_patrol que move ela pro topo do
	# mapa no caso da Duskrose). Pra bosses que têm patrol_y exposto, usa
	# esse valor diretamente porque o snap ainda não rodou nessa frame.
	var boss_node := get_tree().get_first_node_in_group("boss") as Node2D
	var camera_target: Vector2 = _wave7_boss_center
	if boss_node != null and is_instance_valid(boss_node):
		var bx: float = boss_node.global_position.x
		var by: float = boss_node.global_position.y
		if "patrol_y" in boss_node:
			by = boss_node.patrol_y
		camera_target = Vector2(bx, by - 16.0)  # -16 pra mirar no corpo (não nos pés)
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = true
		if camera is Node2D:
			(camera as Node2D).global_position = camera_target
	# HUD: black overlay + texto + cinematic sprite (16 frames @ 2 fps = 8s).
	if hud != null and hud.has_method("play_boss_intro"):
		await hud.play_boss_intro(wave_number)
	if stopped:
		if camera != null and "cinematic_mode" in camera:
			camera.cinematic_mode = false
		_freeze_entities(false)
		return
	# Hold 2.5s focado no boss depois da cinematic acabar — player vê o boss
	# em defense + a horda ao redor antes da camera começar a mover.
	await get_tree().create_timer(BOSS_INTRO_HOLD_ON_BOSS).timeout
	if stopped:
		if camera != null and "cinematic_mode" in camera:
			camera.cinematic_mode = false
		_freeze_entities(false)
		return
	# Pan LENTO do boss → player (movimento dramático).
	if camera != null and camera.has_method("pan_to") and player != null:
		var pan_target: Vector2 = player.global_position + Vector2(0, -16)
		var pan_tween: Tween = camera.pan_to(pan_target, BOSS_INTRO_PAN_DURATION)
		if pan_tween != null:
			await pan_tween.finished
	# Libera camera + descongela tudo.
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = false
	_freeze_entities(false)


func _play_dual_boss_intro_cinematic(hud: Node, camera: Node, player: Node2D) -> void:
	# Acha os dois bosses por grupo.
	var dusk: Node2D = null
	var gorilla: Node2D = null
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		if (b as Node).is_in_group("duskrose"):
			dusk = b
		elif (b as Node).is_in_group("mage_monkey"):
			gorilla = b
	# Alvos de câmera (corpo, não os pés). Duskrose usa patrol_y (snap ainda não
	# rodou nesta frame).
	var dusk_target: Vector2 = _wave7_boss_center
	if dusk != null:
		var dy: float = dusk.patrol_y if "patrol_y" in dusk else dusk.global_position.y
		dusk_target = Vector2(dusk.global_position.x, dy - 16.0)
	var gorilla_target: Vector2 = _wave7_boss_center
	if gorilla != null:
		gorilla_target = Vector2(gorilla.global_position.x, gorilla.global_position.y - 16.0)
	# Trava câmera na Duskrose pro reveal do overlay.
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = true
		if camera is Node2D:
			(camera as Node2D).global_position = dusk_target
	# Overlay "Raid 21" + fade (path da Duskrose no HUD, sem sprite do Gorilla).
	if hud != null and hud.has_method("play_boss_intro"):
		await hud.play_boss_intro(wave_number)
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 1) Segura na Duskrose.
	await get_tree().create_timer(BOSS_DUAL_INTRO_HOLD_DUSK).timeout
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 2) Pan pro Gorilla + segura.
	if camera != null and camera.has_method("pan_to"):
		var t1: Tween = camera.pan_to(gorilla_target, BOSS_DUAL_INTRO_PAN)
		if t1 != null:
			await t1.finished
	await get_tree().create_timer(BOSS_DUAL_INTRO_HOLD_GORILLA).timeout
	if stopped:
		_end_dual_cinematic(camera)
		return
	# 3) Pan pro player (canto inferior-esquerdo).
	if camera != null and camera.has_method("pan_to") and player != null:
		var t2: Tween = camera.pan_to(player.global_position + Vector2(0, -16), BOSS_INTRO_PAN_DURATION)
		if t2 != null:
			await t2.finished
	_end_dual_cinematic(camera)


func _end_dual_cinematic(camera: Node) -> void:
	if camera != null and "cinematic_mode" in camera:
		camera.cinematic_mode = false
	_freeze_entities(false)


func _freeze_entities(freeze: bool) -> void:
	# Congela/descongela player + enemies + allies/estruturas. Usado pra
	# cinematic do boss não permitir AI rodando durante o overlay preto.
	var mode: int = Node.PROCESS_MODE_DISABLED if freeze else Node.PROCESS_MODE_INHERIT
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		(player as Node).process_mode = mode
	for group_name in ["enemy", "ally", "structure"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(n):
				(n as Node).process_mode = mode


func _find_camera_fallback() -> Node:
	# Camera não está num grupo "camera" — busca por tipo na cena.
	var root := get_tree().current_scene
	if root == null:
		return null
	for child in root.get_children():
		if child is Camera2D:
			return child
	return null
