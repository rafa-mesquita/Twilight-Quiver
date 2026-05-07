extends Area2D

# Pickup de coração dropado por inimigo quando player tem o upgrade Life Steal.
# Player anda por cima e cura `heal_pct * max_hp`. Origem no chão (Y-sort com
# player/inimigos), visual offsetado pra cima. Lifetime + bobbing + blink final
# espelham o gold.

@export var heal_pct: float = 0.20
@export var bob_amplitude: float = 1.5
@export var bob_speed: float = 4.0
@export var pickup_sound: AudioStream
@export var lifetime: float = 8.0
@export var blink_warn_duration: float = 2.5

const VISUAL_OFFSET_Y: float = -6.0
const HOP_HEIGHT: float = 8.0
const HOP_DURATION: float = 0.4
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/Sprite

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _silhouette_mat: ShaderMaterial


func magnet_to_player(target_pos_callable: Callable) -> void:
	# Modo magnet pro fim de wave (espelha o gold). Suga todos os corações
	# restantes pro player ao terminar a round.
	if _picked:
		return
	_picked = true
	set_process(false)
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
	if player != null and player.has_method("heal") and "max_hp" in player:
		player.heal(player.max_hp * heal_pct)
	_play_pickup_sound()
	queue_free()


func _ready() -> void:
	add_to_group("heart")
	body_entered.connect(_on_body_entered)
	# Phase inicial random pra corações dropados juntos não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_silhouette_mat = ShaderMaterial.new()
	_silhouette_mat.shader = SILHOUETTE_SHADER


func _process(delta: float) -> void:
	if _picked:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
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
	# Blink warning nos últimos blink_warn_duration segundos.
	var time_left: float = lifetime - _elapsed
	if time_left <= blink_warn_duration:
		var ratio: float = 1.0 - time_left / blink_warn_duration
		var freq: float = lerp(4.0, 14.0, ratio)
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
