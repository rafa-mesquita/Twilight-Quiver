extends Area2D

@export var speed: float = 165.0
@export var lifetime: float = 2.5
@export var damage: float = 15.0
# Identificador da fonte pro stats_damage_taken_by_source do player. Cada
# spawner pode sobrescrever — ex: fire_mage seta "fire_mage", mage_monkey
# seta "mage_monkey".
@export var source_id: String = "mage"
@export var trail_max_points: int = 14
@export var redirect_strength: float = 0.45  # desvio na metade (0 = sem desvio, 1 = trava no player)
@export var final_redirect_strength: float = 0.85  # trava forte quando perto
@export var final_redirect_distance: float = 5.0  # px do alvo pra disparar lock-on final
@export var hit_effect_scene: PackedScene

# Origem do node fica no chão (pra Y-sort certo); visual fica 24px acima.
const VISUAL_OFFSET: Vector2 = Vector2(0, -24)
# Offset do alvo (peito do player) no espaço do nó: visual mira em player.y - 12,
# então node mira em player.y - 12 - VISUAL_OFFSET.y = player.y + 12.
const PLAYER_NODE_TARGET_OFFSET: Vector2 = Vector2(0, 12)

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var trail: Line2D = get_node_or_null("Trail")
@onready var shoot_sound: AudioStreamPlayer2D = get_node_or_null("ShootSound")

var direction: Vector2 = Vector2.RIGHT
var player: Node2D
var spawn_position: Vector2 = Vector2.ZERO
var halfway_distance: float = -1.0
var has_redirected_halfway: bool = false
var has_redirected_final: bool = false
# Maldição: setado pelo mage convertido. Inverte alvo (mira em enemy, ignora allies).
var is_ally_source: bool = false
# Lv3+ da Maldição: aplica CurseDebuff no alvo (setado pelo source ao spawnar).
var apply_curse: bool = false
# Boss gorila: projétil ignora aliados/estruturas e só bate no player.
var pierce_allies: bool = false
# Multiplicador de dano que o boss aplica em aliados (= +80% extra). Usado
# só na lógica de pierce_allies — não afeta dano no player nem em enemies.
const BOSS_ALLY_DMG_MULT: float = 1.8


func _ready() -> void:
	# Grupo "mage_projectile" usado pelo Woodwarden pra detectar projéteis a
	# interceptar no raio de escudo humano.
	add_to_group("mage_projectile")
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_die)
	player = get_tree().get_first_node_in_group("player")
	if shoot_sound != null:
		shoot_sound.play()
		var sound_ref: AudioStreamPlayer2D = shoot_sound
		get_tree().create_timer(4.0).timeout.connect(func() -> void:
			if is_instance_valid(sound_ref):
				sound_ref.stop()
		)


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	spawn_position = global_position
	if player != null and is_instance_valid(player):
		var target := player.global_position + PLAYER_NODE_TARGET_OFFSET
		halfway_distance = spawn_position.distance_to(target) * 0.5
	if sprite != null:
		sprite.rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position + VISUAL_OFFSET)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	# Mago convertido: pula o redirect (anda em linha reta na direção setada).
	if is_ally_source:
		if trail != null:
			trail.add_point(global_position + VISUAL_OFFSET)
			while trail.get_point_count() > trail_max_points:
				trail.remove_point(0)
		return
	if not has_redirected_halfway and halfway_distance > 0.0:
		if spawn_position.distance_to(global_position) >= halfway_distance:
			has_redirected_halfway = true
			_redirect_toward_player(redirect_strength)
	if not has_redirected_final and player != null and is_instance_valid(player):
		var target := player.global_position + PLAYER_NODE_TARGET_OFFSET
		if global_position.distance_to(target) <= final_redirect_distance:
			has_redirected_final = true
			_redirect_toward_player(final_redirect_strength)
	if trail != null:
		trail.add_point(global_position + VISUAL_OFFSET)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func magnet_to(target_node: Node2D) -> void:
	# Chamado pelo Woodwarden (escudo humano) — desvia o projétil pro warden
	# e desabilita os redirects internos pra ele não voltar a mirar no player.
	# Quando o projétil colidir com o warden, body_entered dispara o dano normal.
	if target_node == null or not is_instance_valid(target_node):
		return
	has_redirected_halfway = true
	has_redirected_final = true
	var to_target: Vector2 = (target_node.global_position - global_position).normalized()
	if to_target.length_squared() < 0.001:
		return
	direction = to_target
	if sprite != null:
		sprite.rotation = direction.angle()


func _redirect_toward_player(strength: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	var target := player.global_position + PLAYER_NODE_TARGET_OFFSET
	var to_target := (target - global_position).normalized()
	direction = direction.lerp(to_target, strength).normalized()
	if sprite != null:
		sprite.rotation = direction.angle()


func _on_body_entered(body: Node) -> void:
	if is_ally_source:
		# Mago convertido: ignora aliados (player + tank_ally + structure), bate em enemy.
		if body.is_in_group("ally") or body.is_in_group("player") or body.is_in_group("structure"):
			return
	else:
		# Mago original: friendly fire bloqueado entre enemies.
		if body.is_in_group("enemy"):
			return
		# Boss gorila: atravessa aliados/estruturas mas ainda aplica dano de
		# passagem (o projétil segue rumo ao player). Boss dá +80% de dano em
		# aliados (BOSS_ALLY_DMG_MULT) — ataque é forte contra eles.
		if pierce_allies and (body.is_in_group("ally") or body.is_in_group("structure")):
			var pierce_target: Node = _find_damageable(body)
			if pierce_target != null:
				# Pierce sempre acerta ally/structure (não-player) — sem source_id.
				# Boss dá +80% de dano em aliados (BOSS_ALLY_DMG_MULT).
				pierce_target.take_damage(damage * BOSS_ALLY_DMG_MULT)
			return
	var target: Node = _find_damageable(body)
	if target != null:
		# Curse ANTES do take_damage pra contar na conversão se matar.
		if apply_curse:
			CurseAllyHelper.apply_ally_curse_on_damage(target, self)
		if target.is_in_group("player"):
			target.take_damage(damage, source_id)
		else:
			target.take_damage(damage)
			# Mago convertido pela Maldição: contabiliza dano no breakdown do
			# painel TAB sob "curse_ally" (somado entre todos os aliados profanos).
			if is_ally_source and player != null and player.has_method("notify_damage_dealt_by_source"):
				player.notify_damage_dealt_by_source(damage, "curse_ally")
	_spawn_hit_effect()
	_die()


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.has_method("take_damage"):
			return n
		n = n.get_parent()
	return null


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(fx)
	# Visual do projétil fica em VISUAL_OFFSET acima da origem; spawna efeito ali
	# pra impacto bater no ponto que o player vê.
	fx.global_position = global_position + VISUAL_OFFSET


func _die() -> void:
	if is_inside_tree():
		queue_free()
