extends CharacterBody2D

# Dark Ball — inimigo aéreo/bola sombria que aparece a partir da wave 3 e
# substitui ~30% dos macacos. HP baixo (menos que mago), walk mais lento que
# o macaco, mas quando chega perto do player ATIVA DASH: acelera bastante,
# deixa rastro roxo, e se conectar o ataque dá +20% dmg do macaco + queimadura
# 3s (1 dps base, escala +0.5/s).

@export var speed: float = 28.0          # walk normal — mais lento que macaco (40)
@export var dash_speed: float = 72.0     # boost quando entra em range de dash
@export var dash_trigger_distance: float = 44.0  # entra em dash quando player nessa dist
@export var dash_exit_distance: float = 84.0     # sai de dash se player ficou longe (hysteresis)
@export var max_hp: float = 14.0         # < mage (18)
@export var damage: float = 26.0         # ~+45% sobre macaco (18) — golpe forte pra compensar HP frágil
@export var attack_range: float = 8.0    # trigger: precisa colar bem antes de iniciar a anim
# Tolerância extra no momento do HIT — o golpe pega até essa dist (player pode
# ter andado durante a anim). attack_range + tolerance ≈ raio efetivo do ataque.
@export var attack_hit_tolerance: float = 10.0
@export var attack_cooldown: float = 0.5
# Depois de atacar, fica nesse modo "post-attack walk" por X segundos sem
# poder dar dash nem atacar de novo. Faz a dark ball recuar/respirar antes
# da próxima investida.
@export var post_attack_walk_duration: float = 3.0
# Wind-up antes do attack: ela trava no idle por X segundos com um pulse
# visual de scale. Dá tempo do player reagir/atirar antes do golpe sair.
@export var pre_attack_telegraph: float = 0.22
# Burn DoT aplicado no hit: 3s total, dps escala. final_bonus 0 (sem explosão final).
@export var burn_duration: float = 3.0
@export var burn_dps_base: float = 1.0   # ponto inicial
@export var burn_dps_scale: float = 0.5  # +0.5/s sobre o base (3s → 2.5 dps último)
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var venom_puddle_scene: PackedScene
@export var death_silhouette_duration: float = 1.0
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -18.0
@export var dash_sound: AudioStream
@export var dash_sound_volume_db: float = -14.0
# Duração do dash sound — só os 2.5s iniciais do mp3 são tocados.
const DASH_SOUND_DURATION: float = 2.5
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 0.27
@export var heart_scene: PackedScene
@export var gold_drop_min: int = 1
@export var gold_drop_max: int = 2
@export var separation_radius: float = 14.0
@export var separation_strength: float = 25.0
@export var knockback_decay: float = 400.0
@export var tower_target_switch_distance: float = 220.0

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Frame em que o dano é aplicado durante a anim de attack (2 frames, hit no 1).
const HIT_FRAME: int = 1
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -10)
# Rastro roxo: emitido enquanto está em dash. Cor #bb8be9 sem HDR — boost
# em R + B virava magenta/rosa.
const DASH_TRAIL_COLOR: Color = Color(0.733, 0.545, 0.914, 1.0)
const DASH_TRAIL_AMOUNT: int = 28
const DASH_TRAIL_LIFETIME: float = 0.55
# Afterimage do dash: silhueta roxa da própria dark ball, spawnada a cada
# AFTERIMAGE_INTERVAL segundos enquanto dasha. Fica visível por
# AFTERIMAGE_LIFETIME segundos e fadeia.
const AFTERIMAGE_INTERVAL: float = 0.06
const AFTERIMAGE_LIFETIME: float = 0.35
const AFTERIMAGE_COLOR: Color = Color(0.733, 0.545, 0.914, 0.7)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

var hp: float
var can_hit: bool = true
var is_attacking: bool = false
var hit_applied: bool = false
var player: Node2D
var knockback_velocity: Vector2 = Vector2.ZERO
var sprite_base_offset_y: float = 0.0
var current_target: Node2D = null
var _stun_remaining: float = 0.0
var is_curse_ally: bool = false
var _is_dashing: bool = false
var _trail_emitter: CPUParticles2D = null
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()
# Timer do estado "post-attack walk" (bloqueia dash + ataque por X segundos).
var _post_attack_remaining: float = 0.0
# Acumulador do timer de spawn das afterimages durante o dash.
var _afterimage_accum: float = 0.0
# Wind-up antes do ataque: dark ball trava por pre_attack_telegraph segundos
# antes do hit começar. Sprite faz pulse de scale como cue visual.
var _telegraph_remaining: float = 0.0
var _telegraph_tween: Tween = null


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("dark_ball")
	hp = max_hp
	player = get_tree().get_first_node_in_group("player")
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite_base_offset_y = sprite.offset.y
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	if _stun_remaining > 0.0:
		_stun_remaining -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Timer do "post-attack walk": bloqueia dash + ataque até zerar.
	if _post_attack_remaining > 0.0:
		_post_attack_remaining = maxf(_post_attack_remaining - delta, 0.0)
	# Wind-up do ataque: travada parada com pulse de scale. Quando zerar,
	# dispara o _attack() de verdade.
	if _telegraph_remaining > 0.0:
		_telegraph_remaining = maxf(_telegraph_remaining - delta, 0.0)
		velocity = knockback_velocity
		knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
		move_and_slide()
		if _telegraph_remaining <= 0.0:
			_attack()
		return
	current_target = _pick_target()
	var ai_velocity: Vector2 = Vector2.ZERO
	var anchor_pos: Vector2 = global_position
	if current_target != null and is_instance_valid(current_target) and not is_attacking:
		var to_target: Vector2 = current_target.global_position - global_position
		var dist: float = to_target.length()
		anchor_pos = current_target.global_position
		# Hysteresis pro dash: entra em dash dentro de dash_trigger_distance,
		# sai só quando passa de dash_exit_distance. Bloqueia dash durante
		# o post_attack_walk (período de "recuperação" pós-hit).
		var is_player_target: bool = current_target.is_in_group("player")
		var dash_allowed: bool = is_player_target and _post_attack_remaining <= 0.0
		if dash_allowed:
			if not _is_dashing and dist <= dash_trigger_distance and dist > attack_range:
				_enter_dash()
			elif _is_dashing and dist > dash_exit_distance:
				_exit_dash()
		else:
			# Não pode dash (post-attack ou alvo não-player): sai se estava em dash.
			if _is_dashing:
				_exit_dash()
		var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_target / dist
		if dist > attack_range:
			var move_speed: float = dash_speed if _is_dashing else speed
			# Anti-stuck: redireciona lateral se preso em árvore/parede.
			dir = _anti_stuck.resolve(dir, delta)
			ai_velocity = dir * move_speed
			# Anims: "dash" durante boost, "walk" normal.
			var wanted_anim: StringName = &"dash" if _is_dashing else &"walk"
			if sprite.animation != wanted_anim:
				sprite.play(wanted_anim)
		else:
			# Em range — encerra dash se ainda ativo e ataca (se não está no
			# período de recuperação post-attack).
			if _is_dashing:
				_exit_dash()
			if can_hit and _post_attack_remaining <= 0.0:
				_start_telegraph()
			else:
				# Em recuperação: anda em volta do alvo em vez de ficar idle parado.
				# Sem isso a dark ball trava no attack_range esperando o cooldown.
				if sprite.animation != "walk":
					sprite.play("walk")
		if absf(dir.x) > 0.001:
			sprite.flip_h = dir.x < 0.0
	# Separação contra outros inimigos pra não empilhar.
	var separation: Vector2 = EnemySeparation.compute(self, separation_radius, separation_strength)
	velocity = ai_velocity + knockback_velocity + separation
	knockback_velocity = knockback_velocity.move_toward(Vector2.ZERO, knockback_decay * delta)
	move_and_slide()
	_anti_stuck.update(self, anchor_pos, ai_velocity.length_squared() > 0.01, delta)
	# Spawn de afterimages enquanto dasha (silhuetas roxas que ficam pra trás).
	if _is_dashing:
		_afterimage_accum += delta
		while _afterimage_accum >= AFTERIMAGE_INTERVAL:
			_afterimage_accum -= AFTERIMAGE_INTERVAL
			_spawn_dash_afterimage()
	else:
		_afterimage_accum = 0.0


func _pick_target() -> Node2D:
	# Player vivo + perto = alvo prioritário. Se player longe ou morto, vai pra
	# torre/aliado mais próximo (mesma lógica do monkey).
	if player != null and is_instance_valid(player):
		var dist: float = global_position.distance_to(player.global_position)
		var p_alive: bool = (not ("is_dead" in player)) or not bool(player.is_dead)
		if p_alive and dist <= tower_target_switch_distance:
			return player
	# Fallback: torre/aliado mais próximo dentro do raio.
	var nearest: Node2D = null
	var best: float = INF
	for n in get_tree().get_nodes_in_group("structure"):
		if is_instance_valid(n) and n is Node2D:
			var d: float = (n as Node2D).global_position.distance_to(global_position)
			if d < best:
				best = d
				nearest = n
	for n in get_tree().get_nodes_in_group("tank_ally"):
		if is_instance_valid(n) and n is Node2D:
			var d2: float = (n as Node2D).global_position.distance_to(global_position)
			if d2 < best:
				best = d2
				nearest = n
	if nearest != null:
		return nearest
	# Sem alvo válido — fica no player se existe (mesmo longe).
	return player


func _enter_dash() -> void:
	if _is_dashing:
		return
	_is_dashing = true
	_spawn_trail()
	_play_dash_sound()


func _play_dash_sound() -> void:
	if dash_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = dash_sound
	p.volume_db = dash_sound_volume_db
	# Filho do world (não do dark_ball) — se a dark ball morrer durante o dash,
	# o som continua tocando até o cleanup natural. Posição inicial = dark ball.
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	# Corta após DASH_SOUND_DURATION pra usar só os 2.5s iniciais do mp3.
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(DASH_SOUND_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _exit_dash() -> void:
	if not _is_dashing:
		return
	_is_dashing = false
	_remove_trail()


func _spawn_trail() -> void:
	if _trail_emitter != null and is_instance_valid(_trail_emitter):
		_trail_emitter.emitting = true
		return
	var p := CPUParticles2D.new()
	p.amount = DASH_TRAIL_AMOUNT
	p.lifetime = DASH_TRAIL_LIFETIME
	# local_coords=false: partículas ficam em world space (não acompanham a
	# dark ball depois de spawnar — efeito de rastro).
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.spread = 45.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.4
	# Posição relativa: spawn no centro do corpo (não nos pés).
	p.position = Vector2(0, -10)
	# z_as_relative=false + z_index=1 garante que aparece ACIMA do chão
	# (TileMap z=-1) mas atrás do sprite (z=0 por padrão no AnimatedSprite2D).
	p.z_as_relative = false
	p.z_index = 0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([DASH_TRAIL_COLOR, Color(DASH_TRAIL_COLOR.r, DASH_TRAIL_COLOR.g, DASH_TRAIL_COLOR.b, 0.0)])
	p.color_ramp = ramp
	p.emitting = true
	add_child(p)
	_trail_emitter = p


func _spawn_dash_afterimage() -> void:
	# Snapshot do sprite atual: copia textura + flip + offset + scale, aplica
	# SILHOUETTE_SHADER pra "blanquear" o RGB, tinta com #bb8be9 e fadeia.
	if sprite == null or sprite.sprite_frames == null:
		return
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	ghost.scale = sprite.scale
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	ghost.material = mat
	# z_index baixo pra ficar ATRÁS da dark ball atual (rastro).
	ghost.z_as_relative = false
	ghost.z_index = -1
	_get_world().add_child(ghost)
	ghost.global_position = global_position + sprite.position
	ghost.modulate = AFTERIMAGE_COLOR
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, AFTERIMAGE_LIFETIME)
	t.tween_callback(ghost.queue_free)


func _remove_trail() -> void:
	if _trail_emitter == null or not is_instance_valid(_trail_emitter):
		return
	_trail_emitter.emitting = false
	var ref: CPUParticles2D = _trail_emitter
	_trail_emitter = null
	# Cleanup após o lifetime das partículas existentes.
	var t := ref.create_tween()
	t.tween_interval(DASH_TRAIL_LIFETIME + 0.1)
	t.tween_callback(ref.queue_free)


func _spawn_venom_puddle() -> void:
	if venom_puddle_scene == null:
		return
	var puddle: Node2D = venom_puddle_scene.instantiate()
	# Poça: 3 dps enquanto player está dentro (sem linger artificial).
	if "dps" in puddle:
		puddle.dps = 3.0
	_get_world().add_child(puddle)
	# Spawn alguns pixels NA FRENTE da dark ball (na direção do alvo) — efeito
	# de cuspir veneno pra frente, não exatamente em cima dela.
	var offset_dir: Vector2 = Vector2(-1.0 if sprite.flip_h else 1.0, 0.0)
	if current_target != null and is_instance_valid(current_target):
		var to_target: Vector2 = current_target.global_position - global_position
		if to_target.length_squared() > 0.01:
			offset_dir = to_target.normalized()
	# Offset suficiente pra venom_center ficar além do player (que está a
	# attack_range=8 da dark ball no momento do hit). Com radius 9 da poça,
	# offset 20 deixa 3px de gap entre player e borda da poça → dash sai fácil.
	const VENOM_SPAWN_OFFSET: float = 20.0
	puddle.global_position = global_position + offset_dir * VENOM_SPAWN_OFFSET


func _start_telegraph() -> void:
	# Trava a dark ball por pre_attack_telegraph segundos antes do ataque
	# começar. Pulse de scale serve de cue visual ("ela vai bater").
	_telegraph_remaining = pre_attack_telegraph
	can_hit = false
	if sprite.animation != "idle":
		sprite.play("idle")
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	var base_scale: Vector2 = sprite.scale
	var max_scale: Vector2 = base_scale * 1.18
	var half: float = pre_attack_telegraph * 0.5
	_telegraph_tween = sprite.create_tween()
	_telegraph_tween.tween_property(sprite, "scale", max_scale, half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_telegraph_tween.tween_property(sprite, "scale", base_scale, half)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _attack() -> void:
	is_attacking = true
	hit_applied = false
	sprite.play("attack")


func _on_frame_changed() -> void:
	if is_attacking and sprite.frame == HIT_FRAME and not hit_applied:
		hit_applied = true
		# Spawna poça de veneno no chão, no momento do swing — independente
		# do hit conectar (efeito de "explosão de veneno" no impacto).
		_spawn_venom_puddle()
		if current_target != null and is_instance_valid(current_target):
			var dist: float = global_position.distance_to(current_target.global_position)
			if dist <= attack_range + attack_hit_tolerance and current_target.has_method("take_damage"):
				if is_curse_ally:
					CurseAllyHelper.apply_ally_curse_on_damage(current_target, self)
				if current_target.is_in_group("player"):
					current_target.take_damage(damage, "dark_ball")
				else:
					current_target.take_damage(damage)
					if is_curse_ally:
						var p := get_tree().get_first_node_in_group("player")
						if p != null and p.has_method("notify_damage_dealt_by_source"):
							p.notify_damage_dealt_by_source(damage, "curse_ally")
				_apply_dark_burn(current_target)


func _apply_dark_burn(target: Node) -> void:
	# Burn escalonado: 1 dps no início, +burn_dps_scale por segundo no decorrer.
	# Total = avg_dps × duration.
	if not target.has_method("take_damage"):
		return
	if not (target is Node):
		return
	var avg_dps: float = _burn_dps_avg()
	# Player: usa o pipeline `apply_poison` (tem ticker próprio + dmg number
	# colorido + integração com death screen via source_id). Passa roxo
	# (#bb8be9) pra match com o tema visual da dark ball.
	if (target as Node).is_in_group("player") and target.has_method("apply_poison"):
		# tick_delay 0.18s: player tem janela pra dashar/esquivar e escapar
		# do primeiro tick. Sem isso, dodgar o impacto ainda comia o tick.
		target.apply_poison(avg_dps * burn_duration, burn_duration, "dark_ball_burn", Color(0.733, 0.545, 0.914, 1.0), true, 0.18)
		return
	# Inimigo (caso de curse-ally): usa BurnDoT como componente filho. Mesmo
	# pattern do fogo do player.
	for c in (target as Node).get_children():
		if c is BurnDoT:
			(c as BurnDoT).refresh(burn_duration, avg_dps)
			return
	var dot := BurnDoT.new()
	dot.dps = avg_dps
	dot.duration = burn_duration
	dot.source_id = "dark_ball_burn"
	(target as Node).add_child(dot)


func _burn_dps_avg() -> float:
	return burn_dps_base + burn_dps_scale * burn_duration * 0.5


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		sprite.play("walk")
		# Após o ataque entra no modo "post-attack walk": fica X segundos andando
		# normal, sem dash e sem poder atacar de novo. Cooldown do can_hit é o
		# fim dessa janela.
		_post_attack_remaining = post_attack_walk_duration
		get_tree().create_timer(post_attack_walk_duration).timeout.connect(_on_attack_cooldown_done, CONNECT_ONE_SHOT)


func _on_attack_cooldown_done() -> void:
	can_hit = true


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
		_remove_trail()
		if not is_curse_ally:
			if CurseAllyHelper.try_convert_on_death(self):
				return
			HeartDrop.try_drop(_get_world(), heart_scene, global_position, self)
			var p2 := get_tree().get_first_node_in_group("player")
			if p2 != null and p2.has_method("notify_enemy_killed"):
				p2.notify_enemy_killed()
		GoldDrop.try_drop(_get_world(), gold_scene, global_position,
			gold_drop_chance, gold_drop_min, gold_drop_max)
		_spawn_kill_effect()
		_spawn_death_silhouette()
		queue_free()


var _suppress_damage_sound_once: bool = false


func _play_damage_sound(duration: float = 0.7) -> void:
	if _suppress_damage_sound_once:
		_suppress_damage_sound_once = false
		return
	for c in get_children():
		if c is FreezeDebuff:
			return
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 0.85
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
	var tex: Texture2D = sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = tex
	ghost.flip_h = sprite.flip_h
	ghost.offset = sprite.offset
	# Replica scale + posição local do sprite original — sem isso a silhueta
	# renderiza em tamanho cheio (32px) ignorando o scale 0.65 da dark ball.
	ghost.scale = sprite.scale
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	ghost.material = mat
	_get_world().add_child(ghost)
	ghost.global_position = global_position + sprite.position
	ghost.modulate.a = 0.5
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, death_silhouette_duration)
	t.tween_callback(ghost.queue_free)


var _flash_tween: Tween
var _crit_pending: bool = false


func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	# Crit segue o padrão amarelo do projeto. Flash normal usa SILHOUETTE_SHADER
	# temporariamente: substitui RGB do sprite por #bb8be9 puro (sem mistura
	# com o roxo escuro original que produzia tom rosa). Material restaura no
	# fim do tween.
	if _crit_pending:
		sprite.modulate = CritFeedback.CRIT_FLASH_COLOR
		_flash_tween = create_tween()
		_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
		return
	# Aplica shader pra "blankear" o sprite e tinta com a cor da dark ball.
	var prev_material: Material = sprite.material
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	sprite.material = mat
	sprite.modulate = Color(0.733, 0.545, 0.914, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)
	# Restaura o material original ao fim — sem isso o sprite ficaria silhueta.
	_flash_tween.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.material = prev_material
	)


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
	num.position = global_position + Vector2(0, -24)
	get_tree().current_scene.add_child(num)


func apply_knockback(dir: Vector2, strength: float) -> void:
	knockback_velocity = dir.normalized() * strength


func apply_stun(duration: float) -> void:
	_stun_remaining = maxf(_stun_remaining, duration)
	is_attacking = false
	hit_applied = false
	# Cancela telegraph se em wind-up (stun deve interromper).
	_telegraph_remaining = 0.0
	if _telegraph_tween != null and _telegraph_tween.is_valid():
		_telegraph_tween.kill()
	# Restaura scale base caso o tween tenha parado em meio pulse.
	if sprite != null:
		sprite.scale = Vector2(0.65, 0.65)
	can_hit = true
	_exit_dash()


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
