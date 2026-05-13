class_name MageEnemy
extends CharacterBody2D

@export var speed: float = 22.0
@export var max_hp: float = 18.0
@export var preferred_distance: float = 130.0
@export var distance_tolerance: float = 12.0
@export var detection_range: float = 240.0
@export var shoot_interval: float = 2.0
@export var projectile_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var knockback_decay: float = 400.0
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 0.47
@export var gold_drop_min: int = 1
@export var gold_drop_max: int = 2
@export var heart_scene: PackedScene
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0
@export var tower_target_switch_distance: float = 240.0

# Habilidade de invocação: a cada `summon_check_every` ataques, rola `summon_chance`
# pra trocar o ataque por uma invocação de inseto. Só ativo a partir da wave configurada.
@export var insect_scene: PackedScene
@export var summon_effect_scene: PackedScene
@export var summon_chance: float = 0.45
@export var summon_check_every: int = 2
@export var summon_min_wave: int = 1
@export var summon_distance_tiles: int = 3
@export var summon_tile_size: float = 16.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Sprite do mago invocador: swap do atlas em runtime (mesmas regiões do sheet
# base, layout idêntico). Substitui o filtro lilás antigo por arte dedicada.
const SUMMONER_TEXTURE: Texture2D = preload("res://assets/enemies/mage/mage-summ2-Sheet-export.png")
const MUZZLE_OFFSET_X: float = 8.0
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -16)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle
@onready var shoot_timer: Timer = $ShootTimer

var hp: float
var damage_mult: float = 1.0  # setado pelo wave_manager — aplica no projectile no disparo
var hp_mult: float = 1.0  # setado pelo wave_manager — propaga pro inseto invocado
var player: Node2D
var current_target: Node2D = null
var is_attacking: bool = false
var is_summoning: bool = false
var attack_count: int = 0
var locked_attack_dir: Vector2 = Vector2.RIGHT
var knockback_velocity: Vector2 = Vector2.ZERO
var _stun_remaining: float = 0.0
var _flash_tween: Tween
# Maldição: AI vira aliada ao ser convertido (mira em enemies, projétil hit them).
var is_curse_ally: bool = false


func _ready() -> void:
	add_to_group("enemy")
	# Mago invocador (insect_scene setado) entra num grupo separado pra wave_manager
	# poder balancear quantos de cada tipo aparecem na horda.
	if insect_scene != null:
		add_to_group("summoner_mage")
		_apply_summoner_skin()
	else:
		add_to_group("mage")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	shoot_timer.wait_time = shoot_interval
	shoot_timer.timeout.connect(_try_shoot)
	shoot_timer.start()
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play("walk")


func _apply_summoner_skin() -> void:
	# Swap do atlas de cada AtlasTexture pra textura do mago invocador. Duplica
	# o SpriteFrames e cada AtlasTexture pra não vazar pros magos comuns.
	if sprite == null or sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = sprite.sprite_frames.duplicate(true)
	for anim_name: StringName in sf.get_animation_names():
		var n: int = sf.get_frame_count(anim_name)
		for i in n:
			var tex: Texture2D = sf.get_frame_texture(anim_name, i)
			if tex is AtlasTexture:
				var new_atlas: AtlasTexture = (tex as AtlasTexture).duplicate()
				new_atlas.atlas = SUMMONER_TEXTURE
				sf.set_frame(anim_name, i, new_atlas)
	sprite.sprite_frames = sf


func _physics_process(delta: float) -> void:
	# Stun: bloqueia AI/ataque/invocação durante a duração.
	if _stun_remaining > 0.0:
		_stun_remaining -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	var ai_velocity: Vector2 = Vector2.ZERO
	current_target = _pick_target()

	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		var dir: Vector2 = to_target.normalized()

		if not is_attacking:
			if dist < preferred_distance - distance_tolerance:
				ai_velocity = -dir * speed
			elif dist > preferred_distance + distance_tolerance:
				ai_velocity = dir * speed

		_update_facing(to_target)

	# Separação contra outros inimigos pra não empilhar.
	var separation: Vector2 = EnemySeparation.compute(self, separation_radius, separation_strength)
	# Knockback soma sobre AI velocity e decai linearmente até zero.
	velocity = ai_velocity + knockback_velocity + separation
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()


func _update_facing(to_player: Vector2) -> void:
	# Cajado fica à esquerda do mago no sprite original; quando flipa, vai pra direita.
	if to_player.x < 0:
		sprite.flip_h = true
		muzzle.position.x = MUZZLE_OFFSET_X
	elif to_player.x > 0:
		sprite.flip_h = false
		muzzle.position.x = -MUZZLE_OFFSET_X


func _try_shoot() -> void:
	if is_attacking:
		return
	if current_target == null or not is_instance_valid(current_target):
		return
	var dist := global_position.distance_to(current_target.global_position)
	if dist > detection_range:
		return

	attack_count += 1

	# Roll de invocação: a cada `summon_check_every` ataques, chance de virar summon.
	# Mago original: só invoca contra o player. Mago convertido (curse ally):
	# invoca contra qualquer enemy — o inseto invocado também vira aliado.
	var summon_valid_target: bool = (current_target == player) or is_curse_ally
	if summon_valid_target and _can_summon() and attack_count % summon_check_every == 0 and randf() < summon_chance:
		is_summoning = true
		is_attacking = true
		sprite.play("attack")
		return

	# Não gateia o ataque em projectile_scene — subclasses (ex: fire_mage) podem
	# usar uma cena diferente via override do _fire_projectile. Animation rolla
	# sempre; o disparo em si é checado lá no _fire_projectile.
	var target := current_target.global_position + Vector2(0, -12)
	locked_attack_dir = (target - muzzle.global_position).normalized()
	is_attacking = true
	sprite.play("attack")


func _can_summon() -> bool:
	if insect_scene == null:
		return false
	# Dev mode: wave nunca inicia (wave_number=0), então o gate de summon_min_wave
	# bloqueava todo summon. Libera no dev pra testar invocação isoladamente.
	if GameState.dev_mode:
		return true
	return _current_wave_number() >= summon_min_wave


func _current_wave_number() -> int:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		return int(wm.wave_number)
	return 1


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		if is_summoning:
			_do_summon()
			is_summoning = false
		else:
			_fire_projectile()
		is_attacking = false
		sprite.play("walk")


func _get_map_center() -> Vector2:
	# Acha o centro do mapa via TileMapLayer "Ground" (used_rect × tile_size).
	# Fallback: posição do nó Map. Último fallback: Vector2.ZERO.
	var map := get_tree().get_first_node_in_group("map") as Node2D
	if map == null:
		return Vector2.ZERO
	var ground := map.get_node_or_null("Ground")
	if ground is TileMapLayer:
		var tml: TileMapLayer = ground
		if tml.tile_set != null:
			var rect: Rect2i = tml.get_used_rect()
			var tile_size: Vector2i = tml.tile_set.tile_size
			var center_local := Vector2(
				float(rect.position.x + rect.size.x / 2) * float(tile_size.x),
				float(rect.position.y + rect.size.y / 2) * float(tile_size.y)
			)
			return tml.to_global(center_local)
	return map.global_position


func _do_summon() -> void:
	# Posição alvo: 3 tiles do mago em direção AO CENTRO DO MAPA (com spread).
	# Antes era 360° aleatório — às vezes o inseto saía atrás das cercas/limites.
	# Fixar o ângulo na direção do centro garante que o inseto fica no mapa,
	# e o spread de ±60° mantém variedade visual.
	var to_center: Vector2 = _get_map_center() - global_position
	var base_angle: float = to_center.angle() if to_center.length_squared() > 1.0 else randf() * TAU
	var angle: float = base_angle + randf_range(-PI / 3.0, PI / 3.0)
	var radius: float = summon_distance_tiles * summon_tile_size + randf_range(-4.0, 4.0)
	var spawn_pos: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * radius

	if summon_effect_scene != null:
		var fx := summon_effect_scene.instantiate()
		_get_world().add_child(fx)
		fx.global_position = spawn_pos

	if insect_scene == null:
		return
	var insect := insect_scene.instantiate()
	# Propaga scaling do mago invocador pro inseto.
	if "max_hp" in insect:
		insect.max_hp = insect.max_hp * hp_mult
	if "damage_mult" in insect:
		insect.damage_mult = damage_mult
	_get_world().add_child(insect)
	insect.global_position = spawn_pos
	if insect.has_method("play_spawn_in"):
		insect.play_spawn_in()
	# Mago convertido pela maldição invoca insetos ALIADOS (mesma conversão).
	if is_curse_ally:
		CurseAllyHelper.convert_to_ally(insect)


func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	# Source ID pra telemetria — summoner_mage e mage_enemy compartilham
	# este script, então diferencia pelo grupo.
	if "source_id" in proj:
		proj.source_id = "summoner_mage" if is_in_group("summoner_mage") else "mage"
	if "damage" in proj and damage_mult != 1.0:
		proj.damage = proj.damage * damage_mult
	# Maldição: mago convertido marca projétil como ally_source (mira em enemy,
	# sem redirect). Lv3+: marca apply_curse pra projétil aplicar slow/DoT.
	if is_curse_ally and "is_ally_source" in proj:
		proj.is_ally_source = true
	if "apply_curse" in proj:
		var p := get_tree().get_first_node_in_group("player")
		if is_curse_ally:
			proj.apply_curse = true
		elif p != null and ("curse_arrow_level" in p) and int(p.curse_arrow_level) >= 3:
			# Lv3+ não-aplica em mago original (ele é enemy), só em ally convertido.
			pass
	_get_world().add_child(proj)
	proj.global_position = Vector2(muzzle.global_position.x, global_position.y + 2)
	if proj.has_method("set_direction"):
		proj.set_direction(locked_attack_dir)
	# Mago invocador: tinta o projétil de verde (sprite + trail + glow) pra
	# combinar com a paleta dele.
	if insect_scene != null:
		_apply_summoner_projectile_skin(proj)


const SUMMONER_PROJ_TINT: Color = Color(0.55, 1.0, 0.75, 1.0)
const SUMMONER_PROJ_TRAIL_TIP: Color = Color(0.4, 1.0, 0.65, 0.7)
const SUMMONER_PROJ_TRAIL_HEAD: Color = Color(0.4, 1.0, 0.65, 0.0)


func _apply_summoner_projectile_skin(proj: Node) -> void:
	var s: Node = proj.get_node_or_null("AnimatedSprite2D")
	if s is CanvasItem:
		(s as CanvasItem).modulate = SUMMONER_PROJ_TINT
	var glow: Node = proj.get_node_or_null("GlowLight")
	if glow is PointLight2D:
		(glow as PointLight2D).color = SUMMONER_PROJ_TINT
	var trail: Node = proj.get_node_or_null("Trail")
	if trail is Line2D:
		var l: Line2D = trail as Line2D
		l.default_color = SUMMONER_PROJ_TINT
		if l.gradient != null:
			# Gradient é compartilhado com outros projéteis — duplica antes de
			# editar pra não vazar nos magos comuns.
			var g: Gradient = l.gradient.duplicate() as Gradient
			g.colors = PackedColorArray([SUMMONER_PROJ_TRAIL_HEAD, SUMMONER_PROJ_TRAIL_TIP])
			l.gradient = g


func take_damage(amount: float) -> void:
	if not is_curse_ally:
		var p := get_tree().get_first_node_in_group("player")
		if p != null and p.has_method("notify_damage_dealt"):
			p.notify_damage_dealt(amount)
	hp = maxf(hp - amount, 0.0)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	var died := hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	if died:
		if not is_curse_ally:
			if CurseAllyHelper.try_convert_on_death(self):
				return
			HeartDrop.try_drop(_get_world(), heart_scene, global_position, self)
			var p2 := get_tree().get_first_node_in_group("player")
			if p2 != null and p2.has_method("notify_enemy_killed"):
				p2.notify_enemy_killed()
			# Conta morte de mago pra escalada de atk speed da torreta do Ting
			# (+1% por mago morto na wave). Inclui fire/ice/electric/summoner —
			# todos extendem este MageEnemy e passam por este take_damage.
			if p2 != null and p2.has_method("notify_mage_killed"):
				p2.notify_mage_killed()
		# Gold dropa em ambos: morte de inimigo normal E morte de aliado convertido
		# pela Maldição. Coerente com a expectativa do jogador — o macaco/mago que
		# ele "transformou" deveria valer gold quando morre lutando.
		GoldDrop.try_drop(_get_world(), gold_scene, global_position,
			gold_drop_chance, gold_drop_min, gold_drop_max)
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


func apply_knockback(dir: Vector2, strength: float) -> void:
	knockback_velocity = dir.normalized() * strength


func apply_stun(duration: float) -> void:
	# Stun do Woodwarden: bloqueia AI/ataque/invocação. Refresca duração se reaplicado.
	_stun_remaining = maxf(_stun_remaining, duration)
	is_attacking = false
	is_summoning = false
	if sprite != null and sprite.animation == "attack":
		sprite.play("idle")


func _play_damage_sound(duration: float = 0.7) -> void:
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 0.8
	# CHILD do enemy — morre junto no queue_free, evita som "continuo" pós-morte.
	add_child(p)
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position + BODY_CENTER_OFFSET


func _spawn_death_silhouette() -> void:
	if sprite == null or sprite.sprite_frames == null:
		return
	var current_tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if current_tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = current_tex
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	ghost.material = mat
	_get_world().add_child(ghost)
	ghost.global_position = global_position
	ghost.modulate.a = 0.5
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, death_silhouette_duration)
	t.tween_callback(ghost.queue_free)


func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


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
	num.position = global_position + Vector2(0, -32)
	get_tree().current_scene.add_child(num)


func _pick_target() -> Node2D:
	# Curse ally: inverte alvo — busca enemies em vez de player.
	if is_curse_ally:
		return _pick_curse_ally_target()
	# Player + tank allies (woodwarden) competem como alvo primário pela distância.
	var primary: Node2D = null
	var primary_dist: float = INF
	var player_alive: bool = player != null and is_instance_valid(player) and not (("is_dead" in player) and player.is_dead)
	if player_alive:
		primary_dist = global_position.distance_to(player.global_position)
		primary = player
	for tank in get_tree().get_nodes_in_group("tank_ally"):
		if not is_instance_valid(tank) or not (tank is Node2D):
			continue
		var d: float = global_position.distance_to((tank as Node2D).global_position)
		if d < primary_dist:
			primary = tank as Node2D
			primary_dist = d
	if primary != null and primary_dist <= tower_target_switch_distance:
		return primary
	var nearest_tower: Node2D = null
	var nearest_dist: float = INF
	for s in get_tree().get_nodes_in_group("structure"):
		if not is_instance_valid(s):
			continue
		var d: float = global_position.distance_to((s as Node2D).global_position)
		if d < nearest_dist:
			nearest_tower = s
			nearest_dist = d
	if nearest_tower != null:
		return nearest_tower
	return player if player_alive else null


func _pick_curse_ally_target() -> Node2D:
	var nearest: Node2D = null
	var best_dist: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < best_dist:
			nearest = e
			best_dist = d
	return nearest


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
