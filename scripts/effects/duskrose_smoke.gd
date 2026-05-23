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
# Raio de dano em aliados (Claudio, Leno, Capivara, Ting, Mini Mago summon,
# Arbusto + curse_ally). Usa group iteration + distance porque allies têm
# collision_layer=0 (não detectáveis via overlapping_bodies do Area2D).
# Raio 70 = mais largo que o visual (sprite escalado 1.8x = ~58px raio) pra
# pegar aliados que cruzam rápido pela borda.
@export var ally_damage_radius: float = 70.0
# Tick separado pra aliados — mais agressivo que o tick do player porque
# aliados (especialmente macaco do Mini Mago) atravessam o gás rápido e
# podiam não pegar o tick de 0.5s. 0.2s garante ~2-3 ticks num pulso curto.
@export var ally_tick_interval: float = 0.2

const TELEGRAPH_DURATION: float = 0.4
const FADE_OUT_DURATION: float = 0.6

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

var _tick_accum: float = 0.0
var _ally_tick_accum: float = 0.0
var _active: bool = false  # true durante a fase de dano
var _remaining: float = 0.0
var _fade_started: bool = false


func _ready() -> void:
	add_to_group("duskrose_decoration")  # cleanup automático no _finish_wave
	add_to_group("duskrose_smoke")  # query rápida por aliados (Capivara) pra evitar gás
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
	_tick_accum = tick_interval       # tick imediato ao ativar (player)
	_ally_tick_accum = ally_tick_interval  # tick imediato ao ativar (aliados)


func _process(delta: float) -> void:
	if not _active or _fade_started:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_start_fade_out()
		return
	# Tick separado pra player (mais devagar, dano forte por tick) e pra
	# aliados (mais rápido, pega quem atravessa veloz).
	_tick_accum += delta
	while _tick_accum >= tick_interval:
		_tick_accum -= tick_interval
		_apply_player_tick()
	_ally_tick_accum += delta
	while _ally_tick_accum >= ally_tick_interval:
		_ally_tick_accum -= ally_tick_interval
		_apply_ally_tick()


func _apply_player_tick() -> void:
	# Player: via overlapping_bodies (CharacterBody2D layer 1 + mask 1 do smoke).
	var dmg: float = damage_per_tick * damage_mult
	for body in get_overlapping_bodies():
		if is_instance_valid(body) and body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(dmg, "duskrose_smoke")


func _apply_ally_tick() -> void:
	# Aliados: iteração no grupo "ally" + distance check, porque eles têm
	# collision_layer=0 (não detectáveis pelo Area2D). Inclui curse_ally
	# (rosas/inimigos convertidos via Disparo Profano também estão em "ally").
	# Macaco do Mini Mago é "ally" + "mini_mago_summon" + "curse_ally" — pega.
	# Dano por tick reduzido pra balancear a frequência maior.
	var dmg: float = damage_per_tick * damage_mult * (ally_tick_interval / tick_interval)
	var center: Vector2 = global_position
	var radius_sq: float = ally_damage_radius * ally_damage_radius
	for ally in get_tree().get_nodes_in_group("ally"):
		if not is_instance_valid(ally) or not (ally is Node2D) or not ally.has_method("take_damage"):
			continue
		if (ally as Node2D).global_position.distance_squared_to(center) <= radius_sq:
			ally.take_damage(dmg)


func _start_fade_out() -> void:
	_fade_started = true
	_active = false
	collision.disabled = true
	var t := create_tween()
	t.tween_property(sprite, "modulate:a", 0.0, FADE_OUT_DURATION)
	t.tween_callback(queue_free)
