extends CharacterBody2D

@export var speed: float = 32.0
@export var max_hp: float = 12.0
@export var preferred_distance: float = 100.0
@export var distance_tolerance: float = 10.0
@export var detection_range: float = 220.0
@export var shoot_interval: float = 2.4
@export var projectile_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var knockback_decay: float = 350.0
@export var hover_amplitude: float = 1.5
@export var hover_speed: float = 4.0
@export var spawn_in_duration: float = 0.45
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0
@export var tower_target_switch_distance: float = 220.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -16)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_timer: Timer = $ShootTimer

var hp: float
var damage_mult: float = 1.0  # setado pelo wave_manager — aplica no projectile no disparo
var player: Node2D
var current_target: Node2D = null
var is_attacking: bool = false
var locked_attack_dir: Vector2 = Vector2.RIGHT
var knockback_velocity: Vector2 = Vector2.ZERO
var _flash_tween: Tween
var _spawning_in: bool = false
# Maldição: convertido pra aliado (mira em enemies, projétil bate em enemies).
var is_curse_ally: bool = false
var _hover_phase: float = 0.0
var _sprite_base_offset_y: float = 0.0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("insect")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	_sprite_base_offset_y = sprite.offset.y
	_hover_phase = randf() * TAU
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_try_shoot)
	shoot_timer.start()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("fly")


func play_spawn_in() -> void:
	_spawning_in = true
	sprite.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 1.0, spawn_in_duration)
	t.tween_callback(func() -> void:
		_spawning_in = false
	)


func _physics_process(delta: float) -> void:
	# Hover suave: sprite balança no Y, sombra fica no chão (não é filha do sprite).
	_hover_phase += hover_speed * delta
	sprite.offset.y = _sprite_base_offset_y + sin(_hover_phase) * hover_amplitude

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

	# Separação contra outros inimigos pra não empilhar.
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


func _pick_target() -> Node2D:
	# Curse ally: mira em enemy mais próximo em vez de player/structure.
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
	var player_alive: bool = player != null and is_instance_valid(player) and not (("is_dead" in player) and player.is_dead)
	if player_alive:
		var pdist: float = global_position.distance_to(player.global_position)
		if pdist <= tower_target_switch_distance:
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
	if nearest_tower != null:
		return nearest_tower
	return player if player_alive else null


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_fire_projectile()
		is_attacking = false
		sprite.play("fly")


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	if "damage" in proj and damage_mult != 1.0:
		proj.damage = proj.damage * damage_mult
	if "poison_damage_total" in proj and damage_mult != 1.0:
		proj.poison_damage_total = proj.poison_damage_total * damage_mult
	# Maldição: inseto convertido marca projétil pra bater em enemies.
	if is_curse_ally and "is_ally_source" in proj:
		proj.is_ally_source = true
	_get_world().add_child(proj)
	# Origem nos pés do inseto (+1 pra sortar depois dele); visual sobe internamente.
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
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 1.15
	# CHILD do enemy — morre junto no queue_free.
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
	sprite.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


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
	num.position = global_position + Vector2(0, -32)
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
