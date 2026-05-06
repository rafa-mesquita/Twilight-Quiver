class_name EnemySeparation
extends RefCounted

# Helper estático: calcula um vetor de "separação" pra empurrar inimigos pra
# longe um do outro, evitando que empilhem visualmente. Cada inimigo soma esse
# vetor à sua AI velocity. Quanto mais perto outro inimigo, mais forte o push.

static func compute(node: Node2D, radius: float = 14.0, strength: float = 25.0) -> Vector2:
	if not is_instance_valid(node):
		return Vector2.ZERO
	var total: Vector2 = Vector2.ZERO
	var count: int = 0
	for other in node.get_tree().get_nodes_in_group("enemy"):
		if other == node or not is_instance_valid(other):
			continue
		var diff: Vector2 = node.global_position - (other as Node2D).global_position
		var dist: float = diff.length()
		if dist <= 0.001 or dist >= radius:
			continue
		# Falloff linear: empurra mais forte quanto mais perto.
		var falloff: float = 1.0 - dist / radius
		total += diff.normalized() * falloff
		count += 1
	if count == 0:
		return Vector2.ZERO
	return total * strength
