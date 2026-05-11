extends Area2D

# Campo de fogo deixado pela skill direita do Fogo lv3. Aplica DPS a inimigos
# dentro da área por `duration` segundos, depois fade e some.

@export var damage_per_second: float = 12.0
@export var duration: float = 6.0
@export var fade_duration: float = 0.6
# Quando true, o campo veio de um inimigo (ex: fire mage do boss). Em vez de
# bater em "enemy", machuca player + tank_ally + structure (e ignora outros
# enemies, evitando friendly fire).
@export var is_enemy_source: bool = false
const TICK_INTERVAL: float = 0.5

var _enemies_inside: Array[Node] = []
var _life_remaining: float = 0.0
var _tick_accum: float = 0.0


func _ready() -> void:
	_life_remaining = duration
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Stagger das anims dos sprites filhos pra parecer caos de chamas (não sync).
	for child in get_children():
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).sprite_frames != null:
			var sp: AnimatedSprite2D = child
			var fc: int = sp.sprite_frames.get_frame_count("default")
			if fc > 1:
				sp.frame = randi() % fc
				sp.frame_progress = randf()
	# Captura bodies já sobrepostos no spawn (overlap inicial). Deferred pro
	# physics step ter populado get_overlapping_bodies — sem isso só pega quem
	# entra DEPOIS via body_entered, atrasando o primeiro hit.
	_capture_initial_overlaps.call_deferred()
	# Tick imediato no spawn (tick_accum = TICK_INTERVAL faz o primeiro
	# _apply_tick acontecer no próximo _process em vez de esperar 0.5s).
	_tick_accum = TICK_INTERVAL
	# Fade out nos últimos `fade_duration` segundos.
	var tw := create_tween()
	tw.tween_interval(duration - fade_duration)
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)


func _capture_initial_overlaps() -> void:
	for body in get_overlapping_bodies():
		_on_body_entered(body)


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
			var was_alive_ff: bool = (not ("hp" in enemy)) or float(enemy.hp) > 0.0
			enemy.take_damage(amount)
			if not is_enemy_source:
				_notify_player_dmg_kill(amount, "fire_skill", was_alive_ff, enemy)


func _on_body_entered(body: Node) -> void:
	# Filter por origem: skill do player → bate em "enemy"; skill do boss/inimigo
	# → bate em player/ally/structure.
	var hits: bool
	if is_enemy_source:
		hits = body.is_in_group("player") or body.is_in_group("tank_ally") or body.is_in_group("structure")
	else:
		hits = body.is_in_group("enemy")
	if hits and not body in _enemies_inside:
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
