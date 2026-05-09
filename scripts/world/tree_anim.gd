extends Node2D

# Embaralha o frame inicial e a velocidade pra cada árvore animar
# em momentos diferentes, dando aparência natural à floresta.

@export var randomize_frame: bool = true
@export var randomize_speed: bool = false
@export var speed_min: float = 0.85
@export var speed_max: float = 1.15


func _ready() -> void:
	var trunk: AnimatedSprite2D = get_node_or_null("Trunk")
	var canopy: AnimatedSprite2D = get_node_or_null("Canopy")

	if randomize_frame:
		var f: int = randi_range(0, 3)
		if trunk != null:
			trunk.frame = f
		if canopy != null:
			canopy.frame = f

	if randomize_speed:
		var s: float = randf_range(speed_min, speed_max)
		if trunk != null:
			trunk.speed_scale = s
		if canopy != null:
			canopy.speed_scale = s
