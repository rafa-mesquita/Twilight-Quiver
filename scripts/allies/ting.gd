extends CharacterBody2D

# Mecânico Ting (esquilo aliado, 4 níveis). Vagueia pelo mapa, periodicamente
# para num spot estratégico e constroi uma torreta que atira nos inimigos.
# Sem HP, não-targetável.
#
# L1: 1 ting, deploy a cada 15s, torreta dura 8s, atira a cada 2s
# L2: torreta dá 10% AoE secundário e dura 9s
# L3: deploy a cada 13s, atk cd da torreta 1.7s
# L4: 2 tings (gerenciado pelo player)

@export var speed: float = 50.0
# Intervalo entre deploys de torreta. Player sobrescreve por nível.
@export var deploy_interval: float = 15.0
# Lifetime/atk_cd/aoe da próxima torreta — player sobrescreve por nível.
@export var turret_lifetime: float = 8.0
@export var turret_attack_cooldown: float = 2.0
@export var turret_aoe_pct: float = 0.0
@export var turret_scene: PackedScene
# Mesmo retângulo da Capivara — limite de wander dentro do mapa interno.
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _waypoint: Vector2 = Vector2.ZERO
var _deploy_cd: float = 0.0
var _is_building: bool = false
# True quando estamos perto do deploy (últimos _BUILD_APPROACH_TIME segundos)
# e o ting deve estar caminhando pro spot de combate. False = fase "safe",
# perto do player mas fora do meio dos inimigos.
var _is_approaching: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()


func _ready() -> void:
	add_to_group("ally")
	add_to_group("ting")
	sprite.animation_finished.connect(_on_anim_finished)
	_deploy_cd = deploy_interval
	_pick_new_waypoint()
	sprite.play("walk")


func _physics_process(delta: float) -> void:
	if _deploy_cd > 0.0:
		_deploy_cd = maxf(_deploy_cd - delta, 0.0)
	# Transição safe → approach: quando entra na janela final, repica waypoint
	# (combat spot). Transição reversa só ocorre depois do build (_finish_build).
	var should_approach: bool = _deploy_cd <= _BUILD_APPROACH_TIME
	if should_approach and not _is_approaching:
		_is_approaching = true
		_pick_new_waypoint()
	# Durante "build" o ting fica parado.
	if _is_building:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Hora de construir a torreta?
	if _deploy_cd <= 0.0:
		_start_build()
		return
	# Wander pro waypoint.
	var to_wp: Vector2 = _waypoint - global_position
	var dist: float = to_wp.length()
	if dist <= arrive_dist:
		_pick_new_waypoint()
		to_wp = _waypoint - global_position
		dist = to_wp.length()
	var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_wp / dist
	# Anti-stuck: redireciona lateral se ficou preso em árvore/parede.
	if dir.length_squared() > 0.001:
		dir = _anti_stuck.resolve(dir, delta)
	velocity = dir * speed
	move_and_slide()
	_anti_stuck.update(self, _waypoint, dir.length_squared() > 0.001, delta)
	if absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0
	if sprite.animation != "walk":
		sprite.play("walk")


func _pick_new_waypoint() -> void:
	# Duas fases:
	# - APPROACH (deploy_cd <= 2.5s): spot de combate dentro do alcance da torreta.
	# - SAFE (resto do tempo): fica perto do player mas longe dos inimigos, pra
	#   não atrapalhar o jogador andando no meio do tiroteio.
	var spot: Vector2
	if _is_approaching:
		spot = _find_combat_spot()
	else:
		spot = _find_safe_spot()
	if spot.x == INF:
		spot = Vector2(
			randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
			randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
		)
	_waypoint = _clamp_to_bounds(spot)


# Alcance efetivo da torreta (mirror de ting_turret.gd attack_range = 180).
# Usado pra contar quantos inimigos um spot candidato cobre. Usamos 0.7×
# pra deixar margem — se um inimigo está a 175px do spot, basta ele se mover
# pouco e sai do range. 126px garante que o inimigo fica em range por um tempo.
const _TURRET_EFFECTIVE_RANGE: float = 126.0
# Quão à frente do player olhar pra prever pra onde ele vai (segundos).
const _PLAYER_LOOKAHEAD: float = 1.5
const _COMBAT_SPOT_SAMPLES: int = 12
# Tempo antes do deploy em que o ting começa a ir pro combate. Resto do CD
# fica em fase "safe" longe da luta.
const _BUILD_APPROACH_TIME: float = 2.5
# Distância mínima de qualquer inimigo na fase safe — abaixo disso, o spot é
# rejeitado como "no meio da luta".
const _SAFE_MIN_ENEMY_DIST: float = 140.0
# Quão longe do player o ting tenta ficar na fase safe (centro do raio de
# spawn dos samples).
const _SAFE_PLAYER_DIST: float = 90.0
const _SAFE_SPOT_SAMPLES: int = 10


func _find_combat_spot() -> Vector2:
	var enemies: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node2D and not e.is_queued_for_deletion():
			enemies.append(e)
	if enemies.is_empty():
		return Vector2(INF, INF)
	var player: Node = get_tree().get_first_node_in_group("player")
	var player_pos: Vector2 = global_position
	var player_vel: Vector2 = Vector2.ZERO
	if player != null and player is Node2D:
		player_pos = (player as Node2D).global_position
		if "velocity" in player:
			player_vel = player.velocity
	# Boss prioritário: em wave de boss (mage_monkey vivo), torreta vai num spot
	# encostado nele pra cobrir o boss + os minions ao redor. Ignora shield —
	# torreta dura 8s, então mesmo se o boss tá protegido agora ela vai pegar
	# ele quando o shield cair. Posição entre player e boss pra ting não passar
	# pelo boss e pra torreta ficar do lado seguro.
	var boss: Node2D = _find_boss()
	if boss != null:
		var to_player: Vector2 = player_pos - boss.global_position
		var dir_off: Vector2
		if to_player.length_squared() < 1.0:
			dir_off = Vector2.RIGHT
		else:
			dir_off = to_player.normalized()
		# 90px do boss = bem dentro do range (126), com folga pro boss se mover
		# um pouco sem sair. Pequeno jitter pra múltiplos tings (lv4) não
		# stackarem no mesmo ponto.
		var jitter: float = randf_range(-30.0, 30.0)
		var perp: Vector2 = Vector2(-dir_off.y, dir_off.x)
		return _clamp_to_bounds(boss.global_position + dir_off * 90.0 + perp * jitter)
	# Onde o player provavelmente vai estar quando o ting chegar lá.
	var predicted_pos: Vector2 = player_pos + player_vel * _PLAYER_LOOKAHEAD
	var best_pos: Vector2 = Vector2(INF, INF)
	var best_score: float = -INF
	for i in _COMBAT_SPOT_SAMPLES:
		var sample: Vector2
		# 2/3 dos samples enviesados pra rota prevista do player; 1/3 perto de
		# um inimigo aleatório (cobre caso "player parado mas inimigos longe").
		if i < 8:
			var angle: float = randf() * TAU
			var radius: float = randf_range(20.0, 90.0)
			sample = predicted_pos + Vector2(cos(angle), sin(angle)) * radius
		else:
			var e: Node2D = enemies[randi() % enemies.size()]
			var angle2: float = randf() * TAU
			var radius2: float = randf_range(40.0, 100.0)
			sample = e.global_position + Vector2(cos(angle2), sin(angle2)) * radius2
		sample = _clamp_to_bounds(sample)
		var hits: int = 0
		for e2 in enemies:
			if sample.distance_to(e2.global_position) <= _TURRET_EFFECTIVE_RANGE:
				hits += 1
		if hits <= 0:
			continue
		# Score: mais inimigos em range = melhor. Penaliza distância à rota do
		# player levemente (peso 0.3) pra não ignorar clusters quando o player
		# está longe deles.
		var dist_penalty: float = sample.distance_to(predicted_pos) * 0.3
		var score: float = float(hits) * 100.0 - dist_penalty
		if score > best_score:
			best_score = score
			best_pos = sample
	# Fallback: nenhum sample teve inimigo em range. Joga o waypoint em cima do
	# inimigo mais próximo da rota prevista do player.
	if best_pos.x == INF:
		var nearest: Node2D = null
		var best_d: float = INF
		for e3 in enemies:
			var d: float = predicted_pos.distance_to(e3.global_position)
			if d < best_d:
				best_d = d
				nearest = e3
		if nearest != null:
			best_pos = nearest.global_position
	return best_pos


func _find_safe_spot() -> Vector2:
	# Fase safe: gira ao redor do player a uma distância confortável e rejeita
	# qualquer sample que esteja a menos de _SAFE_MIN_ENEMY_DIST de um inimigo.
	# Mantém o ting visível/perto do player mas FORA da zona de combate, então
	# ele não passa correndo entre os monstros enquanto espera o próximo build.
	var enemies: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node2D and not e.is_queued_for_deletion():
			enemies.append(e)
	var player: Node = get_tree().get_first_node_in_group("player")
	var anchor: Vector2 = global_position
	if player != null and player is Node2D:
		anchor = (player as Node2D).global_position
	# Sem inimigos: qualquer ponto perto do player serve.
	if enemies.is_empty():
		var ang0: float = randf() * TAU
		return _clamp_to_bounds(anchor + Vector2(cos(ang0), sin(ang0)) * _SAFE_PLAYER_DIST)
	var best_pos: Vector2 = Vector2(INF, INF)
	var best_min_dist: float = -1.0
	for i in _SAFE_SPOT_SAMPLES:
		var ang: float = randf() * TAU
		var rad: float = randf_range(_SAFE_PLAYER_DIST * 0.6, _SAFE_PLAYER_DIST * 1.4)
		var sample: Vector2 = anchor + Vector2(cos(ang), sin(ang)) * rad
		sample = _clamp_to_bounds(sample)
		# Distância ao inimigo mais próximo — queremos maximizar (mas pelo
		# menos _SAFE_MIN_ENEMY_DIST).
		var nearest_e: float = INF
		for e2 in enemies:
			var d: float = sample.distance_to(e2.global_position)
			if d < nearest_e:
				nearest_e = d
		if nearest_e < _SAFE_MIN_ENEMY_DIST:
			continue
		# Score: prefere o que está mais longe dos inimigos (clamp pra evitar
		# que ele saia voando pra longe se houver muito espaço vazio).
		if nearest_e > best_min_dist:
			best_min_dist = nearest_e
			best_pos = sample
	# Nenhum sample passou no mínimo (cercado de inimigos): pega o sample com
	# maior distância ao inimigo mais próximo, ignorando o threshold.
	if best_pos.x == INF:
		for j in _SAFE_SPOT_SAMPLES:
			var ang2: float = randf() * TAU
			var rad2: float = randf_range(_SAFE_PLAYER_DIST * 0.8, _SAFE_PLAYER_DIST * 1.6)
			var s: Vector2 = _clamp_to_bounds(anchor + Vector2(cos(ang2), sin(ang2)) * rad2)
			var ne: float = INF
			for e3 in enemies:
				var dd: float = s.distance_to(e3.global_position)
				if dd < ne:
					ne = dd
			if ne > best_min_dist:
				best_min_dist = ne
				best_pos = s
	return best_pos


func _find_boss() -> Node2D:
	# Retorna o primeiro boss vivo na cena, com ou sem shield (torreta dura
	# bastante e pega o boss quando o shield cai). Null se não há boss.
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		if (b as Node).is_queued_for_deletion():
			continue
		if "hp" in b and float(b.hp) <= 0.0:
			continue
		return b as Node2D
	return null


func _clamp_to_bounds(p: Vector2) -> Vector2:
	return Vector2(
		clampf(p.x, wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		clampf(p.y, wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _start_build() -> void:
	_is_building = true
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("build"):
		sprite.play("build")
	else:
		_finish_build()


func _on_anim_finished() -> void:
	if sprite.animation == "build":
		_finish_build()


func _finish_build() -> void:
	_spawn_turret()
	_deploy_cd = deploy_interval
	_is_building = false
	# Volta pra fase safe: sai do meio dos inimigos.
	_is_approaching = false
	_pick_new_waypoint()
	sprite.play("walk")


func _spawn_turret() -> void:
	if turret_scene == null:
		return
	var t: Node2D = turret_scene.instantiate()
	if "lifetime" in t:
		t.lifetime = turret_lifetime
	if "attack_cooldown_base" in t:
		t.attack_cooldown_base = turret_attack_cooldown
	if "aoe_damage_pct" in t:
		t.aoe_damage_pct = turret_aoe_pct
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(t)
	t.global_position = global_position
