extends Area2D

# Projétil da torreta do Mecânico Ting. Reaproveita o visual do mage projetil
# mas com lógica ally-source (ignora player/aliados/estruturas, hita enemy) +
# curva homing pro inimigo travado. L2+: dano AoE secundário no impacto.

@export var speed: float = 175.0
@export var lifetime: float = 2.2
@export var damage: float = 25.0
# AoE secundário (lv2+): aoe_damage_pct > 0 ativa explosão no impacto que dá
# damage * aoe_damage_pct nos enemies dentro de aoe_radius (exceto o atingido).
@export var aoe_radius: float = 0.0
@export var aoe_damage_pct: float = 0.0
@export var hit_effect_scene: PackedScene

const VISUAL_OFFSET: Vector2 = Vector2(0, -24)
const ENEMY_AIM_OFFSET: Vector2 = Vector2(0, -12)
const REDIRECT_HALFWAY: float = 0.55
const REDIRECT_FINAL: float = 0.95
const REDIRECT_FINAL_DISTANCE: float = 8.0
const TRAIL_MAX_POINTS: int = 14

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var trail: Line2D = get_node_or_null("Trail")
@onready var shoot_sound: AudioStreamPlayer2D = get_node_or_null("ShootSound")

var direction: Vector2 = Vector2.RIGHT
var target_enemy: Node2D = null
# Referência do player setada pelo turret pra notificar damage/kill por source
# ("ting_turret") — telemetria de fonte de dano.
var source: Node = null
var _spawn_position: Vector2 = Vector2.ZERO
var _halfway_distance: float = -1.0
var _has_redirected_halfway: bool = false
var _has_redirected_final: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_die)
	if shoot_sound != null:
		shoot_sound.play()
		var ref: AudioStreamPlayer2D = shoot_sound
		get_tree().create_timer(2.0).timeout.connect(func() -> void:
			if is_instance_valid(ref):
				ref.stop()
		)


func set_target(enemy: Node2D, dir: Vector2) -> void:
	target_enemy = enemy
	direction = dir.normalized()
	_spawn_position = global_position
	if enemy != null and is_instance_valid(enemy):
		var t: Vector2 = enemy.global_position + ENEMY_AIM_OFFSET
		_halfway_distance = _spawn_position.distance_to(t) * 0.5
	if sprite != null:
		sprite.rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position + VISUAL_OFFSET)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if not _has_redirected_halfway and _halfway_distance > 0.0:
		if _spawn_position.distance_to(global_position) >= _halfway_distance:
			_has_redirected_halfway = true
			_redirect_toward_target(REDIRECT_HALFWAY)
	if not _has_redirected_final and target_enemy != null and is_instance_valid(target_enemy):
		var t: Vector2 = target_enemy.global_position + ENEMY_AIM_OFFSET
		if global_position.distance_to(t) <= REDIRECT_FINAL_DISTANCE:
			_has_redirected_final = true
			_redirect_toward_target(REDIRECT_FINAL)
	if trail != null:
		trail.add_point(global_position + VISUAL_OFFSET)
		while trail.get_point_count() > TRAIL_MAX_POINTS:
			trail.remove_point(0)


func _redirect_toward_target(strength: float) -> void:
	if target_enemy == null or not is_instance_valid(target_enemy):
		return
	var t: Vector2 = target_enemy.global_position + ENEMY_AIM_OFFSET
	var to_t: Vector2 = (t - global_position).normalized()
	direction = direction.lerp(to_t, strength).normalized()
	if sprite != null:
		sprite.rotation = direction.angle()


func _on_body_entered(body: Node) -> void:
	# Ally-source: ignora player/ally/structure; só conta enemy.
	if not body.is_in_group("enemy"):
		return
	if body.is_queued_for_deletion():
		return
	var damageable: Node = _find_damageable(body)
	if damageable == null:
		return
	_hit_primary(damageable)
	_spawn_hit_effect()
	_die()


func _hit_primary(target: Node) -> void:
	if not target.has_method("take_damage"):
		return
	var was_alive: bool = (not ("hp" in target)) or float(target.hp) > 0.0
	target.take_damage(damage)
	_notify_player(damage, was_alive, target)
	if aoe_radius > 0.0 and aoe_damage_pct > 0.0:
		_apply_aoe(target)


func _apply_aoe(skip: Node) -> void:
	var splash: float = damage * aoe_damage_pct
	if splash <= 0.0:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == skip or not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		if (e as Node2D).global_position.distance_to(global_position) > aoe_radius:
			continue
		if not e.has_method("take_damage"):
			continue
		var was_alive: bool = (not ("hp" in e)) or float(e.hp) > 0.0
		e.take_damage(splash)
		_notify_player(splash, was_alive, e)


func _notify_player(amount: float, was_alive: bool, target: Node) -> void:
	if source == null:
		return
	if source.has_method("notify_damage_dealt"):
		source.notify_damage_dealt(amount)
	if source.has_method("notify_damage_dealt_by_source"):
		source.notify_damage_dealt_by_source(amount, "ting_turret")
	if was_alive and source.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			source.notify_kill_by_source("ting_turret")


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.has_method("take_damage"):
			return n
		n = n.get_parent()
	return null


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx: Node2D = hit_effect_scene.instantiate()
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(fx)
	fx.global_position = global_position + VISUAL_OFFSET


func _die() -> void:
	if is_inside_tree():
		queue_free()
