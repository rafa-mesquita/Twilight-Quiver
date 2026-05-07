extends Area2D

# Segmento do "Rastro de Poder" deixado pelo dash. Cada segmento é um Area2D
# roxo com colisão que aplica DPS em inimigos dentro.
# - Lifetime: 3s, fade nos últimos 0.5s
# - DPS aplica a cada `TICK_INTERVAL` (não literalmente "por segundo" mas
#   aproximado — total damage = damage_per_second * 3.0 over lifetime)

const LIFETIME: float = 3.0
const FADE_DURATION: float = 0.5
const TICK_INTERVAL: float = 0.5  # 2 ticks por segundo

@export var damage_per_second: float = 8.0

var _enemies_inside: Array[Node] = []
var _life_remaining: float = LIFETIME
var _tick_accum: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Stagger: cada segmento começa num frame aleatório pra não pulsarem todos
	# em sync (o dash dropa vários segmentos no mesmo physics frame).
	var sprite := get_node_or_null("Sprite") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null:
		var frame_count: int = sprite.sprite_frames.get_frame_count("default")
		if frame_count > 1:
			sprite.frame = randi() % frame_count
			sprite.frame_progress = randf()
	# Fade out nos últimos FADE_DURATION segundos.
	var tw := create_tween()
	tw.tween_interval(LIFETIME - FADE_DURATION)
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)


func _process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		queue_free()
		return
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick()


func _apply_tick() -> void:
	# DPS escalado pra fração do segundo coberta pelo tick.
	var amount: float = damage_per_second * TICK_INTERVAL
	for enemy in _enemies_inside.duplicate():
		if not is_instance_valid(enemy):
			_enemies_inside.erase(enemy)
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(amount)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not body in _enemies_inside:
		_enemies_inside.append(body)


func _on_body_exited(body: Node) -> void:
	_enemies_inside.erase(body)
