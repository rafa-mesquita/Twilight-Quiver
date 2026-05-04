extends Area2D

@export var faded_alpha: float = 0.5
@export var fade_duration: float = 0.15

var entities_inside: int = 0
var current_tween: Tween


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(_body: Node) -> void:
	entities_inside += 1
	if entities_inside == 1:
		_set_alpha(faded_alpha)


func _on_body_exited(_body: Node) -> void:
	entities_inside = maxi(entities_inside - 1, 0)
	if entities_inside == 0:
		_set_alpha(1.0)


func _set_alpha(target: float) -> void:
	var parent := get_parent() as CanvasItem
	if parent == null:
		return
	if current_tween != null and current_tween.is_valid():
		current_tween.kill()
	current_tween = create_tween()
	current_tween.tween_property(parent, "modulate:a", target, fade_duration)
