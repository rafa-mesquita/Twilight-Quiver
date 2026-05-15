extends CharacterBody2D

# Aliado pet voador — estilo mob (similar ao woodwarden) MAS sem HP.
# Comportamento:
# - Sem inimigo perto: anda em formação ao redor do player
# - Inimigo no aggro_range: corre na direção dele
# - Em attack_range: para e atira projétil reto (slow area no impacto)
# - Sem hp / não-target: enemies ignoram (sem tank_ally), arrows do player passam
# - Cleanup no _die() do player (player faz queue_free direto)

@export var speed: float = 36.0
@export var attack_range: float = 110.0
@export var aggro_range: float = 140.0
@export var follow_min_distance: float = 24.0
@export var follow_max_distance: float = 44.0
@export var attack_cooldown: float = 2.3  # 1 ataque a cada 2.3s
@export var damage: float = 8.0
@export var projectile_scene: PackedScene
@export var phase_offset: float = 0.0  # diferencia múltiplos lenos no follow
@export var separation_radius: float = 18.0
@export var separation_strength: float = 30.0
@export var attack_sound: AudioStream
@export var attack_sound_volume_db: float = -22.0
# Só os primeiros 1.2s do mp3 são tocados.
const ATTACK_SOUND_DURATION: float = 1.2
# Voo: sprite/muzzle bobam em volta dos seus offsets-base (sombra fica fixa).
# Y muito negativo = leno alto, sombra no chão dá a noção de altura.
const SPRITE_BASE_OFFSET_Y: float = -32.0
const MUZZLE_BASE_OFFSET_Y: float = -14.0  # parte de baixo do corpo (era -22 = cabeça)
const BOB_HEIGHT: float = 2.0
const BOB_SPEED: float = 3.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var _player: Node2D = null
var _current_target: Node2D = null
var _is_attacking: bool = false
var _attack_cd_remaining: float = 0.0
var _bob_t: float = 0.0
# Pattern do mago: lock direção/posição/alvo no início do attack anim, spawna
# projétil no animation_finished.
var _locked_dir: Vector2 = Vector2.RIGHT
var _locked_target: Node2D = null
var _locked_muzzle_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("ally")
	add_to_group("leno")
	_player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_anim_finished)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	# Voo: bob vertical do sprite/muzzle (sombra não acompanha — fica fixa
	# como referência do chão).
	_bob_t += delta
	var bob: float = sin(_bob_t * BOB_SPEED) * BOB_HEIGHT
	sprite.offset.y = SPRITE_BASE_OFFSET_Y + bob
	muzzle.position.y = MUZZLE_BASE_OFFSET_Y + bob
	# Cooldown de ataque baseado em delta (mais robusto que SceneTreeTimer).
	if _attack_cd_remaining > 0.0:
		_attack_cd_remaining = maxf(_attack_cd_remaining - delta, 0.0)
	# Durante atk anim, fica parado.
	if _is_attacking:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_current_target = _pick_enemy_target()
	var move_vec: Vector2 = Vector2.ZERO
	if _current_target != null and is_instance_valid(_current_target):
		var to_target: Vector2 = _current_target.global_position - global_position
		var dist: float = to_target.length()
		if dist > attack_range:
			move_vec = to_target.normalized()
		else:
			_try_attack()
			# Se em cooldown (não atacou agora), volta pra formação ao redor do
			# player em vez de ficar parado. Cooldown ainda está rolando.
			if _attack_cd_remaining > 0.0 and _player != null and is_instance_valid(_player):
				var ideal_anchor: Vector2 = _player.global_position + _formation_offset()
				var to_anchor: Vector2 = ideal_anchor - global_position
				if to_anchor.length() > follow_min_distance:
					move_vec = to_anchor.normalized()
		# Flip pro alvo enquanto ataca/persegue.
		if absf(to_target.x) > 0.001:
			sprite.flip_h = to_target.x < 0.0
	elif _player != null and is_instance_valid(_player):
		# Modo pacífico: anel ao redor do player. Cada leno tem phase_offset
		# diferente pra orbital "loose" (não fica em cima).
		var ideal_anchor: Vector2 = _player.global_position + _formation_offset()
		var to_anchor: Vector2 = ideal_anchor - global_position
		var dist: float = to_anchor.length()
		if dist > follow_max_distance:
			move_vec = to_anchor.normalized()
		elif dist > follow_min_distance:
			move_vec = to_anchor.normalized() * 0.5  # aproxima devagar
		# Flip seguindo direção de movimento ou player.
		var face_dir: float = move_vec.x if move_vec.length_squared() > 0.001 else (_player.global_position.x - global_position.x)
		if absf(face_dir) > 0.001:
			sprite.flip_h = face_dir < 0.0
	# Separation contra outros lenos.
	var sep: Vector2 = _separation_force()
	velocity = move_vec * speed + sep
	move_and_slide()
	_update_animation(move_vec)


func _formation_offset() -> Vector2:
	# Posição-âncora ao redor do player baseada em phase_offset (pra múltiplos
	# lenos não se amontoarem no mesmo lado).
	var radius: float = (follow_min_distance + follow_max_distance) * 0.5
	return Vector2(cos(phase_offset), sin(phase_offset)) * radius


func _separation_force() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("leno"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		var diff: Vector2 = global_position - (other as Node2D).global_position
		var d: float = diff.length()
		if d < 0.01 or d > separation_radius:
			continue
		force += diff.normalized() * separation_strength * (1.0 - d / separation_radius)
	return force


func _pick_enemy_target() -> Node2D:
	# Boss prioritário: se há um boss vivo e SEM shield, foca nele independente
	# da distância (leno corre até chegar no attack_range). Em boss wave o boss
	# invoca minions constantemente — sem essa prioridade, leno fica matando
	# minion e ignorando o alvo principal.
	var boss: Node2D = _find_unshielded_boss()
	if boss != null:
		return boss
	# Fallback: inimigo mais próximo dentro do aggro_range.
	var nearest: Node2D = null
	var best: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		# Pula bosses com shield ativo — atacar não dá dano e desperdiça
		# cooldown do pet.
		if (e as Node).is_in_group("boss_shielded"):
			continue
		var d: float = (e as Node2D).global_position.distance_to(global_position)
		if d <= aggro_range and d < best:
			nearest = e
			best = d
	return nearest


func _find_unshielded_boss() -> Node2D:
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b) or not (b is Node2D):
			continue
		if (b as Node).is_queued_for_deletion():
			continue
		if (b as Node).is_in_group("boss_shielded"):
			continue
		if "hp" in b and float(b.hp) <= 0.0:
			continue
		return b as Node2D
	return null


func _update_animation(move_vec: Vector2) -> void:
	if _is_attacking:
		return
	if move_vec.length_squared() > 0.01:
		if sprite.animation != "walk":
			sprite.play("walk")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")


# Pattern do mago: trava o ALVO no início, mas re-calcula direção e posição
# do muzzle no momento do disparo (animation_finished). Antes travava tudo no
# início e o projétil errava porque o alvo (e o leno!) mexiam durante o cast.
func _try_attack() -> void:
	if _attack_cd_remaining > 0.0 or _is_attacking or _current_target == null:
		return
	if projectile_scene == null:
		return
	_locked_target = _current_target
	_is_attacking = true
	# Cooldown só é consumido DEPOIS do disparo válido (em _fire_projectile),
	# senão alvo que vira null durante a anim deixa o leno em "abrindo a boca"
	# sem tiro e ainda gastando o CD.
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("attack"):
		sprite.play("attack")
	else:
		_fire_projectile()
		_is_attacking = false


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	# Re-aim no momento do disparo. Usa target travado se ainda válido, senão
	# pega o alvo atual mais próximo. Sem alvo válido, cancela (não desperdiça).
	var aim_target: Node2D = null
	if _locked_target != null and is_instance_valid(_locked_target) and not _locked_target.is_queued_for_deletion():
		aim_target = _locked_target
	elif _current_target != null and is_instance_valid(_current_target):
		aim_target = _current_target
	if aim_target == null:
		return
	var spawn_pos: Vector2 = muzzle.global_position
	# Mira no centro do corpo do inimigo (não no chão). Insect flutua mais alto,
	# então usa offset maior — sem isso o projétil reto passava abaixo dele.
	var aim_pos: Vector2 = aim_target.global_position + _get_target_aim_offset(aim_target)
	var dir: Vector2 = (aim_pos - spawn_pos).normalized()
	if dir.length_squared() < 0.001:
		return
	var proj: Node2D = projectile_scene.instantiate()
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	if "damage" in proj:
		proj.damage = damage
	world.add_child(proj)
	proj.global_position = spawn_pos
	if proj.has_method("set_direction"):
		proj.set_direction(dir)
	_play_attack_sound()
	# CD consumido aqui (não em _try_attack) — garante que só conta se um tiro
	# realmente saiu.
	_attack_cd_remaining = attack_cooldown


func _get_target_aim_offset(target: Node) -> Vector2:
	# Centro do corpo do inimigo varia por tipo:
	#   - Monkey/Mage: collision em (0, -12) → -12 acerta o centro.
	#   - Insect: flutua em (0, -18) → precisa de offset maior pra não passar
	#     abaixo do corpo (projétil reto sem homing).
	if target.is_in_group("insect"):
		return Vector2(0, -16)
	return Vector2(0, -12)


func _on_anim_finished() -> void:
	if sprite.animation == "attack":
		_fire_projectile()
		_is_attacking = false
		sprite.play("idle")


func _play_attack_sound() -> void:
	if attack_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = attack_sound
	p.volume_db = attack_sound_volume_db
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(ATTACK_SOUND_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)
