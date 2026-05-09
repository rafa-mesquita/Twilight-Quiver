extends Area2D

# Área de slow do projétil do Leno (sprite no chão, tipo dash_trail).
# Aplica SlowDebuff em inimigos que entram, dura `lifetime` segundos.

@export var slow_factor: float = 0.50  # 50% slow
@export var lifetime: float = 7.0
@export var fade_duration: float = 0.4

var _life: float = 0.0


func _ready() -> void:
	_life = lifetime
	body_entered.connect(_on_body_entered)
	# Aplica slow nos inimigos JÁ dentro do raio no spawn (overlap inicial).
	for body in get_overlapping_bodies():
		_on_body_entered(body)
	# Fade nos últimos fade_duration segundos.
	var tw := create_tween()
	tw.tween_interval(maxf(lifetime - fade_duration, 0.0))
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("enemy"):
		return
	# CC immune: skip totalmente.
	if body.is_in_group("cc_immune"):
		return
	# Reaproveita SlowDebuff existente (refresh) ou cria novo. CurseDebuff
	# já dá slow + DoT, então não conflita — pula.
	for c in body.get_children():
		if c is SlowDebuff:
			(c as SlowDebuff).refresh(_life, slow_factor)
			return
		if c is CurseDebuff:
			return
	var deb := SlowDebuff.new()
	deb.duration = _life
	deb.slow_factor = slow_factor
	body.add_child(deb)
