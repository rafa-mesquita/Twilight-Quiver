class_name ClockDrop
extends RefCounted

# Helper estático pro drop do "Relógio de Reset" (pickup que zera o cooldown de
# todas as skills ativas do player). Cada inimigo chama ClockDrop.try_drop(...)
# no death, logo após o GoldDrop — assim herda as exclusões anti-exploit do gold
# (insetos invocados não chamam gold/clock; macacos do mini-mago ficam no guard).
#
# Gate: só dropa se o player JÁ tem alguma skill ativa de Espaço (dash/esquivando/
# fenda) ou Q (fogo/maldição/pedra) — senão o relógio não teria o que resetar.
#
# Dev: GameState.dev_clock_always_drop força chance 100% e ignora o gate (teste).

const CLOCK_SCENE: PackedScene = preload("res://scenes/pickups/clock.tscn")
const DROP_CHANCE: float = 0.04
const PICKUP_SPREAD: float = 16.0
# Skills ativas que o relógio reseta — se o player tem QUALQUER uma, libera o drop.
const ACTIVE_SKILL_IDS: Array[String] = [
	"dash", "esquivando", "fenda", "fire_arrow", "curse_arrow", "stone_arrow",
]


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
	var chance: float = 1.0 if force else DROP_CHANCE
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
	for id in ACTIVE_SKILL_IDS:
		if player.get_upgrade_count(id) > 0:
			return true
	return false
