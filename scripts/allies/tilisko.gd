extends CharacterBody2D

# Pet pinguim arqueiro. Sem HP, não-alvo (enemies ignoram; flechas do player passam).
# NÃO atira sozinho: o player.gd dispara a flecha dele no _release_arrow e chama
# on_player_shot() pra tocar a anim. Aqui só tem follow/voo/anim + muzzle.

@export var speed: float = 38.0
@export var follow_min_distance: float = 22.0
@export var follow_max_distance: float = 40.0
@export var phase_offset: float = 0.0
@export var separation_radius: float = 18.0
@export var separation_strength: float = 30.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var _player: Node2D = null
var _is_shooting: bool = false
# Wander: vagueia numa área perto do player (não gruda); idle entre os pontos. Se o
# player se afasta, re-pega alvo perto dele + acelera (catch-up) pra nunca ficar longe.
const WANDER_RADIUS: float = 56.0
const WANDER_PAUSE_MIN: float = 0.5
const WANDER_PAUSE_MAX: float = 1.4
const WANDER_ARRIVE_DIST: float = 6.0
var _wander_target: Vector2 = Vector2.ZERO
var _has_target: bool = false
var _wander_pause: float = 0.0


func _ready() -> void:
	add_to_group("ally")
	add_to_group("tilisko")
	_player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player == null:
			return
	# Durante o tiro: para no lugar (a anim "atirar" roda; o flip já foi pro lado do tiro).
	if _is_shooting:
		velocity = velocity.lerp(Vector2.ZERO, 0.3)
		move_and_slide()
		return
	var dist_player: float = global_position.distance_to(_player.global_position)
	# Pausa entre pontos do wander → fica parado (idle).
	if _wander_pause > 0.0:
		_wander_pause -= delta
		velocity = velocity.lerp(Vector2.ZERO, 0.3)
		move_and_slide()
		_apply_move_anim()
		return
	# Re-pega um alvo perto do player se não tem ou se o player se afastou da área.
	if not _has_target or _player.global_position.distance_to(_wander_target) > WANDER_RADIUS:
		_pick_wander_target()
	var to_t: Vector2 = _wander_target - global_position
	if to_t.length() < WANDER_ARRIVE_DIST:
		# Chegou → idle por um tempinho, depois escolhe outro ponto.
		_has_target = false
		_wander_pause = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
		velocity = velocity.lerp(Vector2.ZERO, 0.4)
		move_and_slide()
		_apply_move_anim()
		return
	# Catch-up: quanto mais longe do player, mais rápido — nunca fica longe demais.
	var sp: float = speed * (1.0 + clampf((dist_player - WANDER_RADIUS) / WANDER_RADIUS, 0.0, 2.0))
	velocity = to_t.normalized() * sp + _separation()
	move_and_slide()
	_apply_move_anim()


func _apply_move_anim() -> void:
	if absf(velocity.x) > 4.0:
		sprite.flip_h = velocity.x < 0.0
		muzzle.position.x = -absf(muzzle.position.x) if sprite.flip_h else absf(muzzle.position.x)
	if velocity.length() > 10.0:
		if sprite.animation != &"walk":
			sprite.play("walk")
	elif sprite.animation != &"idle":
		sprite.play("idle")


func _pick_wander_target() -> void:
	var ang: float = randf() * TAU
	var dist: float = randf_range(WANDER_RADIUS * 0.25, WANDER_RADIUS * 0.95)
	_wander_target = _player.global_position + Vector2(cos(ang), sin(ang) * 0.7) * dist
	_has_target = true


func _separation() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("tilisko"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		var d: Vector2 = global_position - (other as Node2D).global_position
		var dist: float = d.length()
		if dist > 0.01 and dist < separation_radius:
			force += d.normalized() * (separation_radius - dist) / separation_radius * separation_strength
	return force


# Chamado pelo player no _release_arrow com a direção do tiro: vira pro lado do tiro
# (senão a flecha sai de costas) e toca a anim. O spawn da flecha é feito pelo player.
func on_player_shot(dir: Vector2) -> void:
	_is_shooting = true
	if absf(dir.x) > 0.01:
		sprite.flip_h = dir.x < 0.0
		muzzle.position.x = -absf(muzzle.position.x) if sprite.flip_h else absf(muzzle.position.x)
	sprite.play("atirar")


func get_muzzle_pos() -> Vector2:
	return muzzle.global_position


func _on_anim_finished() -> void:
	if sprite.animation == &"atirar":
		_is_shooting = false
		sprite.play("idle")
