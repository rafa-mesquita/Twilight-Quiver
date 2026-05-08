extends CharacterBody2D

# Woodwarden — primeiro aliado.
# Comportamento:
# - Sem inimigo perto: fica em formação atrás/perto do player
# - Com inimigo no `aggro_range`: corre na direção do mais próximo
# - Em `attack_range`: ataca (slow attack speed)
# - Hit: 50 dmg + stun no inimigo
# - Tanka: enemies podem mirar nele (group "tank_ally")
# - Imune ao ataque do inseto (group "insect_immune")
# - Renasce no início do próximo round (wave_manager respawna via owned_structures)

signal died(woodwarden: Node)

@export var max_hp: float = 320.0
@export var damage: float = 50.0
@export var stun_duration: float = 1.2
@export var attack_cooldown: float = 1.6  # 1 ataque a cada 1.6s (era 2.4)
@export var attack_range: float = 16.0
@export var aggro_range: float = 140.0
# Foco do Woodwarden é DEFENDER o player — só persegue inimigos que estão
# dentro deste raio em volta do PLAYER (não do warden). Evita correr pra
# longe atrás de inimigo solto e deixar o player descoberto.
@export var defense_radius: float = 110.0
# Anel de respiro ao redor do player: woodwarden persegue se mais longe que
# follow_max_distance, recua se mais perto que follow_min_distance, fica parado
# entre os dois.
@export var follow_min_distance: float = 28.0
@export var follow_max_distance: float = 50.0
@export var speed: float = 38.0
# Anti-overlap entre múltiplos woodwardens — se outro está mais perto que isso,
# aplica força de separação lateral pra não ficarem em cima um do outro.
@export var separation_radius: float = 20.0
@export var separation_strength: float = 35.0
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var attack_sound: AudioStream
@export var attack_sound_volume_db: float = -12.0
const ATTACK_SOUND_DURATION: float = 1.0  # tocar só 1s do mp3

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Frame do dano: 1 = ~0.167s na anim @ 6fps (cedo o suficiente pra inimigo
# não escapar do alcance durante a anim de 0.667s).
const HIT_FRAME: int = 1
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -12)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

var hp: float
var is_attacking: bool = false
var hit_applied: bool = false
var can_hit: bool = true
var current_target: Node2D = null
var player: Node2D
var knockback_velocity: Vector2 = Vector2.ZERO
var sprite_base_offset_y: float = 0.0
var _is_dead: bool = false


func _ready() -> void:
	add_to_group("ally")
	add_to_group("structure")  # respawn pattern + estrutura para inimigos quando longe do player
	add_to_group("tank_ally")  # _pick_target dos enemies considera estes além do player
	add_to_group("insect_immune")  # insect_projectile pula este alvo
	hp = max_hp
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
		hp_bar.visible = true
	if sprite != null:
		sprite_base_offset_y = sprite.offset.y
		sprite.animation_finished.connect(_on_animation_finished)
		sprite.frame_changed.connect(_on_frame_changed)
		sprite.play("idle")
	player = get_tree().get_first_node_in_group("player") as Node2D


func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		return
	# Re-pega player se referência morreu (ex: respawn).
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
	current_target = _pick_enemy_target()
	# Knockback decai linearmente.
	if knockback_velocity.length() > 0.0:
		var dec: float = 400.0 * delta
		var k_len: float = knockback_velocity.length()
		var new_len: float = maxf(k_len - dec, 0.0)
		knockback_velocity = knockback_velocity.normalized() * new_len
	if is_attacking:
		velocity = knockback_velocity
		move_and_slide()
		return
	var move_vec: Vector2 = Vector2.ZERO
	if current_target != null and is_instance_valid(current_target):
		# Modo combate: corre pro inimigo. Para no attack_range pra atacar.
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		if dist > attack_range:
			move_vec = to_target.normalized()
		else:
			_try_attack()
	elif player != null and is_instance_valid(player):
		# Modo pacífico: mantém um anel ao redor do player. Fora do anel: persegue.
		# Dentro do anel mais íntimo: recua. Entre os dois: parado (zona de respiro).
		var to_player: Vector2 = player.global_position - global_position
		var dist: float = to_player.length()
		if dist > follow_max_distance:
			move_vec = to_player.normalized()
		elif dist < follow_min_distance and dist > 0.01:
			move_vec = -to_player.normalized()
	# Separation: empurra pra longe de outros woodwardens próximos.
	var sep: Vector2 = _separation_force()
	velocity = move_vec * speed + knockback_velocity + sep
	move_and_slide()
	_update_facing(move_vec)
	_update_animation(move_vec)


func _separation_force() -> Vector2:
	var force: Vector2 = Vector2.ZERO
	for other in get_tree().get_nodes_in_group("ally"):
		if other == self or not is_instance_valid(other) or not (other is Node2D):
			continue
		# Só repele de outros woodwardens (mesmo tipo) — não quero separar de torre.
		if not (other.get_script() == get_script()):
			continue
		var diff: Vector2 = global_position - (other as Node2D).global_position
		var d: float = diff.length()
		if d < 0.01 or d > separation_radius:
			continue
		# Força inversamente proporcional à distância (mais perto, mais empurra).
		force += diff.normalized() * separation_strength * (1.0 - d / separation_radius)
	return force


func _pick_enemy_target() -> Node2D:
	# Foca em DEFENDER o player: só engaja inimigos dentro do defense_radius
	# medido do PLAYER (não do warden). Inimigos fora desse anel ficam pro
	# arco do player. Empate de distância: pega o mais perto do warden.
	var nearest: Node2D = null
	var best_dist: float = INF
	var anchor: Vector2 = global_position
	if player != null and is_instance_valid(player):
		anchor = player.global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var enemy_pos: Vector2 = (e as Node2D).global_position
		# Filtro principal: inimigo precisa estar perto do PLAYER.
		if anchor.distance_to(enemy_pos) > defense_radius:
			continue
		# Entre os candidatos, escolhe o mais perto do próprio warden.
		var d: float = global_position.distance_to(enemy_pos)
		if d < best_dist:
			nearest = e
			best_dist = d
	return nearest


func _try_attack() -> void:
	if not can_hit or is_attacking:
		return
	is_attacking = true
	can_hit = false
	hit_applied = false
	if sprite != null:
		sprite.play("attack")
	_play_attack_sound()
	# Cooldown timer.
	get_tree().create_timer(attack_cooldown).timeout.connect(func() -> void:
		if is_instance_valid(self):
			can_hit = true
	)


func _play_attack_sound() -> void:
	if attack_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = attack_sound
	p.volume_db = attack_sound_volume_db
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	# Corta após ATTACK_SOUND_DURATION pra não tocar o áudio inteiro.
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(ATTACK_SOUND_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _on_frame_changed() -> void:
	if not is_attacking or hit_applied:
		return
	if sprite.animation == "attack" and sprite.frame == HIT_FRAME:
		_apply_hit()


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		# Se ainda tem alvo válido, _physics_process re-decide próximo frame.
		sprite.play("idle")


func _apply_hit() -> void:
	hit_applied = true
	if current_target == null or not is_instance_valid(current_target):
		return
	var dist: float = global_position.distance_to(current_target.global_position)
	# Tolerância generosa pro hit conectar mesmo com inimigo recuando — anim
	# slow (0.667s) dá tempo do alvo se afastar ~13px naturalmente.
	if dist > attack_range + 14.0:
		return  # alvo escapou
	if current_target.has_method("take_damage"):
		# Curse ANTES do take_damage pra contar na conversão se o hit matar.
		CurseAllyHelper.apply_ally_curse_on_damage(current_target, self)
		current_target.take_damage(damage)
	if current_target.has_method("apply_stun"):
		current_target.apply_stun(stun_duration)
	if current_target.has_method("apply_knockback"):
		var dir: Vector2 = (current_target.global_position - global_position).normalized()
		current_target.apply_knockback(dir, 60.0)
	# Lv2+ do Woodwarden: ataques curam todos os aliados (e player) em 25% do dano.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("get_upgrade_count"):
		if int(p.get_upgrade_count("woodwarden")) >= 2:
			_heal_all_allies(damage * 0.25)


func _heal_all_allies(amount: float) -> void:
	if amount <= 0.0:
		return
	# Cura todos os entities no group "ally" (woodwardens, towers, etc.) e o player.
	# Spawna flash verde sobre cada um que efetivamente recebeu heal pra feedback.
	for ally in get_tree().get_nodes_in_group("ally"):
		if not is_instance_valid(ally):
			continue
		if ally.has_method("heal"):
			ally.heal(amount)
			if ally is Node2D:
				_spawn_heal_flash(ally as Node2D)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p != self and p.has_method("heal"):
		p.heal(amount)
		if p is Node2D:
			_spawn_heal_flash(p as Node2D)


func _spawn_heal_flash(target: Node2D) -> void:
	# Snapshot do sprite atual do alvo (procura AnimatedSprite2D ou Sprite2D no
	# subtree), aplica silhouette shader (vira "branco preservando alpha"),
	# tinge de verde via modulate, e fade out. Resultado: silhueta verde com
	# o formato exato da entidade (não círculo). Acompanha o alvo (filho dele).
	var src_sprite: Node2D = _find_sprite_in(target)
	if src_sprite == null:
		return
	var sil := Sprite2D.new()
	# Pega a textura do frame atual.
	if src_sprite is AnimatedSprite2D:
		var anim_sp: AnimatedSprite2D = src_sprite
		if anim_sp.sprite_frames == null:
			return
		var tex := anim_sp.sprite_frames.get_frame_texture(anim_sp.animation, anim_sp.frame)
		if tex == null:
			return
		sil.texture = tex
		sil.flip_h = anim_sp.flip_h
		sil.offset = anim_sp.offset
		sil.scale = anim_sp.scale
	elif src_sprite is Sprite2D:
		var st: Sprite2D = src_sprite
		sil.texture = st.texture
		sil.flip_h = st.flip_h
		sil.offset = st.offset
		sil.scale = st.scale
	else:
		return
	sil.position = src_sprite.position
	sil.material = ShaderMaterial.new()
	sil.material.shader = SILHOUETTE_SHADER
	sil.modulate = Color(0.45, 1.0, 0.5, 0.7)
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sil.z_index = 5
	target.add_child(sil)
	var tw := sil.create_tween()
	tw.tween_property(sil, "modulate:a", 0.0, 0.55)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sil.queue_free)


func _find_sprite_in(node: Node) -> Node2D:
	# Busca AnimatedSprite2D ou Sprite2D no subtree imediato (1 nível de profundidade).
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child as Node2D
	return null


func _update_facing(move_vec: Vector2) -> void:
	if sprite == null:
		return
	if current_target != null and is_instance_valid(current_target):
		# Encara o alvo durante combate.
		sprite.flip_h = current_target.global_position.x < global_position.x
	elif move_vec.x != 0.0:
		sprite.flip_h = move_vec.x < 0.0


func _update_animation(move_vec: Vector2) -> void:
	if is_attacking or sprite == null:
		return
	if move_vec.length() > 0.0:
		if sprite.animation != "walk":
			sprite.play("walk")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")


func take_damage(amount: float) -> void:
	if _is_dead:
		return
	hp = maxf(hp - amount, 0.0)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	if hp <= 0.0:
		_die()


func apply_knockback(dir: Vector2, strength: float) -> void:
	# Aliados também podem ser empurrados, mas com força reduzida.
	knockback_velocity = dir.normalized() * (strength * 0.5)


func heal(amount: float) -> void:
	# Cura usada pela mecânica lv2+ do Woodwarden (ataques curam aliados).
	if _is_dead or amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit(self)
	_spawn_kill_effect()
	_spawn_death_silhouette()
	queue_free()


var _flash_tween: Tween

func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.5, 0.4, 0.4, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.18)


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	num.position = global_position + Vector2(0, -28)
	get_tree().current_scene.add_child(num)


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_death_silhouette() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var sil := Sprite2D.new()
	sil.texture = tex
	sil.flip_h = sprite.flip_h
	sil.offset = sprite.offset
	sil.global_position = global_position
	sil.material = ShaderMaterial.new()
	sil.material.shader = SILHOUETTE_SHADER
	sil.modulate = Color(1, 1, 1, 0.85)
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_get_world().add_child(sil)
	var tw := sil.create_tween()
	tw.tween_property(sil, "modulate:a", 0.0, death_silhouette_duration)
	tw.tween_callback(sil.queue_free)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
