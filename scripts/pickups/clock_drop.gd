class_name ClockDrop
extends RefCounted

# Helper estático pro drop do "Relógio de Reset" (pickup que zera o cooldown de
# todas as skills ativas do player). Cada inimigo chama ClockDrop.try_drop(...)
# no death, logo após o GoldDrop — assim herda as exclusões anti-exploit do gold
# (insetos invocados não chamam gold/clock; macacos do mini-mago ficam no guard).
#
# Gate: só dropa se o player JÁ tem alguma skill ATIVÁVEL de Espaço (dash/
# esquivando/fenda) ou Q — senão o relógio não teria cooldown pra reduzir.
# ⚠ Os elementais só viram skill de Q a partir do nível que destrava o ativável
# (fogo lv3, maldição lv4, pedra lv3, cadeia lv3, gelo/time-freeze lv4). Ter o
# elemental no lv1-2 (passivo) NÃO conta — era o bug de dropar "sem skill".
# ⚠ O Esquivando só ganha a skill do espaço no lv2 (ESQUIVANDO_ABILITY_MIN_LEVEL);
# no lv1 é só passivo (stacks/dodge), sem cooldown pra resetar.
#
# Dev: GameState.dev_clock_always_drop força chance 100% e ignora o gate (teste).

const CLOCK_SCENE: PackedScene = preload("res://scenes/pickups/clock.tscn")
const DROP_CHANCE: float = 0.015
const PICKUP_SPREAD: float = 16.0
# id do upgrade → nível mínimo pra contar como "skill ativável". Dash/fenda valem
# do lv1; esquivando só no lv2 (libera a skill do espaço); Q (elementais) só no
# nível que libera o ativo.
const ACTIVE_SKILL_REQS: Dictionary = {
	"dash": 1, "esquivando": 2, "fenda": 1,
	"fire_arrow": 3, "curse_arrow": 4, "stone_arrow": 3,
	"chain_lightning": 3, "ice_arrow": 4,
}


static func try_drop(world: Node, drop_position: Vector2) -> void:
	if world == null:
		return
	var player := world.get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var force: bool = bool(GameState.dev_clock_always_drop)
	# Gate de skill (pulado no modo dev de drop forçado).
	if not force and not _player_has_active_skill(player):
		return
	# Cajado do Crepúsculo (item) sobe a chance pra 4% via override no player.
	var base_chance: float = DROP_CHANCE
	if player.has_method("clock_drop_chance_override"):
		var ov: float = float(player.clock_drop_chance_override())
		if ov > 0.0:
			base_chance = ov
	var chance: float = 1.0 if force else base_chance
	if randf() > chance:
		return

	var clock: Node2D = CLOCK_SCENE.instantiate()
	world.add_child(clock)
	var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
		randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
	clock.global_position = drop_position + off


static func _player_has_active_skill(player: Node) -> bool:
	if not player.has_method("get_upgrade_count"):
		return false
	for id in ACTIVE_SKILL_REQS:
		if player.get_upgrade_count(id) >= int(ACTIVE_SKILL_REQS[id]):
			return true
	return false
