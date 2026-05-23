extends Area2D

# Projétil ranged da Duskrose. Lançado em leques de 3 (centro + ±angle_spread).
# Voa em linha reta, dano único no impacto com player. Ignora aliados/inimigos
# (filtragem em _on_body_entered) — só ameaça o player.
# Visual: sprite animado + glow rosa aditivo + rastro Line2D suave seguindo o
# trajeto (top_level pra ficar no espaço do mundo, não rotacionando junto).

@export var speed: float = 180.0
@export var lifetime: float = 3.5
@export var damage: float = 16.0
@export var damage_mult: float = 1.0
@export var source_id: String = "duskrose_projectile"
@export var trail_max_points: int = 16
@export var hit_sound_volume_db: float = -8.0

# Som de impacto quando o projétil acerta o player — reusa o asset do melee
# strike pra dar feedback consistente entre os 2 ataques da boss (dash + proj).
const HIT_SOUND_PATH: String = "res://assets/enemies/duskrose/melee atack sound.mp3"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var glow: Sprite2D = $Glow
@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var trail: Line2D = $Trail

var direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	add_to_group("duskrose_decoration")
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_die)
	if sprite != null:
		sprite.rotation = direction.angle()
		sprite.play("default")
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)


func set_direction(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	direction = dir.normalized()
	if sprite != null:
		sprite.rotation = direction.angle()


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_body_entered(body: Node) -> void:
	# Ignora qualquer coisa que não seja o player (inimigos, aliados, estruturas).
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage * damage_mult, source_id)
	# Som de impacto no ponto do hit — soma ao damage_audio do próprio player
	# pra ficar bem claro que o golpe conectou.
	_play_hit_sound()
	_die()


func _play_hit_sound() -> void:
	var sound: AudioStream = load(HIT_SOUND_PATH) as AudioStream
	if sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = sound
	p.volume_db = hit_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.08)
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(p)
	p.global_position = global_position
	p.play()
	p.finished.connect(p.queue_free)


func _die() -> void:
	if is_inside_tree():
		queue_free()
