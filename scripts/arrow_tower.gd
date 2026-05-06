extends Node2D

# Torre de flechas: 2 muzzles independentes (esq + dir) atirando em inimigos
# próximos. Cada muzzle tem cooldown próprio. Flecha = arrow do player com
# 80% do dano. Tem HP — pode ser atacada por inimigos.

signal tower_attacked(tower: Node2D)
signal tower_destroyed(tower: Node2D)

@export var arrow_scene: PackedScene
@export var detection_range: float = 180.0
@export var muzzle_cooldown: float = 3.0
@export var damage_multiplier: float = 0.8
@export var max_hp: float = 300.0
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -38)

@onready var muzzle_left: Marker2D = $MuzzleLeft
@onready var muzzle_right: Marker2D = $MuzzleRight
@onready var timer_left: Timer = $TimerLeft
@onready var timer_right: Timer = $TimerRight
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

var hp: float
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("structure")
	add_to_group("ally")
	hp = max_hp
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
		hp_bar.visible = true
	timer_left.wait_time = muzzle_cooldown
	timer_right.wait_time = muzzle_cooldown
	timer_left.one_shot = true
	timer_right.one_shot = true
	timer_left.start(randf_range(0.0, 0.5))
	timer_right.start(randf_range(0.5, 1.0))
	timer_left.timeout.connect(_try_shoot.bind(muzzle_left, timer_left))
	timer_right.timeout.connect(_try_shoot.bind(muzzle_right, timer_right))
	# Conecta no HUD pra notificar quando levar hit (indicator off-screen).
	tower_attacked.connect(_notify_hud_attacked)


func _notify_hud_attacked(_tower: Node2D) -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("notify_tower_attacked"):
		hud.notify_tower_attacked(self)


func _try_shoot(muzzle: Marker2D, timer: Timer) -> void:
	var target: Node2D = _find_nearest_enemy()
	if target != null and arrow_scene != null:
		_fire_arrow(muzzle, target)
	timer.start(muzzle_cooldown)


func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var nearest_dist: float = detection_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var enemy: Node2D = e as Node2D
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest = enemy
			nearest_dist = dist
	return nearest


func _fire_arrow(muzzle: Marker2D, target: Node2D) -> void:
	var arrow := arrow_scene.instantiate()
	# Source ANTES de add_child pra arrow ignorar colisão com a própria torre.
	if "source" in arrow:
		arrow.source = self
	_get_world().add_child(arrow)
	arrow.global_position = muzzle.global_position
	if "damage" in arrow:
		arrow.damage = arrow.damage * damage_multiplier
	var target_pos: Vector2 = target.global_position + Vector2(0, -12)
	var dir: Vector2 = (target_pos - muzzle.global_position).normalized()
	if arrow.has_method("set_direction"):
		arrow.set_direction(dir)


func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
		hp_bar.visible = true
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	tower_attacked.emit(self)
	if hp <= 0.0:
		_destroy()


func _destroy() -> void:
	tower_destroyed.emit(self)
	# Desativa colisão e tiros durante a animação de destruição.
	var body := get_node_or_null("Body")
	if body != null:
		body.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)
	timer_left.stop()
	timer_right.stop()
	if hp_bar != null:
		hp_bar.visible = false
	# Múltiplas explosões espalhadas pra um efeito mais dramático.
	if kill_effect_scene != null:
		for i in 6:
			var fx := kill_effect_scene.instantiate()
			_get_world().add_child(fx)
			var off := Vector2(randf_range(-22.0, 22.0), randf_range(-65.0, -8.0))
			fx.global_position = global_position + off
			if fx is Node2D:
				(fx as Node2D).scale = Vector2.ONE * randf_range(0.7, 1.3)
	# Sprite e sombra desaparecem com fade + escala crescente.
	if sprite != null:
		var t := create_tween().set_parallel(true)
		t.tween_property(sprite, "modulate", Color(1.0, 0.5, 0.3, 0.0), 0.55)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		t.tween_property(sprite, "scale", sprite.scale * 1.35, 0.55)
	var shadow := get_node_or_null("Shadow")
	if shadow is CanvasItem:
		var ts := create_tween()
		ts.tween_property(shadow, "modulate:a", 0.0, 0.45)
	# Free após o efeito.
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)


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
	num.position = global_position + Vector2(0, -90)
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
