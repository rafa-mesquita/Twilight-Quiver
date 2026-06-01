extends CharacterBody2D

# Arbusto Carrara — aliado wanderer rápido. Sem HP, não-targetável.
#
# Ciclo:
# 1. RUN: corre por run_duration segundos passando por waypoints aleatórios.
#    A primeira corrida da instância usa FIRST_RUN_DURATION (mais curta).
# 2. IDLE: para indefinidamente esperando o player entrar nele.
# 3. HIDDEN: quando player encosta no IDLE, o arbusto fica translúcido e o
#    mini_arbusto (decoy spawnado junto pelo player.gd) entra em group
#    "tank_ally" — todos os mobs passam a focar nele. Player ganha:
#    - +12% atk speed (multiplicativo)
#    - +5 dano on-hit por flecha
#    - Tint verde nas flechas
#    - Group "bush_hidden" → mobs ignoram o player
#    HIDDEN dura até o mini morrer (signal `died`). Sem timer fixo.
# 4. Volta pra RUN, repete (agora com run_duration completo).
#
# L1: ativa o pet com o comportamento acima.
# L2-L4: TBD.

@export var run_speed: float = 70.0
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0

const FIRST_RUN_DURATION: float = 8.0
const HIDE_ALPHA: float = 0.45
# Janela de invencibilidade após o último mini morrer. Player continua em
# bush_hidden por POST_DEATH_GRACE segundos antes do _exit_hidden — dá um
# "fôlego" pro player escapar quando a horda mata o decoy.
const POST_DEATH_GRACE: float = 1.3
# Tabelas por nível do upgrade (index 1..4). Index 0 = sem upgrade (sem efeito).
# - L2: atk speed e dano dos buffs sobem.
# - L3: 2 minis + 30 HP extra cada + big senta com menos CD.
# - L4: atk/dano sobem mais + cada hit dentro do bush cura o player.
const ATK_SPEED_BONUS_BY_LEVEL: Array[float] = [0.0, 0.12, 0.20, 0.20, 0.30]
const ARROW_BONUS_DAMAGE_BY_LEVEL: Array[float] = [0.0, 5.0, 9.0, 9.0, 14.0]
const MINI_MAX_HP_BY_LEVEL: Array[float] = [0.0, 120.0, 120.0, 150.0, 150.0]
const RUN_DURATION_BY_LEVEL: Array[float] = [0.0, 16.0, 16.0, 10.0, 10.0]
const HEAL_PER_HIT_BY_LEVEL: Array[float] = [0.0, 0.0, 0.0, 0.0, 5.0]
# Player se mexendo dentro do bush dispara o som a cada N px de deslocamento
# acumulado. 24px ~= 2 tiles — suficiente pra não spammar mas reagir a movimento real.
const PLAYER_MOVE_SOUND_THRESHOLD: float = 24.0

enum State { RUN, IDLE, HIDDEN }

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hide_zone: Area2D = $HideZone
@onready var bush_sound: AudioStreamPlayer2D = $BushSound
@onready var run_clock: Node2D = $RunClock

var _state: int = State.RUN
var _waypoint: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
# Duração total da corrida atual — referência pra calcular o ratio (0..1) do
# relógio que indica quando ele vai parar. Setada junto do _state_timer em RUN.
var _run_duration_total: float = 0.0
var _player_inside: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()
# Flag pra primeira corrida do arbusto — usa FIRST_RUN_DURATION (8s) em vez
# de run_duration (20s) pra parar mais cedo logo após spawn.
var _first_run: bool = true
# Minis atuando como decoy nessa sessão de HIDDEN. L1/L2 tem 1, L3+ tem 2.
# Setado em _enter_hidden, limpo em _exit_hidden.
var _mini_decoys: Array[Node2D] = []
# Tracking do movimento do player dentro do bush — quando o acumulado passa
# do threshold, toca o som de novo (rustle de folhas).
var _last_player_pos: Vector2 = Vector2.ZERO
var _player_move_accumulator: float = 0.0


func _ready() -> void:
	add_to_group("ally")
	add_to_group("arbusto")
	hide_zone.body_entered.connect(_on_zone_body_entered)
	hide_zone.body_exited.connect(_on_zone_body_exited)
	_apply_wave14_safe_bounds_if_needed()
	_pick_new_waypoint()
	_enter_run()


func _apply_wave14_safe_bounds_if_needed() -> void:
	# Wave 14 (Duskrose): arbusto fica restrito à área safe do mapa, longe da
	# zona tóxica do TopBarrier (y < ~50) e da cerca de baixo (y > ~395). Sem
	# isso ele anda pra dentro do veneno e morre instantâneo.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	if "wave_number" in wm and "boss_redux_wave" in wm and int(wm.wave_number) == int(wm.boss_redux_wave):
		wander_bounds = Rect2(5, 60, 510, 320)


func _physics_process(delta: float) -> void:
	if not _is_wave_active():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_state_timer = maxf(_state_timer - delta, 0.0)
	_tick_player_rustle()
	match _state:
		State.RUN:
			_process_run(delta)
		State.IDLE:
			_process_idle()
		State.HIDDEN:
			_process_hidden(delta)


# --- States ---

func _enter_run() -> void:
	_state = State.RUN
	# Primeira corrida do arbusto sempre dura 8s; subsequentes usam o
	# run_duration do nível (L1/L2 = 16s, L3+ = 10s — "senta mais rápido").
	_state_timer = FIRST_RUN_DURATION if _first_run else RUN_DURATION_BY_LEVEL[_get_arbusto_level()]
	_run_duration_total = _state_timer
	_first_run = false
	_pick_new_waypoint()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	# Relógio "pizza" cheio: indica quanto falta pra ele parar e virar esconderijo.
	run_clock.visible = true
	run_clock.set_ratio(1.0)
	_play_bush_sound()


func _process_run(delta: float) -> void:
	# Run state dura run_duration segundos. Quando chega no waypoint atual,
	# pega outro e continua correndo até o timer estourar — aí entra em idle.
	if _state_timer <= 0.0:
		# Anti-grief contra mage_monkey (boss W7/14): se for parar perto do
		# gorila, segue correndo pra longe — player não pode hidear num spot
		# em melee range do boss sem ter saída.
		if _too_close_to_mage_monkey():
			_state_timer = 4.0
			# Novo segmento de corrida: total = 4s pra o relógio não passar de 100%.
			_run_duration_total = 4.0
			_pick_waypoint_away_from_mage_monkey()
		else:
			_enter_idle()
			return
	var to_wp: Vector2 = _waypoint - global_position
	var dist: float = to_wp.length()
	if dist <= arrive_dist:
		_pick_new_waypoint()
		to_wp = _waypoint - global_position
		dist = to_wp.length()
	var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_wp / dist
	if dir.length_squared() > 0.001:
		dir = _anti_stuck.resolve(dir, delta)
	velocity = dir * run_speed
	move_and_slide()
	_anti_stuck.update(self, _waypoint, dir.length_squared() > 0.001, delta)
	if absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0
	# Relógio esvazia conforme o tempo de corrida restante.
	if _run_duration_total > 0.0:
		run_clock.set_ratio(_state_timer / _run_duration_total)


func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = 0.0
	velocity = Vector2.ZERO
	# Parou de correr — relógio some (não há mais cooldown a mostrar).
	run_clock.visible = false
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle"):
		sprite.play("idle")
	# Se o player já está em cima nesse momento, ativa hidden direto.
	if _player_inside:
		_enter_hidden()


func _process_idle() -> void:
	# IDLE não tem timeout — fica parado indefinidamente esperando o player
	# encostar. Saída do estado só via _on_zone_body_entered → _enter_hidden.
	velocity = Vector2.ZERO
	move_and_slide()


func _enter_hidden() -> void:
	_state = State.HIDDEN
	_state_timer = 0.0
	# Escondido = parado: sem relógio (defensivo caso não tenha vindo do IDLE).
	run_clock.visible = false
	# Visual translúcido + bush em cima do player (vence Y-sort). Veja
	# _apply_hide_visual.
	_apply_hide_visual(true)
	# Garante que a animação de idle continua tocando enquanto o player está
	# escondido — defensivo caso _enter_hidden seja chamado por um caminho
	# que não tenha passado por _enter_idle.
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle"):
		if sprite.animation != &"idle" or not sprite.is_playing():
			sprite.play("idle")
	_play_bush_sound()
	# Ativa TODOS os minis vivos como decoy (L1/L2 tem 1, L3+ tem 2).
	# Cada um vira tank_ally + recebe o HP override do nível.
	var level: int = _get_arbusto_level()
	var mini_hp: float = MINI_MAX_HP_BY_LEVEL[level]
	_mini_decoys.clear()
	for n in get_tree().get_nodes_in_group("mini_arbusto"):
		if not (is_instance_valid(n) and n is Node2D):
			continue
		_mini_decoys.append(n)
		if n.has_method("set_decoy_active"):
			n.set_decoy_active(true, mini_hp)
		if n.has_signal("died") and not n.died.is_connected(_on_mini_decoy_died):
			n.died.connect(_on_mini_decoy_died)
	_apply_player_hide(true)


func _process_hidden(_delta: float) -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	# Limpa refs inválidas (mini morto ou liberado externamente). Só sai do
	# HIDDEN quando NENHUM decoy continua vivo.
	_mini_decoys = _mini_decoys.filter(func(n): return is_instance_valid(n))
	if _mini_decoys.is_empty():
		_exit_hidden()


func _on_mini_decoy_died() -> void:
	# Só dispara o exit quando todos os minis morreram. Se ainda tem outro
	# vivo (L3+), continua o hide.
	if _state != State.HIDDEN:
		return
	for n in _mini_decoys:
		if is_instance_valid(n) and not bool(n.get("_is_dead")):
			return
	_exit_hidden()


func _exit_hidden() -> void:
	_apply_hide_visual(false)
	for mini in _mini_decoys:
		if not is_instance_valid(mini):
			continue
		if mini.died.is_connected(_on_mini_decoy_died):
			mini.died.disconnect(_on_mini_decoy_died)
		if mini.has_method("set_decoy_active"):
			mini.set_decoy_active(false)
	_mini_decoys.clear()
	# Player ganha janela de iframes pós-bush — buffs caem na hora, mas
	# bush_hidden (invuln) persiste por POST_DEATH_GRACE seg no lado do player.
	# Bush volta a andar normalmente em paralelo.
	_apply_player_hide(false, POST_DEATH_GRACE)
	_enter_run()


func _get_arbusto_level() -> int:
	# Nível corrente do upgrade no player. Default 1 se não achar (defensivo).
	# Clampado em [1, 4] pra indexar as tabelas com segurança.
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return 1
	if "arbusto_level" in p:
		return clampi(int(p.arbusto_level), 1, 4)
	return 1


func _apply_hide_visual(active: bool) -> void:
	# Alterna o visual do hide: translúcido + z_index acima do player quando o
	# player ESTÁ dentro; opaco e z_index neutro quando ele sai. Estado lógico
	# (HIDDEN, mini decoy etc.) continua até o mini morrer — só o visual segue
	# o player_inside.
	if active:
		modulate.a = HIDE_ALPHA
		z_index = 1
	else:
		modulate.a = 1.0
		z_index = 0


func _tick_player_rustle() -> void:
	# Enquanto o player está dentro do bush, acumula a distância percorrida.
	# A cada PLAYER_MOVE_SOUND_THRESHOLD px, toca o som de novo (folhas
	# mexendo). Se ele fica parado, sem novo som.
	if not _player_inside:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var current_pos: Vector2 = (player as Node2D).global_position
	var step: float = current_pos.distance_to(_last_player_pos)
	_last_player_pos = current_pos
	if step <= 0.001:
		return
	_player_move_accumulator += step
	if _player_move_accumulator >= PLAYER_MOVE_SOUND_THRESHOLD:
		_player_move_accumulator = 0.0
		_play_bush_sound()


func _play_bush_sound() -> void:
	# Toca o som de "mato mexendo" sempre que o bush começa uma nova corrida
	# (RUN) ou quando o player entra no esconderijo (HIDDEN). Idle/parado não
	# dispara — fica em silêncio até o próximo evento.
	if bush_sound != null and bush_sound.stream != null:
		bush_sound.play()


# --- Player hide buffs ---

func _apply_player_hide(active: bool, grace_iframes: float = 0.0) -> void:
	# Liga/desliga buffs do hide + group bush_hidden (que faz enemies ignorarem
	# o player no _pick_target deles). Aggro shield agora é simples: enquanto
	# o mini estiver vivo, mobs focam o mini (tank_ally) — não importa se tem
	# macaco dentro do bush ou não.
	#
	# grace_iframes (só relevante quando active=false): se > 0, buffs caem na
	# hora mas o group bush_hidden persiste por N segundos no player (controlado
	# pelo timer interno dele). Usado na saída por morte do mini pra dar fôlego.
	#
	# Valores dos buffs (atk speed, dano flat, heal/hit) escalam por nível.
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return
	if active:
		var level: int = _get_arbusto_level()
		var atk_bonus: float = ATK_SPEED_BONUS_BY_LEVEL[level]
		var arrow_bonus: float = ARROW_BONUS_DAMAGE_BY_LEVEL[level]
		var heal_per_hit: float = HEAL_PER_HIT_BY_LEVEL[level]
		if player.has_method("arbusto_enter_hide"):
			player.arbusto_enter_hide(atk_bonus, arrow_bonus, heal_per_hit)
		if not player.is_in_group("bush_hidden"):
			player.add_to_group("bush_hidden")
	else:
		if player.has_method("arbusto_exit_hide"):
			player.arbusto_exit_hide()
		if grace_iframes > 0.0 and player.has_method("arbusto_grant_iframe_grace"):
			player.arbusto_grant_iframe_grace(grace_iframes)
		elif player.is_in_group("bush_hidden"):
			player.remove_from_group("bush_hidden")


# --- Zone detection ---

func _on_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_last_player_pos = (body as Node2D).global_position
		_player_move_accumulator = 0.0
		# Player só consegue se esconder quando o bush ESTÁ parado (IDLE) — se
		# ele tá correndo (RUN), passar por cima não conta. _enter_idle re-checa
		# _player_inside no próximo ciclo de IDLE pra fazer a transição se o
		# player ainda estiver em cima.
		if _state == State.IDLE:
			_enter_hidden()
		elif _state == State.HIDDEN:
			# Re-entrou durante HIDDEN (saiu e voltou enquanto mini ainda vivo) —
			# reaplica os buffs, o group bush_hidden e o visual translúcido.
			_apply_player_hide(true)
			_apply_hide_visual(true)
			_play_bush_sound()


func _on_zone_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		# Saiu da zona durante HIDDEN: tira os buffs, mas player mantém iframes
		# por POST_DEATH_GRACE seg pra ter fôlego pra escapar. Estado continua
		# HIDDEN (bush não anda) até o mini morrer.
		if _state == State.HIDDEN:
			_apply_player_hide(false, POST_DEATH_GRACE)
			_apply_hide_visual(false)


# --- Utils ---

# Raio máximo que o Pai do Verde se afasta do player. Sem isso ele vagueava o
# mapa inteiro e o player tinha que correr longe pra se esconder. Tunável.
const MAX_DIST_FROM_PLAYER: float = 200.0


func _pick_new_waypoint() -> void:
	var wp := Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)
	# Mantém o waypoint dentro de um raio máximo do player (estava indo longe
	# demais). Se cair além, puxa pro círculo de raio MAX em volta do player e
	# re-clampa nos bounds do mapa.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and is_instance_valid(player):
		var from_player: Vector2 = wp - player.global_position
		if from_player.length() > MAX_DIST_FROM_PLAYER:
			wp = player.global_position + from_player.normalized() * MAX_DIST_FROM_PLAYER
			wp.x = clampf(wp.x, wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x)
			wp.y = clampf(wp.y, wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	_waypoint = wp


# Distância mínima em que o arbusto considera "perto demais" do mage_monkey
# pra parar e virar idle. Player não consegue hidear seguro em melee range do
# boss, então o bush continua correndo até achar spot longe o suficiente.
const MAGE_MONKEY_SAFE_DIST: float = 140.0


func _too_close_to_mage_monkey() -> bool:
	for boss in get_tree().get_nodes_in_group("mage_monkey"):
		if not is_instance_valid(boss) or not (boss is Node2D):
			continue
		if global_position.distance_to((boss as Node2D).global_position) < MAGE_MONKEY_SAFE_DIST:
			return true
	return false


func _pick_waypoint_away_from_mage_monkey() -> void:
	var boss: Node2D = null
	for n in get_tree().get_nodes_in_group("mage_monkey"):
		if is_instance_valid(n) and n is Node2D:
			boss = n as Node2D
			break
	if boss == null:
		_pick_new_waypoint()
		return
	# Sorteia 8 candidatos e pega o mais distante do boss.
	var best: Vector2 = global_position
	var best_dist: float = -1.0
	for i in 8:
		var candidate := Vector2(
			randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
			randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
		)
		var d: float = candidate.distance_to(boss.global_position)
		if d > best_dist:
			best_dist = d
			best = candidate
	_waypoint = best


func _is_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return true
	return bool(wm.get("wave_active"))


func _exit_tree() -> void:
	# Cleanup defensivo: se o arbusto for liberado durante o hide, garante que
	# o player não fique com os buffs/shield pendurados.
	if _state == State.HIDDEN:
		_apply_player_hide(false)
