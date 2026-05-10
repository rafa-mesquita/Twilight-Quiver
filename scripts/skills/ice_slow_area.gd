extends Area2D

# Área de slow do Ice Mage. Colisão e visual são MULTIPLOS tiles 16×16 em
# diamante (13 no total). Slow é aplicado continuamente enquanto o body está
# sobreposto e expira em ~0.15s ao sair ou ao despawn da área. Mira em player
# + aliados quando o mago é hostil, ou em inimigos quando curse-ally.

@export var slow_multiplier: float = 0.75  # 0.75 = 25% slow (target.speed × 0.75)
@export var lifetime: float = 6.0
@export var fade_duration: float = 0.5
# True: spawnado por enemy (atrasa player + allies). False: spawnado por
# curse-ally (atrasa enemies — espelha o flip do fire_mage curse).
@export var is_enemy_source: bool = true

# Visual + colisão: 13 tiles 16×16 em diamante. Mesmo padrão do leno_projectile
# (5 tiles em +), só que 2× maior. Colisão usa RectangleShape2D pra cada tile
# → área de slow MATCH exato com o visual (sem círculo grande estourando nos
# diagonais).
const TILE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/ice mage slow area.png")
const TILE_SIZE: float = 16.0
const TILE_OFFSETS: Array[Vector2] = [
	Vector2(0, -32),
	Vector2(-16, -16), Vector2(0, -16), Vector2(16, -16),
	Vector2(-32, 0), Vector2(-16, 0), Vector2(0, 0), Vector2(16, 0), Vector2(32, 0),
	Vector2(-16, 16), Vector2(0, 16), Vector2(16, 16),
	Vector2(0, 32),
]
# Threshold de velocidade pra considerar o player "andando" — abaixo disso o
# áudio de caminhada no gelo pausa (player parado/desacelerando por slow).
const WALK_VELOCITY_THRESHOLD: float = 8.0
# Slow é refrescado per-frame com essa duração curta. Quando o body sai da
# área (ou ela despawna), os refresh param e o slow expira em ~REFRESH_SLOW.
const REFRESH_SLOW_DURATION: float = 0.15

@onready var walk_sound: AudioStreamPlayer2D = get_node_or_null("WalkSound")

var _life: float = 0.0
# Player atualmente sobre a área (pra audio de caminhar).
var _player_in_area: Node2D = null
# Bodies sobrepostos válidos pra slow. Refresh do slow rola por frame nesses.
var _slowed_bodies: Array[Node] = []


func _ready() -> void:
	_life = lifetime
	_build_visual_tiles()
	_build_collision_tiles()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Loop do mp3 de caminhar (setado via código pra não depender do .import).
	if walk_sound != null and walk_sound.stream is AudioStreamMP3:
		(walk_sound.stream as AudioStreamMP3).loop = true
	# Pega quem já está dentro do raio no momento do spawn (overlap inicial).
	for body in get_overlapping_bodies():
		_on_body_entered(body)
	# Fade out nos últimos `fade_duration` segundos.
	var tw := create_tween()
	tw.tween_interval(maxf(lifetime - fade_duration, 0.0))
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)


func _build_visual_tiles() -> void:
	# Spawna múltiplos Sprite2D 16×16 (sem scale — escala 1.0) na cobertura
	# diamante. z_index = -1 absoluto (mesmo bucket do Ground TileMap em
	# main.tscn) — renderiza em cima do chão (porque é adicionado depois no
	# tree) e SEMPRE atrás de props/walls/entities (que ficam em z=0 default).
	for off in TILE_OFFSETS:
		var s := Sprite2D.new()
		s.texture = TILE_TEXTURE
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.modulate = Color(1, 1, 1, 0.6)
		s.position = off
		s.z_index = -1
		s.z_as_relative = false
		add_child(s)


func _build_collision_tiles() -> void:
	# 13 RectangleShape2D 16×16, uma por tile — Area2D faz UNION das shapes,
	# resultando em colisão exatamente do tamanho do visual (não estourando).
	for off in TILE_OFFSETS:
		var shape := RectangleShape2D.new()
		shape.size = Vector2(TILE_SIZE, TILE_SIZE)
		var col := CollisionShape2D.new()
		col.shape = shape
		col.position = off
		add_child(col)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_refresh_slow_on_overlapping()
	_update_walk_sound()


func _refresh_slow_on_overlapping() -> void:
	# Reaplica slow nos bodies sobrepostos com duration curta. Quando o body
	# sai (body_exited remove da lista) ou a área despawna (queue_free), os
	# refresh param e o slow expira em ~REFRESH_SLOW_DURATION.
	for body in _slowed_bodies.duplicate():
		if not is_instance_valid(body):
			_slowed_bodies.erase(body)
			continue
		_apply_slow_to(body)


func _update_walk_sound() -> void:
	# Toca o áudio de caminhar no gelo SÓ quando o player está sobre a área E
	# se movendo. Player parado ou fora → para o som.
	if walk_sound == null:
		return
	if _player_in_area == null or not is_instance_valid(_player_in_area):
		if walk_sound.playing:
			walk_sound.stop()
		return
	var moving: bool = false
	if "velocity" in _player_in_area:
		moving = (_player_in_area.velocity as Vector2).length() > WALK_VELOCITY_THRESHOLD
	if moving and not walk_sound.playing:
		walk_sound.play()
	elif not moving and walk_sound.playing:
		walk_sound.stop()


func _on_body_entered(body: Node) -> void:
	if body == null or not is_instance_valid(body):
		return
	# Track player pra audio de caminhar (independente do filtro de slow abaixo).
	if body.is_in_group("player") and body is Node2D:
		_player_in_area = body
	if body.is_in_group("cc_immune"):
		return
	if is_enemy_source:
		# Mago normal: bate em player + allies (ignora enemies pra não dar
		# friendly fire entre magos).
		if body.is_in_group("enemy"):
			return
		if not (body.is_in_group("player") or body.is_in_group("ally")):
			return
	else:
		# Mago convertido (curse-ally): bate em enemies.
		if not body.is_in_group("enemy"):
			return
	if body not in _slowed_bodies:
		_slowed_bodies.append(body)
	# Aplica slow imediato no enter (refresh-loop também rola, mas isso evita
	# 1 frame de atraso na primeira aplicação).
	_apply_slow_to(body)


func _on_body_exited(body: Node) -> void:
	if body == _player_in_area:
		_player_in_area = null
		if walk_sound != null and walk_sound.playing:
			walk_sound.stop()
	_slowed_bodies.erase(body)
	# Slow expira sozinho em ~REFRESH_SLOW_DURATION (0.15s) — sem refresh, o
	# _slow_remaining do player decai e zera. Ally/enemy SlowDebuff idem.


func _apply_slow_to(target: Node) -> void:
	# Player tem apply_slow nativo (gerencia stack próprio com _slow_factor).
	if target.has_method("apply_slow"):
		target.apply_slow(slow_multiplier, REFRESH_SLOW_DURATION)
		return
	# Ally/enemy: usa SlowDebuff. Refresh se já existir, senão cria novo.
	# CurseDebuff já dá slow + DoT, então não conflita — pula.
	if not ("speed" in target):
		return
	for c in target.get_children():
		if c is SlowDebuff:
			(c as SlowDebuff).refresh(REFRESH_SLOW_DURATION, slow_multiplier)
			return
		if c is CurseDebuff:
			return
	var deb := SlowDebuff.new()
	deb.duration = REFRESH_SLOW_DURATION
	deb.slow_factor = slow_multiplier
	target.add_child(deb)
