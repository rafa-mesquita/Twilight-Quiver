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
# Shader que substitui RGB por branco preservando alpha — usado pro blink final.
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _silhouette_mat: ShaderMaterial


func _ready() -> void:
	add_to_group("gold")
	body_entered.connect(_on_body_entered)
	# Phase inicial random pra moedas dropadas no mesmo instante não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = SILHOUETTE_SHADER


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
		var ratio: float = 1.0 - time_left / blink_warn_duration  # 0 → 1
		var freq: float = lerp(4.0, 14.0, ratio)
		# Proporção do ciclo em branco: 40% no início → 80% no fim (cada vez mais "branco")
		var white_threshold: float = lerp(0.4, 0.8, ratio)
		var phase: float = fmod(_elapsed * freq, 1.0)
		sprite.material = _silhouette_mat if phase < white_threshold else null
	else:
		sprite.material = null


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
