extends Area2D

# Nuvem de fumaça letal da Duskrose. Spawna em posições aleatórias do mapa
# quando boss cast smoke. Player tem que sair da área antes do tick de dano.
#
# Lifecycle:
# 1. Spawn-in: 0.4s — fade-in da sprite + área de colisão pulsa indicando dano
#    iminente (telegraph).
# 2. Active: `duration` segundos tickando dano enquanto player overlapa.
# 3. Fade-out: 0.6s — alpha pra 0 e queue_free.
#
# Frames usam o tag "smoke" do duskrose-Sheet (frames 2-4).

@export var duration: float = 5.0
@export var tick_interval: float = 0.5
@export var damage_per_tick: float = 8.0
@export var damage_mult: float = 1.0  # setado pela Duskrose pra propagar wave scaling

const TELEGRAPH_DURATION: float = 0.4
const FADE_OUT_DURATION: float = 0.6

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _player_in_area: bool = false
var _player_ref: Node2D = null
var _tick_accum: float = 0.0
var _active: bool = false  # true durante a fase de dano
var _remaining: float = 0.0
var _fade_started: bool = false


func _ready() -> void:
	add_to_group("duskrose_decoration")  # cleanup automático no _finish_wave
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Fase 1: telegraph fade-in (sem dano).
	sprite.modulate.a = 0.0
	collision.disabled = true
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 0.85, TELEGRAPH_DURATION)
	t.tween_callback(_start_active)


func _start_active() -> void:
	_active = true
	collision.disabled = false
	_remaining = duration


func _process(delta: float) -> void:
	if not _active or _fade_started:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_start_fade_out()
		return
	if _player_in_area:
		_tick_accum += delta
		while _tick_accum >= tick_interval:
			_tick_accum -= tick_interval
			_apply_tick()


func _apply_tick() -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if not _player_ref.has_method("take_damage"):
		return
	_player_ref.take_damage(damage_per_tick * damage_mult, "duskrose_smoke")


func _start_fade_out() -> void:
	_fade_started = true
	_active = false
	collision.disabled = true
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, FADE_OUT_DURATION)
	t.tween_callback(queue_free)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_area = true
		_player_ref = body as Node2D
		_tick_accum = tick_interval  # tick imediato ao entrar (não espera o full interval)


func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_area = false
		_player_ref = null
		_tick_accum = 0.0
