extends Node2D

# Frostwisp — aliada voadora do L3 do Fica Frio.
# - Vagueia aleatoriamente em torno do player (waypoints random dentro de um raio)
# - SEM HP, SEM colisão com inimigos, NÃO targetável, freeze_immune
# - A cada 16s: voa pra área com mais inimigos (centroide), spawna um
#   FrostwispField (dano + slow em AoE) e bombardeia com projeteis caindo
#   dentro do campo por 5s. Voos rasantes em órbita, rastro azul, sons.

@export var wander_radius: float = 110.0  # raio em volta do player onde escolhe waypoints
@export var wander_min_pause: float = 0.4
@export var wander_max_pause: float = 1.2
@export var follow_speed: float = 65.0
@export var attack_speed: float = 160.0
@export var bob_amplitude: float = 3.0
@export var bob_speed: float = 2.5
@export var attack_cycle_interval: float = 16.0
@export var attack_duration: float = 5.0
@export var projectile_spawn_interval: float = 0.08  # tempestade densa: ~62 projeteis em 5s
@export var projectile_damage: float = 4.0  # baixo, mas muita frequência = burst alto
@export var projectile_slow_factor: float = 0.55
@export var projectile_slow_duration: float = 1.5
@export var projectile_scene: PackedScene
@export var field_scene: PackedScene
@export var field_dps: float = 8.0  # dano contínuo do FrostwispField (8 dps × 5s = 40 base)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

const CAST_SOUND: AudioStream = preload("res://audios/effects/Cast frostwisp.mp3")
const AVALANCHE_SOUND: AudioStream = preload("res://audios/effects/Avalanche snow.mp3")
const CAST_SOUND_DURATION: float = 2.0
const CAST_SOUND_VOLUME_DB: float = -10.0
const AVALANCHE_SOUND_VOLUME_DB: float = -20.0
# Raio dentro do campo onde projeteis aleatorizam pra parecer chuva de gelo.
const PROJECTILE_DROP_RADIUS: float = 46.0

var _player: Node2D = null
var _bob_t: float = 0.0
var _attack_cd_remaining: float = 0.0
var _is_attacking: bool = false
var _attack_remaining: float = 0.0
var _attack_target_pos: Vector2 = Vector2.ZERO
var _next_proj_in: float = 0.0
var _rasant_t: float = 0.0
var _trail_emitter: CPUParticles2D = null
var _avalanche_player: AudioStreamPlayer2D = null
# Wander state — waypoint atual + pause timer entre waypoints.
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause_remaining: float = 0.0
var _active_field: Node2D = null


func _ready() -> void:
	add_to_group("ally")
	add_to_group("freeze_immune")  # L4 do Gelo não congela a Frostwisp
	_attack_cd_remaining = attack_cycle_interval
	_player = get_tree().get_first_node_in_group("player") as Node2D
	if sprite != null:
		sprite.play("fly")
	_pick_new_wander_target()


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
		if _player == null:
			return
	_bob_t += delta
	if _is_attacking:
		_update_attack(delta)
	else:
		_update_wander(delta)
	_apply_bob()
	_apply_facing()


func _apply_bob() -> void:
	var bob_mult: float = 1.3 if _is_attacking else 1.0
	var y_off: float = sin(_bob_t * bob_speed * bob_mult) * bob_amplitude
	if sprite != null:
		sprite.position.y = y_off


func _apply_facing() -> void:
	var ref_x: float = _wander_target.x
	if _is_attacking:
		ref_x = _attack_target_pos.x
	if sprite != null:
		sprite.flip_h = global_position.x > ref_x


func _update_wander(delta: float) -> void:
	# Movimento aleatório: escolhe waypoints dentro de wander_radius do player,
	# anda até lá, pausa um pouco, escolhe outro. Mantém ela "perto" do player
	# mas sem grudar.
	if _wander_pause_remaining > 0.0:
		_wander_pause_remaining -= delta
	else:
		var dir := _wander_target - global_position
		var dist := dir.length()
		if dist <= 4.0:
			_wander_pause_remaining = randf_range(wander_min_pause, wander_max_pause)
			_pick_new_wander_target()
		else:
			var step: float = minf(follow_speed * delta, dist)
			global_position += dir / dist * step
	# Re-seleciona waypoint se ele saiu muito longe do player (ex: player se moveu).
	if global_position.distance_to(_player.global_position) > wander_radius * 1.8:
		_pick_new_wander_target()
	_attack_cd_remaining -= delta
	if _attack_cd_remaining <= 0.0:
		_start_attack()


func _pick_new_wander_target() -> void:
	# Random ponto dentro do raio do player.
	var angle: float = randf() * TAU
	var dist: float = randf_range(wander_radius * 0.4, wander_radius)
	_wander_target = _player.global_position + Vector2(cos(angle), sin(angle) * 0.65) * dist


func _start_attack() -> void:
	var center := _find_enemy_centroid()
	if center == Vector2.INF:
		_attack_cd_remaining = 2.0
		return
	_attack_target_pos = center
	_is_attacking = true
	_attack_remaining = attack_duration
	_next_proj_in = 0.15
	_rasant_t = 0.0
	_spawn_field()
	_spawn_trail()
	_play_cast_sound()
	_start_avalanche_sound()


func _update_attack(delta: float) -> void:
	_attack_remaining -= delta
	_rasant_t += delta
	# Voos rasantes em órbita lateral em torno do campo.
	var orbit_r: float = 36.0
	var ang: float = 3.2
	var orbit := Vector2(cos(_rasant_t * ang), sin(_rasant_t * ang * 0.65)) * orbit_r
	var desired := _attack_target_pos + orbit
	var dir := desired - global_position
	var dist := dir.length()
	if dist > 1.5:
		var step: float = minf(attack_speed * delta, dist)
		global_position += dir / dist * step
	_next_proj_in -= delta
	if _next_proj_in <= 0.0:
		_spawn_projectile()
		_next_proj_in = projectile_spawn_interval
	if _attack_remaining <= 0.0:
		_end_attack()


func _end_attack() -> void:
	_is_attacking = false
	_attack_cd_remaining = attack_cycle_interval
	_remove_trail()
	_stop_avalanche_sound()
	_active_field = null  # field cleanua sozinho via _life_remaining
	_pick_new_wander_target()


func _find_enemy_centroid() -> Vector2:
	# Acha o CLUSTER MAIS DENSO (não a média geral — média acaba apontando
	# pro meio do mapa quando inimigos espalham). Pra cada inimigo, conta
	# vizinhos dentro do raio de cluster; o inimigo com mais vizinhos define
	# o centro, e o ponto de spawn é a centroide só dele + os vizinhos dele.
	var enemies := get_tree().get_nodes_in_group("enemy")
	if enemies.is_empty():
		return Vector2.INF
	var positions: Array[Vector2] = []
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		if "hp" in e and float(e.hp) <= 0.0:
			continue
		positions.append((e as Node2D).global_position)
	if positions.is_empty():
		return Vector2.INF
	if positions.size() == 1:
		return positions[0]
	# Raio de "vizinhança" — um pouco maior que o field radius pra agrupar
	# inimigos que vão sentir o ataque inteiro mesmo se nas bordas.
	var cluster_radius_sq: float = 75.0 * 75.0
	var best_centroid: Vector2 = positions[0]
	var best_count: int = 0
	for i in positions.size():
		var pos_i: Vector2 = positions[i]
		var sum: Vector2 = pos_i
		var count: int = 1
		for j in positions.size():
			if i == j:
				continue
			if pos_i.distance_squared_to(positions[j]) <= cluster_radius_sq:
				sum += positions[j]
				count += 1
		if count > best_count:
			best_count = count
			best_centroid = sum / float(count)
	return best_centroid


# Chamado pelo player.reset_all_cooldowns no início de cada wave. Atrasa o
# primeiro cast pra dar tempo do jogador se posicionar antes da Frostwisp
# começar a bombardear.
func set_initial_cooldown(seconds: float) -> void:
	_attack_cd_remaining = maxf(_attack_cd_remaining, seconds)


func _spawn_field() -> void:
	if field_scene == null:
		return
	var field: Node = field_scene.instantiate()
	if "damage_per_second" in field:
		field.damage_per_second = field_dps
	if "duration" in field:
		field.duration = attack_duration
	get_tree().current_scene.add_child(field)
	if field is Node2D:
		(field as Node2D).global_position = _attack_target_pos
	_active_field = field as Node2D


func _spawn_projectile() -> void:
	if projectile_scene == null:
		return
	# Cai DENTRO do campo (raio menor que o do field).
	var off := Vector2(
		randf_range(-PROJECTILE_DROP_RADIUS, PROJECTILE_DROP_RADIUS),
		randf_range(-PROJECTILE_DROP_RADIUS * 0.55, PROJECTILE_DROP_RADIUS * 0.55)
	)
	var land_pos: Vector2 = _attack_target_pos + off
	var proj: Node = projectile_scene.instantiate()
	if "land_position" in proj:
		proj.land_position = land_pos
	if "damage" in proj:
		proj.damage = projectile_damage
	if "slow_factor" in proj:
		proj.slow_factor = projectile_slow_factor
	if "slow_duration" in proj:
		proj.slow_duration = projectile_slow_duration
	get_tree().current_scene.add_child(proj)
	if proj is Node2D:
		(proj as Node2D).global_position = land_pos + Vector2(0, -130.0)


func _spawn_trail() -> void:
	if _trail_emitter != null and is_instance_valid(_trail_emitter):
		return
	var p := CPUParticles2D.new()
	p.amount = 18
	p.lifetime = 0.6
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 4.0
	p.spread = 70.0
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 30.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.75
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.55, 0.85, 1.0, 0.85),
		Color(0.55, 0.85, 1.0, 0.0),
	])
	p.color_ramp = ramp
	p.z_index = -1
	add_child(p)
	_trail_emitter = p


func _remove_trail() -> void:
	if _trail_emitter == null or not is_instance_valid(_trail_emitter):
		return
	_trail_emitter.emitting = false
	var ref: CPUParticles2D = _trail_emitter
	_trail_emitter = null
	var tw := ref.create_tween()
	tw.tween_interval(0.8)
	tw.tween_callback(ref.queue_free)


func _play_cast_sound() -> void:
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = CAST_SOUND
	p.volume_db = CAST_SOUND_VOLUME_DB
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(CAST_SOUND_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _start_avalanche_sound() -> void:
	if _avalanche_player != null and is_instance_valid(_avalanche_player):
		return
	var stream: AudioStream = AVALANCHE_SOUND
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_avalanche_player = AudioStreamPlayer2D.new()
	_avalanche_player.bus = &"SFX"
	_avalanche_player.stream = stream
	_avalanche_player.volume_db = AVALANCHE_SOUND_VOLUME_DB
	add_child(_avalanche_player)
	_avalanche_player.play()


func _stop_avalanche_sound() -> void:
	if _avalanche_player == null or not is_instance_valid(_avalanche_player):
		return
	_avalanche_player.stop()
	_avalanche_player.queue_free()
	_avalanche_player = null
