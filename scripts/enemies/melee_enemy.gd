extends CharacterBody2D

@export var speed: float = 30.0
@export var max_hp: float = 30.0
@export var damage: float = 10.0
@export var attack_range: float = 14.0
@export var attack_cooldown: float = 0.9
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene

@onready var hp_bar: Node2D = $HpBar
@onready var body_visual: Polygon2D = $Body

var hp: float
var can_hit: bool = true
var player: Node2D
var _flash_tween: Tween


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
		player.take_damage(damage, "melee")
	get_tree().create_timer(attack_cooldown).timeout.connect(func(): can_hit = true)


func take_damage(amount: float) -> void:
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	if hp <= 0.0:
		_spawn_kill_effect()
		queue_free()


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position


func _flash_damage() -> void:
	if body_visual == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	body_visual.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(body_visual, "modulate", Color.WHITE, 0.2)


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
