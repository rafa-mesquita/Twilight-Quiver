extends CharacterBody2D

# Mecânico Ting (esquilo aliado, 4 níveis). Vagueia pelo mapa, periodicamente
# para num spot estratégico e constroi uma torreta que atira nos inimigos.
# Sem HP, não-targetável.
#
# L1: 1 ting, deploy a cada 15s, torreta dura 8s, atira a cada 2s
# L2: torreta dá 10% AoE secundário e dura 9s
# L3: deploy a cada 13s, atk cd da torreta 1.7s
# L4: 2 tings (gerenciado pelo player)

@export var speed: float = 50.0
# Intervalo entre deploys de torreta. Player sobrescreve por nível.
@export var deploy_interval: float = 15.0
# Lifetime/atk_cd/aoe da próxima torreta — player sobrescreve por nível.
@export var turret_lifetime: float = 8.0
@export var turret_attack_cooldown: float = 2.0
@export var turret_aoe_pct: float = 0.0
@export var turret_scene: PackedScene
# Mesmo retângulo da Capivara — limite de wander dentro do mapa interno.
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _waypoint: Vector2 = Vector2.ZERO
var _deploy_cd: float = 0.0
var _is_building: bool = false


func _ready() -> void:
	add_to_group("ally")
	add_to_group("ting")
	sprite.animation_finished.connect(_on_anim_finished)
	_pick_new_waypoint()
	_deploy_cd = deploy_interval
	sprite.play("walk")


func _physics_process(delta: float) -> void:
	if _deploy_cd > 0.0:
		_deploy_cd = maxf(_deploy_cd - delta, 0.0)
	# Durante "build" o ting fica parado.
	if _is_building:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Hora de construir a torreta?
	if _deploy_cd <= 0.0:
		_start_build()
		return
	# Wander pro waypoint.
	var to_wp: Vector2 = _waypoint - global_position
	var dist: float = to_wp.length()
	if dist <= arrive_dist:
		_pick_new_waypoint()
		to_wp = _waypoint - global_position
		dist = to_wp.length()
	var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_wp / dist
	velocity = dir * speed
	move_and_slide()
	if absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0
	if sprite.animation != "walk":
		sprite.play("walk")


func _pick_new_waypoint() -> void:
	# Spot "estratégico": ponto médio dos 3 enemies mais próximos do ting.
	# Sem enemies por perto, sorteia ponto random dentro do wander_bounds.
	var spot: Vector2 = _find_strategic_spot()
	if spot.x == INF:
		spot = Vector2(
			randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
			randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
		)
	_waypoint = _clamp_to_bounds(spot)


func _find_strategic_spot() -> Vector2:
	var enemies: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node2D and not e.is_queued_for_deletion():
			enemies.append(e)
	if enemies.is_empty():
		return Vector2(INF, INF)
	enemies.sort_custom(func(a: Node2D, b: Node2D) -> bool:
		return a.global_position.distance_to(global_position) < b.global_position.distance_to(global_position)
	)
	var sum: Vector2 = Vector2.ZERO
	var n: int = mini(3, enemies.size())
	for i in n:
		sum += enemies[i].global_position
	return sum / float(n)


func _clamp_to_bounds(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		clampf(p.y, wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _start_build() -> void:
	_is_building = true
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("build"):
		sprite.play("build")
	else:
		_finish_build()


func _on_anim_finished() -> void:
	if sprite.animation == "build":
		_finish_build()


func _finish_build() -> void:
	_spawn_turret()
	_deploy_cd = deploy_interval
	_is_building = false
	_pick_new_waypoint()
	sprite.play("walk")


func _spawn_turret() -> void:
	if turret_scene == null:
		return
	var t: Node2D = turret_scene.instantiate()
	if "lifetime" in t:
		t.lifetime = turret_lifetime
	if "attack_cooldown_base" in t:
		t.attack_cooldown_base = turret_attack_cooldown
	if "aoe_damage_pct" in t:
		t.aoe_damage_pct = turret_aoe_pct
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(t)
	t.global_position = global_position
