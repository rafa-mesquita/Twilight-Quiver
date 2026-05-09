extends Area2D

# Projétil do Leno. Voa reto na direção setada por set_direction. Ao acertar
# um inimigo, dá dano single-target + spawna LenoSlowArea no chão (Area2D
# que aplica slow nos enemies que entram, lifetime fixo).

@export var damage: float = 20.0
@export var speed: float = 280.0
@export var lifetime: float = 2.0
@export var hit_sound: AudioStream
@export var hit_sound_volume_db: float = -20.0
@export var trail_max_points: int = 8
@export var hit_effect_scene: PackedScene

@onready var trail: Line2D = get_node_or_null("Trail")

var target: Node2D = null
var _direction: Vector2 = Vector2.RIGHT
var _t: float = 0.0
var _spent: bool = false

const SLOW_AREA_SCENE: PackedScene = preload("res://scenes/allies/leno_slow_area.tscn")


func _ready() -> void:
	body_entered.connect(_on_hit)
	# Se o leno chamou set_direction, _direction já tá setado. Senão fallback
	# pro target (caso de uso que não passa por set_direction).
	if _direction == Vector2.RIGHT and target != null and is_instance_valid(target):
		_direction = (target.global_position - global_position).normalized()
	rotation = _direction.angle()
	# Trail vazio aqui: global_position ainda é (0,0) durante add_child — o
	# leno seta a posição correta DEPOIS. Primeiro ponto entra no _physics_process.
	if trail != null:
		trail.clear_points()


func set_direction(dir: Vector2) -> void:
	if dir.length_squared() > 0.001:
		_direction = dir.normalized()
		rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	if _spent:
		return
	_t += delta
	if _t >= lifetime:
		_die_no_hit()
		return
	# Voo reto: direção/rotação travadas no spawn. Sem homing nem rotação
	# durante o voo (era o que dava efeito "girando").
	global_position += _direction * speed * delta
	# Trail: adiciona ponto na posição atual, trim quando passa do max.
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_hit(body: Node) -> void:
	if _spent:
		return
	if not body.is_in_group("enemy"):
		return
	_spent = true
	# Single-target damage no inimigo atingido.
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_play_hit_sound()
	_spawn_hit_effect()
	_spawn_slow_area()
	queue_free()


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx: Node2D = hit_effect_scene.instantiate()
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(fx)
	fx.global_position = global_position


func _play_hit_sound() -> void:
	if hit_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	# MP3 importado pode vir com loop=true por default — força stop manual via
	# Timer pra garantir que não fica em loop infinito.
	p.stream = hit_sound
	p.volume_db = hit_sound_volume_db
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(p)
	p.global_position = global_position
	# Pula os primeiros 0.5s do mp3 (intro silenciosa/abafada — delay perceptível
	# entre hit visual e som mesmo com 0.3s).
	p.play(0.5)
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(0.9).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _die_no_hit() -> void:
	# Lifetime esgotou sem acertar enemy — ainda spawna a área no ponto final.
	if _spent:
		return
	_spent = true
	_spawn_slow_area()
	queue_free()


func _spawn_slow_area() -> void:
	# Spawna 5 áreas: centro + 4 satélites (cima/baixo/esq/dir) formando uma cruz.
	# Offset = ~2x raio do círculo (12px) com leve overlap pra cobertura contínua.
	const SAT_OFFSET: float = 22.0
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	var offsets: Array[Vector2] = [
		Vector2.ZERO,
		Vector2(0, -SAT_OFFSET),
		Vector2(0, SAT_OFFSET),
		Vector2(-SAT_OFFSET, 0),
		Vector2(SAT_OFFSET, 0),
	]
	for off in offsets:
		var area: Node2D = SLOW_AREA_SCENE.instantiate()
		world.add_child(area)
		area.global_position = global_position + off
