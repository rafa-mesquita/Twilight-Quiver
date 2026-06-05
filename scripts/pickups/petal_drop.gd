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
	if randf() > DROP_CHANCE:
		return
	var petal: Node2D = PETAL_SCENE.instantiate()
	world.add_child(petal)
	var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
		randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
	petal.global_position = drop_position + off
