class_name HeartDrop
extends RefCounted

# Helper estático pra inimigos dropar coração ao morrer.
# Só dropa se o player tem `life_steal_level > 0`. Chance e heal_pct escalam:
# - Stack 1: 12% chance, 20% heal
# - Stack 4: 27% chance, 35% heal
# Inseto NÃO chama (anti-exploit summoner farm), igual ao gold.
# Inimigos do contexto boss (grupo "boss" ou "boss_minion") têm -5% chance
# em todos os níveis pra evitar fountain durante a boss fight.

const PICKUP_SPREAD: float = 14.0
const BASE_CHANCE: float = 0.12
const CHANCE_PER_STACK: float = 0.05
const BASE_HEAL_PCT: float = 0.20
const HEAL_PCT_PER_STACK: float = 0.05
const BOSS_CONTEXT_CHANCE_PENALTY: float = 0.05
# Distância mínima de gold/coração já existente — evita pickups sobrepostos
# quando ambos dropam do mesmo inimigo.
const MIN_PICKUP_SEPARATION: float = 16.0
const PLACEMENT_ATTEMPTS: int = 12


static func try_drop(world: Node, scene: PackedScene, drop_position: Vector2,
		source: Node = null) -> void:
	if scene == null or world == null:
		return
	var player := world.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var level: int = 0
	if player.has_method("get_upgrade_count"):
		level = player.get_upgrade_count("life_steal")
	if level <= 0:
		return
	var chance: float = BASE_CHANCE + CHANCE_PER_STACK * float(level - 1)
	if source != null and (source.is_in_group("boss") or source.is_in_group("boss_minion")):
		chance = max(0.0, chance - BOSS_CONTEXT_CHANCE_PENALTY)
	if randf() > chance:
		return
	var heal_pct: float = BASE_HEAL_PCT + HEAL_PCT_PER_STACK * float(level - 1)
	var heart: Node2D = scene.instantiate()
	if "heal_pct" in heart:
		heart.heal_pct = heal_pct
	world.add_child(heart)
	heart.global_position = _find_non_overlapping_position(world, drop_position)


# Tenta achar um spot perto de drop_position que não esteja em cima de outro
# pickup (gold ou heart). Se não conseguir em PLACEMENT_ATTEMPTS, usa o último
# offset gerado mesmo (pickups vão sobrepor — fallback raro).
static func _find_non_overlapping_position(world: Node, base: Vector2) -> Vector2:
	var tree := world.get_tree()
	var existing: Array = []
	existing.append_array(tree.get_nodes_in_group("gold"))
	existing.append_array(tree.get_nodes_in_group("heart"))
	var candidate: Vector2 = base
	for i in PLACEMENT_ATTEMPTS:
		var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
			randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
		candidate = base + off
		var ok: bool = true
		for n in existing:
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			if (n as Node2D).global_position.distance_to(candidate) < MIN_PICKUP_SEPARATION:
				ok = false
				break
		if ok:
			return candidate
	return candidate
