class_name CurseAllyHelper
extends RefCounted

# Helper estático pra converter inimigos em aliados via Maldição (lv2-4).
# Chamado por cada enemy.take_damage no momento da morte.
# Conversão: switches groups (enemy → ally + tank_ally), restaura HP, tinta
# sprite roxo, seta `is_curse_ally = true` (que cada enemy AI usa pra inverter
# o pick_target).
#
# Lv3+: quando aliados (incl. converted) causam dano, aplicam CurseDebuff no
# alvo. Helper expõe `apply_ally_curse_on_damage(target, player)` pra ser
# chamado em cada hit de aliado.

const PURPLE_ALLY_TINT: Color = Color(0.85, 0.55, 1.0, 1.0)
# Cor verde padrão dos aliados (mesmo fg_color do woodwarden e arrow_tower).
const ALLY_HP_COLOR: Color = Color(0.4627451, 0.654902, 0.29803923, 1)
const SUMMON_EFFECT_SCENE: PackedScene = preload("res://scenes/summon_effect.tscn")
# Som de impacto de aliados removido — bug irreproduzível causava som contínuo
# em certas situações. Cada enemy mantém seu próprio damage_sound (que é filho
# do enemy agora, então morre junto).


static func try_convert_on_death(enemy: Node) -> bool:
	# Retorna true se o enemy foi convertido (não deve dar queue_free).
	# Verifica se enemy tem CurseDebuff ativo + roll na chance do player.
	if not is_instance_valid(enemy):
		return false
	if not _has_curse_debuff(enemy):
		return false
	var player := enemy.get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("curse_convert_chance"):
		return false
	var chance: float = player.curse_convert_chance()
	if chance <= 0.0 or randf() >= chance:
		return false
	convert_to_ally(enemy)
	return true


static func convert_to_ally(enemy: Node) -> void:
	# Restaura full HP, switches grupos, tinta sprite roxo, seta flag.
	# Wave_manager rastreia via grupo "curse_ally" pra cleanup no fim da horda.
	if "max_hp" in enemy and "hp" in enemy:
		enemy.hp = enemy.max_hp
	if enemy.is_in_group("enemy"):
		enemy.remove_from_group("enemy")
	if not enemy.is_in_group("ally"):
		enemy.add_to_group("ally")
	if not enemy.is_in_group("tank_ally"):
		enemy.add_to_group("tank_ally")
	if not enemy.is_in_group("curse_ally"):
		enemy.add_to_group("curse_ally")
	if "is_curse_ally" in enemy:
		enemy.is_curse_ally = true
	# Cleanup de estado "do enemy": para audio players de damage_sound que estavam
	# tocando (filhos do enemy agora) + remove CurseDebuff restaurando speed.
	# Sem isso, o aliado convertido herda o som de dano da entidade anterior.
	for child in enemy.get_children():
		if child is CurseDebuff:
			(child as CurseDebuff).release()
		elif child is AudioStreamPlayer2D:
			(child as AudioStreamPlayer2D).stop()
			child.queue_free()
	# Tint sprite roxo (multiplicativo). Procura AnimatedSprite2D ou Sprite2D no subtree.
	var sprite: Node2D = _find_sprite_in(enemy)
	if sprite is CanvasItem:
		(sprite as CanvasItem).modulate = PURPLE_ALLY_TINT
	# HP bar: troca cor pro verde de aliado (mesmo do woodwarden/torre) e refresca.
	if enemy.has_node("HpBar"):
		var bar: Node = enemy.get_node("HpBar")
		if "fg_color" in bar:
			bar.fg_color = ALLY_HP_COLOR
		var fg := bar.get_node_or_null("Fg")
		if fg is Polygon2D:
			(fg as Polygon2D).color = ALLY_HP_COLOR
		if bar.has_method("set_ratio"):
			bar.set_ratio(1.0)
	# Anima conversão com o mesmo summon effect lilás do summoner mage.
	_spawn_summon_effect(enemy)


static func _spawn_summon_effect(enemy: Node) -> void:
	if SUMMON_EFFECT_SCENE == null or not (enemy is Node2D):
		return
	var fx: Node = SUMMON_EFFECT_SCENE.instantiate()
	var world := enemy.get_tree().get_first_node_in_group("world")
	if world == null:
		world = enemy.get_tree().current_scene
	world.add_child(fx)
	if fx is Node2D:
		(fx as Node2D).global_position = (enemy as Node2D).global_position


static func apply_ally_curse_on_damage(target: Node, source: Node) -> void:
	# Lv3+: aliado que causa dano também aplica CurseDebuff no alvo.
	# `source` = quem atacou (woodwarden, torre, converted enemy, etc).
	if not is_instance_valid(target):
		return
	var player := target.get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if not ("curse_arrow_level" in player) or int(player.curse_arrow_level) < 3:
		return
	# Refresh debuff existente OU cria novo. Usa stats do nível atual do player.
	var dps: float = 4.0
	var dur: float = 4.0
	var slow: float = 0.65
	if player.has_method("_curse_dps"):
		dps = player._curse_dps()
	if player.has_method("_curse_duration"):
		dur = player._curse_duration()
	if player.has_method("_curse_slow_factor"):
		slow = player._curse_slow_factor()
	for child in target.get_children():
		if child is CurseDebuff:
			(child as CurseDebuff).refresh(dur, dps, slow)
			return
	var deb := CurseDebuff.new()
	deb.dps = dps
	deb.duration = dur
	deb.slow_factor = slow
	target.add_child(deb)


static func _has_curse_debuff(node: Node) -> bool:
	for child in node.get_children():
		if child is CurseDebuff:
			return true
	return false


static func _find_sprite_in(node: Node) -> Node2D:
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child as Node2D
	return null
