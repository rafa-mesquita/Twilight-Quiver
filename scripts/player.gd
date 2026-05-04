extends CharacterBody2D

signal hp_changed(current: float, maximum: float)
signal died

@export var speed: float = 55.0
@export var attack_cooldown: float = 1.0
@export var arrow_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var max_hp: float = 100.0
@export var muzzle_offset_x: float = 8.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var attack_timer: Timer = $AttackTimer
@onready var hp_bar: Node2D = $HpBar

const RELEASE_FRAME: int = 4

var hp: float
var can_attack: bool = true
var is_attacking: bool = false
var is_drawing: bool = false
var locked_aim_dir: Vector2 = Vector2.RIGHT
var locked_facing_left: bool = false


func _ready() -> void:
	add_to_group("player")
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(1.0)

	attack_timer.wait_time = attack_cooldown
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.play("idle")


func _physics_process(_delta: float) -> void:
	# Durante o cast (atacando), o player fica travado.
	var input_vec := Vector2.ZERO
	if not is_attacking:
		input_vec = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
		if input_vec.length() > 1.0:
			input_vec = input_vec.normalized()

	velocity = input_vec * speed
	move_and_slide()

	_update_facing(input_vec)
	_update_animation(input_vec)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if event.is_action_pressed("attack") and can_attack:
		_start_attack()
	elif event.is_action_pressed("skill"):
		_use_skill()


func _update_facing(input_vec: Vector2) -> void:
	# Atacando: usa o lado travado no clique (mesmo critério usado pra prever o muzzle).
	# Andando: direção do movimento.
	if is_attacking:
		sprite.flip_h = locked_facing_left
	elif input_vec.x != 0.0:
		sprite.flip_h = input_vec.x < 0.0
	# Mantém o muzzle no lado pra onde o boneco está olhando.
	muzzle.position.x = -muzzle_offset_x if sprite.flip_h else muzzle_offset_x


func _update_animation(_input_vec: Vector2) -> void:
	if is_attacking:
		return
	if velocity.length() > 0.0:
		if sprite.animation != "walk":
			sprite.play("walk")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")


func _start_attack() -> void:
	# Trava a direção AGORA (no clique). A flecha sai no frame de release com essa direção.
	# Calcula a partir da posição prevista do muzzle (lado pra onde o player vai virar),
	# não do centro do player — senão a flecha sai paralela e erra o alvo por ~muzzle_offset_x.
	var mouse_pos := get_global_mouse_position()
	locked_facing_left = mouse_pos.x < global_position.x
	var predicted_muzzle := global_position + Vector2(
		-muzzle_offset_x if locked_facing_left else muzzle_offset_x,
		muzzle.position.y
	)
	locked_aim_dir = (mouse_pos - predicted_muzzle).normalized()
	can_attack = false
	is_attacking = true
	is_drawing = true
	attack_timer.start()
	sprite.play("attack")


func _release_arrow() -> void:
	is_drawing = false
	if arrow_scene == null:
		return
	var arrow := arrow_scene.instantiate()
	_get_world().add_child(arrow)
	arrow.global_position = muzzle.global_position
	if arrow.has_method("set_direction"):
		arrow.set_direction(locked_aim_dir)


func _use_skill() -> void:
	# placeholder — definimos a skill depois
	print("skill triggered toward: ", get_global_mouse_position())


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(hp / max_hp)
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	if hp == 0.0:
		died.emit()
		print("player morreu")


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	# global_position do player = pés (refator do pivô). Sobe 16 pra centro do sprite.
	fx.global_position = global_position + Vector2(0, -16)


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	# 10 acima do centro do sprite (que é 16 acima dos pés).
	num.position = global_position + Vector2(0, -26)
	# Damage numbers ficam fora do World pra sempre aparecer por cima (tipo UI).
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_attack_timer_timeout() -> void:
	can_attack = true


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		# Garantia: se algo cortou a anim antes do release_frame, solta agora.
		if is_drawing:
			_release_arrow()
		sprite.play("idle")


func _on_frame_changed() -> void:
	if is_drawing and sprite.animation == "attack" and sprite.frame == RELEASE_FRAME:
		_release_arrow()
