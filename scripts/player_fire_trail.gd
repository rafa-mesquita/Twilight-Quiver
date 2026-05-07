extends Area2D

# Rastro passivo deixado pelo player no Fogo lv4. Visual: orbe de 3 círculos
# concêntricos (vermelho/laranja/branco) com PointLight2D de glow, semi-opaco
# e pulsando suavemente. Distintivo do rastro de flecha (chamas).

const LIFETIME: float = 2.0
const FADE_DURATION: float = 0.4
const TICK_INTERVAL: float = 0.5
const PULSE_PERIOD: float = 0.50
# Base 1.4x da animação por preferência visual + pulse suave em cima.
const PULSE_SCALE_MIN: Vector2 = Vector2(1.4, 1.4)
const PULSE_SCALE_MAX: Vector2 = Vector2(1.65, 1.65)

@export var damage_per_second: float = 3.0

var _enemies_inside: Array[Node] = []
var _life_remaining: float = LIFETIME
var _tick_accum: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Pulse: scale do orbe respira pra dar vida — fase random pra cada segmento
	# pulsar fora de sincronia (vários droppados juntos).
	var t: float = randf()
	scale = PULSE_SCALE_MIN.lerp(PULSE_SCALE_MAX, t)
	var pulse := create_tween().set_loops()
	pulse.tween_property(self, "scale", PULSE_SCALE_MAX, PULSE_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(self, "scale", PULSE_SCALE_MIN, PULSE_PERIOD)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Fade out final (modulate root começa em 0.78 da .tscn → desce pra 0).
	var fade := create_tween()
	fade.tween_interval(LIFETIME - FADE_DURATION)
	fade.tween_property(self, "modulate:a", 0.0, FADE_DURATION)


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
