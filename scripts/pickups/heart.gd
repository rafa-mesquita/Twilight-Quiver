extends Area2D

# Pickup de coração dropado por inimigo quando player tem o upgrade Life Steal.
# Player anda por cima e cura `heal_pct * max_hp`. Origem no chão (Y-sort com
# player/inimigos), visual offsetado pra cima. Lifetime + bobbing + blink final
# espelham o gold.

@export var heal_pct: float = 0.20
@export var bob_amplitude: float = 1.5
@export var bob_speed: float = 4.0
@export var pickup_sound: AudioStream
# Coração da Coleta de Coração não expira — fica até ser pego ou a wave acabar.
# `lifetime <= 0` = nunca expira.
@export var lifetime: float = 0.0
@export var blink_warn_duration: float = 2.5

const VISUAL_OFFSET_Y: float = -6.0
const HOP_HEIGHT: float = 8.0
const HOP_DURATION: float = 0.4
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Indicador vermelho acima do coração — espelha o dourado do gold.
const INDICATOR_COLOR: Color = Color(0.95, 0.25, 0.3, 1.0)
# Life Steal L3+: coração persegue o player. Mesmo padrão do Imã de Gold.
# L3 limita o pull ao raio MAGNET_RADIUS (decisão tática preservada).
# L4 ignora o raio (puxa do mapa inteiro).
# Speed mais lenta que o player (~120 walking) — jogador consegue interceptar
# andando se quiser acelerar a coleta.
const MAGNET_PULL_SPEED: float = 75.0
const MAGNET_RADIUS: float = 110.0
# End-of-wave sweep usa um magnet ainda mais lento, e wave_manager chama um por
# vez (próximo só inicia quando o anterior é coletado). Player pode interceptar
# qualquer um andando — pickup normal via body_entered cura na hora.
const MAGNET_END_WAVE_SPEED: float = 55.0

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _silhouette_mat: ShaderMaterial
# Cache lazy do player pra checar `life_steal_level` sem buscar no group todo frame.
var _player_ref: Node2D = null
# Flag do magnet de fim-de-wave (acionado por wave_manager). Diferente do magnet
# de Life Steal L3/L4: pickup acontece via body_entered normal (player anda em
# cima) — não força heal automático no final.
var _end_wave_magnet: bool = false


func magnet_to_player(_target_pos_callable: Callable = Callable()) -> void:
	# End-of-wave sweep: ativa magnet contínuo até o player tocar o coração
	# (body_entered cura normal). Player pode acelerar andando ao encontro.
	if _picked:
		return
	_end_wave_magnet = true


func _ready() -> void:
	add_to_group("heart")
	body_entered.connect(_on_body_entered)
	# Phase inicial random pra corações dropados juntos não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = SILHOUETTE_SHADER
	_create_occlusion_indicator()


# Bolinha vermelha pulsante acima do coração (z_index 100) — mesmo padrão da
# moeda, sinaliza o pickup atrás de árvores/props.
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
	ind.color = INDICATOR_COLOR
	add_child(ind)
	ind.modulate.a = randf_range(0.7, 1.0)
	var tw := ind.create_tween().set_loops()
	tw.tween_property(ind, "modulate:a", 0.6, 0.55).set_trans(Tween.TRANS_SINE)
	tw.tween_property(ind, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if _picked:
		return
	_elapsed += delta
	# Life Steal L3+: persegue o player (L3 só dentro do raio, L4 mapa todo).
	# Skip lifetime/hop/bob — coração magnetado não expira.
	# End-wave magnet usa speed menor pra dar tempo do player ler/interceptar.
	if _end_wave_magnet:
		_magnet_chase_player(delta, MAGNET_END_WAVE_SPEED)
		return
	if _is_player_magnet_active():
		_magnet_chase_player(delta, MAGNET_PULL_SPEED)
		return
	# lifetime <= 0 = coração nunca expira (Coleta de Coração não some).
	if lifetime > 0.0 and _elapsed >= lifetime:
		queue_free()
		return
	# Hop inicial parabólico.
	var hop_offset: float = 0.0
	if _elapsed < HOP_DURATION:
		var t: float = _elapsed / HOP_DURATION
		hop_offset = -HOP_HEIGHT * 4.0 * t * (1.0 - t)
	# Bobbing contínuo.
	_bob_phase += delta * bob_speed
	var bob_offset: float = sin(_bob_phase) * bob_amplitude
	visual.position.y = VISUAL_OFFSET_Y + bob_offset + hop_offset
	# Blink warning só faz sentido quando a moeda EXPIRA — coração não expira.
	if lifetime > 0.0:
		var time_left: float = lifetime - _elapsed
		if time_left <= blink_warn_duration:
			var ratio: float = 1.0 - time_left / blink_warn_duration
			var freq: float = lerp(4.0, 14.0, ratio)
			var white_threshold: float = lerp(0.4, 0.8, ratio)
			var phase: float = fmod(_elapsed * freq, 1.0)
			sprite.material = _silhouette_mat if phase < white_threshold else null
		else:
			sprite.material = null


func _is_player_magnet_active() -> bool:
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node2D
	if _player_ref == null:
		return false
	var lvl: int = int(_player_ref.get("life_steal_level"))
	if lvl < 3:
		return false
	if lvl >= 4:
		return true  # mapa todo
	# L3: só puxa dentro do raio.
	return global_position.distance_squared_to(_player_ref.global_position) <= MAGNET_RADIUS * MAGNET_RADIUS


func _magnet_chase_player(delta: float, speed: float = MAGNET_PULL_SPEED) -> void:
	# Garante ref do player mesmo se o magnet foi acionado externamente
	# (end-wave magnet não passa por _is_player_magnet_active).
	if _player_ref == null or not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player") as Node2D
	if _player_ref == null:
		return
	var dir: Vector2 = _player_ref.global_position - global_position
	var dist: float = dir.length()
	if dist < 0.5:
		return
	global_position += (dir / dist) * speed * delta


func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("heal"):
		return
	_picked = true
	var heal_amount: float = 0.0
	if "max_hp" in body:
		heal_amount = body.max_hp * heal_pct
	body.heal(heal_amount)
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
	p.bus = &"SFX"
	p.stream = pickup_sound
	p.volume_db = -14.0
	p.pitch_scale = randf_range(0.95, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)
