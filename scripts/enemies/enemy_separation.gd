class_name EnemySeparation
extends RefCounted

# Helper estático: calcula um vetor de "separação" pra empurrar inimigos pra
# longe um do outro, evitando que empilhem visualmente. Cada inimigo soma esse
# vetor à sua AI velocity. Quanto mais perto outro inimigo, mais forte o push.
#
# Otimizações (0.5.7):
# - Cache estático por instance_id com TTL de CACHE_TTL_SEC. Cada inimigo
#   recalcula só a cada ~100ms em vez de toda frame. Sem isso, com 50+ inimigos
#   o O(N²) por frame derrubava o FPS em PCs fracos.
# - distance_squared first — evita sqrt nos inimigos fora do raio (maioria).

const CACHE_TTL_SEC: float = 0.1
const _CACHE_CLEANUP_THRESHOLD: int = 100  # cleanup quando dict passar disso

static var _cache: Dictionary = {}


static func compute(node: Node2D, radius: float = 14.0, strength: float = 25.0) -> Vector2:
	if not is_instance_valid(node):
		return Vector2.ZERO
	var id: int = node.get_instance_id()
	var now: float = Time.get_ticks_msec() / 1000.0
	var cached: Dictionary = _cache.get(id, {})
	if not cached.is_empty() and float(cached.get("expires", 0.0)) > now:
		return cached.get("value", Vector2.ZERO)
	var total: Vector2 = Vector2.ZERO
	var count: int = 0
	var radius_sq: float = radius * radius
	var my_pos: Vector2 = node.global_position
	for other in node.get_tree().get_nodes_in_group("enemy"):
		if other == node or not is_instance_valid(other):
			continue
		var diff: Vector2 = my_pos - (other as Node2D).global_position
		var dist_sq: float = diff.length_squared()
		# Fora do raio? Pula sem calcular sqrt. Maioria das comparações entra aqui.
		if dist_sq <= 0.000001 or dist_sq >= radius_sq:
			continue
		var dist: float = sqrt(dist_sq)
		var falloff: float = 1.0 - dist / radius
		# diff.normalized() = diff/dist — economiza um normalize() call.
		total += (diff / dist) * falloff
		count += 1
	var result: Vector2 = total * strength if count > 0 else Vector2.ZERO
	_cache[id] = {"value": result, "expires": now + CACHE_TTL_SEC}
	if _cache.size() > _CACHE_CLEANUP_THRESHOLD:
		_cleanup_expired(now)
	return result


static func _cleanup_expired(now: float) -> void:
	# Remove entradas muito antigas (2× TTL) — evita o dict acumular ids de
	# inimigos já queue_free'd indefinidamente.
	var stale: float = now - CACHE_TTL_SEC * 2.0
	var to_remove: Array = []
	for k in _cache.keys():
		if float(_cache[k].get("expires", 0.0)) < stale:
			to_remove.append(k)
	for k in to_remove:
		_cache.erase(k)
