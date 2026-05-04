extends CharacterBody2D

@export var speed: float = 30.0
@export var max_hp: float = 30.0
@export var damage: float = 10.0
@export var attack_range: float = 14.0
@export var attack_cooldown: float = 0.9
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene

@onready var hp_bar: Node2D = $HpBar

var hp: float
var can_hit: bool = true
var player: Node2D


func _ready() -> void:
	add_to_group("enemy")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")


func _physics_process(_delta: float) -> void:
	if player == null or not is_instance_valid(player):
		velocity = Vector2.ZERO
		return

	var to_player := player.global_position - global_position
	var dist := to_player.length()
	var dir := to_player.normalized()

	if dist > attack_range:
		velocity = dir * speed
	else:
		velocity = Vector2.ZERO
		if can_hit:
			_attack()

	move_and_slide()


func _attack() -> void:
	can_hit = false
	if player.has_method("take_damage"):
		player.take_damage(damage)
	get_tree().create_timer(attack_cooldown).timeout.connect(func(): can_hit = true)


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
