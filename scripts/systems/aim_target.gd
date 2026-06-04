class_name AimTarget
extends RefCounted

# Helper estático pra MIRA/perseguição dos inimigos. Normalmente o alvo é mirado
# pela posição/velocidade REAIS. Mas alguns alvos (o player durante o blink da
# Fenda Crepuscular) expõem get_aim_position()/get_aim_velocity() pra "congelar"
# a mira num ponto antigo — assim chargers correm pro lugar errado e magos fincam
# o telegraph onde o player ESTAVA. Os inimigos leem a posição/velocidade de mira
# por aqui em vez de acessar global_position/velocity direto.
#
# Só a MIRA é afetada: colisão/contato continuam usando a posição real (o player
# fica imune a dano durante o blink, então atravessar inimigos não machuca).


static func pos(target: Node2D) -> Vector2:
	if target == null:
		return Vector2.ZERO
	if target.has_method("get_aim_position"):
		return target.get_aim_position()
	return target.global_position


static func vel(target: Node2D) -> Vector2:
	if target == null:
		return Vector2.ZERO
	if target.has_method("get_aim_velocity"):
		return target.get_aim_velocity()
	if "velocity" in target:
		return target.velocity
	return Vector2.ZERO
