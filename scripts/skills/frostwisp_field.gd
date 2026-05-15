extends Area2D

# Campo de gelo deixado pela Frostwisp durante o cast (L3 do Fica Frio).
# Padrão visual do FireField (área circular do Q do Fogo), mas com os tiles
# de gelo do L2 (IceSlowArea). Aplica DPS + slow contínuo nos inimigos dentro.
# Projeteis da Frostwisp caem DENTRO desse campo durante a duração.

@export var damage_per_second: float = 8.0
@export var slow_factor: float = 0.63  # 0.63 = 37% slow (igual L2)
@export var duration: float = 5.0
@export var fade_duration: float = 0.6
# Raio levemente maior que a extent dos tiles visíveis (~48px diagonal) pra
# garantir que TODO inimigo visualmente sobre o campo receba o tick.
@export var radius: float = 52.0
const TICK_INTERVAL: float = 0.5
# Slow refresh duration curta — re-aplicada por frame nos overlapping enquanto
# o body estiver dentro. Sai da área → slow expira em ~0.15s.
const SLOW_REFRESH: float = 0.15

const TILE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/ice mage slow area.png")
const TILE_SIZE: float = 16.0
# Layout de tiles em diamante denso ~44 raio (cobre o circulo da damage zone).
const TILE_OFFSETS: Array[Vector2] = [
	Vector2(0, -40),
	Vector2(-16, -24), Vector2(0, -24), Vector2(16, -24),
	Vector2(-32, -8), Vector2(-16, -8), Vector2(0, -8), Vector2(16, -8), Vector2(32, -8),
	Vector2(-40, 8), Vector2(-24, 8), Vector2(-8, 8), Vector2(8, 8), Vector2(24, 8), Vector2(40, 8),
	Vector2(-32, 24), Vector2(-16, 24), Vector2(0, 24), Vector2(16, 24), Vector2(32, 24),
	Vector2(-16, 40), Vector2(0, 40), Vector2(16, 40),
]

var _enemies_inside: Array[Node] = []
var _life_remaining: float = 0.0
var _tick_accum: float = 0.0


func _ready() -> void:
	# freeze_immune — durante o L4 o campo continua tickando dano nos congelados.
	add_to_group("freeze_immune")
	_life_remaining = duration
	_build_visual_tiles()
	_build_collision_shape()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Captura inimigos já sobrepostos no spawn.
	_capture_initial_overlaps.call_deferred()
	# Tick imediato no spawn (sem esperar 0.5s pro primeiro hit).
	_tick_accum = TICK_INTERVAL
	# Fade out nos últimos `fade_duration` segundos.
	var tw := create_tween()
	tw.tween_interval(maxf(duration - fade_duration, 0.0))
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)


func _build_visual_tiles() -> void:
	# z_index = -1 absoluto pra ficar atrás de inimigos/player.
	for off in TILE_OFFSETS:
		var s := Sprite2D.new()
		s.texture = TILE_TEXTURE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = Color(1, 1, 1, 0.55)
		s.position = off
		s.z_index = -1
		s.z_as_relative = false
		add_child(s)


func _build_collision_shape() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)


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
	_refresh_slows()


func _apply_tick() -> void:
	var amount: float = damage_per_second * TICK_INTERVAL
	var p_for_crit := get_tree().get_first_node_in_group("player")
	for enemy in _enemies_inside.duplicate():
		if not is_instance_valid(enemy):
			_enemies_inside.erase(enemy)
			continue
		if (enemy as Node).is_queued_for_deletion():
			continue
		if "hp" in enemy and float(enemy.hp) <= 0.0:
			continue
		if not enemy.has_method("take_damage"):
			continue
		var dmg: float = amount
		var is_crit: bool = false
		if p_for_crit != null and p_for_crit.has_method("roll_crit_dot"):
			var crit: Dictionary = p_for_crit.roll_crit_dot(dmg)
			dmg = float(crit.get("dmg", dmg))
			is_crit = bool(crit.get("crit", false))
			if is_crit:
				CritFeedback.mark_next_hit_crit(enemy)
		var was_alive: bool = (not ("hp" in enemy)) or float(enemy.hp) > 0.0
		enemy.take_damage(dmg)
		if p_for_crit != null and p_for_crit.has_method("notify_damage_dealt_by_source"):
			p_for_crit.notify_damage_dealt_by_source(dmg, "ice_arrow")
		if was_alive and p_for_crit != null and p_for_crit.has_method("notify_kill_by_source"):
			if "hp" in enemy and float(enemy.hp) <= 0.0:
				p_for_crit.notify_kill_by_source("ice_arrow")


func _refresh_slows() -> void:
	# Reaplica slow nos overlapping. Slow expira em ~SLOW_REFRESH após sair.
	# Skip se inimigo tem FreezeDebuff (frozen — slow encavalado causa bug
	# de speed restaurada errada).
	for enemy in _enemies_inside:
		if not is_instance_valid(enemy):
			continue
		_apply_slow_to(enemy)


func _apply_slow_to(target: Node) -> void:
	for c in target.get_children():
		if c is FreezeDebuff:
			return
		if c is CurseDebuff:
			return
	if not ("speed" in target):
		return
	for c in target.get_children():
		if c is SlowDebuff:
			(c as SlowDebuff).refresh(SLOW_REFRESH, slow_factor)
			return
	var deb := SlowDebuff.new()
	deb.duration = SLOW_REFRESH
	deb.slow_factor = slow_factor
	target.add_child(deb)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("enemy"):
		return
	if body not in _enemies_inside:
		_enemies_inside.append(body)


func _on_body_exited(body: Node) -> void:
	_enemies_inside.erase(body)
