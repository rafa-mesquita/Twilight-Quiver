extends Node2D

@export var rise_distance: float = 12.0
@export var duration: float = 0.6
@export var horizontal_jitter: float = 4.0

var amount: int = 0
var start_y: float = 0.0
var elapsed: float = 0.0


func _ready() -> void:
	$Label.text = str(amount)
	position.x += randf_range(-horizontal_jitter, horizontal_jitter)
	start_y = position.y


func _process(delta: float) -> void:
	elapsed += delta
	var t := clampf(elapsed / duration, 0.0, 1.0)
	# Ease-out quad pra subir rápido e desacelerar.
	var ease_t := 1.0 - (1.0 - t) * (1.0 - t)
	position.y = start_y - rise_distance * ease_t
	# Fade quadrático: começa visível e some no fim.
	modulate.a = 1.0 - t * t
	if elapsed >= duration:
		queue_free()
