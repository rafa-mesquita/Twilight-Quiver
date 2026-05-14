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
	var p_for_crit := get_tree().get_first_node_in_group("player")
	for body in get_overlapping_bodies():
		if not body.is_in_group("enemy"):
			continue
		if body.has_method("take_damage"):
			var was_alive_cap: bool = (not ("hp" in body)) or float(body.hp) > 0.0
			var dmg_cap: float = per_tick
			# Crit roll por tick (DoT, mín +1 dano no bônus).
			if p_for_crit != null and p_for_crit.has_method("roll_crit_dot"):
				var crit_cap: Dictionary = p_for_crit.roll_crit_dot(dmg_cap)
				dmg_cap = float(crit_cap.get("dmg", dmg_cap))
				if bool(crit_cap.get("crit", false)):
					CritFeedback.mark_next_hit_crit(body)
			body.take_damage(dmg_cap)
			_notify_player_dmg_kill(dmg_cap, "capivara_joe", was_alive_cap, body)


func _notify_player_dmg_kill(amount: float, source_id: String, was_alive: bool, target: Node) -> void:
	if not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("notify_damage_dealt_by_source"):
		p.notify_damage_dealt_by_source(amount, source_id)
	if was_alive and p.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			p.notify_kill_by_source(source_id)
