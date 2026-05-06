class_name GoldDrop
extends RefCounted

# Helper estático pra inimigos dropar gold ao morrer.
# Cada inimigo chama GoldDrop.try_drop(...) no death — só não dropa quem não deveria
# (ex: inseto invocado, pra não virar exploit do mago invocador).

const PICKUP_SPREAD: float = 14.0


static func try_drop(world: Node, scene: PackedScene, position: Vector2,
		chance: float, min_amount: int, max_amount: int) -> void:
	if scene == null or world == null or chance <= 0.0:
		return
	if randf() > chance:
		return
	var amount: int = randi_range(maxi(min_amount, 1), maxi(max_amount, min_amount))
	for i in amount:
		var coin: Node2D = scene.instantiate()
		world.add_child(coin)
		var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
			randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
		coin.global_position = position + off
