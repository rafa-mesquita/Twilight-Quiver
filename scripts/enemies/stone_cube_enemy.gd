extends CharacterBody2D

# Stone Cube — inimigo tanque com 2 modos:
#   DEFENSE: anda devagar (mais lento que o player), tem armor alta (reduz dano)
#   CHARGE: quando player entra no detect_range, ativa walk acelerado e corre
#           na direção dele. Encostou (attack_range), executa SLAM (anim attack)
#           dando dano alto. Após o slam, volta pra DEFENSE.

@export var speed: float = 16.0  # velocidade lenta no modo defense
@export var charge_speed: float = 75.0  # speed do charge (mais rápido que player)
@export var max_hp: float = 90.0
@export var damage: float = 25.0  # dano alto no slam
# Multiplicadores de dano por estado:
#   DEFENSE + STAND: 0.05 (95% redução)
#   DEFENSE + WALK:  0.35 (65% redução)
#   CHARGE / ATTACK: 1.20 (recebe 20% a mais — vulnerável correndo)
@export var dmg_mult_defense_stand: float = 0.05
@export var dmg_mult_defense_walk: float = 0.35
@export var dmg_mult_vulnerable: float = 1.20
# Quando só restam stone cubes no mapa, abaixa a redução pra não arrastar a
# wave: STAND 95%→30% redução (mult 0.70), WALK 65%→15% redução (mult 0.85).
@export var dmg_mult_defense_stand_lone: float = 0.70
@export var dmg_mult_defense_walk_lone: float = 0.85
@export var attack_range: float = 18.0  # range do slam (contato)
@export var detect_range: float = 95.0  # distância em que sai de defense pra charge
@export var leash_range: float = 200.0  # distância em que volta pra defense
@export var attack_cooldown: float = 5.0  # CD alto entre slams.
# Tempo travado em DEFENSE após cada ataque (não chaseia/charga durante esse tempo).
@export var post_attack_defense_lock: float = 5.0
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -16.0
# Tempo máximo do som de dano (corta após X segundos pra não tocar barulho longo).
@export var damage_sound_max_duration: float = 0.8
# Som tocado no impacto do slam (frame de hit do attack).
@export var impact_sound: AudioStream
@export var impact_sound_volume_db: float = -12.0
@export var impact_sound_max_duration: float = 0.8
# Som tocado enquanto está correndo (CHARGE). Para quando começa o ataque
# ou perde aggro.
@export var run_sound: AudioStream
@export var run_sound_volume_db: float = -14.0
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 0.40
@export var heart_scene: PackedScene
@export var gold_drop_min: int = 1
@export var gold_drop_max: int = 3
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0
@export var knockback_decay: float = 400.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const HIT_FRAME: int = 2  # frame do attack que dispara o dano (0..2 = 3 frames)
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -10)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

enum State { DEFENSE, CHARGE, ATTACK }
# Modo aleatório de DEFENSE — sorteado no _ready:
#   WALK: anda devagar na direção do alvo (player/torre)
#   STAND: fica parado playing defense anim
enum DefenseMode { WALK, STAND }

var hp: float
var player: Node2D
var current_target: Node2D = null
var knockback_velocity: Vector2 = Vector2.ZERO
var sprite_base_offset_y: float = 0.0

var _state: int = State.DEFENSE
var _defense_mode: int = DefenseMode.WALK
# Timer pro re-roll do modo de defesa (alterna entre WALK e STAND a cada 4-7s).
var _defense_mode_timer: float = 0.0
var _can_hit: bool = true
var _hit_applied: bool = false
var _stun_remaining: float = 0.0
var _run_sfx_player: AudioStreamPlayer2D = null
# Trava em DEFENSE após o ataque — durante esse tempo não vira CHARGE
# mesmo com player perto.
var _defense_lock_remaining: float = 0.0
# Flag setada pela arrow.gd antes de chamar take_damage quando o hit é da
# flecha do player (auto-attack / pierce / ricochet). Só esse tipo de dano
# cancela CHARGE/ATTACK; ticks (DoT, burn, curse), aliados e estruturas não.
var _arrow_hit_flag: bool = false
# Curse ally: convertido pela maldição, AI inverte (mira em enemies).
var is_curse_ally: bool = false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("stone_cube")
	# Imune a CC: slow, knockback, stun, pull do graviton.
	add_to_group("cc_immune")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite_base_offset_y = sprite.offset.y
	# Sorteia comportamento de DEFENSE inicial; re-roll periódico em _physics_process.
	_defense_mode = DefenseMode.WALK if randf() < 0.5 else DefenseMode.STAND
	_defense_mode_timer = randf_range(4.0, 7.0)
	sprite.play("defense")


func _physics_process(delta: float) -> void:
	# Stun: bloqueia tudo, só knockback aplica.
	if _stun_remaining > 0.0:
		_stun_remaining -= delta
		velocity = Vector2.ZERO + knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
		move_and_slide()
		return
	# Tick do lock pós-attack (mantém em DEFENSE forçado).
	if _defense_lock_remaining > 0.0:
		_defense_lock_remaining -= delta
	# Re-roll periódico do modo de defesa pra alternar entre WALK e STAND.
	# Só acontece em DEFENSE (quando charge/atacando, mode é irrelevante).
	if _state == State.DEFENSE:
		_defense_mode_timer -= delta
		if _defense_mode_timer <= 0.0:
			_defense_mode = DefenseMode.WALK if randf() < 0.5 else DefenseMode.STAND
			_defense_mode_timer = randf_range(4.0, 7.0)

	current_target = _pick_target()
	var ai_velocity: Vector2 = Vector2.ZERO

	if _state == State.ATTACK:
		# Durante slam: parado.
		ai_velocity = Vector2.ZERO
	elif current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_target / dist
		# Transições de estado:
		# - DEFENSE → CHARGE quando player entra em detect_range (e não está
		#   travado em DEFENSE após ataque)
		# - CHARGE → DEFENSE quando player sai do leash_range (perde aggro)
		if _state == State.DEFENSE and dist <= detect_range and _defense_lock_remaining <= 0.0:
			_state = State.CHARGE
			_play_run_sound()
		elif _state == State.CHARGE and dist > leash_range:
			_state = State.DEFENSE
			_stop_run_sound()

		if dist <= attack_range and _can_hit:
			_start_attack()
		else:
			# Velocidade + animação dependem de estado + modo:
			# - CHARGE: walk anim em speed_scale 1.0, charge_speed
			# - DEFENSE + WALK: walk anim em framerate lento, speed lento
			# - DEFENSE + STAND: defense anim, parado total (ai_vel = 0)
			var sp: float = 0.0
			var desired_anim: String = "defense"
			var desired_scale: float = 1.0
			if _state == State.CHARGE:
				sp = charge_speed
				desired_anim = "walk"
				desired_scale = 1.0
			elif _state == State.DEFENSE:
				if _defense_mode == DefenseMode.WALK:
					sp = speed
					desired_anim = "walk"
					desired_scale = 0.35  # framerate bem lento
				else:
					sp = 0.0
					desired_anim = "defense"
					desired_scale = 1.0
			ai_velocity = dir * sp
			if sprite.animation != desired_anim:
				sprite.play(desired_anim)
			sprite.speed_scale = desired_scale
			if absf(dir.x) > 0.001:
				sprite.flip_h = dir.x < 0.0

	# Separação contra outros inimigos.
	var separation: Vector2 = EnemySeparation.compute(self, separation_radius, separation_strength)
	velocity = ai_velocity + knockback_velocity + separation
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()


func _start_attack() -> void:
	_can_hit = false
	_state = State.ATTACK
	_hit_applied = false
	_stop_run_sound()
	sprite.speed_scale = 1.0  # reset framerate (DEFENSE+WALK usa scale 0.35)
	sprite.play("attack")


func _on_frame_changed() -> void:
	if _state == State.ATTACK and sprite.frame == HIT_FRAME and not _hit_applied:
		_hit_applied = true
		_play_impact_sound()
		if current_target != null and is_instance_valid(current_target):
			var d: float = global_position.distance_to(current_target.global_position)
			if d <= attack_range * 2.0 and current_target.has_method("take_damage"):
				if is_curse_ally:
					CurseAllyHelper.apply_ally_curse_on_damage(current_target, self)
				if current_target.is_in_group("player"):
					current_target.take_damage(damage, "stone_cube")
				else:
					current_target.take_damage(damage)


func _play_run_sound() -> void:
	if run_sound == null or _run_sfx_player != null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = run_sound
	p.volume_db = run_sound_volume_db
	add_child(p)
	p.play()
	_run_sfx_player = p


func _stop_run_sound() -> void:
	if _run_sfx_player != null and is_instance_valid(_run_sfx_player):
		_run_sfx_player.stop()
		_run_sfx_player.queue_free()
	_run_sfx_player = null


func _play_impact_sound() -> void:
	if impact_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = impact_sound
	p.volume_db = impact_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	add_child(p)
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(impact_sound_max_duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		# Após o slam: volta pra DEFENSE PURO (modo STAND, parado total) travado
		# por post_attack_defense_lock segundos. Sem walk, sem charge nesse tempo.
		_state = State.DEFENSE
		_defense_mode = DefenseMode.STAND
		_defense_lock_remaining = post_attack_defense_lock
		# Reseta o timer do re-roll pra MAIOR que o lock — assim não troca pra
		# WALK durante o lock pós-ataque.
		_defense_mode_timer = post_attack_defense_lock + randf_range(2.0, 4.0)
		sprite.play("defense")
		get_tree().create_timer(attack_cooldown).timeout.connect(func() -> void:
			_can_hit = true
		, CONNECT_ONE_SHOT)


func take_damage(amount: float) -> void:
	# Multiplicador de dano por estado:
	#   DEFENSE + STAND: 0.05 (95% redução) — ou 0.70 se só restam stone cubes
	#   DEFENSE + WALK:  0.35 (65% redução) — ou 0.85 se só restam stone cubes
	#   CHARGE / ATTACK: 1.20 (vulnerável)
	var lone: bool = _only_stone_cubes_remaining()
	var mult: float = dmg_mult_vulnerable
	if _state == State.DEFENSE:
		if _defense_mode == DefenseMode.STAND:
			mult = dmg_mult_defense_stand_lone if lone else dmg_mult_defense_stand
		else:
			mult = dmg_mult_defense_walk_lone if lone else dmg_mult_defense_walk
	var actual: float = amount * mult
	# Só dano da flecha do player (auto-attack, pierce, ricochet) cancela
	# CHARGE/ATTACK. Ticks (burn/curse), aliados e estruturas não interrompem.
	var from_arrow: bool = _arrow_hit_flag
	_arrow_hit_flag = false
	var was_aggressive: bool = _state == State.CHARGE or _state == State.ATTACK
	if not is_curse_ally:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("notify_damage_dealt"):
			p.notify_damage_dealt(actual)
	hp = maxf(hp - actual, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(actual)
	var died: bool = hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	# Interrompe CHARGE/ATTACK só se o hit veio de uma flecha do player.
	# DoT/aliado/estrutura batem normal mas não cancelam o ataque.
	if not died and was_aggressive and from_arrow:
		_state = State.DEFENSE
		_defense_mode = DefenseMode.STAND
		_defense_lock_remaining = post_attack_defense_lock
		_defense_mode_timer = post_attack_defense_lock + randf_range(2.0, 4.0)
		_hit_applied = false
		_can_hit = false
		_stop_run_sound()
		sprite.speed_scale = 1.0
		sprite.play("defense")
		# Re-libera _can_hit após o cooldown normal.
		get_tree().create_timer(attack_cooldown).timeout.connect(func() -> void:
			_can_hit = true
		, CONNECT_ONE_SHOT)
	if died:
		if not is_curse_ally:
			if CurseAllyHelper.try_convert_on_death(self):
				return
			HeartDrop.try_drop(_get_world(), heart_scene, global_position, self)
			var p2 := get_tree().get_first_node_in_group("player")
			if p2 != null and p2.has_method("notify_enemy_killed"):
				p2.notify_enemy_killed()
		# Gold dropa em ambos: morte de inimigo normal E morte de aliado convertido
		# pela Maldição (vale o trabalho que ele teve até cair).
		GoldDrop.try_drop(_get_world(), gold_scene, global_position,
			gold_drop_chance, gold_drop_min, gold_drop_max)
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


func _play_damage_sound(_duration: float = 0.7) -> void:
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	add_child(p)
	p.play()
	# Corta após damage_sound_max_duration (player só ouve os primeiros 0.8s).
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(damage_sound_max_duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_death_silhouette() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var current_tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if current_tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = current_tex
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	ghost.material = mat
	_get_world().add_child(ghost)
	ghost.global_position = global_position
	ghost.modulate.a = 0.5
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, death_silhouette_duration)
	t.tween_callback(ghost.queue_free)


var _flash_tween: Tween

func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


func apply_knockback(_dir: Vector2, _strength: float) -> void:
	# Imune a knockback (CC).
	pass


func apply_stun(_duration: float) -> void:
	# Imune a stun (CC).
	pass


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	num.position = global_position + Vector2(0, -28)
	get_tree().current_scene.add_child(num)


func _pick_target() -> Node2D:
	if is_curse_ally:
		return _pick_curse_ally_target()
	# Default: player se vivo, senão tank ally / torre mais próxima.
	var primary: Node2D = null
	var primary_dist: float = INF
	var player_alive: bool = player != null and is_instance_valid(player) and not (("is_dead" in player) and player.is_dead)
	if player_alive:
		primary_dist = global_position.distance_to(player.global_position)
		primary = player
	for tank in get_tree().get_nodes_in_group("tank_ally"):
		if not is_instance_valid(tank) or not (tank is Node2D):
			continue
		var d: float = global_position.distance_to((tank as Node2D).global_position)
		if d < primary_dist:
			primary = tank as Node2D
			primary_dist = d
	if primary != null:
		return primary
	# Sem player nem tank — tenta torre.
	var nearest_tower: Node2D = null
	var nearest_dist: float = INF
	for s in get_tree().get_nodes_in_group("structure"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to((s as Node2D).global_position)
		if d < nearest_dist:
			nearest_tower = s
			nearest_dist = d
	return nearest_tower


func _pick_curse_ally_target() -> Node2D:
	var nearest: Node2D = null
	var best_dist: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_dist:
			nearest = e
			best_dist = d
	return nearest


func _only_stone_cubes_remaining() -> bool:
	# Verdadeiro quando todo enemy vivo no mapa é stone_cube — usado pra reduzir
	# a redução de dano e não arrastar a wave.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if not (e as Node).is_in_group("stone_cube"):
			return false
	return true


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
