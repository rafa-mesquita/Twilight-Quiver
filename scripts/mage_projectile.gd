extends Area2D

@export var speed: float = 110.0
@export var lifetime: float = 2.5
@export var damage: float = 15.0
@export var trail_max_points: int = 14

@onready var trail: Line2D = get_node_or_null("Trail")

var direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_die)


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_body_entered(body: Node) -> void:
	# Player: dá dano. Qualquer outro corpo (parede/objeto): só some.
	if body.has_method("take_damage"):
		body.take_damage(damage)
	_die()


func _die() -> void:
	if is_inside_tree():
		queue_free()
