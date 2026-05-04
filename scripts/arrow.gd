extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: float = 25.0
@export var trail_max_points: int = 10
@export var hit_effect_scene: PackedScene
@export var stick_surface_duration: float = 7.5
@export var stick_enemy_duration: float = 2.0
@export var fade_duration: float = 0.5
@export var stick_pullback: float = 5.0
@export var impact_sound: AudioStream
@export var object_impact_sound: AudioStream
@export var sound_volume_db: float = -12.0
@export var knockback_strength: float = 80.0

@onready var trail: Line2D = get_node_or_null("Trail")
@onready var shoot_sound: AudioStreamPlayer2D = get_node_or_null("ShootSound")

var direction: Vector2 = Vector2.RIGHT
var is_stuck: bool = false


func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_hit)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)
	# Defer pra detachar/tocar o som DEPOIS do spawner setar a posição da flecha.
	if shoot_sound != null:
		_setup_shoot_sound.call_deferred()


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)


func _physics_process(delta: float) -> void:
	if is_stuck:
		return
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_hit(body: Node) -> void:
	if is_stuck:
		return
	if body.has_method("take_damage"):
		# Inimigo: dá dano e crava NO corpo (segue o movimento) por stick_enemy_duration.
		body.take_damage(damage)
		# Empurra o corpo na direção que a flecha estava indo.
		if body.has_method("apply_knockback"):
			body.apply_knockback(direction, knockback_strength)
		_play_oneshot(impact_sound, global_position, sound_volume_db, 0.7)
		_stick_in_body(body, stick_enemy_duration)
	else:
		# Superfície sólida (parede, tronco): crava no lugar por stick_surface_duration.
		_play_oneshot(object_impact_sound, global_position, sound_volume_db, 0.7)
		_stick_in_place(stick_surface_duration)


func _stick_in_place(visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	# Z-index direcional: se a flecha voava p/ sul (bateu na parede NORTE do objeto),
	# fica atrás. Se voava p/ norte ou lateral (bateu na parede sul/leste/oeste),
	# fica na frente do objeto. Threshold 0.5 = mais de ~30° de inclinação sul.
	if direction.y > 0.5:
		pass  # mantém z_index = -1 do voo (atrás)
	else:
		z_index = 1  # na frente
	# Recua na direção oposta ao movimento pra:
	# 1. A flecha ficar "encostada" na superfície em vez de enterrada
	# 2. Garantir que arrow.y fique consistentemente do lado certo do alvo pro y-sort
	position -= direction * stick_pullback
	_schedule_fade_out(visible_duration)


func _stick_in_body(body: Node, visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	z_index = 1
	# Defer reparent pra evitar mexer na árvore de cenas durante callback de física.
	_reparent_to.call_deferred(body)
	_schedule_fade_out(visible_duration)


func _begin_stick() -> void:
	is_stuck = true
	set_deferred("monitoring", false)
	if trail != null:
		trail.clear_points()


func _reparent_to(new_parent: Node) -> void:
	if not is_inside_tree() or not is_instance_valid(new_parent) or not new_parent.is_inside_tree():
		return
	var gp := global_position
	var gr := global_rotation
	var current_parent := get_parent()
	if current_parent != null:
		current_parent.remove_child(self)
	new_parent.add_child(self)
	global_position = gp
	global_rotation = gr


func _schedule_fade_out(visible_duration: float) -> void:
	var t := create_tween()
	t.tween_interval(visible_duration)
	t.tween_property(self, "modulate:a", 0.0, fade_duration)
	t.tween_callback(_die)


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_lifetime_expired() -> void:
	# Se já cravou, ignora — o stick timer cuida da remoção.
	if not is_stuck:
		_die()


func _die() -> void:
	if is_inside_tree():
		queue_free()


func _setup_shoot_sound() -> void:
	if shoot_sound == null or not is_instance_valid(shoot_sound):
		return
	if shoot_sound.get_parent() != self:
		return  # já foi detachado
	# Salva posição (já setada pelo spawner agora) e detacha pro World.
	var sound_global_pos: Vector2 = shoot_sound.global_position
	remove_child(shoot_sound)
	_get_world().add_child(shoot_sound)
	shoot_sound.global_position = sound_global_pos
	shoot_sound.volume_db = sound_volume_db
	shoot_sound.play()
	# Lambda captura o ref direto — sobrevive mesmo se a flecha for liberada cedo
	# (ex: inimigo morre e a flecha some como filha dele antes dos 0.7s).
	var sound_ref: AudioStreamPlayer2D = shoot_sound
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(sound_ref):
			sound_ref.stop()
			sound_ref.queue_free()
	)


func _play_oneshot(stream: AudioStream, pos: Vector2, vol_db: float, max_duration: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = vol_db
	_get_world().add_child(player)
	player.global_position = pos
	player.play()
	if max_duration > 0.0:
		var ref: AudioStreamPlayer2D = player
		get_tree().create_timer(max_duration).timeout.connect(func() -> void:
			if is_instance_valid(ref):
				ref.stop()
				ref.queue_free()
		)
