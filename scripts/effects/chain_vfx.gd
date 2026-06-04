class_name ChainVfx
extends Object

# Helpers compartilhados do visual/áudio da Cadeia de Raios. Usados tanto pelo
# proc de cadeia da flecha (arrow.gd) quanto pelo raio automático do L2 da Cadeia
# (player.gd). Centraliza o desenho da faísca e o som (com throttle global) pra
# não duplicar entre os dois.

const CHAIN_SOUND: AudioStream = preload("res://audios/upgrades/cadeia de raios/Cadeia de raios effect.mp3")
const CHAIN_SOUND_THROTTLE_MS: int = 80
const CHAIN_SOUND_VOLUME_DB: float = -10.0

# Throttle global do som — várias faíscas juntas (multi-arrow, ou proc + auto-bolt)
# tocam só uma vez por janela.
static var _last_chain_sound_msec: int = -1000


# Desenha a faísca elétrica (zig-zag amarelo) entre dois pontos no mundo. `world`
# é o nó pai (tipicamente o grupo "world" ou a cena atual).
static func spark_between(world: Node, from: Vector2, to: Vector2) -> void:
	if world == null:
		return
	var dir: Vector2 = to - from
	if dir.length() < 0.01:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
	var line := Line2D.new()
	line.width = 2.5
	# Amarelo elétrico saturado (R/G altos, B baixo) — modulate > 1 pra brilho extra.
	line.default_color = Color(2.2, 1.9, 0.4, 1.0)
	line.z_index = 10
	# Zigue-zague: 7 segmentos com offset perpendicular randômico nos pontos do meio.
	var segments: int = 7
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var p: Vector2 = from.lerp(to, t)
		if i > 0 and i < segments:
			p += perp * randf_range(-7.0, 7.0)
		line.add_point(p)
	world.add_child(line)
	line.global_position = Vector2.ZERO  # add_point usa coords absolutas
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)


# Toca o som da cadeia em `pos` (espacializado), com throttle global.
static func play_chain_sound(world: Node, pos: Vector2) -> void:
	if world == null:
		return
	var now: int = Time.get_ticks_msec()
	if now - _last_chain_sound_msec < CHAIN_SOUND_THROTTLE_MS:
		return
	_last_chain_sound_msec = now
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = CHAIN_SOUND
	p.volume_db = CHAIN_SOUND_VOLUME_DB
	world.add_child(p)
	p.global_position = pos
	p.play()
	var ref: AudioStreamPlayer2D = p
	world.get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)
