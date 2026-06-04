class_name TideWave
extends Node2D

# Onda da "Fúria da Maré" L4 (sai junto do Escudo no Q). Uma parede de água que
# cobre a LARGURA inteira do mapa e desce do topo até a base em `duration` segundos.
# A PONTA (borda ondulada) lidera a descida; o CORPO preenche atrás dela (rows
# tileadas) à medida que a ponta passa. Inimigos que a ponta alcança tomam `damage`
# de dano + `debuff_stacks` stacks de Vulnerabilidade. Toca um som durante a passagem.
#
# Sprites tileados horizontalmente (150px). Lê os bounds da Camera2D ativa em runtime
# (funciona em qualquer mapa); cai nos defaults do mapa principal se não achar câmera.

const PONTA_TEX: Texture2D = preload("res://assets/effects/water/ponta onda.png")  # 300x18 = 2 frames de 150x18
const CORPO_TEX: Texture2D = preload("res://assets/effects/water/corpo onda.png")  # 300x26 = 2 frames de 150x26
const WAVE_SOUND: AudioStream = preload("res://assets/effects/water/sound wave.mp3")
const TILE_W: int = 150
const PONTA_H: int = 18
const CORPO_H: int = 26
const FRAME_INTERVAL: float = 0.16  # troca entre os 2 frames
const Z: int = -1  # camada do chão (mesmo nível da poça): abaixo de inimigos/objetos/player, acima do piso

# Bounds (defaults = mapa principal; sobrescritos pela câmera no _ready).
var left_x: float = -156.0
var right_x: float = 657.0
var top_y: float = -112.0
var bottom_y: float = 414.0
var duration: float = 6.0
var damage: float = 35.0
var debuff_stacks: int = 2
var debuff_per_stack: float = 0.30
var debuff_duration: float = 3.0

var _tip_y: float = 0.0
var _prev_tip_y: float = 0.0  # y da ponta no frame anterior (só a PONTA dá dano)
var _speed: float = 0.0
var _frame: int = 0
var _frame_t: float = 0.0
var _committed_y: float = 0.0       # base das rows cheias já fixadas
var _tip_sprites: Array = []
var _body_sprites: Array = []       # rows cheias (corpo)
var _partial_sprites: Array = []    # linha parcial que cresce até encaixar na ponta
var _hit: Dictionary = {}
var _audio: AudioStreamPlayer2D = null


func _ready() -> void:
	_read_camera_bounds()
	z_index = Z
	modulate.a = 0.85
	_tip_y = top_y
	_prev_tip_y = top_y
	_committed_y = top_y
	_speed = (bottom_y - top_y) / maxf(duration, 0.01)
	_build_tip()
	_play_sound()


func _read_camera_bounds() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		left_x = float(cam.limit_left)
		right_x = float(cam.limit_right)
		top_y = float(cam.limit_top)
		bottom_y = float(cam.limit_bottom)


func _cols() -> int:
	return maxi(1, int(ceil((right_x - left_x) / float(TILE_W))))


func _make_tile(tex: Texture2D, frame_h: int, y: float, col: int, z: int) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.centered = false
	sp.region_enabled = true
	sp.region_rect = Rect2(_frame * TILE_W, 0, TILE_W, frame_h)
	sp.position = Vector2(left_x + col * TILE_W, y)
	sp.z_index = z
	add_child(sp)
	return sp


# Ponta e corpo no mesmo nível do nó (z=-1 → abaixo dos inimigos, acima do piso).
# Mal se sobrepõem (a ponta encosta no corpo em _tip_y), então a ordem não importa.
func _build_tip() -> void:
	for c in _cols():
		_tip_sprites.append(_make_tile(PONTA_TEX, PONTA_H, _tip_y, c, 0))


func _spawn_body_row(y: float) -> void:
	for c in _cols():
		_body_sprites.append(_make_tile(CORPO_TEX, CORPO_H, y, c, 0))


func _process(delta: float) -> void:
	# Animação dos 2 frames (toggle aplicado a todas as tiles).
	_frame_t += delta
	if _frame_t >= FRAME_INTERVAL:
		_frame_t -= FRAME_INTERVAL
		_frame = 1 - _frame
		for sp in _tip_sprites:
			if is_instance_valid(sp):
				sp.region_rect.position.x = _frame * TILE_W
		for sp in _body_sprites:
			if is_instance_valid(sp):
				sp.region_rect.position.x = _frame * TILE_W
	# Desce a ponta.
	_tip_y += _speed * delta
	for sp in _tip_sprites:
		if is_instance_valid(sp):
			sp.position.y = _tip_y
	# Preenche o corpo até encaixar exatamente na ponta (sem gap).
	_update_body()
	# Dano só nos inimigos que a PONTA cruzou neste frame.
	_damage_reached_enemies()
	_prev_tip_y = _tip_y
	if _tip_y >= bottom_y:
		_finish()


# Corpo = rows cheias fixadas (a cada CORPO_H px) + uma linha PARCIAL que cresce de
# _committed_y até _tip_y, encaixando na ponta sem deixar buraco.
func _update_body() -> void:
	var changed: bool = false
	while _committed_y + float(CORPO_H) <= _tip_y:
		_spawn_body_row(_committed_y)
		_committed_y += float(CORPO_H)
		changed = true
	if changed:
		_free_partial()
	var ph: int = int(round(_tip_y - _committed_y))
	if ph <= 0:
		return
	if _partial_sprites.is_empty():
		for c in _cols():
			var sp := Sprite2D.new()
			sp.texture = CORPO_TEX
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp.centered = false
			sp.region_enabled = true
			sp.position = Vector2(left_x + c * TILE_W, _committed_y)
			sp.z_index = 0
			add_child(sp)
			_partial_sprites.append(sp)
	for sp in _partial_sprites:
		if is_instance_valid(sp):
			sp.region_rect = Rect2(_frame * TILE_W, 0, TILE_W, ph)
			sp.position.y = _committed_y


func _free_partial() -> void:
	for sp in _partial_sprites:
		if is_instance_valid(sp):
			sp.queue_free()
	_partial_sprites.clear()


func _damage_reached_enemies() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		var eid: int = (e as Node).get_instance_id()
		if _hit.has(eid):
			continue
		# Só a PONTA dá dano: o inimigo precisa estar na faixa que a frente cruzou
		# AGORA (_prev_tip_y < y <= _tip_y). Quem já estava na água (acima da ponta,
		# ex: spawnou no corpo) tem y <= _prev_tip_y → não toma dano.
		var ey: float = (e as Node2D).global_position.y
		if ey > _prev_tip_y and ey <= _tip_y:
			_hit[eid] = true
			if e.has_method("take_damage"):
				e.take_damage(damage)
			# 2 stacks de Vulnerabilidade de uma vez (apply_to soma 1 por chamada).
			for _i in debuff_stacks:
				TideVulnerability.apply_to(e, debuff_duration, debuff_stacks, debuff_per_stack)


func _play_sound() -> void:
	_audio = AudioStreamPlayer2D.new()
	_audio.bus = &"SFX"
	var s: AudioStream = WAVE_SOUND
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	_audio.stream = s
	_audio.volume_db = -6.0
	add_child(_audio)
	_audio.global_position = Vector2((left_x + right_x) * 0.5, (top_y + bottom_y) * 0.5)
	_audio.play()


func _finish() -> void:
	set_process(false)
	# Visual some rápido.
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	# Áudio continua +1.5s depois da onda acabar, com fade out; só então libera o nó.
	if _audio != null and is_instance_valid(_audio):
		var atw := create_tween()
		atw.tween_property(_audio, "volume_db", -40.0, 1.5)
		atw.tween_callback(queue_free)
	else:
		tw.tween_callback(queue_free)
