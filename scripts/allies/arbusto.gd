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
@export var run_duration: float = 16.0
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0

const FIRST_RUN_DURATION: float = 8.0
const HIDE_ALPHA: float = 0.45
const ATK_SPEED_BONUS: float = 0.12
const ARROW_BONUS_DAMAGE: float = 5.0
# Player se mexendo dentro do bush dispara o som a cada N px de deslocamento
# acumulado. 24px ~= 2 tiles — suficiente pra não spammar mas reagir a movimento real.
const PLAYER_MOVE_SOUND_THRESHOLD: float = 24.0

enum State { RUN, IDLE, HIDDEN }

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hide_zone: Area2D = $HideZone
@onready var bush_sound: AudioStreamPlayer2D = $BushSound

var _state: int = State.RUN
var _waypoint: Vector2 = Vector2.ZERO
var _state_timer: float = 0.0
var _player_inside: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()
# Flag pra primeira corrida do arbusto — usa FIRST_RUN_DURATION (8s) em vez
# de run_duration (20s) pra parar mais cedo logo após spawn.
var _first_run: bool = true
# Ref pro mini_arbusto que está atuando como decoy nessa sessão de HIDDEN.
# Setado em _enter_hidden, limpo em _exit_hidden.
var _mini_decoy: Node2D = null
# Tracking do movimento do player dentro do bush — quando o acumulado passa
# do threshold, toca o som de novo (rustle de folhas).
var _last_player_pos: Vector2 = Vector2.ZERO
var _player_move_accumulator: float = 0.0


func _ready() -> void:
	add_to_group("ally")
	add_to_group("arbusto")
	hide_zone.body_entered.connect(_on_zone_body_entered)
	hide_zone.body_exited.connect(_on_zone_body_exited)
	_pick_new_waypoint()
	_enter_run()


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
			_process_hidden()


# --- States ---

func _enter_run() -> void:
	_state = State.RUN
	# Primeira corrida do arbusto dura 8s; subsequentes duram run_duration (20s).
	_state_timer = FIRST_RUN_DURATION if _first_run else run_duration
	_first_run = false
	_pick_new_waypoint()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")
	_play_bush_sound()


func _process_run(delta: float) -> void:
	# Run state dura run_duration segundos. Quando chega no waypoint atual,
	# pega outro e continua correndo até o timer estourar — aí entra em idle.
	if _state_timer <= 0.0:
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


func _enter_idle() -> void:
	_state = State.IDLE
	_state_timer = 0.0
	velocity = Vector2.ZERO
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
	# Procura um mini_arbusto vivo pra atuar como decoy. Se não tem, o hide
	# não tem efeito de aggro — o player ainda ganha buffs mas mobs continuam
	# vendo ele (pq bush_hidden só é aplicado se tem decoy).
	_mini_decoy = _find_live_mini()
	if _mini_decoy != null:
		if _mini_decoy.has_method("set_decoy_active"):
			_mini_decoy.set_decoy_active(true)
		if _mini_decoy.has_signal("died") and not _mini_decoy.died.is_connected(_on_mini_decoy_died):
			_mini_decoy.died.connect(_on_mini_decoy_died)
	_apply_player_hide(true)


func _process_hidden() -> void:
	velocity = Vector2.ZERO
	move_and_slide()
	# Fallback: se o mini sumiu sem disparar o signal (queue_free externo,
	# wave reset, etc.), sai do hidden defensivamente.
	if _mini_decoy == null or not is_instance_valid(_mini_decoy):
		_exit_hidden()


func _on_mini_decoy_died() -> void:
	if _state == State.HIDDEN:
		_exit_hidden()


func _exit_hidden() -> void:
	_apply_hide_visual(false)
	if _mini_decoy != null and is_instance_valid(_mini_decoy):
		if _mini_decoy.died.is_connected(_on_mini_decoy_died):
			_mini_decoy.died.disconnect(_on_mini_decoy_died)
		if _mini_decoy.has_method("set_decoy_active"):
			_mini_decoy.set_decoy_active(false)
	_mini_decoy = null
	_apply_player_hide(false)
	_enter_run()


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


func _find_live_mini() -> Node2D:
	for n in get_tree().get_nodes_in_group("mini_arbusto"):
		if is_instance_valid(n) and n is Node2D:
			return n as Node2D
	return null


# --- Player hide buffs ---

func _apply_player_hide(active: bool) -> void:
	# Liga/desliga buffs do hide + group bush_hidden (que faz enemies ignorarem
	# o player no _pick_target deles). Aggro shield agora é simples: enquanto
	# o mini estiver vivo, mobs focam o mini (tank_ally) — não importa se tem
	# macaco dentro do bush ou não.
	var tree := get_tree()
	if tree == null:
		return
	var player := tree.get_first_node_in_group("player")
	if player == null:
		return
	if active:
		if player.has_method("arbusto_enter_hide"):
			player.arbusto_enter_hide(ATK_SPEED_BONUS, ARROW_BONUS_DAMAGE)
		if not player.is_in_group("bush_hidden"):
			player.add_to_group("bush_hidden")
	else:
		if player.has_method("arbusto_exit_hide"):
			player.arbusto_exit_hide()
		if player.is_in_group("bush_hidden"):
			player.remove_from_group("bush_hidden")


# --- Zone detection ---

func _on_zone_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_last_player_pos = (body as Node2D).global_position
		_player_move_accumulator = 0.0
		# Player encostou: entra em HIDDEN tanto vindo de IDLE quanto interceptando
		# durante RUN. Antes só permitia IDLE, mas resultava no bush continuar
		# correndo enquanto o player tentava colar nele — o visual de hide não
		# aplicava e parecia que o player estava "fora" do bush.
		if _state == State.RUN or _state == State.IDLE:
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
		# Saiu da zona durante HIDDEN: tira os buffs, o aggro shield e o visual
		# translúcido. Estado continua HIDDEN (bush não anda) até o mini morrer.
		if _state == State.HIDDEN:
			_apply_player_hide(false)
			_apply_hide_visual(false)


# --- Utils ---

func _pick_new_waypoint() -> void:
	_waypoint = Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


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
