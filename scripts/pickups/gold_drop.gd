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
# Buffer extra além da borda da estrutura pra moeda não ficar grudada no
# pixel exato da colisão (player não consegue encostar o body).
const STRUCTURE_PUSHOUT_BUFFER: float = 6.0


static func try_drop(world: Node, scene: PackedScene, position: Vector2,
		chance: float, min_amount: int, max_amount: int) -> void:
	if scene == null or world == null or chance <= 0.0:
		return
	# Player com Chuva de Coins: bonus aditivo de drop chance escala por nível.
	# L1 = +5%, L2 = +7%, L3+ = +9% (capa em L3 — L4 só puxa do mapa todo).
	# Diamante: +1% extra por nível a partir do L2 (via gold_magnet_diamond_drop_bonus).
	var player := world.get_tree().get_first_node_in_group("player")
	if player != null:
		var lvl: int = int(player.get("gold_magnet_level"))
		if lvl >= 1:
			chance += GOLD_MAGNET_BONUS_L1
			chance += GOLD_MAGNET_BONUS_PER_LEVEL * float(mini(lvl - 1, 2))
		if player.has_method("gold_magnet_diamond_drop_bonus"):
			chance += float(player.gold_magnet_diamond_drop_bonus())
	if randf() > chance:
		return
	var amount: int = randi_range(maxi(min_amount, 1), maxi(max_amount, min_amount))
	# Cache dos footprints das estruturas em vez de queryar a cada moeda — quando
	# um inimigo morre encostado numa torre, várias moedas dropam no mesmo frame.
	var structure_rects: Array = _collect_structure_footprints(world)
	for i in amount:
		var coin: Node2D = scene.instantiate()
		world.add_child(coin)
		var off := Vector2(randf_range(-PICKUP_SPREAD, PICKUP_SPREAD),
			randf_range(-PICKUP_SPREAD * 0.5, PICKUP_SPREAD * 0.5))
		coin.global_position = _push_out_of_structures(position + off, structure_rects)
	# Notifica o wave_manager pro pity system de wave 1.
	var wm := world.get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("notify_coin_dropped"):
		wm.notify_coin_dropped(amount)


# Cada entry: { "center": Vector2 mundo, "half": Vector2 com buffer aplicado }.
# Só estruturas com Body/CollisionShape2D RectangleShape2D entram — outras (Area2D
# de fade, allies sem corpo bloqueante) são ignoradas.
static func _collect_structure_footprints(world: Node) -> Array:
	var rects: Array = []
	for s in world.get_tree().get_nodes_in_group("structure"):
		if not is_instance_valid(s) or not (s is Node2D):
			continue
		var body := (s as Node2D).get_node_or_null("Body") as Node2D
		if body == null:
			continue
		var col := body.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if col == null or not (col.shape is RectangleShape2D):
			continue
		var size: Vector2 = (col.shape as RectangleShape2D).size
		var center: Vector2 = (s as Node2D).global_position + body.position + col.position
		rects.append({
			"center": center,
			"half": size * 0.5 + Vector2(STRUCTURE_PUSHOUT_BUFFER, STRUCTURE_PUSHOUT_BUFFER),
		})
	return rects


# Se a posição cair dentro do footprint de alguma estrutura, empurra pro eixo
# de menor penetração (geralmente mantém a moeda perto do ponto de drop).
# Roda 2 passes pra cobrir o raro caso de torres adjacentes empurrarem em conflito.
static func _push_out_of_structures(pos: Vector2, rects: Array) -> Vector2:
	if rects.is_empty():
		return pos
	for _pass in 2:
		var moved: bool = false
		for r in rects:
			var center: Vector2 = r["center"]
			var half: Vector2 = r["half"]
			var dx: float = pos.x - center.x
			var dy: float = pos.y - center.y
			if absf(dx) >= half.x or absf(dy) >= half.y:
				continue
			var push_x: float = half.x - absf(dx)
			var push_y: float = half.y - absf(dy)
			if push_x < push_y:
				pos.x = center.x + (half.x if dx >= 0.0 else -half.x)
			else:
				pos.y = center.y + (half.y if dy >= 0.0 else -half.y)
			moved = true
		if not moved:
			break
	return pos
