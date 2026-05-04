extends CharacterBody2D

@export var speed: float = 24.0
@export var max_hp: float = 20.0
@export var preferred_distance: float = 110.0
@export var distance_tolerance: float = 12.0
@export var detection_range: float = 220.0
@export var shoot_interval: float = 1.6
@export var enemy_arrow_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene

@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_timer: Timer = $ShootTimer

var hp: float
var player: Node2D


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_try_shoot)
	shoot_timer.start()


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		velocity = Vector2.ZERO
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()

	# Mantém distância: se perto demais, recua; se longe demais, avança.
	if dist < preferred_distance - distance_tolerance:
		velocity = -dir * speed
	elif dist > preferred_distance + distance_tolerance:
		velocity = dir * speed
	else:
		velocity = Vector2.ZERO

	move_and_slide()


func _try_shoot() -> void:
	if player == null or not is_instance_valid(player):
		return
	if enemy_arrow_scene == null:
		return
	var dist := global_position.distance_to(player.global_position)
	if dist > detection_range:
		return

	var dir := (player.global_position - global_position).normalized()
	var arrow := enemy_arrow_scene.instantiate()
	_get_world().add_child(arrow)
	arrow.global_position = muzzle.global_position
	if arrow.has_method("set_direction"):
		arrow.set_direction(dir)


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	if hp <= 0.0:
		queue_free()


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	num.position = global_position + Vector2(0, -10)
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
