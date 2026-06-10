class_name HeartDrop
extends RefCounted

# Helper estático pra inimigos dropar coração ao morrer.
# Só dropa se o player tem `life_steal_level > 0`. A chance escala +5%/stack
# (L1 12% → L4 27%). A cura é por nível (HEAL_PCT_BY_LEVEL), não-linear:
# - L1 12% chance, 15% cura
# - L2 17% chance, 20% cura
# - L3 22% chance, 25% cura
# - L4 27% chance, 25% cura (o L4 investe no pull de curas, não em +cura)
# O pull/magnetismo das curas vive no heart.gd e só liga no L4.
# Inseto NÃO chama (anti-exploit summoner farm), igual ao gold.
# Inimigos do contexto boss (grupo "boss" ou "boss_minion") têm chance × 0.75
# (25% mais raro) pra não virar fountain durante a boss fight. O mesmo
# multiplier é aplicado por coração no `drop_guaranteed` do boss.

const PICKUP_SPREAD: float = 14.0
const BASE_CHANCE: float = 0.12
const CHANCE_PER_STACK: float = 0.05
# Cura (% do HP máx) por nível do upgrade — índice = level - 1. Não-linear:
# L4 repete a cura do L3 (o ganho do L4 é o pull de curas, ver heart.gd).
const HEAL_PCT_BY_LEVEL: Array[float] = [0.15, 0.20, 0.25, 0.25]
# Multiplier global pra drops em contexto boss (boss + minions). 0.75 = 25% mais raro.
const BOSS_CONTEXT_DROP_MULTIPLIER: float = 0.75
# Distância mínima de gold/coração já existente — evita pickups sobrepostos
# quando ambos dropam do mesmo inimigo.
const MIN_PICKUP_SEPARATION: float = 16.0
const PLACEMENT_ATTEMPTS: int = 12


# Bosses: chama isto em vez de try_drop pra spawn garantido de N corações
# (sem random / penalty). Quantidade vinda do life_steal_level — recompensa
# proporcional ao investimento do player.
static func drop_guaranteed(world: Node, scene: PackedScene, drop_position: Vector2,
		count: int) -> void:
	if scene == null or world == null or count <= 0:
		return
	var player := world.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var level: int = 0
	if player.has_method("get_upgrade_count"):
		level = player.get_upgrade_count("life_steal")
	if level <= 0:
		return
	var heal_pct: float = _heal_pct_for_level(level)
	# Diamante do Mestre da Cura 💎: cura por hit ×1.3.
	if player.has_method("is_diamond") and player.is_diamond("life_steal"):
		heal_pct *= 1.3
	for i in count:
		# Boss = drop 25% mais raro: cada coração tem 75% de chance.
		if randf() > BOSS_CONTEXT_DROP_MULTIPLIER:
			continue
		var heart: Node2D = scene.instantiate()
		if "heal_pct" in heart:
			heart.heal_pct = heal_pct
		world.add_child(heart)
		heart.global_position = _find_non_overlapping_position(world, drop_position)


# Cura (% do HP máx) pro nível dado, com clamp nos limites do array.
static func _heal_pct_for_level(level: int) -> float:
	var idx: int = clampi(level - 1, 0, HEAL_PCT_BY_LEVEL.size() - 1)
	return HEAL_PCT_BY_LEVEL[idx]


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
		chance *= BOSS_CONTEXT_DROP_MULTIPLIER
	if randf() > chance:
		return
	var heal_pct: float = _heal_pct_for_level(level)
	# Diamante do Mestre da Cura 💎: cura por hit ×1.3.
	if player.has_method("is_diamond") and player.is_diamond("life_steal"):
		heal_pct *= 1.3
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
