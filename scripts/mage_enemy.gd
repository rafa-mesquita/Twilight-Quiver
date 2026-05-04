extends CharacterBody2D

@export var speed: float = 22.0
@export var max_hp: float = 18.0
@export var preferred_distance: float = 130.0
@export var distance_tolerance: float = 12.0
@export var detection_range: float = 240.0
@export var shoot_interval: float = 2.0
@export var projectile_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var knockback_decay: float = 400.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const MUZZLE_OFFSET_X: float = 8.0
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -16)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_timer: Timer = $ShootTimer

var hp: float
var player: Node2D
var is_attacking: bool = false
var locked_attack_dir: Vector2 = Vector2.RIGHT
var knockback_velocity: Vector2 = Vector2.ZERO
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_try_shoot)
	shoot_timer.start()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("walk")


func _physics_process(delta: float) -> void:
	var ai_velocity: Vector2 = Vector2.ZERO

	if player != null and is_instance_valid(player):
		var to_player: Vector2 = player.global_position - global_position
		var dist: float = to_player.length()
		var dir: Vector2 = to_player.normalized()

		if not is_attacking:
			if dist < preferred_distance - distance_tolerance:
				ai_velocity = -dir * speed
			elif dist > preferred_distance + distance_tolerance:
				ai_velocity = dir * speed

		_update_facing(to_player)

	# Knockback soma sobre AI velocity e decai linearmente até zero.
	velocity = ai_velocity + knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()


func _update_facing(to_player: Vector2) -> void:
	if to_player.x < 0:
		sprite.flip_h = true
		muzzle.position.x = -MUZZLE_OFFSET_X
	elif to_player.x > 0:
		sprite.flip_h = false
		muzzle.position.x = MUZZLE_OFFSET_X


func _try_shoot() -> void:
	if is_attacking:
		return
	if player == null or not is_instance_valid(player):
		return
	if projectile_scene == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > detection_range:
		return

	var target := player.global_position + Vector2(0, -12)
	locked_attack_dir = (target - muzzle.global_position).normalized()
	is_attacking = true
	sprite.play("attack")


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		_fire_projectile()
		is_attacking = false
		sprite.play("walk")


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	_get_world().add_child(proj)
	proj.global_position = muzzle.global_position
	if proj.has_method("set_direction"):
		proj.set_direction(locked_attack_dir)


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	var died := hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	if died:
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


func apply_knockback(dir: Vector2, strength: float) -> void:
	knockback_velocity = dir.normalized() * strength


func _play_damage_sound(duration: float = 0.7) -> void:
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 0.8
	_get_world().add_child(p)
	p.global_position = global_position
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
