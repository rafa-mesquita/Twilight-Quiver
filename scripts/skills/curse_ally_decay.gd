class_name CurseAllyDecay
extends Node

# Decay de HP em aliados convertidos pela Maldição. Anexado em curse_ally_helper
# quando o inimigo é convertido. Faz o aliado morrer naturalmente em `duration`
# segundos drenando max_hp / duration de HP por segundo.
#
# Reduz HP diretamente (sem take_damage) pra não spammar damage numbers/sound
# nem flash a cada frame. Quando hp <= 0, dispara take_damage(0.001) pra usar
# o death path normal do enemy (kill_effect, queue_free, etc).

const DURATION: float = 12.0
# Diamante: aliados convertidos duram mais (25s).
const DURATION_DIAMOND: float = 25.0

var _dps: float = 0.0
var _triggered_death: bool = false


func _ready() -> void:
	var parent: Node = get_parent()
	if parent == null:
		queue_free()
		return
	if not ("max_hp" in parent) or float(parent.max_hp) <= 0.0:
		queue_free()
		return
	# Diamante: se curse_arrow é o upgrade do diamante, aliado dura 25s.
	var effective_duration: float = DURATION
	if is_inside_tree():
		var p: Node = get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("is_diamond") and p.is_diamond("curse_arrow"):
			effective_duration = DURATION_DIAMOND
	_dps = float(parent.max_hp) / effective_duration


func _process(delta: float) -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		queue_free()
		return
	if parent.is_queued_for_deletion():
		queue_free()
		return
	if not ("hp" in parent and "max_hp" in parent):
		return
	if _triggered_death:
		return
	var current: float = float(parent.hp)
	var new_hp: float = maxf(current - _dps * delta, 0.0)
	parent.hp = new_hp
	# Atualiza HP bar pro player ver o aliado drenando. Usa set_ratio_silent
	# (sem trail/squash) — chamando todo frame, o set_ratio normal segurava o
	# trail branco no HP inicial e a barra parecia drenada inteira de cara.
	if parent.has_node("HpBar"):
		var bar: Node = parent.get_node("HpBar")
		if float(parent.max_hp) > 0.0:
			var ratio: float = new_hp / float(parent.max_hp)
			if bar.has_method("set_ratio_silent"):
				bar.set_ratio_silent(ratio)
			elif bar.has_method("set_ratio"):
				bar.set_ratio(ratio)
	if new_hp <= 0.0 and parent.has_method("take_damage"):
		# Dispara o death path normal (kill effect, silhouette, queue_free).
		# Gold não dropa porque is_curse_ally já gate.
		_triggered_death = true
		parent.take_damage(0.001)
