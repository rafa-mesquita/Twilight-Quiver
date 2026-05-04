extends Node2D

@export var trail_delay: float = 0.35
@export var trail_speed: float = 5.0
@export var fg_color: Color = Color(0.463, 0.655, 0.298, 1)

@onready var fg: Polygon2D = $Fg
@onready var trail: Polygon2D = $Trail

var current_ratio: float = 1.0
var trail_ratio: float = 1.0
var trail_timer: float = 0.0


func _ready() -> void:
	fg.color = fg_color
	fg.scale.x = current_ratio
	trail.scale.x = trail_ratio


func set_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio < current_ratio:
		# Tomou dano — trail mantém o valor anterior e segura por trail_delay antes de cair.
		trail_timer = trail_delay
	else:
		# Curou (ou set inicial maior) — trail acompanha imediatamente.
		trail_ratio = ratio
	current_ratio = ratio
	fg.scale.x = current_ratio
	trail.scale.x = trail_ratio


func _process(delta: float) -> void:
	if trail_ratio > current_ratio:
		if trail_timer > 0.0:
			trail_timer -= delta
			return
		# Exponential decay: framerate-independent ease-out, naturalmente smooth.
		trail_ratio = lerp(trail_ratio, current_ratio, 1.0 - exp(-trail_speed * delta))
		if absf(trail_ratio - current_ratio) < 0.002:
			trail_ratio = current_ratio
		trail.scale.x = trail_ratio
