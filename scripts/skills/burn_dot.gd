class_name BurnDoT
extends Node

# Damage-over-time aplicado em inimigos pela flecha de fogo (e futuros efeitos
# de queimadura). Filho do inimigo — quando inimigo é freed, BurnDoT também é.
# Re-aplicação refresca a duração ao invés de empilhar nodes.

@export var dps: float = 5.0
@export var duration: float = 3.0
@export var tick_interval: float = 0.5
# Dano extra aplicado uma única vez quando o burn TERMINA por timeout natural
# (não quando o inimigo morre antes). 0 = desabilitado.
@export var final_bonus_damage: float = 0.0

var _remaining: float = 0.0
var _tick_accum: float = 0.0


func _ready() -> void:
	_remaining = duration


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_apply_final_bonus()
		queue_free()
		return
	_tick_accum += delta
	while _tick_accum >= tick_interval:
		_tick_accum -= tick_interval
		_apply_tick()
		if not is_inside_tree():
			return  # parent (enemy) morreu durante o tick


func _apply_tick() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if not parent.has_method("take_damage"):
		return
	# Skip se parent já morto/morrendo — evita spam de damage_sound (que vive
	# em world e gera som "continuo" depois da morte).
	if parent.is_queued_for_deletion():
		return
	if "hp" in parent and float(parent.hp) <= 0.0:
		return
	var tick_dmg: float = dps * tick_interval
	var was_alive: bool = (not ("hp" in parent)) or float(parent.hp) > 0.0
	parent.take_damage(tick_dmg)
	_notify_player_dmg_kill(tick_dmg, "fire_arrow", was_alive, parent)


# Refresca duração se nova flecha de fogo bate no mesmo alvo.
# Mantém o `dps` mais alto entre o atual e o novo (não down-grade).
func refresh(new_duration: float, new_dps: float) -> void:
	_remaining = maxf(_remaining, new_duration)
	if new_dps > dps:
		dps = new_dps


func _apply_final_bonus() -> void:
	if final_bonus_damage <= 0.0:
		return
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if parent.is_queued_for_deletion():
		return
	if "hp" in parent and float(parent.hp) <= 0.0:
		return
	if not parent.has_method("take_damage"):
		return
	var was_alive: bool = (not ("hp" in parent)) or float(parent.hp) > 0.0
	parent.take_damage(final_bonus_damage)
	_notify_player_dmg_kill(final_bonus_damage, "fire_arrow", was_alive, parent)


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
