class_name SlowDebuff
extends Node

# Slow puro aplicado em inimigos (Chuva de Coins L3: pulso amarelo ao coletar
# moeda aplica slow em área). Diferente do CurseDebuff: não causa DoT, só
# multiplica o `speed` do inimigo durante a duração.

@export var duration: float = 3.0
@export var slow_factor: float = 0.55  # 0.55 = 45% slow

var _remaining: float = 0.0
var _original_speed: float = -1.0


func _ready() -> void:
	_remaining = duration
	_apply_slow()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_restore_speed()
		queue_free()


func _apply_slow() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if not ("speed" in parent):
		return
	if _original_speed < 0.0:
		_original_speed = parent.speed
	parent.speed = _original_speed * slow_factor


func _restore_speed() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if "speed" in parent and _original_speed >= 0.0:
		parent.speed = _original_speed


# Re-aplicação: estende duração e mantém slow mais forte.
func refresh(new_duration: float, new_slow_factor: float) -> void:
	_remaining = maxf(_remaining, new_duration)
	if new_slow_factor < slow_factor:
		slow_factor = new_slow_factor
		_apply_slow()
