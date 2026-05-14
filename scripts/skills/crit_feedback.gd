class_name CritFeedback
extends RefCounted

# Helper estático para o efeito visual de hit crítico (upgrade Flecha Crítica).
# Damage sites chamam `mark_next_hit_crit(target)` ANTES de `target.take_damage`.
# Cada enemy lê o flag `_crit_pending` no seu `_spawn_damage_number` (cor amarela)
# e `_flash_damage` (tint amarelo) e reseta o flag depois.

# #eea17d — laranja-pêssego, usado tanto no texto do número quanto no filtro do flash.
const CRIT_NUMBER_COLOR: Color = Color(0xee / 255.0, 0xa1 / 255.0, 0x7d / 255.0, 1.0)
const CRIT_FLASH_COLOR: Color = Color(0xee / 255.0, 0xa1 / 255.0, 0x7d / 255.0, 1.0)


static func mark_next_hit_crit(target: Node) -> void:
	# Seta o flag no target. Defensive: só seta se o property existe (enemies
	# que não foram instrumentados ignoram silenciosamente).
	if target != null and is_instance_valid(target) and "_crit_pending" in target:
		target._crit_pending = true
