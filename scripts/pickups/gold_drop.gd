class_name GoldDrop
extends RefCounted

# Helper estático pra inimigos dropar gold ao morrer.
# Cada inimigo chama GoldDrop.try_drop(...) no death — só não dropa quem não deveria
# (ex: inseto invocado, pra não virar exploit do mago invocador).

const PICKUP_SPREAD: float = 22.0
# Bônus de drop chance da Chuva de Coins (excalidraw): L1 +5%, L2 +7%, L3+ +9%.
# Aditivo absoluto sobre a chance base do inimigo.
const GOLD_MAGNET_BONUS_L1: float = 0.05
const GOLD_MAGNET_BONUS_PER_LEVEL: float = 0.02


static func try_drop(world: Node, scene: PackedScene, position: Vector2,
		chance: float, min_amount: int, max_amount: int) -> void:
	if scene == null or world == null or chance <= 0.0:
		return
	# Player com Chuva de Coins: bonus aditivo de drop chance escala por nível.
	# L1 = +5%, L2 = +7%, L3+ = +9% (capa em L3 — L4 só puxa do mapa todo).
	var player := world.get_tree().get_first_node_in_group("player")
	if player != null:
		var lvl: int = int(player.get("gold_magnet_level"))
		if lvl >= 1:
			chance += GOLD_MAGNET_BONUS_L1
			chance += GOLD_MAGNET_BONUS_PER_LEVEL * float(mini(lvl - 1, 2))
	if randf() > chance:
		return
	var amount: int = randi_range(maxi(min_amount, 1), maxi(max_amount, min_amount))
	for i in amount:
		var coin: Node2D = scene.instantiate()
		world.add_child(coin)
		var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
			randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
		coin.global_position = position + off
	# Notifica o wave_manager pro pity system de wave 1.
	var wm := world.get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("notify_coin_dropped"):
		wm.notify_coin_dropped(amount)
