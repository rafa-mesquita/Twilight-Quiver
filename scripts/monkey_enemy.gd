extends CharacterBody2D

@export var speed: float = 40.0
@export var max_hp: float = 40.0
@export var damage: float = 18.0
@export var attack_range: float = 12.0
@export var attack_cooldown: float = 0.5
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 0.27
@export var heart_scene: PackedScene
@export var gold_drop_min: int = 1
@export var gold_drop_max: int = 2
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Knockback: decai linearmente até zero. Maior valor = decai mais rápido.
@export var knockback_decay: float = 400.0
# Pulinho durante walk: sprite sobe N pixels nos frames pares.
@export var walk_hop_height: float = 2.0
# Anti-stuck: se o monkey quer se mover mas não progride X pixels em Y segundos,
# faz um desvio lateral por Z segundos pra contornar o obstáculo.
@export var stuck_check_interval: float = 0.25
@export var stuck_step_duration: float = 0.4
@export var stuck_min_progress: float = 3.0
# Se player está mais longe que isso (ou morto), inimigo troca pra atacar torre.
@export var tower_target_switch_distance: float = 220.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

const HIT_FRAME: int = 3
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -12)

var hp: float
var can_hit: bool = true
var is_attacking: bool = false
var hit_applied: bool = false
var player: Node2D
var knockback_velocity: Vector2 = Vector2.ZERO
var sprite_base_offset_y: float = 0.0

# Estado do anti-stuck.
var _last_position: Vector2 = Vector2.ZERO
var _stuck_check_timer: float = 0.0
var _stuck_step_timer: float = 0.0
var _stuck_step_dir: Vector2 = Vector2.ZERO
var current_target: Node2D = null
var _stun_remaining: float = 0.0
# Maldição: quando convertido por curse, AI inverte (mira em enemies em vez do player).
var is_curse_ally: bool = false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("monkey")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite_base_offset_y = sprite.offset.y
	_last_position = global_position
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	# Stun: bloqueia AI/ataque, só knockback move o body.
	if _stun_remaining > 0.0:
		_stun_remaining -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Calcula a velocidade da AI separadamente, depois soma o knockback.
	var ai_velocity: Vector2 = Vector2.ZERO
	current_target = _pick_target()

	if current_target != null and is_instance_valid(current_target) and not is_attacking:
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		var dir: Vector2 = to_target.normalized()

		if dist > attack_range:
			# Direção de movimento — se está em "stuck step", usa direção lateral
			# pra contornar obstáculos; senão direto pro alvo.
			var move_dir: Vector2 = dir
			if _stuck_step_timer > 0.0:
				move_dir = _stuck_step_dir
				_stuck_step_timer -= delta
			ai_velocity = move_dir * speed
			if sprite.animation != "walk":
				sprite.play("walk")
		else:
			if can_hit:
				_attack()
			elif sprite.animation != "idle":
				sprite.play("idle")

		if absf(dir.x) > 0.001:
			sprite.flip_h = dir.x < 0.0

	# Separação contra outros inimigos pra não empilhar.
	var separation: Vector2 = EnemySeparation.compute(self, separation_radius, separation_strength)
	# Aplica knockback em cima da movimentação da AI; decai até zero.
	velocity = ai_velocity + knockback_velocity + separation
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()

	# Anti-stuck: se quis mover mas não progrediu, vira lateral.
	if ai_velocity.length() > 0.1 and not is_attacking:
		_stuck_check_timer += delta
		if _stuck_check_timer >= stuck_check_interval:
			_stuck_check_timer = 0.0
			var progress: float = global_position.distance_to(_last_position)
			_last_position = global_position
			if progress < stuck_min_progress and _stuck_step_timer <= 0.0 and player != null:
				var to_p: Vector2 = (player.global_position - global_position).normalized()
				var s: float = -1.0 if randf() < 0.5 else 1.0
				_stuck_step_dir = to_p.rotated(deg_to_rad(90.0) * s)
				_stuck_step_timer = stuck_step_duration
	else:
		_stuck_check_timer = 0.0
		_last_position = global_position


func _attack() -> void:
	can_hit = false
	is_attacking = true
	hit_applied = false
	sprite.play("attack")


func _on_frame_changed() -> void:
	# Aplica dano no frame específico do ataque, no current_target (player ou torre).
	if is_attacking and sprite.frame == HIT_FRAME and not hit_applied:
		hit_applied = true
		if current_target != null and is_instance_valid(current_target):
			var dist: float = global_position.distance_to(current_target.global_position)
			if dist <= attack_range + 6.0 and current_target.has_method("take_damage"):
				# Curse ANTES do take_damage pra contar na conversão se matar.
				if is_curse_ally:
					CurseAllyHelper.apply_ally_curse_on_damage(current_target, self)
				current_target.take_damage(damage)

	# Pulinho do walk: sprite sobe nos frames pares (visual de saltitar).
	# Sombra fica intacta porque é um node separado, não filho do sprite.
	if sprite.animation == "walk":
		var hop: float = -walk_hop_height if sprite.frame == 0 else 0.0
		sprite.offset.y = sprite_base_offset_y + hop
	else:
		sprite.offset.y = sprite_base_offset_y


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		sprite.play("idle")
		get_tree().create_timer(attack_cooldown).timeout.connect(_on_attack_cooldown_done, CONNECT_ONE_SHOT)


func _on_attack_cooldown_done() -> void:
	can_hit = true


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	var died := hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	if died:
		# Maldição: chance de virar aliado em vez de morrer (lv2-4 da curse).
		# Só roda se ainda for enemy (não duplo-converte aliado já convertido).
		if not is_curse_ally and CurseAllyHelper.try_convert_on_death(self):
			return
		GoldDrop.try_drop(_get_world(), gold_scene, global_position,
			gold_drop_chance, gold_drop_min, gold_drop_max)
		HeartDrop.try_drop(_get_world(), heart_scene, global_position)
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


func _play_damage_sound(duration: float = 0.7) -> void:
	if damage_sound == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = damage_sound
	player.volume_db = damage_sound_volume_db
	player.pitch_scale = 0.8
	# CHILD do enemy (não do world) — quando enemy queue_frees, o audio morre
	# junto. Evita som "continuo" depois da morte. Posição = enemy (local 0,0).
	add_child(player)
	player.play()
	# Lambda captura a ref direto — sobrevive mesmo se o macaco morrer/sumir antes do timeout.
	var ref: AudioStreamPlayer2D = player
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	_get_world().add_child(fx)
	# No centro do corpo do macaco (pivô fica nos pés).
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_death_silhouette() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var current_tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if current_tex == null:
		return
	# Cria um Sprite2D estático que copia o frame atual do macaco no momento da morte.
	var ghost := Sprite2D.new()
	ghost.texture = current_tex
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Aplica shader que substitui RGB por branco, preservando alpha do sprite.
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	ghost.material = mat
	_get_world().add_child(ghost)
	ghost.global_position = global_position
	ghost.modulate.a = 0.5
	# Fade out até sumir.
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


# Aplica empurrão na direção dada. Strength em pixels/segundo iniciais (decai depois).
func apply_knockback(dir: Vector2, strength: float) -> void:
	knockback_velocity = dir.normalized() * strength


# Stun: aplicado pelo Woodwarden no hit. Bloqueia AI/ataque por `duration` segs.
# Re-aplicação refresca a duração.
func apply_stun(duration: float) -> void:
	_stun_remaining = maxf(_stun_remaining, duration)
	# Quebra ataque em curso pra não reagendar dano após sair do stun.
	is_attacking = false
	hit_applied = false
	if sprite != null and sprite.animation == "attack":
		sprite.play("idle")


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	# Spawna no centro do corpo, não nos pés.
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	# Acima da cabeça (cabeça por volta de y=-24, número 4px acima).
	num.position = global_position + Vector2(0, -28)
	get_tree().current_scene.add_child(num)


func _pick_target() -> Node2D:
	# Curse ally: inverte alvo — busca enemies em vez de player/structure.
	if is_curse_ally:
		return _pick_curse_ally_target()
	# Default: player ou tank ally mais próximo (woodwarden etc.).
	# Se ambos longe ou inválidos, troca pra torre/estrutura mais próxima.
	var primary: Node2D = null
	var primary_dist: float = INF
	var player_alive: bool = player != null and is_instance_valid(player) and not (("is_dead" in player) and player.is_dead)
	if player_alive:
		primary_dist = global_position.distance_to(player.global_position)
		primary = player
	# Tank allies (group "tank_ally") competem como alvo primário se mais perto.
	for tank in get_tree().get_nodes_in_group("tank_ally"):
		if not is_instance_valid(tank) or not (tank is Node2D):
			continue
		var d: float = global_position.distance_to((tank as Node2D).global_position)
		if d < primary_dist:
			primary = tank as Node2D
			primary_dist = d
	if primary != null and primary_dist <= tower_target_switch_distance:
		return primary
	# Procura torre mais próxima.
	var nearest_tower: Node2D = null
	var nearest_dist: float = INF
	for s in get_tree().get_nodes_in_group("structure"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to((s as Node2D).global_position)
		if d < nearest_dist:
			nearest_tower = s
			nearest_dist = d
	if nearest_tower != null:
		return nearest_tower
	# Sem torre disponível — volta pro player se ele existir.
	return player if player_alive else null


func _pick_curse_ally_target() -> Node2D:
	# Quando convertido pela maldição: busca enemy mais próximo no mapa.
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


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
