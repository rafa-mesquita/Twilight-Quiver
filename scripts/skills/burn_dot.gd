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
# Source ID que aparece no painel de dano. Default "fire_arrow" pra Flecha de
# Fogo do player. Outros usos (ex: inseto-aliado aplicando poison) sobrescrevem
# antes do add_child pra atribuir no breakdown correto.
@export var source_id: String = "fire_arrow"

# Splash: a cada tick, os 2 inimigos vivos mais próximos do queimando levam
# metade do tick_dmg como dano direto (sem propagar burn). Aplica em todos os
# níveis da Flecha de Fogo.
const SPLASH_RADIUS: float = 70.0
const SPLASH_DAMAGE_MULT: float = 0.5
const SPLASH_TARGETS: int = 2

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
	# Crit roll por tick (bônus mín +1 em DoTs pequenos).
	var p_for_crit := get_tree().get_first_node_in_group("player")
	if p_for_crit != null and p_for_crit.has_method("roll_crit_dot"):
		var crit_d: Dictionary = p_for_crit.roll_crit_dot(tick_dmg)
		tick_dmg = float(crit_d.get("dmg", tick_dmg))
		if bool(crit_d.get("crit", false)):
			CritFeedback.mark_next_hit_crit(parent)
	var was_alive: bool = (not ("hp" in parent)) or float(parent.hp) > 0.0
	parent.take_damage(tick_dmg)
	_notify_player_dmg_kill(tick_dmg, source_id, was_alive, parent)
	_apply_splash(parent as Node2D, tick_dmg)


func _apply_splash(source: Node2D, tick_dmg: float) -> void:
	# Procura os SPLASH_TARGETS inimigos vivos mais próximos do queimando
	# (dentro de SPLASH_RADIUS) e aplica SPLASH_DAMAGE_MULT × tick_dmg em cada.
	# Não propaga burn nem aplica status — só dano direto.
	if source == null:
		return
	var splash_dmg: float = tick_dmg * SPLASH_DAMAGE_MULT
	if splash_dmg <= 0.0:
		return
	var src_pos: Vector2 = source.global_position
	var radius_sq: float = SPLASH_RADIUS * SPLASH_RADIUS
	# Coleta candidatos com distância pra ordenar.
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == source or not is_instance_valid(e) or not (e is Node2D):
			continue
		if not e.has_method("take_damage"):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		if "hp" in e and float(e.hp) <= 0.0:
			continue
		var d_sq: float = (e as Node2D).global_position.distance_squared_to(src_pos)
		if d_sq > radius_sq:
			continue
		candidates.append({"node": e, "d_sq": d_sq})
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a["d_sq"] < b["d_sq"])
	var n: int = mini(SPLASH_TARGETS, candidates.size())
	# Splash herda o crit do tick primário (tick_dmg já vem multiplicado). Não
	# rola crit independente por alvo — convenção do projeto (ting_turret,
	# frostwisp) pra evitar duplicação de chance.
	for i in n:
		var target: Node = candidates[i]["node"]
		if not is_instance_valid(target):
			continue
		var t_alive: bool = (not ("hp" in target)) or float(target.hp) > 0.0
		target.take_damage(splash_dmg)
		_notify_player_dmg_kill(splash_dmg, source_id, t_alive, target)


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
	_notify_player_dmg_kill(final_bonus_damage, source_id, was_alive, parent)


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
