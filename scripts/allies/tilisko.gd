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
const SPRITE_BASE_OFFSET_Y: float = -16.0
const MUZZLE_BASE_OFFSET_Y: float = -8.0
const BOB_HEIGHT: float = 2.0
const BOB_SPEED: float = 3.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var _player: Node2D = null
var _is_shooting: bool = false
var _bob_t: float = 0.0


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
	_bob_t += delta
	var bob: float = sin(_bob_t * BOB_SPEED) * BOB_HEIGHT
	sprite.offset.y = SPRITE_BASE_OFFSET_Y + bob
	muzzle.position.y = MUZZLE_BASE_OFFSET_Y + bob
	# Posição de formação ao redor do player (órbita por phase_offset).
	var t: float = _bob_t * 0.6 + phase_offset
	var orbit_r: float = (follow_min_distance + follow_max_distance) * 0.5
	var desired: Vector2 = _player.global_position + Vector2(cos(t), sin(t) * 0.6) * orbit_r
	var to_desired: Vector2 = desired - global_position
	var sep: Vector2 = _separation()
	velocity = to_desired * 2.2 + sep
	move_and_slide()
	# Flip pro lado do movimento.
	if absf(velocity.x) > 4.0:
		sprite.flip_h = velocity.x < 0.0
		muzzle.position.x = -absf(muzzle.position.x) if sprite.flip_h else absf(muzzle.position.x)
	# Anim: shooting > walk > idle.
	if not _is_shooting:
		if velocity.length() > 12.0:
			if sprite.animation != &"walk":
				sprite.play("walk")
		elif sprite.animation != &"idle":
			sprite.play("idle")


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


# Chamado pelo player no _release_arrow: toca a anim de tiro (o spawn da flecha é
# feito pelo player a partir de get_muzzle_pos()).
func on_player_shot() -> void:
	_is_shooting = true
	sprite.play("atirar")


func get_muzzle_pos() -> Vector2:
	return muzzle.global_position


func _on_anim_finished() -> void:
	if sprite.animation == &"atirar":
		_is_shooting = false
		sprite.play("idle")
