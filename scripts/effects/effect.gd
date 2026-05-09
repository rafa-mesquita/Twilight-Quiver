extends AnimatedSprite2D

@export var frame_alphas: PackedFloat32Array


func _ready() -> void:
	animation_finished.connect(queue_free)
	frame_changed.connect(_apply_frame_alpha)
	_apply_frame_alpha()
	play()


func _apply_frame_alpha() -> void:
	if frame_alphas.is_empty():
		return
	if frame >= 0 and frame < frame_alphas.size():
		modulate.a = frame_alphas[frame]
