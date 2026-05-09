extends Area2D

# AoE roxa que aparece quando um inimigo pisa no cogumelo de dano.
# Total damage / duration = DPS aplicado a TODOS os inimigos dentro durante a vida.

@export var total_damage: float = 40.0
@export var duration: float = 5.0
@export var fade_duration: float = 0.5

var _life: float = 0.0
var _tick_accum: float = 0.0
const TICK_INTERVAL: float = 0.5  # 10 ticks ao longo dos 5s = 4 dmg cada


func _ready() -> void:
	_life = duration
	# Fade nos últimos fade_duration segundos.
	var tw := create_tween()
	tw.tween_interval(maxf(duration - fade_duration, 0.0))
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	_tick_accum += delta
	if _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick_damage()


func _apply_tick_damage() -> void:
	# Dano por tick = total_damage / numero de ticks.
	var ticks: float = duration / TICK_INTERVAL
	var per_tick: float = total_damage / maxf(ticks, 1.0)
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemy"):
			continue
		if body.has_method("take_damage"):
			body.take_damage(per_tick)
