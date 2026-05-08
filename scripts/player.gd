extends CharacterBody2D

signal hp_changed(current: float, maximum: float)
signal gold_changed(total: int)
signal died
# Dash: emitido ao comprar o upgrade (HUD mostra a barra) e a cada frame
# durante o cooldown (HUD atualiza progress).
signal dash_unlocked
signal dash_cooldown_changed(remaining: float, total: float)
# Fire Skill (lv3 do elemental Fogo): emitido ao chegar no lv3 (HUD mostra ícone)
# e a cada frame durante o cooldown.
signal fire_skill_unlocked
signal fire_skill_cooldown_changed(remaining: float, total: float)
# Curse Skill (lv4 do elemental Maldição): raio roxo em linha reta, cd 3s.
signal curse_skill_unlocked
signal curse_skill_cooldown_changed(remaining: float, total: float)

@export var speed: float = 55.825  # +1.5% sobre o base 55.0
@export var attack_cooldown: float = 1.0
@export var arrow_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var max_hp: float = 100.0
@export var muzzle_offset_x: float = 8.0
@export var death_freeze_duration: float = 1.5  # tempo parado antes da animação de morte
@export var death_fadeout_duration: float = 0.4  # tempo do sprite sumir após kill_effect
@export var death_blackout_duration: float = 0.3  # tempo da tela ficar preta
@export var kill_effect_scene: PackedScene = preload("res://scenes/kill_effect.tscn")
const DEATH_SOUND: AudioStream = preload("res://audios/effects/dead effect.mp3")
const DASH_SOUND: AudioStream = preload("res://audios/effects/player arrow/dash.mp3")
@export var poison_number_color: Color = Color(0.55, 1.0, 0.45, 1.0)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var attack_timer: Timer = $AttackTimer
@onready var hp_bar: Node2D = $HpBar
@onready var damage_audio: AudioStreamPlayer2D = $DamageAudio

const RELEASE_FRAME: int = 4
const POISON_TICK_INTERVAL: float = 0.5

var hp: float
var gold: int = 0
# Upgrade tracking — incrementa ao comprar na shop pós-wave.
var hp_upgrades: int = 0
# Armor (status): reduz % do dano recebido. Computado de armor_level.
var armor_level: int = 0
var damage_reduction_pct: float = 0.0
var damage_upgrades: int = 0
var perfuracao_level: int = 0  # capa em 4 (níveis 1-4)
var attack_speed_level: int = 0
var multi_arrow_level: int = 0  # capa em 4 (níveis 1-4)
var chain_lightning_level: int = 0  # capa em 4 (níveis 1-4)
var move_speed_level: int = 0
var life_steal_level: int = 0  # cada stack +5% chance e +10% heal nos drops de coração
var fire_arrow_level: int = 0  # elemental Fogo (excalidraw lv1-4)
var curse_arrow_level: int = 0  # elemental Maldição (excalidraw lv1, escala lv1-4)
var woodwarden_level: int = 0  # aliado tank — cada compra "uppa" stats e custo
# Leno (aliado voador, 4 níveis). Sem HP, orbita o player, dispara projétil
# com slow area no impacto. L1=1 leno (20 dmg), L2=1 leno (50 dmg + atk speed),
# L3=2 lenos, L4=3 lenos. Lenos morrem quando o player morre.
const LENO_SCENE: PackedScene = preload("res://scenes/leno.tscn")
var leno_level: int = 0
var _lenos: Array[Node2D] = []
# Fire skill (botão direito a partir do lv3 do Fogo).
const FIRE_SKILL_COOLDOWN: float = 7.0
const FIRE_SKILL_RANGE: float = 140.0
const FIRE_SKILL_AREA_RADIUS: float = 32.0
const FIRE_SKILL_DPS: float = 12.0
const FIRE_SKILL_DURATION: float = 6.0
const FIRE_SKILL_INDICATOR_SCENE: PackedScene = preload("res://scenes/fire_skill_indicator.tscn")
const FIRE_SKILL_PROJECTILE_SCENE: PackedScene = preload("res://scenes/fire_skill_projectile.tscn")
var _fire_skill_cd_remaining: float = 0.0
var _fire_skill_targeting: bool = false
var _fire_skill_indicator: Node2D = null
# Curse skill (Q a partir do lv4 da Maldição): raio roxo gigante que corta o
# mapa de um lado ao outro (ignora walls). Warmup 0.4s + sustained 5s. Cd 3s
# começa depois que o beam acaba — total cycle = 8.4s.
# Sem target mode — atira instant na direção do mouse.
const CURSE_SKILL_COOLDOWN_AFTER: float = 20.0
const CURSE_SKILL_WARMUP: float = 0.4
const CURSE_SKILL_DURATION: float = 5.0
const CURSE_SKILL_TOTAL_CYCLE: float = CURSE_SKILL_WARMUP + CURSE_SKILL_DURATION + CURSE_SKILL_COOLDOWN_AFTER
# Range em CADA direção do player (total = 2× isso). Capado pra cortar o mapa
# inteiro de ponta a ponta sem travar (mapa visível ~680×380, então 1000/lado
# = 2000 total cobre folgado).
const CURSE_SKILL_RANGE: float = 1000.0
const CURSE_SKILL_DAMAGE_PER_TICK: float = 8.0
const CURSE_BEAM_SCENE: PackedScene = preload("res://scenes/curse_beam.tscn")
var _curse_skill_cd_remaining: float = 0.0
# Lv4 do Fogo: rastro passivo do player + 30% global em queimaduras + 25% área lv2/lv3.
const FIRE_LV4_BURN_MULTIPLIER: float = 1.30
const FIRE_LV4_AREA_SCALE: float = 1.25
const PLAYER_FIRE_TRAIL_SCENE: PackedScene = preload("res://scenes/player_fire_trail.tscn")
const PLAYER_FIRE_TRAIL_SPACING: float = 16.0
const PLAYER_FIRE_TRAIL_DPS: float = 3.0
var _player_fire_trail_last_pos: Vector2 = Vector2.ZERO
var _player_fire_trail_initialized: bool = false
# Chuva de Coins — refatorado pra 4 níveis (era one-shot has_gold_magnet).
# Lv1: +5% drop. Lv2: coins duram 2x + +2% drop. Lv3: +2% drop + pulso slow.
# Lv4: puxa coins na area (mantém has_gold_magnet=true pro código antigo).
var gold_magnet_level: int = 0
var has_gold_magnet: bool = false  # legacy flag (lv4 da Chuva de Coins)
# Dash (refatorado pra 4 níveis em um único upgrade).
# Lv1: dash básico (5s cd). Lv2: rastro de fogo (4.5s). Lv3: auto-attack (4s).
# Lv4: 2 flechas (3.5s).
const DASH_LEVEL_MAX: int = 4
const DASH_COOLDOWNS_BY_LEVEL: Array[float] = [5.5, 4.5, 4.0, 3.5]
var dash_level: int = 0
var has_dash: bool = false
var dash_distance: float = 45.0
var dash_duration: float = 0.22
var dash_cooldown: float = 5.0
var _dash_cd_remaining: float = 0.0
var _is_dashing: bool = false
var _dash_velocity: Vector2 = Vector2.ZERO
var _dash_time_left: float = 0.0
# Flags derivadas de dash_level:
# - has_dash_auto_attack: dash_level >= 3
# - has_dash_double_arrow: dash_level >= 4
var has_dash_auto_attack: bool = false
var has_dash_double_arrow: bool = false
# Flecha de Ricochete (novo upgrade, 4 níveis). Mecânica em arrow.gd.
# Counter incrementa por ATAQUE (não por flecha) — toda volley do Multi Arrow
# compartilha o flag de ricochete, igual à perfuração.
# L1: cada 3 ataques. L2+: cada 2 ataques.
var ricochet_arrow_level: int = 0
var _ricochet_shot_counter: int = 0
# Graviton (ramo Arco/Ataque, 4 níveis). Mecânica do pulso em graviton_pulse.gd.
# Counter idem ricochete: L1 cada 3 ataques, L2+ cada 2. Volley compartilha.
var graviton_level: int = 0
var _graviton_shot_counter: int = 0
# Trilha de poder do dash: spawna um segmento a cada N px percorridos durante
# o dash. Cada segmento dura 3s e dá DPS roxo em inimigos na área.
# DPS escala com dash_level: lv2+ ativa o trail, lv3 e lv4 aumentam dano.
const DASH_TRAIL_SCENE: PackedScene = preload("res://scenes/dash_trail.tscn")
const DASH_TRAIL_SPACING: float = 14.0
const DASH_TRAIL_DPS_BASE: float = 3.0
const DASH_TRAIL_DPS_PER_STACK: float = 2.5
var _dash_last_trail_pos: Vector2 = Vector2.ZERO
# Delay antes da primeira flecha auto-disparada pelo dash (1.3).
const DASH_FIRST_ARROW_DELAY: float = 0.60
# Delay entre 1ª e 2ª flecha (1.3.1) — referente ao tempo da primeira.
const DASH_DOUBLE_ARROW_DELAY: float = 0.40
var arrow_damage_multiplier: float = 1.0  # aplicado ao dano da arrow no spawn
var attack_speed_multiplier: float = 1.0  # 1.0 base, +0.30 por stack
var move_speed_multiplier: float = 1.0  # 1.0 base, +0.10 por stack
# Conta ataques pra decidir quando proca a flecha perfurante (a cada 3 ataques).
# Reseta ao procar. Em level 4, todo ataque é perfurante (counter ignorado).
# IMPORTANTE: incrementa 1× por ATAQUE (não por flecha) — a volley inteira
# de Multiple Arrows compartilha a mesma decisão de pierce.
var _perf_shot_counter: int = 0
var can_attack: bool = true
var is_attacking: bool = false
var is_drawing: bool = false
var is_dead: bool = false
var locked_aim_dir: Vector2 = Vector2.RIGHT
var locked_facing_left: bool = false
var start_position: Vector2 = Vector2.ZERO

# Status effects (slow + poison DoT). Slow só rastreia o multiplicador mais forte ativo.
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0
var _poison_dps: float = 0.0
var _poison_remaining: float = 0.0
var _poison_tick_accum: float = 0.0

# Run stats — exibidos na tela de morte. Tudo zerado em _ready.
var _run_start_msec: int = 0
var stats_enemies_killed: int = 0
var stats_allies_made: int = 0
var stats_damage_dealt: float = 0.0
var stats_damage_taken: float = 0.0


func _ready() -> void:
	add_to_group("player")
	start_position = global_position
	reset_hp()
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(1.0)
	_run_start_msec = Time.get_ticks_msec()

	attack_timer.wait_time = attack_cooldown
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)
	_update_dash(delta)
	_update_fire_skill(delta)
	_update_curse_skill(delta)
	_update_player_fire_trail()
	# Dash trigger lê via polling pra garantir que o cooldown decrementa ANTES
	# do check, e que múltiplas pressões na mesma frame só viram 1 dash.
	if has_dash and not is_dead and Input.is_action_just_pressed("dash"):
		_try_start_dash()
	if is_dead:
		velocity = Vector2.ZERO
		return
	# Durante dash, ignora input e move com velocidade fixa pré-calculada.
	if _is_dashing:
		velocity = _dash_velocity
		move_and_slide()
		return
	# Durante o cast (atacando), o player fica travado.
	var input_vec := Vector2.ZERO
	if not is_attacking:
		input_vec = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
		if input_vec.length() > 1.0:
			input_vec = input_vec.normalized()

	velocity = input_vec * speed * _slow_factor * move_speed_multiplier
	move_and_slide()

	_update_facing(input_vec)
	_update_animation(input_vec)


func apply_slow(multiplier: float, duration: float) -> void:
	# Pega o slow mais forte ativo (multiplier mais baixo) e estende a duração se necessário.
	if is_dead:
		return
	if multiplier < _slow_factor or _slow_remaining <= 0.0:
		_slow_factor = multiplier
	_slow_remaining = maxf(_slow_remaining, duration)


func apply_poison(total_damage: float, duration: float) -> void:
	# Sobrescreve poison ativo se o novo for mais forte (DPS maior) ou refresca duração.
	if is_dead or duration <= 0.0:
		return
	var new_dps: float = total_damage / duration
	if new_dps > _poison_dps or _poison_remaining <= 0.0:
		_poison_dps = new_dps
	_poison_remaining = maxf(_poison_remaining, duration)


func _update_status_effects(delta: float) -> void:
	if _slow_remaining > 0.0:
		_slow_remaining -= delta
		if _slow_remaining <= 0.0:
			_slow_remaining = 0.0
			_slow_factor = 1.0

	if _poison_remaining > 0.0:
		_poison_remaining -= delta
		_poison_tick_accum += delta
		while _poison_tick_accum >= POISON_TICK_INTERVAL and _poison_remaining > -POISON_TICK_INTERVAL:
			_poison_tick_accum -= POISON_TICK_INTERVAL
			_apply_poison_tick(_poison_dps * POISON_TICK_INTERVAL)
			if is_dead:
				return
		if _poison_remaining <= 0.0:
			_poison_remaining = 0.0
			_poison_tick_accum = 0.0
			_poison_dps = 0.0


func _apply_poison_tick(amount: float) -> void:
	# Dano silencioso: sem flash/som/damage_effect — só hp-, hp_bar, e damage number verde.
	if is_dead or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	notify_damage_taken(amount)
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_spawn_poison_number(amount)
	if hp == 0.0:
		_die()


func _spawn_poison_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	num.modulate = poison_number_color
	num.position = global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(num)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if is_dead:
		return
	if event.is_action_pressed("attack") and can_attack:
		# Em target mode da fire skill, left-click confirma o cast em vez de
		# atirar a flecha. Sem targeter aberto, comportamento normal.
		if _fire_skill_targeting:
			_confirm_fire_skill_cast()
		else:
			_start_attack()
	elif event.is_action_pressed("skill"):
		_use_skill()
	elif event.is_action_pressed("fire_cast"):
		# Q dispatcha pra elemental skill ativa. Fogo lv3+ → indicator+area.
		# Maldição lv4+ → raio em linha reta instantâneo. Por design, só uma
		# categoria por jogo. Se ambas (ex: dev mode), Fogo tem prioridade.
		if fire_arrow_level >= 3:
			_handle_fire_skill_press()
		elif curse_arrow_level >= 4:
			_cast_curse_beam()


func _update_facing(input_vec: Vector2) -> void:
	# Atacando: usa o lado travado no clique (mesmo critério usado pra prever o muzzle).
	# Andando: direção do movimento.
	if is_attacking:
		sprite.flip_h = locked_facing_left
	elif input_vec.x != 0.0:
		sprite.flip_h = input_vec.x < 0.0
	# Mantém o muzzle no lado pra onde o boneco está olhando.
	muzzle.position.x = -muzzle_offset_x if sprite.flip_h else muzzle_offset_x


func _update_animation(_input_vec: Vector2) -> void:
	if is_attacking:
		return
	# Garante que walk/idle não herdem o speed_scale do ataque (attack speed
	# upgrade só acelera a anim de ataque, não a movimentação).
	if sprite.speed_scale != 1.0:
		sprite.speed_scale = 1.0
	if velocity.length() > 0.0:
		if sprite.animation != "walk":
			sprite.play("walk")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")


func _start_attack() -> void:
	# Trava a direção AGORA (no clique). A flecha sai no frame de release com essa direção.
	# Calcula a partir da posição prevista do muzzle (lado pra onde o player vai virar),
	# não do centro do player — senão a flecha sai paralela e erra o alvo por ~muzzle_offset_x.
	var mouse_pos := get_global_mouse_position()
	locked_facing_left = mouse_pos.x < global_position.x
	var predicted_muzzle := global_position + Vector2(
		-muzzle_offset_x if locked_facing_left else muzzle_offset_x,
		muzzle.position.y
	)
	locked_aim_dir = (mouse_pos - predicted_muzzle).normalized()
	can_attack = false
	is_attacking = true
	is_drawing = true
	# Attack speed: encurta cooldown e acelera a anim de ataque (release_frame chega
	# proporcionalmente mais cedo). speed_scale só vale enquanto a anim está rolando.
	attack_timer.wait_time = attack_cooldown / attack_speed_multiplier
	sprite.speed_scale = attack_speed_multiplier
	attack_timer.start()
	sprite.play("attack")


func _release_arrow() -> void:
	is_drawing = false
	if arrow_scene == null:
		return
	# Decisão de pierce é feita UMA VEZ por ataque — a volley inteira de
	# Multiple Arrows compartilha o mesmo flag (ex: lv perfuração 1 + multi lv1
	# = a cada 3º ataque, as 3 flechas perfuram juntas).
	var is_pierce: bool = _is_piercing_shot()
	if is_pierce:
		_perf_shot_counter = 0
	else:
		_perf_shot_counter += 1
	# Ricochete: mesma regra (1× por ataque, toda volley compartilha).
	var is_ricochet: bool = _is_ricochet_shot()
	if is_ricochet:
		_ricochet_shot_counter = 0
	elif ricochet_arrow_level > 0:
		_ricochet_shot_counter += 1
	# Graviton: mesma regra (volley compartilha o flag).
	var is_graviton: bool = _is_graviton_shot()
	if is_graviton:
		_graviton_shot_counter = 0
	elif graviton_level > 0:
		_graviton_shot_counter += 1
	var volley: Array = _build_volley()
	for i in volley.size():
		var shot: Dictionary = volley[i]
		# Só a primeira flecha toca o som — evita 3-10 cópias do shoot.mp3
		# tocando juntas (cada uma +~3dB acima da anterior).
		# is_primary = i == 0 → flechas extras têm fogo reduzido pra 35%.
		_spawn_arrow(shot["dir"], shot["dmg_mult"], is_pierce, i == 0, i == 0, is_ricochet, is_graviton)


# Cada entrada da volley = {dir: Vector2, dmg_mult: float} (relativo ao dmg base).
# Multi Arrow combina com perfuração/elementais aplicando o mesmo flag em todas.
func _build_volley() -> Array:
	var primary: Vector2 = locked_aim_dir
	var shots: Array = []
	match multi_arrow_level:
		0:
			shots.append({"dir": primary, "dmg_mult": 1.0})
		1:
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(30.0)), "dmg_mult": 0.5})
			shots.append({"dir": primary.rotated(deg_to_rad(-30.0)), "dmg_mult": 0.5})
		2:
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(30.0)), "dmg_mult": 0.8})
			shots.append({"dir": primary.rotated(deg_to_rad(-30.0)), "dmg_mult": 0.8})
		3:
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(15.0)), "dmg_mult": 0.8})
			shots.append({"dir": primary.rotated(deg_to_rad(-15.0)), "dmg_mult": 0.8})
			shots.append({"dir": primary.rotated(deg_to_rad(45.0)), "dmg_mult": 0.8})
			shots.append({"dir": primary.rotated(deg_to_rad(-45.0)), "dmg_mult": 0.8})
		_:
			# Lv 4: 10 flechas em todas as direções (TAU/10 = 36°), 80% cada.
			for i in 10:
				var ang: float = (TAU / 10.0) * float(i)
				shots.append({"dir": primary.rotated(ang), "dmg_mult": 0.8})
	return shots


func _spawn_arrow(dir: Vector2, dmg_mult: float, is_pierce: bool, play_sound: bool, is_primary: bool = true, is_ricochet: bool = false, is_graviton: bool = false) -> void:
	var arrow := arrow_scene.instantiate()
	# Configura ANTES de add_child pra _ready() já enxergar os flags.
	arrow.global_position = muzzle.global_position
	if "play_shoot_sound" in arrow:
		arrow.play_shoot_sound = play_sound
	if "damage" in arrow:
		arrow.damage = arrow.damage * arrow_damage_multiplier * dmg_mult
	if is_pierce:
		if "is_piercing" in arrow:
			arrow.is_piercing = true
		# Bonus de dano da perfuração entra como multiplicador do PRIMEIRO alvo
		# atingido. Os demais que a flecha atravessar recebem `damage` base.
		if "pierce_first_dmg_mult" in arrow:
			arrow.pierce_first_dmg_mult = 1.0 + _perf_damage_bonus()
		if "hitbox_scale" in arrow and perfuracao_level >= 2:
			arrow.hitbox_scale = 1.8
	if chain_lightning_level > 0:
		if "chain_count" in arrow:
			arrow.chain_count = _chain_target_count()
		if "chain_dmg_pct" in arrow:
			arrow.chain_dmg_pct = _chain_damage_pct()
		if "chain_bonus_chance" in arrow:
			arrow.chain_bonus_chance = _chain_bonus_chance()
	if fire_arrow_level > 0:
		if "is_fire" in arrow:
			arrow.is_fire = true
		# Multi Arrow combo: flechas extras têm fogo reduzido. Burn (tick do
		# hit) cai 30% (= 70% do normal); rastro cai 65% (= 35% do normal).
		var burn_scale: float = 1.0 if is_primary else 0.70
		var trail_scale: float = 1.0 if is_primary else 0.35
		if "burn_dps" in arrow:
			arrow.burn_dps = _fire_burn_dps() * burn_scale
		if "burn_duration" in arrow:
			arrow.burn_duration = _fire_burn_duration()
		# Lv2+: rastro de fogo no caminho da flecha.
		if fire_arrow_level >= 2:
			if "fire_trail_enabled" in arrow:
				arrow.fire_trail_enabled = true
			if "fire_trail_dps" in arrow:
				arrow.fire_trail_dps = _fire_trail_dps() * trail_scale
			# Lv4: aumenta área dos segmentos de rastro em 25%.
			if "fire_trail_scale" in arrow:
				arrow.fire_trail_scale = _fire_area_scale()
	if curse_arrow_level > 0:
		if "is_curse" in arrow:
			arrow.is_curse = true
		# Multi Arrow combo: flechas extras com curse reduzido (igual fogo).
		var curse_scale: float = 1.0 if is_primary else 0.70
		if "curse_dps" in arrow:
			arrow.curse_dps = _curse_dps() * curse_scale
		if "curse_duration" in arrow:
			arrow.curse_duration = _curse_duration()
		if "curse_slow_factor" in arrow:
			arrow.curse_slow_factor = _curse_slow_factor()
	if is_ricochet:
		if "is_ricochet" in arrow:
			arrow.is_ricochet = true
		if "ricochet_hops_remaining" in arrow:
			arrow.ricochet_hops_remaining = _ricochet_max_hops()
		if "ricochet_splits_remaining" in arrow:
			arrow.ricochet_splits_remaining = _ricochet_max_splits()
	if is_graviton:
		if "is_graviton" in arrow:
			arrow.is_graviton = true
		if "graviton_radius" in arrow:
			arrow.graviton_radius = _graviton_radius()
		if "graviton_lifetime" in arrow:
			arrow.graviton_lifetime = _graviton_lifetime()
		if "graviton_slow_factor" in arrow:
			arrow.graviton_slow_factor = _graviton_slow_factor()
		if "graviton_explosion_damage" in arrow:
			arrow.graviton_explosion_damage = _graviton_explosion_damage()
		if "source" in arrow:
			arrow.source = self
	_get_world().add_child(arrow)
	if arrow.has_method("set_direction"):
		arrow.set_direction(dir)


func _is_piercing_shot() -> bool:
	if perfuracao_level <= 0:
		return false
	if perfuracao_level >= 4:
		return true
	# Levels 1-3: a cada 3 ataques (shots 1,2,3 → 3rd procca).
	return _perf_shot_counter >= 2


func _is_ricochet_shot() -> bool:
	# L1: cada 3 ataques. L2+: cada 2 ataques.
	if ricochet_arrow_level <= 0:
		return false
	if ricochet_arrow_level == 1:
		return _ricochet_shot_counter >= 2
	return _ricochet_shot_counter >= 1


func _ricochet_max_hops() -> int:
	# L1/L2: 1 ricochete. L3+: 2 ricochetes.
	if ricochet_arrow_level >= 3:
		return 2
	return 1


func _ricochet_max_splits() -> int:
	# Quantos ricochetes ainda podem se dividir em 2.
	# L1: 0. L2: 1 (só o 1º). L3: 1 (só o 1º — 2º não divide). L4: 2 (todos dividem).
	if ricochet_arrow_level <= 1:
		return 0
	if ricochet_arrow_level == 4:
		return 2
	return 1


func _is_graviton_shot() -> bool:
	# L1: cada 3 ataques. L2+: cada 2 ataques.
	if graviton_level <= 0:
		return false
	if graviton_level == 1:
		return _graviton_shot_counter >= 2
	return _graviton_shot_counter >= 1


func _graviton_radius() -> float:
	# Range do pulso. Tunado pra ficar contido — L4 cresce mas não absurdo.
	match graviton_level:
		1: return 45.0
		2: return 60.0
		3: return 60.0
		4: return 75.0
	return 45.0


func _graviton_lifetime() -> float:
	# L1 nerf: dura menos pra não dominar (pulso ficava muito mais útil que custo).
	# L2+ mantém os 3s da spec.
	if graviton_level == 1:
		return 1.8
	return 3.0


func _graviton_slow_factor() -> float:
	# Slow no campo. L1-L3 = 30% slow (factor 0.7). L4 = 45% (factor 0.55).
	if graviton_level >= 4:
		return 0.55
	return 0.7


func _graviton_explosion_damage() -> float:
	# L3+ o pulso explode no fim. L3=30, L4=50 (área e dano aumentados).
	match graviton_level:
		3: return 30.0
		4: return 50.0
	return 0.0


func _fire_burn_multiplier() -> float:
	# Lv4 dá +30% global em todas queimaduras (BurnDoT, fire trail, fire field).
	return FIRE_LV4_BURN_MULTIPLIER if fire_arrow_level >= 4 else 1.0


func _fire_area_scale() -> float:
	# Lv4 aumenta área do rastro de flecha (lv2) e do fire field (lv3) em 25%.
	return FIRE_LV4_AREA_SCALE if fire_arrow_level >= 4 else 1.0


func _fire_burn_dps() -> float:
	# Base por nível × multiplier global. tick_interval do BurnDoT é 0.5s, então
	# +2 em dps = +1 dano por tick (balanceamento pedido pelo design).
	var base: float = 0.0
	match fire_arrow_level:
		1: base = 6.0
		2: base = 7.0
		3: base = 9.0
		4: base = 12.0
	return base * _fire_burn_multiplier()


func _fire_burn_duration() -> float:
	# Tempo total que o fogo causa tick — aumentado de 3s pra 4.5s pra mais ticks.
	return 4.5


func _fire_trail_dps() -> float:
	# Lv2+ : DPS do rastro de fogo da flecha × multiplier global.
	var base: float = 0.0
	match fire_arrow_level:
		2: base = 4.0
		3: base = 5.0
		4: base = 7.0
	return base * _fire_burn_multiplier()


func _curse_dps() -> float:
	# DoT toxic da maldição. Spec só define lv1 — escalei levemente pra
	# diferenciar níveis sem mudar o design (lv2-4 focam na conversão de aliados).
	# Lv1 = 3 dps × 4s = 12 total dmg. Mesmo gate do fogo: sem dano, arrow(25)
	# + DoT(12) = 37 não mata macaco wave 1 (40 HP); com dano, arrow(30) +
	# DoT(12) = 42 mata via DoT.
	match curse_arrow_level:
		1: return 3.0
		2: return 4.0
		3: return 6.0
		4: return 8.0
	return 0.0


func _curse_duration() -> float:
	return 4.0


func _curse_slow_factor() -> float:
	# Slow aplicado ao inimigo. Escala suave por nível.
	match curse_arrow_level:
		1: return 0.65
		2: return 0.58
		3: return 0.52
		4: return 0.45
	return 1.0


func curse_convert_chance() -> float:
	# Chance ao matar enemy de convertê-lo em aliado. Lv2 = 18%, lv3 = 33%, lv4 = 50%.
	# Verificado pelo enemy.take_damage no momento da morte se tem CurseDebuff ativo.
	match curse_arrow_level:
		2: return 0.18
		3: return 0.33
		4: return 0.50
	return 0.0


func curse_convert_duration() -> String:
	# Lv2: até final da horda. Lv3+: até final do turno.
	# Como horda/turno são sinônimos no jogo, ambos usam wave_manager.end_of_wave_cleanup.
	# Retorna string descritiva pra UI/debug.
	if curse_arrow_level >= 3:
		return "turno"
	return "horda"


func _chain_target_count() -> int:
	# Lv4 = "todos da área" — usa um número alto (1000) que é capado pelo
	# tamanho real de candidates no arrow.
	match chain_lightning_level:
		1: return 1
		2: return 2
		3: return 4
		4: return 1000
	return 0


func _chain_damage_pct() -> float:
	match chain_lightning_level:
		1: return 0.30
		2: return 0.50
		3: return 0.60
		4: return 1.00
	return 0.0


func _chain_bonus_chance() -> float:
	# Lv2: 30% de chance de cadeiar num 3º alvo além dos 2 garantidos.
	if chain_lightning_level == 2:
		return 0.30
	return 0.0


func _perf_damage_bonus() -> float:
	match perfuracao_level:
		1: return 0.30
		2: return 0.60
		3: return 0.90
		4: return 0.90
	return 0.0


func _use_skill() -> void:
	# Botão direito: placeholder pra futuras skills (fire skill foi pra Q+left).
	print("skill triggered toward: ", get_global_mouse_position())


func _handle_fire_skill_press() -> void:
	if _fire_skill_targeting:
		_confirm_fire_skill_cast()
		return
	if _fire_skill_cd_remaining > 0.0:
		return
	_start_fire_skill_targeting()


func _start_fire_skill_targeting() -> void:
	_fire_skill_targeting = true
	_fire_skill_indicator = FIRE_SKILL_INDICATOR_SCENE.instantiate()
	if "range_radius" in _fire_skill_indicator:
		_fire_skill_indicator.range_radius = FIRE_SKILL_RANGE
	if "area_radius" in _fire_skill_indicator:
		_fire_skill_indicator.area_radius = FIRE_SKILL_AREA_RADIUS
	_get_world().add_child(_fire_skill_indicator)
	_update_fire_skill_indicator()


func _update_fire_skill_indicator() -> void:
	if _fire_skill_indicator == null or not is_instance_valid(_fire_skill_indicator):
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var target: Vector2 = mouse_pos
	if _fire_skill_indicator.has_method("get_clamped_target"):
		target = _fire_skill_indicator.get_clamped_target(global_position, mouse_pos)
	if _fire_skill_indicator.has_method("update_positions"):
		_fire_skill_indicator.update_positions(global_position, target)


func _confirm_fire_skill_cast() -> void:
	if _fire_skill_indicator == null or not is_instance_valid(_fire_skill_indicator):
		_fire_skill_targeting = false
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var target: Vector2 = mouse_pos
	if _fire_skill_indicator.has_method("get_clamped_target"):
		target = _fire_skill_indicator.get_clamped_target(global_position, mouse_pos)
	# Despawn indicator
	_fire_skill_indicator.queue_free()
	_fire_skill_indicator = null
	_fire_skill_targeting = false
	# Spawn projectile (com lv4 multipliers se aplicáveis).
	var proj: Node = FIRE_SKILL_PROJECTILE_SCENE.instantiate()
	if "field_dps" in proj:
		proj.field_dps = FIRE_SKILL_DPS * _fire_burn_multiplier()
	if "field_duration" in proj:
		proj.field_duration = FIRE_SKILL_DURATION
	if "field_scale" in proj:
		proj.field_scale = _fire_area_scale()
	_get_world().add_child(proj)
	if proj.has_method("setup"):
		proj.setup(global_position, target)
	# Cooldown
	_fire_skill_cd_remaining = FIRE_SKILL_COOLDOWN
	fire_skill_cooldown_changed.emit(_fire_skill_cd_remaining, FIRE_SKILL_COOLDOWN)


func _update_player_fire_trail() -> void:
	# Lv4 do Fogo: dropa segmentos de player_fire_trail enquanto o player anda.
	# NÃO dropa parado (velocity zero) nem morto.
	if fire_arrow_level < 4 or is_dead:
		return
	if velocity.length() < 1.0:
		_player_fire_trail_initialized = false  # reset, próximo movimento dropa imediato
		return
	if not _player_fire_trail_initialized:
		_player_fire_trail_initialized = true
		_player_fire_trail_last_pos = global_position
		_spawn_player_fire_trail_segment()
		return
	if global_position.distance_to(_player_fire_trail_last_pos) >= PLAYER_FIRE_TRAIL_SPACING:
		_player_fire_trail_last_pos = global_position
		_spawn_player_fire_trail_segment()


func _spawn_player_fire_trail_segment() -> void:
	if PLAYER_FIRE_TRAIL_SCENE == null:
		return
	var seg: Node = PLAYER_FIRE_TRAIL_SCENE.instantiate()
	if "damage_per_second" in seg:
		seg.damage_per_second = PLAYER_FIRE_TRAIL_DPS * _fire_burn_multiplier()
	_get_world().add_child(seg)
	if seg is Node2D:
		(seg as Node2D).global_position = global_position


func _update_fire_skill(delta: float) -> void:
	if _fire_skill_targeting:
		_update_fire_skill_indicator()
	if _fire_skill_cd_remaining > 0.0:
		_fire_skill_cd_remaining = maxf(_fire_skill_cd_remaining - delta, 0.0)
		fire_skill_cooldown_changed.emit(_fire_skill_cd_remaining, FIRE_SKILL_COOLDOWN)


func _cast_curse_beam() -> void:
	# Lv4: raio roxo sustentado por CURSE_SKILL_DURATION segundos. Direção
	# travada no momento do cast (mouse). Aplica damage + CurseDebuff por tick.
	if _curse_skill_cd_remaining > 0.0:
		return
	if CURSE_BEAM_SCENE == null:
		return
	var mouse_pos: Vector2 = get_global_mouse_position()
	var dir: Vector2 = (mouse_pos - global_position).normalized()
	if dir.length() < 0.01:
		return
	var beam: Node = CURSE_BEAM_SCENE.instantiate()
	if "damage_per_tick" in beam:
		beam.damage_per_tick = CURSE_SKILL_DAMAGE_PER_TICK
	if "max_range_per_side" in beam:
		beam.max_range_per_side = CURSE_SKILL_RANGE
	if "lifetime" in beam:
		beam.lifetime = CURSE_SKILL_DURATION
	if "warmup_duration" in beam:
		beam.warmup_duration = CURSE_SKILL_WARMUP
	if "curse_dps" in beam:
		beam.curse_dps = _curse_dps()
	if "curse_duration" in beam:
		beam.curse_duration = _curse_duration()
	if "curse_slow_factor" in beam:
		beam.curse_slow_factor = _curse_slow_factor()
	_get_world().add_child(beam)
	if beam.has_method("setup"):
		beam.setup(global_position, dir)
	# Cd cobre duração do beam (5s) + cooldown limpo (3s) = 8s total cycle.
	_curse_skill_cd_remaining = CURSE_SKILL_TOTAL_CYCLE
	curse_skill_cooldown_changed.emit(_curse_skill_cd_remaining, CURSE_SKILL_TOTAL_CYCLE)


func _update_curse_skill(delta: float) -> void:
	if _curse_skill_cd_remaining > 0.0:
		_curse_skill_cd_remaining = maxf(_curse_skill_cd_remaining - delta, 0.0)
		curse_skill_cooldown_changed.emit(_curse_skill_cd_remaining, CURSE_SKILL_TOTAL_CYCLE)


func _try_start_dash() -> void:
	if _is_dashing or _dash_cd_remaining > 0.0 or is_attacking:
		return
	# Direção: input atual; se não tiver, dash pra onde o sprite está virado.
	var dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)
	if dir.length() < 0.1:
		dir = Vector2.LEFT if sprite.flip_h else Vector2.RIGHT
	dir = dir.normalized()
	_is_dashing = true
	_dash_time_left = dash_duration
	_dash_velocity = dir * (dash_distance / dash_duration)
	_dash_cd_remaining = dash_cooldown
	# Vira o sprite na direção do dash (mantém facing se for puramente vertical).
	if dir.x != 0.0:
		sprite.flip_h = dir.x < 0.0
		muzzle.position.x = -muzzle_offset_x if sprite.flip_h else muzzle_offset_x
	# Anim "dash" se existir; senão mantém a atual.
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("dash"):
		sprite.speed_scale = 1.0
		sprite.play("dash")
	_play_dash_sound()
	dash_cooldown_changed.emit(_dash_cd_remaining, dash_cooldown)
	# Trilha de poder: dropa primeiro segmento + reseta marker pra próximos.
	# Lv2+ do dash consolidado.
	if dash_level >= 2:
		_dash_last_trail_pos = global_position
		_spawn_dash_trail_segment()
	# Auto-attack: dispara flecha no inimigo mais próximo após delay
	# (e segunda flecha após mais um delay se tiver 1.3.1).
	if has_dash_auto_attack:
		get_tree().create_timer(DASH_FIRST_ARROW_DELAY).timeout.connect(func() -> void:
			if not is_dead:
				_dash_auto_attack_volley()
		)
		if has_dash_double_arrow:
			get_tree().create_timer(DASH_FIRST_ARROW_DELAY + DASH_DOUBLE_ARROW_DELAY).timeout.connect(func() -> void:
				if not is_dead:
					_dash_auto_attack_volley()
			)


func _play_dash_sound() -> void:
	if DASH_SOUND == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = DASH_SOUND
	p.volume_db = -22.0
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	p.finished.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _update_dash(delta: float) -> void:
	if _is_dashing:
		_dash_time_left -= delta
		# Drop trail segments periodicamente conforme o player anda durante dash.
		if dash_level >= 2:
			var moved: float = global_position.distance_to(_dash_last_trail_pos)
			if moved >= DASH_TRAIL_SPACING:
				_spawn_dash_trail_segment()
				_dash_last_trail_pos = global_position
		if _dash_time_left <= 0.0:
			_is_dashing = false
			_dash_velocity = Vector2.ZERO
	if _dash_cd_remaining > 0.0:
		_dash_cd_remaining = maxf(_dash_cd_remaining - delta, 0.0)
		dash_cooldown_changed.emit(_dash_cd_remaining, dash_cooldown)


func _spawn_dash_trail_segment() -> void:
	if DASH_TRAIL_SCENE == null:
		return
	var seg: Node = DASH_TRAIL_SCENE.instantiate()
	if "damage_per_second" in seg:
		# Dano cresce com dash_level (lv2 = base, lv3+ ganha bonus).
		seg.damage_per_second = DASH_TRAIL_DPS_BASE + DASH_TRAIL_DPS_PER_STACK * float(maxi(dash_level - 2, 0))
	_get_world().add_child(seg)
	if seg is Node2D:
		(seg as Node2D).global_position = global_position


func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var best_dist: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var d: float = (e as Node2D).global_position.distance_to(global_position)
		if d < best_dist:
			nearest = e
			best_dist = d
	return nearest


func _dash_auto_attack_volley() -> void:
	# Auto-attack durante dash: usa todos os efeitos de upgrade (multi/chain/dmg)
	# mas NÃO incrementa _perf_shot_counter (excalidraw: "não conta como +1
	# ataque para o terceiro do perfurante").
	if arrow_scene == null:
		return
	var target: Node2D = _find_nearest_enemy()
	if target == null:
		return
	var dir: Vector2 = (target.global_position - global_position).normalized()
	if dir.length() < 0.01:
		return
	# Pierce/ricochete/graviton: usa estado atual dos counters sem alterá-los.
	var is_pierce: bool = _is_piercing_shot()
	var is_ricochet: bool = _is_ricochet_shot()
	var is_graviton: bool = _is_graviton_shot()
	# Move muzzle pra direção do tiro pra spawn coerente.
	if dir.x != 0.0:
		muzzle.position.x = -muzzle_offset_x if dir.x < 0.0 else muzzle_offset_x
	# Trava aim no alvo — _build_volley usa locked_aim_dir como direção principal.
	var saved_aim: Vector2 = locked_aim_dir
	locked_aim_dir = dir
	var volley: Array = _build_volley()
	for i in volley.size():
		var shot: Dictionary = volley[i]
		_spawn_arrow(shot["dir"], shot["dmg_mult"], is_pierce, i == 0, i == 0, is_ricochet, is_graviton)
	# Restaura aim e muzzle pro estado atual do sprite (next _update_facing
	# fixaria de qualquer forma, mas restaurar evita visual flicker).
	locked_aim_dir = saved_aim
	muzzle.position.x = -muzzle_offset_x if sprite.flip_h else muzzle_offset_x


func reset_hp() -> void:
	if is_dead:
		return
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
	_clear_status_effects()


func heal(amount: float) -> void:
	# Cura usada pelo coração de Life Steal e qualquer outro pickup curativo.
	if is_dead or amount <= 0.0:
		return
	hp = minf(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# Aplicação dos upgrades comprados na shop pós-wave.
func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"hp":
			hp_upgrades += 1
			# +15% do max_hp original (60) por stack
			max_hp += 15.0
			hp = min(hp + 15.0, max_hp)
			hp_changed.emit(hp, max_hp)
			if hp_bar != null:
				hp_bar.set_ratio(hp / max_hp)
		"armor":
			armor_level += 1
			damage_reduction_pct = _compute_damage_reduction(armor_level)
		"damage":
			damage_upgrades += 1
			# +20% no dano da flecha por stack
			arrow_damage_multiplier += 0.20
		"perfuracao":
			perfuracao_level = mini(perfuracao_level + 1, 4)
		"attack_speed":
			attack_speed_level += 1
			# +30% por stack (aditivo). Aplica imediatamente — próximo ataque
			# já usa o novo wait_time/speed_scale via _start_attack.
			attack_speed_multiplier += 0.30
		"multi_arrow":
			multi_arrow_level = mini(multi_arrow_level + 1, 4)
		"chain_lightning":
			chain_lightning_level = mini(chain_lightning_level + 1, 4)
		"move_speed":
			move_speed_level += 1
			# +10% por stack (aditivo). Aplica imediatamente — _physics_process
			# usa o novo multiplier no próximo frame.
			move_speed_multiplier += 0.10
		"life_steal":
			# +5% chance + +10% heal nos drops de coração por stack (sem max).
			life_steal_level += 1
		"fire_arrow":
			# Elemental Fogo. Lv1: flecha de fogo + queima ao contato (DPS).
			# Lv2: rastro de fogo. Lv3: skill direita (arremesso de área).
			var was_below_3: bool = fire_arrow_level < 3
			fire_arrow_level = mini(fire_arrow_level + 1, 4)
			if was_below_3 and fire_arrow_level >= 3:
				_fire_skill_cd_remaining = 0.0
				fire_skill_unlocked.emit()
				fire_skill_cooldown_changed.emit(0.0, FIRE_SKILL_COOLDOWN)
		"curse_arrow":
			# Elemental Maldição. Lv1: flecha amaldiçoada (slow + DoT toxic).
			# Lv2: 18% chance ao matar → enemy vira aliado até fim da horda.
			# Lv3: 33% + todos aliados aplicam slow/DoT ao causar dano.
			# Lv4: 50% + skill Q (raio roxo em linha reta, cd 3s).
			var was_below_4_curse: bool = curse_arrow_level < 4
			curse_arrow_level = mini(curse_arrow_level + 1, 4)
			if was_below_4_curse and curse_arrow_level >= 4:
				_curse_skill_cd_remaining = 0.0
				curse_skill_unlocked.emit()
				curse_skill_cooldown_changed.emit(0.0, CURSE_SKILL_TOTAL_CYCLE)
		"leno":
			leno_level = mini(leno_level + 1, 4)
			_refresh_lenos()
		"woodwarden":
			# Cada compra do aliado conta como um "level up" — wave_manager
			# usa o level pra escalar HP/dmg quando spawna/respawna.
			# Max 4 compras (= 4 woodwardens, full stats).
			woodwarden_level = mini(woodwarden_level + 1, 4)
		"gold_magnet":
			# Refatorado pra 4 níveis (Chuva de Coins). Lv1+ habilita drop chance
			# bonus (gold_drop.gd lê o level via get_upgrade_count).
			gold_magnet_level = mini(gold_magnet_level + 1, 4)
			# Lv4 (puxe global): mantém a flag legada usada por gold.gd.
			has_gold_magnet = gold_magnet_level >= 4
		"dash":
			# Refatorado pra 4 níveis. Cada nível atualiza cooldown + features.
			# Lv1: dash básico cd 5s
			# Lv2: rastro de fogo, cd 4.5s
			# Lv3: auto-attack após dash, cd 4s
			# Lv4: 2 flechas após dash, cd 3.5s
			if dash_level >= DASH_LEVEL_MAX:
				return
			dash_level = mini(dash_level + 1, DASH_LEVEL_MAX)
			if dash_level == 1:
				has_dash = true
				_dash_cd_remaining = 0.0
				dash_unlocked.emit()
			has_dash_auto_attack = dash_level >= 3
			has_dash_double_arrow = dash_level >= 4
			dash_cooldown = DASH_COOLDOWNS_BY_LEVEL[dash_level - 1]
			dash_cooldown_changed.emit(_dash_cd_remaining, dash_cooldown)
		"ricochet_arrow":
			# Lv1-4 da flecha de ricochete. Mecânica é resolvida em arrow.gd
			# baseada no nível atual do player.
			ricochet_arrow_level = mini(ricochet_arrow_level + 1, 4)
		"graviton":
			# Lv1-4 do Graviton. Mecânica em arrow.gd + graviton_pulse.gd.
			# L1: cada 3 ataques cria pulso ao bater. L2: cada 2 + range maior.
			# L3: pulso explode no fim (30 dano). L4: área e dano aumentados.
			graviton_level = mini(graviton_level + 1, 4)


func get_upgrade_count(upgrade_id: String) -> int:
	match upgrade_id:
		"hp": return hp_upgrades
		"armor": return armor_level
		"damage": return damage_upgrades
		"perfuracao": return perfuracao_level
		"attack_speed": return attack_speed_level
		"multi_arrow": return multi_arrow_level
		"chain_lightning": return chain_lightning_level
		"move_speed": return move_speed_level
		"life_steal": return life_steal_level
		"fire_arrow": return fire_arrow_level
		"curse_arrow": return curse_arrow_level
		"woodwarden": return woodwarden_level
		"leno": return leno_level
		"gold_magnet": return gold_magnet_level
		"dash": return dash_level
		"ricochet_arrow": return ricochet_arrow_level
		"graviton": return graviton_level
	return 0


func _clear_status_effects() -> void:
	_slow_factor = 1.0
	_slow_remaining = 0.0
	_poison_dps = 0.0
	_poison_remaining = 0.0
	_poison_tick_accum = 0.0


func reset_position() -> void:
	if is_dead:
		return
	global_position = start_position
	velocity = Vector2.ZERO


func _refresh_lenos() -> void:
	# Spawna/remove lenos pra match o target_count + atualiza stats em todos.
	# L1: 1 leno @ 20 dmg / 1.4s cd. L2: 1 leno @ 50 dmg / 0.95s cd (mais speed).
	# L3: 2 lenos. L4: 3 lenos. Phase offset garante orbits espaçadas.
	var target_count: int = _leno_target_count()
	# L1=8 dmg / 2.3s cd. L2+=18 dmg / 1.6s cd (boost de speed e dano sem
	# one-shotar macaco wave 1 que tem 40 HP).
	var dmg: float = 18.0 if leno_level >= 2 else 8.0
	var atk_cd: float = 1.6 if leno_level >= 2 else 2.3
	# Limpa entries inválidos (queue_freed entre rounds, etc).
	var alive: Array[Node2D] = []
	for l in _lenos:
		if is_instance_valid(l):
			alive.append(l)
	_lenos = alive
	while _lenos.size() < target_count:
		var leno: Node2D = LENO_SCENE.instantiate()
		_lenos.append(leno)
		_get_world().add_child(leno)
	while _lenos.size() > target_count:
		var extra: Node2D = _lenos.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	# Atualiza stats e phase em todos (re-distribui órbita).
	for i in _lenos.size():
		var l: Node2D = _lenos[i]
		if "damage" in l:
			l.damage = dmg
		if "attack_cooldown" in l:
			l.attack_cooldown = atk_cd
		if "phase_offset" in l:
			l.phase_offset = TAU * float(i) / float(maxi(target_count, 1))


func _leno_target_count() -> int:
	match leno_level:
		1: return 1
		2: return 1
		3: return 2
		4: return 3
	return 0


func _cleanup_lenos() -> void:
	for l in _lenos:
		if is_instance_valid(l):
			l.queue_free()
	_lenos.clear()


func _compute_damage_reduction(level: int) -> float:
	# Armor: L1=5%, L2=7%, L3=10%, L4=13%, L5+=+2% por stack após L4. Cap em
	# 75% pra evitar invencibilidade absoluta.
	match level:
		0: return 0.0
		1: return 0.05
		2: return 0.07
		3: return 0.10
		4: return 0.13
	return minf(0.13 + 0.02 * float(level - 4), 0.75)


func reset_perf_counter() -> void:
	# Chamado pelo wave_manager no início de cada wave pra evitar que o counter
	# persistente faça a 1ª flecha do round virar perfurante.
	_perf_shot_counter = 0


func take_damage(amount: float) -> void:
	if is_dead:
		return
	# Armor: reduz dano antes de aplicar — número/notify usam o valor reduzido,
	# pra a UI mostrar o que de fato saiu do HP do player.
	var reduced: float = amount * (1.0 - damage_reduction_pct)
	hp = maxf(hp - reduced, 0.0)
	notify_damage_taken(reduced)
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(reduced)
	if damage_audio != null:
		damage_audio.play()
	if hp == 0.0:
		_die()


func _die() -> void:
	is_dead = true
	is_attacking = false
	is_drawing = false
	if sprite != null:
		sprite.stop()
	if hp_bar != null:
		hp_bar.visible = false
	# Lenos morrem com o player (spec do excalidraw).
	_cleanup_lenos()
	_stop_world_audio()
	# Som de morte tem que vir DEPOIS do _stop_world_audio pra não ser cortado.
	# Anexa no scene root (fora do "world") pra sobreviver à animação de morte.
	_play_death_sound()
	died.emit()
	_play_death_sequence()


func _play_death_sound() -> void:
	if DEATH_SOUND == null:
		return
	# Música pausa pra dar espaço dramático e volta gradual quando o som termina.
	var music := get_tree().current_scene.get_node_or_null("Music") as AudioStreamPlayer
	var music_original_db: float = -30.0
	if music != null:
		music_original_db = music.volume_db
		var fade_down := create_tween()
		fade_down.tween_property(music, "volume_db", -80.0, 0.25)
		fade_down.tween_callback(music.stop)
	var p := AudioStreamPlayer.new()
	p.stream = DEATH_SOUND
	p.volume_db = -14.0
	get_tree().current_scene.add_child(p)
	p.play()
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		if music != null and is_instance_valid(music):
			music.volume_db = -80.0
			music.play()
			var fade_up := create_tween()
			fade_up.tween_property(music, "volume_db", music_original_db, 1.8)
	)


func _stop_world_audio() -> void:
	# Para todos AudioStreamPlayer2D do mundo (projétil shoot sounds, damage
	# sounds dinâmicos, etc) pra não continuarem soando durante a tela de morte.
	# Música de fundo fica em Main (fora de "world"), então não é afetada.
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_stop_audio_in_subtree(world)


func _stop_audio_in_subtree(node: Node) -> void:
	if node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	for child in node.get_children():
		_stop_audio_in_subtree(child)


func _play_death_sequence() -> void:
	# Toda a sequência roda na HUD (CanvasLayer top), pra ficar por cima do preto.
	# O player "real" no mundo é escondido — o clone na HUD que aparece.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("play_death_sequence"):
		return
	if sprite != null:
		sprite.visible = false
	hud.play_death_sequence(
		sprite,
		kill_effect_scene,
		death_freeze_duration,
		death_fadeout_duration,
		death_blackout_duration
	)


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	# global_position do player = pés (refator do pivô). Sobe 16 pra centro do sprite.
	fx.global_position = global_position + Vector2(0, -16)


var _flash_tween: Tween

func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	# 10 acima do centro do sprite (que é 16 acima dos pés).
	num.position = global_position + Vector2(0, -26)
	# Damage numbers ficam fora do World pra sempre aparecer por cima (tipo UI).
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_attack_timer_timeout() -> void:
	can_attack = true


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		# Garantia: se algo cortou a anim antes do release_frame, solta agora.
		if is_drawing:
			_release_arrow()
		# Reseta speed_scale ANTES de tocar idle pra evitar 1 frame de idle
		# acelerado entre o animation_finished e o próximo _physics_process.
		sprite.speed_scale = 1.0
		sprite.play("idle")


func _on_frame_changed() -> void:
	if is_drawing and sprite.animation == "attack" and sprite.frame == RELEASE_FRAME:
		_release_arrow()


# ---------- Run stats (death screen) ----------

func notify_enemy_killed() -> void:
	stats_enemies_killed += 1


func notify_ally_made() -> void:
	stats_allies_made += 1


func notify_damage_dealt(amount: float) -> void:
	if amount > 0.0:
		stats_damage_dealt += amount
		_heal_woodwardens_from_damage(amount)


const WOODWARDEN_HEAL_FROM_DAMAGE: float = 0.50  # 50% do dano vira cura

func _heal_woodwardens_from_damage(amount: float) -> void:
	# Cada woodwarden vivo cura por % do dano causado pelo player.
	# Identifica via grupo "tank_ally" (woodwarden é o único nesse grupo hoje).
	var heal_amount: float = amount * WOODWARDEN_HEAL_FROM_DAMAGE
	if heal_amount <= 0.0:
		return
	for ally in get_tree().get_nodes_in_group("tank_ally"):
		if not is_instance_valid(ally) or not ally.has_method("heal"):
			continue
		ally.heal(heal_amount)


func notify_damage_taken(amount: float) -> void:
	if amount > 0.0:
		stats_damage_taken += amount


func get_run_time_msec() -> int:
	return Time.get_ticks_msec() - _run_start_msec
