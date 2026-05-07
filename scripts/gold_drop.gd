class_name GoldDrop
extends RefCounted

# Helper estático pra inimigos dropar gold ao morrer.
# Cada inimigo chama GoldDrop.try_drop(...) no death — só não dropa quem não deveria
# (ex: inseto invocado, pra não virar exploit do mago invocador).

const PICKUP_SPREAD: float = 14.0
# Bônus de drop chance dado pelo upgrade Imã de Gold (excalidraw: "+2% chance de drop").
const GOLD_MAGNET_DROP_BONUS: float = 0.02


static func try_drop(world: Node, scene: PackedScene, position: Vector2,
		chance: float, min_amount: int, max_amount: int) -> void:
	if scene == null or world == null or chance <= 0.0:
		return
	# Player com Imã de Gold: +2% absoluto na chance de drop.
	var player := world.get_tree().get_first_node_in_group("player")
	if player != null and player.get("has_gold_magnet") == true:
		chance += GOLD_MAGNET_DROP_BONUS
	if randf() > chance:
		return
	var amount: int = randi_range(maxi(min_amount, 1), maxi(max_amount, min_amount))
	for i in amount:
		var coin: Node2D = scene.instantiate()
		world.add_child(coin)
		var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
			randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
		coin.global_position = position + off
