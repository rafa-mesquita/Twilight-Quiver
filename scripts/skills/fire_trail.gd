extends Area2D

# Segmento do rastro de fogo deixado pela flecha (lv2 do elemental Fogo).
# Cada segmento dá DPS em inimigos que passem na área. Lifetime curto (2s, per
# excalidraw spec) com fade no fim.

const LIFETIME: float = 2.0
const FADE_DURATION: float = 0.4
const TICK_INTERVAL: float = 0.5

@export var damage_per_second: float = 4.0

var _enemies_inside: Array[Node] = []
var _life_remaining: float = LIFETIME
var _tick_accum: float = 0.0


const ORANGE_PULSE_NORMAL: Color = Color(1.0, 1.0, 1.0, 1.0)
const ORANGE_PULSE_TINT: Color = Color(1.25, 0.75, 0.45, 1.0)
const ORANGE_PULSE_PERIOD: float = 0.55


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	var sprite := get_node_or_null("Sprite") as AnimatedSprite2D
	# Stagger: cada segmento começa num frame aleatório pra não pulsarem todos
	# em sync (a flecha dropa vários segmentos no mesmo physics frame).
	if sprite != null and sprite.sprite_frames != null:
		var frame_count: int = sprite.sprite_frames.get_frame_count("default")
		if frame_count > 1:
			sprite.frame = randi() % frame_count
			sprite.frame_progress = randf()
	# Filtro laranja piscando suavemente no sprite (loop infinito até queue_free).
	# Stagger inicial via offset random pra cada segmento pulsar fora de fase.
	if sprite != null:
		sprite.modulate = ORANGE_PULSE_NORMAL.lerp(ORANGE_PULSE_TINT, randf())
		var pulse := sprite.create_tween().set_loops()
		pulse.tween_property(sprite, "modulate", ORANGE_PULSE_TINT, ORANGE_PULSE_PERIOD)
		pulse.tween_property(sprite, "modulate", ORANGE_PULSE_NORMAL, ORANGE_PULSE_PERIOD)
	# Fade out nos últimos FADE_DURATION segundos. Modulate root começa em 0.85
	# (definido na .tscn) e desce pra 0 no fim — preserva a opacidade base.
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
	var amount: float = damage_per_second * TICK_INTERVAL
	for enemy in _enemies_inside.duplicate():
		if not is_instance_valid(enemy):
			_enemies_inside.erase(enemy)
			continue
		if enemy.has_method("take_damage"):
			var was_alive_ft: bool = (not ("hp" in enemy)) or float(enemy.hp) > 0.0
			enemy.take_damage(amount)
			_notify_player_dmg_kill(amount, "fire_arrow", was_alive_ft, enemy)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and not body in _enemies_inside:
		_enemies_inside.append(body)


func _on_body_exited(body: Node) -> void:
	_enemies_inside.erase(body)


func _notify_player_dmg_kill(amount: float, source_id: String, was_alive: bool, target: Node) -> void:
	if not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("notify_damage_dealt_by_source"):
		p.notify_damage_dealt_by_source(amount, source_id)
	if was_alive and p.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			p.notify_kill_by_source(source_id)
