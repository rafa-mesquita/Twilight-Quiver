extends CharacterBody2D

# Rosa Monstro — minion invocado pela Duskrose (boss da wave 14). Anda em
# direção ao player/tank e cospe um projétil (reusa insect_projectile.tscn pra
# começo; pode trocar pra um projetil próprio depois).
#
# Diferenças vs insect_enemy:
# - Anim "walk" rodando enquanto se move (insect só tem "fly")
# - Sem hover (anda no chão)
# - Sprite 40×40 (frames 8-15 da duskrose-Sheet)
#
# Targeting: copia o pattern do insect_enemy (tank_ally > player > tower) com
# tank tendo prioridade incondicional (puxa aggro).

@export var speed: float = 25.0
@export var max_hp: float = 30.0
@export var preferred_distance: float = 110.0
@export var distance_tolerance: float = 12.0
@export var detection_range: float = 240.0
@export var shoot_interval: float = 2.6
# Cor do flash quando toma dano. Rosa pra combinar com o tema da Duskrose.
const HIT_FLASH_COLOR: Color = Color(1.7, 0.55, 0.95, 1.0)
# Tint do damage_effect spawnado. Rosa coerente com o flash.
const HIT_EFFECT_TINT: Color = Color(1.5, 0.55, 0.9, 1.0)
# Som de ataque (cuspe). Carregado lazy via load() pra tolerar mp3 sem .import
# (Godot gera .import automático no próximo refresh do FileSystem dock).
const ATTACK_SOUND_PATH: String = "res://assets/enemies/duskrose/atack rosa mosntro.mp3"
@export var attack_sound_volume_db: float = -14.0
@export var projectile_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var knockback_decay: float = 350.0
@export var spawn_in_duration: float = 0.45
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0
@export var tower_target_switch_distance: float = 240.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -16)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_timer: Timer = $ShootTimer

var hp: float
var damage_mult: float = 1.0
var player: Node2D
var current_target: Node2D = null
var is_attacking: bool = false
var locked_attack_dir: Vector2 = Vector2.RIGHT
var knockback_velocity: Vector2 = Vector2.ZERO
var _flash_tween: Tween
var _crit_pending: bool = false
var _spawning_in: bool = false
var is_curse_ally: bool = false


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("rose_monster")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_try_shoot)
	shoot_timer.start()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("walk")


func play_spawn_in() -> void:
	_spawning_in = true
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 1.0, spawn_in_duration)
	t.tween_callback(func() -> void:
		_spawning_in = false
	)


func _physics_process(delta: float) -> void:
	if _spawning_in:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var ai_velocity: Vector2 = Vector2.ZERO
	current_target = _pick_target()

	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		var dir: Vector2 = to_target.normalized()

		if not is_attacking:
			if dist < preferred_distance - distance_tolerance:
				ai_velocity = -dir * speed
			elif dist > preferred_distance + distance_tolerance:
				ai_velocity = dir * speed

		_update_facing(to_target)

	var separation: Vector2 = EnemySeparation.compute(self, separation_radius, separation_strength)
	velocity = ai_velocity + knockback_velocity + separation
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()


func _update_facing(to_player: Vector2) -> void:
	if to_player.x < 0:
		sprite.flip_h = true
	elif to_player.x > 0:
		sprite.flip_h = false


func _try_shoot() -> void:
	if _spawning_in or is_attacking:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	if projectile_scene == null:
		return
	var dist := global_position.distance_to(current_target.global_position)
	if dist > detection_range:
		return
	var target := current_target.global_position + Vector2(0, -12)
	locked_attack_dir = (target - muzzle.global_position).normalized()
	is_attacking = true
	sprite.play("attack")
	# Som do cuspe — toca no mundo (sobrevive se a rosa morrer mid-attack).
	_play_one_shot(load(ATTACK_SOUND_PATH) as AudioStream, global_position, attack_sound_volume_db)


func _play_one_shot(sound: AudioStream, pos: Vector2, volume_db: float) -> void:
	if sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = sound
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	_get_world().add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)


func _pick_target() -> Node2D:
	# Curse ally: mira em enemy mais próximo.
	if is_curse_ally:
		var nearest: Node2D = null
		var best: float = INF
		for e in get_tree().get_nodes_in_group("enemy"):
			if not is_instance_valid(e) or not (e is Node2D):
				continue
			var d: float = global_position.distance_to((e as Node2D).global_position)
			if d < best:
				nearest = e
				best = d
		return nearest
	# Tank_ally tem prioridade incondicional sobre player (mesmo pattern do insect).
	var nearest_tank: Node2D = null
	var nearest_tank_dist: float = INF
	for t in get_tree().get_nodes_in_group("tank_ally"):
		if not is_instance_valid(t) or not (t is Node2D):
			continue
		var d: float = global_position.distance_to((t as Node2D).global_position)
		if d < nearest_tank_dist:
			nearest_tank = t as Node2D
			nearest_tank_dist = d
	if nearest_tank != null:
		return nearest_tank
	var player_alive: bool = player != null and is_instance_valid(player) and not (("is_dead" in player) and player.is_dead)
	var player_visible: bool = player_alive and not (player as Node).is_in_group("bush_hidden")
	if player_visible:
		return player
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


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_fire_projectile()
		is_attacking = false
		sprite.play("walk")


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	if "damage" in proj and damage_mult != 1.0:
		proj.damage = proj.damage * damage_mult
	if "poison_damage_total" in proj and damage_mult != 1.0:
		proj.poison_damage_total = proj.poison_damage_total * damage_mult
	if is_curse_ally and "is_ally_source" in proj:
		proj.is_ally_source = true
	# Skin rosa: projétil + trail + glow + hit effect ficam tintados pra combinar
	# com o tema da Duskrose (em vez do verde-veneno do inseto).
	if "pink_skin" in proj:
		proj.pink_skin = true
	_get_world().add_child(proj)
	proj.global_position = Vector2(muzzle.global_position.x, global_position.y + 1)
	if proj.has_method("set_direction"):
		proj.set_direction(locked_attack_dir)


func take_damage(amount: float) -> void:
	if not is_curse_ally:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("notify_damage_dealt"):
			p.notify_damage_dealt(amount)
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	var died := hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	if died:
		if not is_curse_ally:
			var p2 := get_tree().get_first_node_in_group("player")
			if p2 != null and p2.has_method("notify_enemy_killed"):
				p2.notify_enemy_killed()
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


func apply_knockback(dir: Vector2, strength: float) -> void:
	knockback_velocity = dir.normalized() * strength


func _play_damage_sound(duration: float = 0.7) -> void:
	for c in get_children():
		if c is FreezeDebuff:
			return
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 1.15
	add_child(p)
	p.play()
	var ref: AudioStreamPlayer2D = p
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


func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Crit mantém o amarelo padrão; hit normal usa rosa do tema da Duskrose.
	var flash_color: Color = CritFeedback.CRIT_FLASH_COLOR if _crit_pending else HIT_FLASH_COLOR
	sprite.modulate = flash_color
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	# Tint rosa pra o impacto combinar com o tema (em vez do branco/laranja default).
	if fx is CanvasItem:
		(fx as CanvasItem).modulate = HIT_EFFECT_TINT
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		_crit_pending = false
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	if _crit_pending and "color_override" in num:
		num.color_override = CritFeedback.CRIT_NUMBER_COLOR
	num.position = global_position + Vector2(0, -32)
	get_tree().current_scene.add_child(num)
	_crit_pending = false


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
