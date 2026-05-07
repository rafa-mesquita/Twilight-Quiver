extends Area2D

# Pickup de gold dropado por inimigo. Player anda por cima e coleta.
# Origem do node fica no chão (pra Y-sort com player/inimigos), visual fica acima.
# Dura `lifetime` segundos; nos últimos `blink_warn_duration` segundos pisca pra avisar.

@export var value: int = 1
@export var bob_amplitude: float = 1.5
@export var bob_speed: float = 4.0
@export var pickup_sound: AudioStream
@export var lifetime: float = 8.0
@export var blink_warn_duration: float = 2.5

const VISUAL_OFFSET_Y: float = -6.0
# Hop inicial: parábola que decai durante HOP_DURATION segundos.
const HOP_HEIGHT: float = 8.0
const HOP_DURATION: float = 0.4
# Imã de Gold (upgrade): velocidade da perseguição contínua durante a wave.
# Diferente do magnet de fim-de-wave que usa tween fixo de 0.55s.
const MAGNET_PULL_SPEED: float = 130.0
# Shader que substitui RGB por branco preservando alpha — usado pro blink final.
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _silhouette_mat: ShaderMaterial
# Cache lazy do player pra checar `has_gold_magnet` sem buscar no group todo frame.
var _player_ref: Node2D = null
# Indicador de oclusão (bolinha em z_index 100) — guardado pra trocar cor/pulse
# durante o blink de aviso (sem ele, o aviso ficaria escondido pelo dourado).
var _indicator: Polygon2D = null
var _indicator_pulse_tween: Tween = null
var _warn_active: bool = false
const INDICATOR_BASE_COLOR: Color = Color(1.0, 0.85, 0.35, 1.0)
const INDICATOR_WARN_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)


func _ready() -> void:
	add_to_group("gold")
	body_entered.connect(_on_body_entered)
	# Phase inicial random pra moedas dropadas no mesmo instante não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = SILHOUETTE_SHADER
	_create_occlusion_indicator()


# Pequena bolinha dourada pulsante ACIMA da moeda, com z_index alto pra
# renderizar sempre por cima de árvores/props/player. Solução pro problema
# da moeda sumir atrás de objetos sem ter que jogar a moeda inteira pra cima
# (o que ficaria estranho com o y-sort).
func _create_occlusion_indicator() -> void:
	var ind := Polygon2D.new()
	ind.z_as_relative = false
	ind.z_index = 100
	ind.position = Vector2(0, VISUAL_OFFSET_Y - 12.0)
	var pts := PackedVector2Array()
	var radius: float = 1.5
	var segments: int = 10
	for i in segments:
		var ang: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(ang) * radius, sin(ang) * radius))
	ind.polygon = pts
	ind.color = INDICATOR_BASE_COLOR  # dourado igual à moeda
	add_child(ind)
	_indicator = ind
	# Pulse de alpha — swing menor pra indicador ficar mais consistente/opaco
	# (antes ia até 0.25 = quase sumia; agora mínimo 0.6 = sempre visível).
	# Fase random pra moedas próximas não piscarem em sync.
	ind.modulate.a = randf_range(0.7, 1.0)
	_indicator_pulse_tween = ind.create_tween().set_loops()
	_indicator_pulse_tween.tween_property(ind, "modulate:a", 0.6, 0.55).set_trans(Tween.TRANS_SINE)
	_indicator_pulse_tween.tween_property(ind, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


func magnet_to_player(target_pos_callable: Callable) -> void:
	# Modo magnet: invocado no fim do round pra sugar todas as moedas restantes.
	# `target_pos_callable` retorna a posição atual do player (Callable pra atualizar
	# ao longo do tween — moeda persegue mesmo se player anda).
	if _picked:
		return
	_picked = true
	# Para o blink/processamento normal — vamos animar manualmente.
	set_process(false)
	# Tween que atualiza a posição em tempo real seguindo o player.
	var tween: Tween = create_tween()
	tween.tween_method(_magnet_step.bind(target_pos_callable), 0.0, 1.0, 0.55)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_magnet_finalize)


func _magnet_step(t: float, target_callable: Callable) -> void:
	var target: Vector2 = global_position
	if target_callable.is_valid():
		var got: Variant = target_callable.call()
		if got is Vector2:
			target = got
	global_position = global_position.lerp(target, t * 0.4 + 0.05)


func _magnet_finalize() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_gold"):
		player.add_gold(value)
	_play_pickup_sound()
	queue_free()


func _process(delta: float) -> void:
	if _picked:
		return
	_elapsed += delta

	# Imã de Gold (upgrade): se player tem, persegue ele a velocidade fixa.
	# Skip lifetime/hop/bob/blink — gold magnetado não expira (sempre vai chegar).
	# A coleta acontece via body_entered quando os shapes overlap.
	if _is_player_magnet_active():
		_magnet_chase_player(delta)
		return

	# Tempo acabou — sai.
	if _elapsed >= lifetime:
		queue_free()
		return

	# Hop inicial: parábola invertida (peak em t=0.5).
	var hop_offset: float = 0.0
	if _elapsed < HOP_DURATION:
		var t: float = _elapsed / HOP_DURATION
		# Equação parabólica: 4*t*(1-t) vai de 0→1→0 com peak em t=0.5
		hop_offset = -HOP_HEIGHT * 4.0 * t * (1.0 - t)

	# Bobbing contínuo.
	_bob_phase += delta * bob_speed
	var bob_offset: float = sin(_bob_phase) * bob_amplitude

	visual.position.y = VISUAL_OFFSET_Y + bob_offset + hop_offset

	# Blink warning: filtro branco pisca, frequência E proporção branca aumentam
	# conforme o tempo acaba. Quando tempo zera, queue_free.
	var time_left: float = lifetime - _elapsed
	if time_left <= blink_warn_duration:
		# Primeira vez que entra no aviso: para o pulse normal pra indicador
		# acompanhar o blink (senão fica em sync com o dourado e esconde o sinal).
		if not _warn_active:
			_warn_active = true
			if _indicator_pulse_tween != null and _indicator_pulse_tween.is_valid():
				_indicator_pulse_tween.kill()
			if _indicator != null:
				_indicator.modulate.a = 1.0
		var ratio: float = 1.0 - time_left / blink_warn_duration  # 0 → 1
		var freq: float = lerp(4.0, 14.0, ratio)
		# Proporção do ciclo em branco: 40% no início → 80% no fim (cada vez mais "branco")
		var white_threshold: float = lerp(0.4, 0.8, ratio)
		var phase: float = fmod(_elapsed * freq, 1.0)
		var on_flash: bool = phase < white_threshold
		sprite.material = _silhouette_mat if on_flash else null
		# Indicador também pisca: vermelho quando o sprite tá branco, dourado caso
		# contrário — fica claro que a moeda tá pra sumir.
		if _indicator != null:
			_indicator.color = INDICATOR_WARN_COLOR if on_flash else INDICATOR_BASE_COLOR
	else:
		sprite.material = null


func _is_player_magnet_active() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node2D
	if _player_ref == null:
		return false
	return _player_ref.get("has_gold_magnet") == true


func _magnet_chase_player(delta: float) -> void:
	var dir: Vector2 = _player_ref.global_position - global_position
	var dist: float = dir.length()
	if dist < 0.5:
		return
	global_position += (dir / dist) * MAGNET_PULL_SPEED * delta


func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("add_gold"):
		return
	_picked = true
	body.add_gold(value)
	_play_pickup_sound()
	# Anim de coleta: sobe e some.
	var t := create_tween().set_parallel(true)
	t.tween_property(visual, "position:y", VISUAL_OFFSET_Y - 12.0, 0.2)
	t.tween_property(visual, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(queue_free)


func _play_pickup_sound() -> void:
	if pickup_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = pickup_sound
	p.volume_db = -16.0
	p.pitch_scale = randf_range(0.95, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)
