extends Area2D

# Pickup raro "Relógio de Reset" — dropado por inimigos (1,5%, só depois que o
# player tem alguma skill ATIVÁVEL de Espaço/Q). Ao coletar, REDUZ em 80% o
# cooldown atual de todas as skills ativas (dash/esquivando/fenda + fogo/cadeia/
# maldição/gelo/pedra). Mantém 20% do que faltava.
#
# Origem do node no chão (Y-sort com player/inimigos); visual offsetado acima.
# Dura `lifetime` segundos (= tempo de uma coin sob Chuva de Coins L1); nos
# últimos `blink_warn_duration` segundos pisca branco pra avisar que vai sumir.
# Estrutura espelha o gold/coração, versão enxuta (sem magnet/lock/slow).

@export var pickup_sound: AudioStream
# 11.875 = lifetime base da coin (9.5) × bônus de Chuva de Coins L1 (×1.25).
@export var lifetime: float = 11.875
@export var blink_warn_duration: float = 2.5
@export var bob_amplitude: float = 1.5
@export var bob_speed: float = 4.0

const VISUAL_OFFSET_Y: float = -6.0
# Hop inicial: parábola que decai durante HOP_DURATION segundos.
const HOP_HEIGHT: float = 8.0
const HOP_DURATION: float = 0.4
# Shader que substitui RGB por branco preservando alpha — usado no blink final.
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Indicador de oclusão (igual à moeda): nó $Indicator no clock.tscn — bolinha em
# z_index alto que renderiza sempre por cima de árvores/props. Edite tamanho/cor/
# posição direto no inspector. Pulsa enquanto está no chão e vira vermelho/piscante
# (INDICATOR_WARN_COLOR) quando o tempo está acabando.
const INDICATOR_WARN_COLOR: Color = Color(1.0, 0.25, 0.2, 1.0)

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite
@onready var _indicator: Polygon2D = $Indicator

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _silhouette_mat: ShaderMaterial
# Cor base do indicador — capturada do nó no _ready (o que estiver setado no .tscn).
var _indicator_base_color: Color = Color(1.0, 0.85, 0.35, 1.0)
var _indicator_pulse_tween: Tween = null
var _warn_active: bool = false


func _ready() -> void:
	add_to_group("clock_pickup")
	body_entered.connect(_on_body_entered)
	# Phase random pra relógios dropados juntos não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = SILHOUETTE_SHADER
	_start_indicator_pulse()


# Liga o pulse de alpha do indicador (o nó $Indicator vem do clock.tscn). Guarda
# a cor base setada no inspector pra restaurar depois do blink de aviso. Fase
# random pra relógios próximos não piscarem em sync.
func _start_indicator_pulse() -> void:
	if _indicator == null:
		return
	_indicator_base_color = _indicator.color
	_indicator.modulate.a = randf_range(0.7, 1.0)
	_indicator_pulse_tween = _indicator.create_tween().set_loops()
	_indicator_pulse_tween.tween_property(_indicator, "modulate:a", 0.6, 0.55).set_trans(Tween.TRANS_SINE)
	_indicator_pulse_tween.tween_property(_indicator, "modulate:a", 1.0, 0.55).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if _picked:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return

	# Hop inicial (parábola, peak em t=0.5) + bobbing contínuo.
	var hop_offset: float = 0.0
	if _elapsed < HOP_DURATION:
		var t: float = _elapsed / HOP_DURATION
		hop_offset = -HOP_HEIGHT * 4.0 * t * (1.0 - t)
	_bob_phase += delta * bob_speed
	visual.position.y = VISUAL_OFFSET_Y + sin(_bob_phase) * bob_amplitude + hop_offset

	# Blink de aviso: pisca branco, frequência e proporção branca sobem conforme
	# o tempo acaba (mesma lógica do gold).
	var time_left: float = lifetime - _elapsed
	if time_left <= blink_warn_duration:
		# Primeira entrada no aviso: para o pulse normal pro indicador acompanhar
		# o blink (senão fica em sync com o dourado e o aviso some).
		if not _warn_active:
			_warn_active = true
			if _indicator_pulse_tween != null and _indicator_pulse_tween.is_valid():
				_indicator_pulse_tween.kill()
			if _indicator != null:
				_indicator.modulate.a = 1.0
		var ratio: float = 1.0 - time_left / blink_warn_duration
		var freq: float = lerp(4.0, 14.0, ratio)
		var white_threshold: float = lerp(0.4, 0.8, ratio)
		var phase: float = fmod(_elapsed * freq, 1.0)
		var on_flash: bool = phase < white_threshold
		sprite.material = _silhouette_mat if on_flash else null
		# Indicador pisca vermelho quando o sprite está branco, cor base caso contrário.
		if _indicator != null:
			_indicator.color = INDICATOR_WARN_COLOR if on_flash else _indicator_base_color
	else:
		sprite.material = null


func _on_body_entered(body: Node) -> void:
	if _picked:
		return
	if not body.is_in_group("player"):
		return
	if not body.has_method("reduce_all_skill_cooldowns"):
		return
	# Fenda Crepuscular: não coleta em trânsito durante o blink do teleporte.
	if body.get("_fenda_teleporting") == true:
		return
	_collect(body)


func _collect(body: Node) -> void:
	if _picked:
		return
	_picked = true
	body.reduce_all_skill_cooldowns()
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
	p.volume_db = -15.0
	p.pitch_scale = randf_range(0.95, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)
