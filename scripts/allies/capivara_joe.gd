extends CharacterBody2D

# Capivara Joe (aliado pet, 4 níveis).
# Sem HP, NÃO é alvejada por inimigos. Vagueia em 75% do mapa interno.
# A cada drop_interval, para, toca anim "drop", e ao terminar spawna
# um cogumelo na posição. Volta a vaguear.
#
# L1: drop a cada 14s. Cogumelo só de buff (cura ou speed).
# L2: drop a cada 7s. Alterna buff/dano (purple) — o de dano explode
#     quando inimigo passa, AoE roxa 40 dmg em 5s.
# L3: cogumelo de buff dá AMBOS efeitos (cura + speed) + atk speed
#     +50% por 3s (resolvido em capivara_mushroom.gd lendo lvl).
# L4: 2 capivaras (gerenciado pelo player).

@export var speed: float = 50.0
@export var drop_interval: float = 14.0
@export var mushroom_scene: PackedScene
# Bounds do wander (75% do mapa interno). Capivara só anda dentro disso.
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
# Distância em que considera "chegou" no waypoint (sorteia outro).
@export var arrive_dist: float = 6.0
# Som tocado ao começar a anim de drop.
@export var drop_sound: AudioStream
@export var drop_sound_volume_db: float = -14.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _waypoint: Vector2 = Vector2.ZERO
var _drop_cd: float = 0.0
var _drop_counter: int = 0  # alterna buff/dano no L2+
var _is_dropping: bool = false


func _ready() -> void:
	add_to_group("ally")
	add_to_group("capivara_joe")
	sprite.animation_finished.connect(_on_anim_finished)
	_pick_new_waypoint()
	_drop_cd = drop_interval
	sprite.play("walk")


func _physics_process(delta: float) -> void:
	# Cooldown do drop.
	if _drop_cd > 0.0:
		_drop_cd = maxf(_drop_cd - delta, 0.0)
	# Durante a animação de drop fica parada.
	if _is_dropping:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Hora de dropar?
	if _drop_cd <= 0.0:
		_start_drop()
		return
	# Wander: vai pro waypoint atual.
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
	_waypoint = Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _start_drop() -> void:
	_is_dropping = true
	_play_drop_sound()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("drop"):
		sprite.play("drop")
	else:
		# Fallback (sprite sem anim drop): spawna direto.
		_finish_drop()


func _play_drop_sound() -> void:
	if drop_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = drop_sound
	p.volume_db = drop_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _on_anim_finished() -> void:
	if sprite.animation == "drop":
		_finish_drop()


func _finish_drop() -> void:
	_spawn_mushroom()
	_drop_counter += 1
	_drop_cd = drop_interval
	_is_dropping = false
	_pick_new_waypoint()
	sprite.play("walk")


func _spawn_mushroom() -> void:
	if mushroom_scene == null:
		return
	var mush: Node2D = mushroom_scene.instantiate()
	# L2+: alterna buff (par) e damage (ímpar).
	var lvl: int = _capivara_level()
	var is_damage: bool = lvl >= 2 and (_drop_counter % 2 == 1)
	if "is_damage_variant" in mush:
		mush.is_damage_variant = is_damage
	_get_world().add_child(mush)
	mush.global_position = global_position


func _capivara_level() -> int:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("get_upgrade_count"):
		return int(p.get_upgrade_count("capivara_joe"))
	return 1


func _get_world() -> Node:
	var w: Node = get_tree().get_first_node_in_group("world")
	if w == null:
		w = get_tree().current_scene
	return w
