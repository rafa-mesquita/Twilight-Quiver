class_name PetalDrop
extends RefCounted

# Drop raro de pétala por inimigo. Cada inimigo chama PetalDrop.try_drop(...) no
# death, junto do GoldDrop/ClockDrop — herda as exclusões anti-exploit do gold
# (inseto invocado não chama gold/clock/petal; macacos do mini-mago no guard).
# Pétala é a meta-moeda escassa (ver economia de pétalas / [[feature]] P1).

const PETAL_SCENE: PackedScene = preload("res://scenes/pickups/petal.tscn")
const DROP_CHANCE: float = 0.0075  # 0.75% por kill
const PICKUP_SPREAD: float = 16.0


static func try_drop(world: Node, drop_position: Vector2) -> void:
	if world == null:
		return
	# Boss rounds (waves 7/14/21) não dropam pétala — nem o boss nem os minions.
	# Pétala é meta-moeda de grind contínuo; rounds de boss são pico de inimigos
	# e dariam um surto desproporcional de drops.
	var tree := world.get_tree()
	if tree != null:
		var wm := tree.get_first_node_in_group("wave_manager")
		if wm != null and wm.has_method("is_boss_wave_now") and wm.is_boss_wave_now():
			return
	# Primavera Eterna (item): sobe a chance de drop por mob (override pra 2%).
	var chance: float = DROP_CHANCE
	var ov: float = InventoryItems.petal_drop_chance_override()
	if ov >= 0.0:
		chance = ov
	if randf() > chance:
		return
	var petal: Node2D = PETAL_SCENE.instantiate()
	world.add_child(petal)
	var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
		randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
	petal.global_position = drop_position + off
