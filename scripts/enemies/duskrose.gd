extends CharacterBody2D

# Duskrose — boss da wave 14. Substitui o boss_redux (mage_monkey) antigo.
#
# Design:
# - Fica no topo do mapa, andando horizontalmente (rápida)
# - Janelas de vulnerabilidade quando inverte direção / cast
# - Poderes (iteração atual): invocação de Rosa Monstro
# - TODO próximas sessões: vinhas, laser solar, smokes de veneno, dash com AoE
#
# HP scaling: o wave_manager seta `max_hp` baseado no wave atual (mesmo padrão
# que o mage_monkey usa pra wave 7 ser exatamente 3000 HP).

@export var max_hp: float = 8000.0
@export var damage_mult: float = 1.0  # set by wave_manager
@export var hp_mult: float = 1.0  # idem

# === Movimento horizontal ===
@export var patrol_speed: float = 64.0
@export var patrol_y: float = 15.0  # alto no mapa, mas com margem visual pra cima
@export var patrol_x_min: float = 100.0
@export var patrol_x_max: float = 420.0
# Tempo parado nos extremos antes de inverter — janela onde player pode mirar.
@export var edge_pause: float = 0.6
# Frenagem perto das bordas: dentro de `edge_slowdown_distance` da borda em que
# está indo, a velocidade desce suavemente até `edge_slowdown_min_factor` × speed.
# Dá impressão de "freada" antes de inverter — telegraph adicional pro player.
@export var edge_slowdown_distance: float = 55.0
@export var edge_slowdown_min_factor: float = 0.3
# Duração em que boss fica PARADA enquanto casta um poder (telegraph corporal).
@export var cast_pause_duration: float = 1.2

# === Sistema de poderes (pesos táticos) ===
# Boss escolhe um poder a cada `power_cooldown` segundos. Pesos por poder
# variam com a situação (ex: poucas roses → summon prioritário).
# Range maior pra variação de ritmo (~4-7s) — poderes não saem em cadência
# fixa, dá sensação de aleatoriedade orgânica. Overlap ainda acontece porque
# smoke dura 5s e vines duram 6s.
@export var power_cooldown_min: float = 3.0
@export var power_cooldown_max: float = 5.0
# Delay inicial antes do primeiro poder (deixa player se posicionar).
@export var initial_attack_delay: float = 4.0
# Primeiro cast SEMPRE invocação com count especial pra encher o mapa
# com mobs logo de cara. Depois o sistema de pesos toma conta.
@export var initial_summon_count: int = 6
# Double cast: a cada cast, X% de chance de disparar 2 poderes no mesmo tick.
# Restrição: ranged + melee (dash/dash_double) NUNCA combinam — combos válidos
# são qualquer outro par (summon+smoke, vines+ranged, dash+summon, etc).
@export var double_cast_chance: float = 0.25

# === Summon de Rosa Monstro ===
@export var rose_monster_scene: PackedScene
# Dark balls spawnam num timer paralelo (cada 18s, 5 unidades), independente
# da rotação de poderes. Não bloqueia patrulha nem outros casts.
@export var dark_ball_scene: PackedScene
@export var dark_ball_summon_interval: float = 18.0
@export var dark_ball_summon_count: int = 5
@export var dark_ball_first_summon_delay: float = 10.0  # delay inicial pra wave aquecer
@export var dark_ball_summon_x_jitter: float = 140.0
@export var dark_ball_summon_y_min: float = 90.0
@export var dark_ball_summon_y_max: float = 230.0
# Wave 21 (boss duplo): dark balls são desligados (setado pelo wave_manager).
var dark_ball_summon_enabled: bool = true
# Casts subsequentes invocam 4-5 roses (randi_range). Primeiro cast usa
# `initial_summon_count` (6, definido abaixo) e bypass do random.
@export var summon_count_min: int = 4
@export var summon_count_max: int = 5
@export var summon_drop_y_min: float = 80.0
@export var summon_drop_y_max: float = 220.0
@export var summon_x_jitter: float = 100.0
@export var summon_effect_scene: PackedScene

# === Vinhas espinhosas ===
@export var vine_scene: PackedScene
# Quantas vinhas por cast (3 ou 4 random). Todas 100% aleatórias no mapa.
@export var vine_count_min: int = 3
@export var vine_count_max: int = 4
# Distância mínima entre vinhas — checa contra vinhas do MESMO cast E também
# contra vinhas ainda VIVAS de casts anteriores (evita overlap entre casts).
@export var vine_min_spacing: float = 100.0
# Y inicial e final da vinha — cobre o MAPA INTEIRO verticalmente. Por padrão
# vai de -80 (cima da cerca norte) até 420 (baixo), atravessando toda a área
# jogável + um pouco além pra reforço visual.
@export var vine_top_y: float = -80.0
@export var vine_target_bottom_y: float = 420.0

# === Smoke de veneno ===
@export var smoke_scene: PackedScene
# Conta alta pra cobrir ~45% do mapa (player tem que tecer entre as nuvens).
@export var smoke_count_min: int = 11
@export var smoke_count_max: int = 15
# Área de spawn das smokes (em coordenadas do mundo).
@export var smoke_x_min: float = 30.0
@export var smoke_x_max: float = 490.0
@export var smoke_y_min: float = 70.0
@export var smoke_y_max: float = 280.0
# Distância mínima entre smokes. Reduzido pra permitir cobertura densa
# (smoke radius efetivo ~32, então spacing 55 deixa overlap controlado).
@export var smoke_min_spacing: float = 55.0

# === Dash + Attack (melee) ===
# Boss vai até o player, executa anim de attack mostrando um indicador branco,
# e depois de `dash_telegraph_duration` segundos aplica dano em quem estiver na
# área. Após o ataque, retorna pra patrol_y.
@export var dash_speed: float = 280.0
@export var dash_attack_radius: float = 42.0  # raio da AoE de impacto
@export var dash_attack_damage: float = 80.0  # dano altíssimo (pune quem fica parado no AoE)
@export var dash_telegraph_duration: float = 0.7
@export var dash_return_duration: float = 0.55
# Distância (px) pra considerar que chegou no alvo e começar o telegraph.
@export var dash_arrive_threshold: float = 14.0
# Offset Y do destino — boss para um pouco acima do player pra não sobrepor visualmente.
@export var dash_target_y_offset: float = -4.0
# Tempo máximo de dash (failsafe se algo trava o caminho).
@export var dash_max_duration: float = 2.5

# === Variante double dash (POWER_DASH_DOUBLE) ===
# Mesma mecânica do dash single, mas dispara em sequência: dash → strike →
# retorna pra patrulha → dash novo → strike → retorna. Strike usa hitbox
# RETANGULAR (longa pra frente, fina pros lados) — diferente do círculo do
# single. Cobre mais distância no eixo do dash e menos perpendicular.
@export var dash_double_damage: float = 60.0  # menor que single (80) porque 2 hits
# Hitbox retangular: forward = profundidade no eixo do dash, side = largura
# perpendicular. Centro do retângulo = _dash_target_pos. Cobre uma "lâmina"
# na direção em que a boss chegou.
@export var dash_rect_forward: float = 95.0
@export var dash_rect_side: float = 22.0  # half-width pra cada lado
# Previsão: 0 = mira na posição atual, 1 = mira onde player estará no momento
# em que a boss chega (assumindo velocidade constante). 0.45 é um lead suave —
# força mudança de direção mas não pune dash/skill spikes.
@export var dash_lead_factor: float = 0.45
# Cap em px pra evitar predição doida. 45px ≈ raio do AoE (42), então mesmo
# no pior caso o player ainda pega o strike se andou em linha reta.
@export var dash_max_lead_distance: float = 45.0
# Cap na magnitude da velocidade do player ANTES de calcular o lead. Sem isso,
# spike momentâneo do dash do player (1000+ px/s) faz a boss prever 5× além
# do real. Walk normal é ~90-120, então 160 deixa margem pra esquivando+stacks
# sem capturar o dash do player.
@export var dash_player_vel_cap: float = 160.0

# === Ranged barrage (projéteis) ===
# Boss para por completo, lança `ranged_volley_count` volleys de 3 projéteis
# em leque, com `ranged_volley_interval` entre eles. Shield NÃO ativa durante
# o cast (janela de oportunidade pro player puxar HP).
@export var projectile_scene: PackedScene
@export var ranged_volley_count: int = 5  # quantos disparos durante o cast
@export var ranged_volley_interval: float = 1.0  # tempo entre cada volley (s)
@export var ranged_projectiles_per_volley: int = 3  # leque centro + ±spread
@export var ranged_angle_spread_deg: float = 15.0  # ângulo dos projéteis laterais
@export var ranged_projectile_damage: float = 16.0
@export var ranged_projectile_speed: float = 180.0
@export var ranged_spawn_offset: Vector2 = Vector2(0, -18)  # spawn no peito da boss

# IDs dos poderes (constantes pra referência consistente)
const POWER_SUMMON: String = "summon"
const POWER_SMOKE: String = "smoke"
const POWER_VINES: String = "vines"
const POWER_RANGED: String = "ranged"
const POWER_DASH: String = "dash"
const POWER_DASH_DOUBLE: String = "dash_double"

# Sons dos poderes — load() lazy pra tolerar mp3 sem .import.
const SUMMON_SOUND_PATH: String = "res://assets/enemies/duskrose/cast rosa monstro.mp3"
const VINE_SOUND_PATH: String = "res://assets/enemies/duskrose/vinhas espinhocas cast or hit.mp3"
const SHIELD_SOUND_PATH: String = "res://assets/enemies/duskrose/cast shield.mp3"
const RANGED_SOUND_PATH: String = "res://assets/enemies/duskrose/cast projetil power duskk rose.mp3"
const DASH_SOUND_PATH: String = "res://assets/enemies/duskrose/duskrose dash + atack.mp3"
const MELEE_HIT_SOUND_PATH: String = "res://assets/enemies/duskrose/melee atack sound.mp3"
@export var summon_sound_volume_db: float = -20.0
@export var vine_sound_volume_db: float = -8.0
@export var shield_sound_volume_db: float = -10.0
@export var ranged_sound_volume_db: float = -12.0
@export var dash_sound_volume_db: float = -10.0
@export var melee_hit_sound_volume_db: float = -8.0

# === Glass Shield ===
# Defensiva: a cada `shield_cooldown` segundos a boss casta um shield de
# `shield_duration` segundos que reduz dano tomado em `shield_damage_reduction`.
# Enquanto o shield tá ativo a boss NÃO usa ataques melee (preparação pra
# quando dash for implementado). Outros poderes (ranged/AoE) continuam normais.
@export var shield_cooldown: float = 20.0  # tempo entre casts
@export var shield_duration: float = 8.0  # tempo ativo
@export var shield_damage_reduction: float = 0.8  # 80% redução
@export var shield_first_delay: float = 8.0  # primeiro shield após X seg
# Anim do shield: usa sheet dedicado (com opacidade correta — diferente da
# versão exportada do aseprite principal). 8 frames @ 40×40 em loop.
const SHIELD_SHEET_PATH: String = "res://assets/enemies/duskrose/duskrose-shield-Sheet.png"
const SHIELD_FRAME_COUNT: int = 8
const SHIELD_FPS: float = 8.0
const SHIELD_FRAME_W: int = 40
const SHIELD_FRAME_H: int = 40
# Skip da animação de entrada (setado pelo wave_manager durante cinematic).
var skip_entrance_animation: bool = false

# === Drops + efeitos ===
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -14.0
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 1.0
@export var gold_drop_min: int = 28
@export var gold_drop_max: int = 56
@export var spawn_in_duration: float = 0.6

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -20)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

var hp: float
var _direction: int = 1  # 1 = right, -1 = left
var _pause_remaining: float = 0.0
var _power_cd: float = 0.0
var _last_power: String = ""  # ID do último poder lançado (evita repetir consecutivo)
var _first_power_done: bool = false  # primeiro cast SEMPRE summon com 6 rosas
var _cast_remaining: float = 0.0  # boss parada enquanto > 0 (telegraph do cast)
var _spawning_in: bool = false
# Shield state
var _shield_active: bool = false
var _shield_remaining: float = 0.0
var _shield_cd_remaining: float = 0.0  # init no _ready com shield_first_delay
var _shield_sprite: AnimatedSprite2D  # overlay anim sobre a boss
var _flash_tween: Tween
var _crit_pending: bool = false
# Ranged barrage state — ativo enquanto a boss está parada cuspindo projéteis.
# Shield NÃO ativa enquanto _ranged_active.
var _ranged_active: bool = false
var _ranged_shots_left: int = 0
var _ranged_shot_timer: float = 0.0
# Timer paralelo do dark ball summon (independente da rotação de poderes).
var _dark_ball_cd: float = 0.0
# Pity counter pra garantir que o dash sai a cada 3-4 poderes. Incrementa em
# cada cast NÃO-dash e zera no cast do dash. Quando >= 2 começa a empurrar o
# peso do dash forte; >= 3 praticamente força ele a sair no próximo cast.
var _casts_since_dash: int = 0
# Dash attack state. Fases:
#   "dashing"   → moves towards _dash_target_pos at dash_speed
#   "telegraph" → para no destino, mostra indicador branco, anim attack
#   "return"    → lerp de volta pra patrol_y (y horizontal de patrulha)
# Shield bloqueado em ativar enquanto _dash_phase != "".
var _dash_phase: String = ""
var _dash_target_pos: Vector2 = Vector2.ZERO
var _dash_phase_timer: float = 0.0
var _dash_return_origin: Vector2 = Vector2.ZERO
var _dash_indicator: Node2D = null
var _dash_strike_done: bool = false
# Double dash: variante que executa 2 dashes em sequência com hitbox retangular.
# _dash_strikes_remaining decrementa após cada strike; > 0 = re-dash.
var _dash_strikes_remaining: int = 0
var _dash_use_rect_strike: bool = false
# Direção do dash atual (origem→alvo, normalizada) — usada pra rotacionar a
# hitbox retangular e o indicador.
var _dash_direction: Vector2 = Vector2.RIGHT
# Snapshot do collision_mask original (setado no _ready). Durante o dash a
# Duskrose vira "fantasma" — passa por estruturas/cercas/props pra não travar
# em obstáculos no caminho até o player. Restaurado quando o dash termina.
var _default_collision_mask: int = 0


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	add_to_group("duskrose")
	add_to_group("cc_immune")  # bosses ignoram stun/freeze/curse heavy
	# wave_manager._apply_wave_scaling já multiplica max_hp por hp_mult antes
	# do _ready, então copia direto. hp_mult fica disponível pra escalar minions
	# invocados (rose_monster.max_hp *= hp_mult no _cast_summon).
	hp = max_hp
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
	# Posição inicial via call_deferred — wave_manager seta global_position
	# DEPOIS de add_child (que dispara _ready). Defer pra rodar após esse set
	# e evita teleport visual de wave7_boss_center pra y=patrol_y na primeira
	# physics frame.
	call_deferred("_snap_to_patrol")
	if sprite != null:
		sprite.play("idle")
	# Spawn-in fade (se não foi pulado pelo wave_manager).
	if not skip_entrance_animation:
		_play_spawn_in()
	_power_cd = initial_attack_delay
	# Direção inicial aleatória pra não ficar previsível.
	_direction = 1 if randf() < 0.5 else -1
	# Shield setup
	_shield_cd_remaining = shield_first_delay
	_build_shield_sprite()
	# Dark ball summon timer (independente, paralelo).
	_dark_ball_cd = dark_ball_first_summon_delay
	# Snapshot do collision_mask original pra restaurar depois do dash.
	_default_collision_mask = collision_mask


func _snap_to_patrol() -> void:
	# Snap pra y=patrol_y mantendo x do spawn (clamped). Chamado via call_deferred
	# no _ready pra rodar APÓS o wave_manager setar global_position.
	global_position = Vector2(clampf(global_position.x, patrol_x_min, patrol_x_max), patrol_y)


func _play_spawn_in() -> void:
	_spawning_in = true
	if sprite != null:
		sprite.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(sprite, "modulate:a", 1.0, spawn_in_duration)
		t.tween_callback(func() -> void:
			_spawning_in = false
		)
	else:
		_spawning_in = false


func _build_shield_sprite() -> void:
	# AnimatedSprite2D filho da boss com a anim "glass_shield" em loop.
	# Usa SpriteFrames SEPARADO carregado do duskrose-shield-Sheet.png
	# (asset dedicado com opacidade correta).
	if sprite == null:
		return
	var shield_tex: Texture2D = load(SHIELD_SHEET_PATH) as Texture2D
	if shield_tex == null:
		return
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"glass_shield")
	sf.set_animation_loop(&"glass_shield", true)
	sf.set_animation_speed(&"glass_shield", SHIELD_FPS)
	for i in SHIELD_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = shield_tex
		atlas.region = Rect2(
			float(i) * float(SHIELD_FRAME_W), 0,
			float(SHIELD_FRAME_W), float(SHIELD_FRAME_H)
		)
		sf.add_frame(&"glass_shield", atlas)
	_shield_sprite = AnimatedSprite2D.new()
	_shield_sprite.sprite_frames = sf
	_shield_sprite.animation = &"glass_shield"
	_shield_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shield_sprite.offset = sprite.offset  # mesma posição do corpo da boss
	_shield_sprite.z_index = 1  # acima do corpo
	_shield_sprite.visible = false
	add_child(_shield_sprite)


func _activate_shield() -> void:
	if _shield_active:
		return
	_shield_active = true
	_shield_remaining = shield_duration
	if _shield_sprite != null:
		_shield_sprite.visible = true
		_shield_sprite.play("glass_shield")


func _deactivate_shield() -> void:
	if not _shield_active:
		return
	_shield_active = false
	_shield_remaining = 0.0
	_shield_cd_remaining = shield_cooldown
	if _shield_sprite != null:
		_shield_sprite.visible = false
		_shield_sprite.stop()


func is_shielded() -> bool:
	# Exposto pra outros sistemas (futura mecânica de dash bloqueado durante shield).
	return _shield_active


func _physics_process(delta: float) -> void:
	if _spawning_in:
		velocity = Vector2.ZERO
		return

	# Dark ball summon (paralelo à rotação de poderes): roda em qualquer fase
	# da boss (patrol, dash, ranged), sem ocupar slot de cast. Cada disparo
	# spawna `dark_ball_summon_count` dark balls em posições aleatórias abaixo
	# da boss e reseta o timer.
	_dark_ball_cd = maxf(_dark_ball_cd - delta, 0.0)
	if _dark_ball_cd <= 0.0:
		_cast_dark_ball_summon()
		_dark_ball_cd = dark_ball_summon_interval

	# Shield tick: ativo decrementa, ao zerar desliga shield + reset cd.
	# Quando inativo, cd ticks até zerar, daí ativa shield. Durante ranged ou
	# dash o shield NÃO ativa (janela de vulnerabilidade pro player) — o cd
	# fica congelado pra não "perder" o ciclo.
	if _shield_active:
		_shield_remaining = maxf(_shield_remaining - delta, 0.0)
		if _shield_remaining <= 0.0:
			_deactivate_shield()
	elif not _ranged_active and _dash_phase.is_empty():
		_shield_cd_remaining = maxf(_shield_cd_remaining - delta, 0.0)
		if _shield_cd_remaining <= 0.0:
			_activate_shield()

	# Dash + Attack: boss vai até o player, mostra telegraph e bate em AoE.
	# Tudo gerenciado em _tick_dash_phase. Quando volta pra "" → patrol normal.
	if not _dash_phase.is_empty():
		_tick_dash_phase(delta)
		return

	# Ranged barrage: boss totalmente parada cuspindo N volleys de 3 projéteis
	# em leque na direção do player. Tick do timer dispara cada volley; ao
	# zerar os shots, libera pra patrulha normal.
	if _ranged_active:
		velocity = Vector2.ZERO
		global_position.y = patrol_y
		_ranged_shot_timer = maxf(_ranged_shot_timer - delta, 0.0)
		if _ranged_shot_timer <= 0.0 and _ranged_shots_left > 0:
			_fire_ranged_volley()
			_ranged_shots_left -= 1
			if _ranged_shots_left <= 0:
				_ranged_active = false
				# Reseta cd do próximo poder pra não disparar imediatamente.
				_power_cd = randf_range(power_cooldown_min, power_cooldown_max)
			else:
				_ranged_shot_timer = ranged_volley_interval
		return

	# Cast pause: boss fica PARADA enquanto _cast_remaining > 0 (telegraph
	# corporal — player vê ela parou e prepara pra desviar). Cooldown do
	# próximo poder continua decrementando normalmente.
	if _cast_remaining > 0.0:
		_cast_remaining = maxf(_cast_remaining - delta, 0.0)
		velocity = Vector2.ZERO
		_power_cd = maxf(_power_cd - delta, 0.0)
		global_position.y = patrol_y
		return

	# Patrulha horizontal no topo. Pausa nas bordas pra dar janela de mira.
	if _pause_remaining > 0.0:
		_pause_remaining = maxf(_pause_remaining - delta, 0.0)
		velocity = Vector2.ZERO
	else:
		var speed_factor: float = _edge_slowdown_factor()
		velocity = Vector2(_direction * patrol_speed * speed_factor, 0.0)
		# Bate na borda → pausa + inverte.
		if global_position.x <= patrol_x_min and _direction < 0:
			global_position.x = patrol_x_min
			_direction = 1
			_pause_remaining = edge_pause
			velocity = Vector2.ZERO
		elif global_position.x >= patrol_x_max and _direction > 0:
			global_position.x = patrol_x_max
			_direction = -1
			_pause_remaining = edge_pause
			velocity = Vector2.ZERO
		else:
			move_and_slide()
	# Mantém Y fixo no topo (impede que physics deixe ela cair).
	global_position.y = patrol_y

	# Flip do sprite seguindo a direção de movimento.
	if sprite != null:
		sprite.flip_h = _direction < 0

	# Power tick: cooldown decrementa, ao chegar a 0 escolhe e lança próximo poder.
	_power_cd = maxf(_power_cd - delta, 0.0)
	if _power_cd <= 0.0:
		# Primeiro cast: SEMPRE summon com `initial_summon_count` (6 rosas) —
		# enche o mapa de mobs imediatamente. Bypass do sistema de pesos.
		if not _first_power_done:
			_cast_summon_with_count(initial_summon_count)
			_first_power_done = true
			_last_power = POWER_SUMMON
			_casts_since_dash += 1
		else:
			var power_id: String = _pick_next_power()
			_cast_power(power_id)
			_last_power = power_id
			# Double cast roll: 25% de chance de disparar um SEGUNDO poder no
			# mesmo tick. Restrição: ranged + melee nunca combinam (regra do
			# user). _pick_compatible_second_power exclui o primeiro power e
			# qualquer power incompatível com ele.
			var dash_was_cast: bool = power_id == POWER_DASH or power_id == POWER_DASH_DOUBLE
			if randf() < double_cast_chance:
				var second_id: String = _pick_compatible_second_power(power_id)
				if not second_id.is_empty():
					_cast_power(second_id)
					if second_id == POWER_DASH or second_id == POWER_DASH_DOUBLE:
						dash_was_cast = true
			if dash_was_cast:
				_casts_since_dash = 0
			else:
				_casts_since_dash += 1
		# Ranged/dash têm sua própria pausa longa via _ranged_active/_dash_phase
		# — não acumula o cast_pause de 1.2s em cima.
		if not _ranged_active and _dash_phase.is_empty():
			_cast_remaining = cast_pause_duration
		_power_cd = randf_range(power_cooldown_min, power_cooldown_max)


# Picks o SEGUNDO poder do double cast, filtrando os incompatíveis com o
# primeiro. Regras:
#   ranged + qualquer melee (dash/dash_double) = inválido
#   dash + dash_double = válido (melee + melee)
#   resto = válido (qualquer outro par)
# Reusa _compute_power_weights pra manter o peso tático. Se nada compatível
# resta, retorna "" (sem segundo cast).
func _pick_compatible_second_power(first_power: String) -> String:
	var weights: Dictionary = _compute_power_weights()
	# Exclui o primeiro pra evitar repetição.
	if first_power in weights:
		weights[first_power] = 0.0
	# Restrição cruzada melee↔ranged.
	var melee_powers: Array[String] = [POWER_DASH, POWER_DASH_DOUBLE]
	if first_power == POWER_RANGED:
		for m in melee_powers:
			if m in weights:
				weights[m] = 0.0
	elif first_power in melee_powers:
		if POWER_RANGED in weights:
			weights[POWER_RANGED] = 0.0
	# Pondera + sorteia (mesmo algoritmo do _pick_next_power).
	var total: float = 0.0
	for w: float in weights.values():
		total += w
	if total <= 0.0:
		return ""
	var roll: float = randf() * total
	var accum: float = 0.0
	for power_id: String in weights.keys():
		accum += weights[power_id]
		if roll <= accum:
			return power_id
	return ""


# Sistema de pesos táticos: cada poder ganha um peso baseado no estado atual
# do jogo. Boss escolhe ponderado pelos pesos. No-repeat consecutivo aplicado
# zerando o peso do _last_power. Se todos os pesos zerarem, fallback random.
func _pick_next_power() -> String:
	var weights: Dictionary = _compute_power_weights()
	# Zera o último poder pra não repetir consecutivo (a menos que seja o único disponível).
	if weights.size() > 1 and _last_power in weights:
		weights[_last_power] = 0.0
	var total: float = 0.0
	for w: float in weights.values():
		total += w
	if total <= 0.0:
		# Fallback: pick random key qualquer.
		var keys: Array = weights.keys()
		return keys[randi() % keys.size()]
	var roll: float = randf() * total
	var accum: float = 0.0
	for power_id: String in weights.keys():
		accum += weights[power_id]
		if roll <= accum:
			return power_id
	# Defensive fallback.
	return weights.keys()[0]


func _edge_slowdown_factor() -> float:
	# Quando a boss está se aproximando da borda em que pretende inverter,
	# diminui a velocidade proporcional à distância restante. Ramp linear de
	# 1.0 (>= edge_slowdown_distance) até edge_slowdown_min_factor (na borda).
	if edge_slowdown_distance <= 0.0:
		return 1.0
	var dist_to_edge: float
	if _direction > 0:
		dist_to_edge = patrol_x_max - global_position.x
	else:
		dist_to_edge = global_position.x - patrol_x_min
	if dist_to_edge >= edge_slowdown_distance:
		return 1.0
	var t: float = clampf(dist_to_edge / edge_slowdown_distance, 0.0, 1.0)
	return lerpf(edge_slowdown_min_factor, 1.0, t)


func _compute_power_weights() -> Dictionary:
	# Pesos base: cada poder começa com 1.0. Modificadores aplicados conforme estado.
	# Adicione novos poderes aqui quando o sprite/sistema estiver pronto.
	var weights: Dictionary = {
		POWER_SUMMON: 1.0,
		POWER_SMOKE: 1.0,
		POWER_VINES: 1.0,
		POWER_RANGED: 1.0,
		POWER_DASH: 1.0,
		POWER_DASH_DOUBLE: 0.7,  # variante mais rara — mais dramática + 2 hits
	}
	# Tactic 1: 0 ou 1 rose vivo → summon prioritário (peso × 3).
	# Boss quer sempre ter pelo menos 2-3 minions no mapa pra pressionar player.
	var rose_count: int = get_tree().get_nodes_in_group("rose_monster").size()
	if rose_count <= 1:
		weights[POWER_SUMMON] *= 3.0
	elif rose_count >= 5:
		# Já tem muita rosa no mapa → reduz peso do summon pra variar.
		weights[POWER_SUMMON] *= 0.3
	# Tactic 2: vines prioritárias se player está perto do boss (ameaça melee).
	# Vinhas vão de cima a baixo bloqueando rotas — força player a recuar.
	var player := get_tree().get_first_node_in_group("player")
	if player != null and is_instance_valid(player) and player is Node2D:
		var dy: float = absf((player as Node2D).global_position.y - global_position.y)
		if dy < 130.0:
			weights[POWER_VINES] *= 2.0
	# Tactic 3: pity counter pro dash — garante 1 dash a cada 3-4 poderes.
	# 2 casts sem dash: 3x peso (fica bem provável); 3+ casts: 15x (quase
	# garantido). Mantém o ritmo melee sem virar 100% previsível.
	if _casts_since_dash >= 3:
		weights[POWER_DASH] *= 15.0
		weights[POWER_DASH_DOUBLE] *= 15.0
	elif _casts_since_dash >= 2:
		weights[POWER_DASH] *= 3.0
		weights[POWER_DASH_DOUBLE] *= 3.0
	return weights


func _cast_power(power_id: String) -> void:
	# Dispatch pro método específico. Adicione cases quando novos poderes
	# estiverem prontos (laser, dash).
	match power_id:
		POWER_SUMMON:
			_cast_summon()
		POWER_SMOKE:
			_cast_smoke()
		POWER_VINES:
			_cast_vines()
		POWER_RANGED:
			_cast_ranged()
		POWER_DASH:
			_cast_dash_attack(false)
		POWER_DASH_DOUBLE:
			_cast_dash_attack(true)


func _cast_summon() -> void:
	# Wrapper que usa range aleatório [summon_count_min, summon_count_max].
	# Casts subsequentes invocam 4-5 mobs. Primeiro cast usa initial_summon_count.
	_cast_summon_with_count(randi_range(summon_count_min, summon_count_max))


func _cast_summon_with_count(count: int) -> void:
	# Flash visual no boss (telegraph rápido).
	_flash_white(0.3)
	# Som do cast de invocação.
	_play_one_shot(load(SUMMON_SOUND_PATH) as AudioStream, global_position, summon_sound_volume_db)
	# Spawna N rose monsters em posições aleatórias abaixo do boss.
	if rose_monster_scene == null:
		return
	var world := _get_world()
	for i in count:
		var spawn_pos := global_position + Vector2(
			randf_range(-summon_x_jitter, summon_x_jitter),
			randf_range(summon_drop_y_min, summon_drop_y_max)
		)
		# Clamp dentro do mapa pra não spawnar fora.
		spawn_pos.x = clampf(spawn_pos.x, patrol_x_min - 20.0, patrol_x_max + 20.0)
		var rose: Node2D = rose_monster_scene.instantiate()
		# Escala damage do summon pelo mesmo damage_mult do boss.
		if "damage_mult" in rose:
			rose.damage_mult = damage_mult
		if "max_hp" in rose:
			rose.max_hp = rose.max_hp * hp_mult
		world.add_child(rose)
		rose.global_position = spawn_pos
		if rose.has_method("play_spawn_in"):
			rose.play_spawn_in()
		# Spawn effect lilás/rosa no ponto.
		if summon_effect_scene != null:
			var fx: Node2D = summon_effect_scene.instantiate()
			world.add_child(fx)
			fx.global_position = spawn_pos


func _cast_smoke() -> void:
	# Spawna N smokes em posições aleatórias no mapa. Cada smoke:
	#   1. Fade-in (telegraph, 0.4s)
	#   2. Damage tick por `duration` segundos enquanto player overlapa
	#   3. Fade-out + queue_free
	# Distribuição: tenta espaçar mín. `smoke_min_spacing` entre clouds pra
	# cobrir mais área. Se não conseguir respeitar o spacing em 5 tentativas,
	# usa a última posição mesmo.
	if smoke_scene == null:
		return
	_flash_white(0.3)
	var world: Node = _get_world()
	var count: int = randi_range(smoke_count_min, smoke_count_max)
	var placed_positions: Array[Vector2] = []
	var spacing_sq: float = smoke_min_spacing * smoke_min_spacing
	for i in count:
		var pos: Vector2 = Vector2.ZERO
		for attempt in 5:
			pos = Vector2(
				randf_range(smoke_x_min, smoke_x_max),
				randf_range(smoke_y_min, smoke_y_max)
			)
			var ok: bool = true
			for prev in placed_positions:
				if pos.distance_squared_to(prev) < spacing_sq:
					ok = false
					break
			if ok:
				break
		placed_positions.append(pos)
		var smoke: Node2D = smoke_scene.instantiate()
		# Propaga damage_mult pra escalar o tick com a wave (mesmo padrão dos
		# minions).
		if "damage_mult" in smoke:
			smoke.damage_mult = damage_mult
		world.add_child(smoke)
		smoke.global_position = pos


func _cast_vines() -> void:
	# Spawna 3-4 vinhas espinhosas 100% RANDOM pelo mapa (sem prioridade pra
	# player). Spacing checado contra:
	#   1. Outras vinhas do MESMO cast (placed_x)
	#   2. Vinhas ainda VIVAS de casts anteriores (group "duskrose_decoration"
	#      filtrado por scene_file_path) — evita vinhas sobrepondo entre casts.
	# Cada vinha: telegraph 1.5s → ativa 5s → fade-out.
	if vine_scene == null:
		return
	_flash_white(0.3)
	# Som do cast das vinhas — toca UMA vez por cast (não por vinha).
	_play_one_shot(load(VINE_SOUND_PATH) as AudioStream, global_position, vine_sound_volume_db)
	var world: Node = _get_world()
	var count: int = randi_range(vine_count_min, vine_count_max)
	# Range completo do mapa.
	var map_x_min: float = patrol_x_min - 20.0
	var map_x_max: float = patrol_x_max + 20.0
	# Inicializa placed_x com vinhas VIVAS de casts anteriores (pra não
	# sobrepor com elas).
	var placed_x: Array[float] = []
	for n in get_tree().get_nodes_in_group("duskrose_decoration"):
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		# Filtra só os que são vinhas (não rosas decorativas / wave14_map / etc).
		if (n as Node).scene_file_path == "res://scenes/effects/duskrose_vine.tscn":
			placed_x.append((n as Node2D).global_position.x)
	# Spawna `count` vinhas todas 100% random, respeitando spacing.
	for i in count:
		var vx: float = 0.0
		var found_ok: bool = false
		for attempt in 12:
			vx = randf_range(map_x_min, map_x_max)
			var ok: bool = true
			for prev_x in placed_x:
				if absf(vx - prev_x) < vine_min_spacing:
					ok = false
					break
			if ok:
				found_ok = true
				break
		# Se não achou posição livre após 12 tentativas, skipa essa vinha
		# (melhor menos vinhas do que vinhas sobrepostas).
		if not found_ok:
			continue
		placed_x.append(vx)
		_spawn_one_vine(world, vx)


func _cast_ranged() -> void:
	# Inicia a barragem: boss para por completo e dispara `ranged_volley_count`
	# leques de 3 projéteis (centro + ±ranged_angle_spread_deg) na direção do
	# player a cada `ranged_volley_interval` segundos. Shield bloqueado enquanto
	# _ranged_active (vide _physics_process); se já estava up, derruba pra abrir
	# a janela de vulnerabilidade prometida.
	if projectile_scene == null:
		return
	if _shield_active:
		_deactivate_shield()
	_flash_white(0.3)
	_ranged_active = true
	_ranged_shots_left = ranged_volley_count
	_ranged_shot_timer = 0.0  # primeiro volley dispara no próximo frame


func _fire_ranged_volley() -> void:
	# Calcula direção até o player (origem no peito da boss) e cospe um leque
	# de `ranged_projectiles_per_volley` projéteis. Som toca uma vez por volley.
	if projectile_scene == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var aim_dir: Vector2 = Vector2.DOWN  # fallback se player não existe
	var spawn_pos: Vector2 = global_position + ranged_spawn_offset
	if player != null and is_instance_valid(player) and player is Node2D:
		var to_player: Vector2 = (player as Node2D).global_position - spawn_pos
		if to_player.length_squared() > 0.0001:
			aim_dir = to_player.normalized()
	_play_one_shot(load(RANGED_SOUND_PATH) as AudioStream, global_position, ranged_sound_volume_db)
	var world: Node = _get_world()
	var count: int = maxi(1, ranged_projectiles_per_volley)
	# Distribui ângulos: centro 0 + simétricos. Pra count=3: [-spread, 0, +spread].
	# Pra outros counts, espaçamento igual em torno do centro.
	var spread_rad: float = deg_to_rad(ranged_angle_spread_deg)
	for i in count:
		var offset_rad: float = 0.0
		if count > 1:
			# Centro do leque em (count-1)/2; cada índice se afasta em spread_rad.
			var idx_from_center: float = float(i) - (float(count) - 1.0) * 0.5
			offset_rad = idx_from_center * spread_rad
		var dir: Vector2 = aim_dir.rotated(offset_rad)
		var proj: Node2D = projectile_scene.instantiate()
		if "damage" in proj:
			proj.damage = ranged_projectile_damage
		if "damage_mult" in proj:
			proj.damage_mult = damage_mult
		if "speed" in proj:
			proj.speed = ranged_projectile_speed
		# Position/direction ANTES do add_child: _ready() do projétil inicializa
		# o trail com o ponto atual de global_position. Se add_child rodar com
		# global_position=(0,0), o trail fica com um ponto em (0,0) ligando até
		# spawn_pos — aparece como um rastro fantasma cruzando o mapa.
		proj.position = spawn_pos
		if proj.has_method("set_direction"):
			proj.set_direction(dir)
		world.add_child(proj)


func _cast_dark_ball_summon() -> void:
	# Spawna N dark balls em posições aleatórias abaixo da boss. Cada um passa
	# pelo `damage_mult` e `hp_mult` da Duskrose (escala com a wave).
	# Independente da rotação de poderes — não consome cast slot.
	# Wave 21 (boss duplo): desligado — nenhum dark ball nessa wave.
	if not dark_ball_summon_enabled:
		return
	if dark_ball_scene == null:
		return
	_play_one_shot(load(SUMMON_SOUND_PATH) as AudioStream, global_position, summon_sound_volume_db)
	var world := _get_world()
	for i in dark_ball_summon_count:
		# Y usa `patrol_y` como base (não global_position.y) — o summon roda em
		# paralelo a qualquer fase da boss, e durante dash ela pode estar lá
		# embaixo perto do player. Sem isso os dark balls saíam fora do mapa.
		var spawn_pos: Vector2 = Vector2(
			global_position.x + randf_range(-dark_ball_summon_x_jitter, dark_ball_summon_x_jitter),
			patrol_y + randf_range(dark_ball_summon_y_min, dark_ball_summon_y_max)
		)
		spawn_pos.x = clampf(spawn_pos.x, patrol_x_min - 20.0, patrol_x_max + 20.0)
		# Garantia extra contra spawn fora da arena (caso patrol_y mude no futuro).
		spawn_pos.y = clampf(spawn_pos.y, patrol_y + 25.0, 380.0)
		var db: Node2D = dark_ball_scene.instantiate()
		if "damage_mult" in db:
			db.damage_mult = damage_mult
		if "max_hp" in db:
			db.max_hp = float(db.max_hp) * hp_mult
		# Dark balls invocados pela Duskrose NÃO dropam gold (single source da
		# wave é a boss). Heart pode cair mas com chance bem reduzida (×0.4
		# local + BOSS_CONTEXT_DROP_MULTIPLIER ×0.75 do HeartDrop = ~30% da
		# chance normal). Em vez de fountain durante a boss fight, fica um
		# heal ocasional pra recompensar quem mata adds.
		if "gold_drop_chance" in db:
			db.gold_drop_chance = 0.0
		if "heart_drop_chance_multiplier" in db:
			db.heart_drop_chance_multiplier = 0.4
		world.add_child(db)
		db.global_position = spawn_pos
		# Spawn-in (fade) se disponível, igual rosas.
		if db.has_method("play_spawn_in"):
			db.play_spawn_in()
		if summon_effect_scene != null:
			var fx: Node2D = summon_effect_scene.instantiate()
			world.add_child(fx)
			fx.global_position = spawn_pos


func _cast_dash_attack(is_double: bool = false) -> void:
	# Dash até o player + telegraph + strike AoE. Fases controladas em
	# _tick_dash_phase. Shield bloqueado durante a sequência inteira (se estava
	# up, derruba pra abrir a janela de vulnerabilidade).
	# is_double: dispara 2 dashes em sequência com hitbox retangular (em vez
	# do círculo do single). Usado pelo POWER_DASH_DOUBLE.
	if _shield_active:
		_deactivate_shield()
	_dash_use_rect_strike = is_double
	_dash_strikes_remaining = 2 if is_double else 1
	# Vira fantasma durante TODA a sequência do dash (incluindo return). Sem
	# isso ela trava em cercas/poste/etc no caminho até o player.
	collision_mask = 0
	_start_single_dash()


func _start_single_dash() -> void:
	# Inicia UM dash da sequência. No single normal, chama uma vez. No double,
	# chama 2 vezes (a segunda vem do _enter_dash_return ao terminar a primeira).
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		# Sem player válido — encerra sequência limpando estado + restaura mask.
		_dash_strikes_remaining = 0
		_dash_phase = ""
		collision_mask = _default_collision_mask
		return
	var player_node: Node2D = player as Node2D
	var player_pos: Vector2 = player_node.global_position
	# Predição de movimento: assume velocidade constante e mira no ponto onde
	# o player estará quando a boss chegar + metade do telegraph (o golpe land
	# 0.7s depois de chegar). Lead factor < 1 evita dashar pra muito longe se
	# player muda de direção. Cap em dash_max_lead_distance pra player com dash
	# rápido não fazer a boss errar pro outro lado do mapa.
	var player_vel: Vector2 = Vector2.ZERO
	if "velocity" in player_node:
		player_vel = player_node.velocity
	# Filtra spike de dash do player: cap na magnitude antes de usar pra lead.
	# Sem isso, dashar enquanto a boss cast o dash fazia ela mirar pra MUITO
	# longe (ex: 1500 px/s × 1s × 0.6 = 900px de lead, capado depois mas já
	# direcionado errado).
	if player_vel.length() > dash_player_vel_cap:
		player_vel = player_vel.normalized() * dash_player_vel_cap
	var distance_to_player: float = global_position.distance_to(player_pos)
	var time_to_arrive: float = distance_to_player / maxf(dash_speed, 1.0)
	var lead_time: float = (time_to_arrive + dash_telegraph_duration * 0.5) * dash_lead_factor
	var lead_offset: Vector2 = player_vel * lead_time
	if lead_offset.length() > dash_max_lead_distance:
		lead_offset = lead_offset.normalized() * dash_max_lead_distance
	var target_pos: Vector2 = player_pos + lead_offset + Vector2(0, dash_target_y_offset)
	# Clamp do target pra área JOGÁVEL real. Bounds das cercas verticais do
	# wave14_map: esquerda em x=-55, direita em x=593. Player chega aos cantos,
	# então clamp tem que cobrir ISSO (não a patrulha da boss). Boss em ghost
	# mode durante dash (collision_mask=0) pode passar por cercas livremente.
	target_pos.x = clampf(target_pos.x, -40.0, 578.0)
	target_pos.y = clampf(target_pos.y, patrol_y + 25.0, 380.0)
	_dash_target_pos = target_pos
	_dash_return_origin = Vector2(global_position.x, patrol_y)
	_dash_direction = (target_pos - global_position).normalized()
	if _dash_direction.length_squared() < 0.0001:
		_dash_direction = Vector2.RIGHT
	_dash_phase = "dashing"
	_dash_phase_timer = dash_max_duration
	_dash_strike_done = false
	# Som de "cast" da boss no início do dash (asset antes usado pelo shield).
	# Shield agora é silencioso — esse áudio combina melhor com o telegraph do
	# dash, sinalizando pro player que algo grande tá vindo.
	_play_one_shot(load(SHIELD_SOUND_PATH) as AudioStream, global_position, shield_sound_volume_db)
	if sprite != null:
		sprite.play("dash")


func _tick_dash_phase(delta: float) -> void:
	match _dash_phase:
		"dashing":
			_dash_phase_timer = maxf(_dash_phase_timer - delta, 0.0)
			var to_target: Vector2 = _dash_target_pos - global_position
			# Flip sprite seguindo direção horizontal pra anim ficar coerente.
			if sprite != null and absf(to_target.x) > 0.5:
				sprite.flip_h = to_target.x < 0.0
			if to_target.length() <= dash_arrive_threshold or _dash_phase_timer <= 0.0:
				global_position = _dash_target_pos
				velocity = Vector2.ZERO
				_enter_dash_telegraph()
				return
			velocity = to_target.normalized() * dash_speed
			move_and_slide()
		"telegraph":
			velocity = Vector2.ZERO
			_dash_phase_timer = maxf(_dash_phase_timer - delta, 0.0)
			if not _dash_strike_done and _dash_phase_timer <= 0.0:
				_dash_strike_done = true
				_apply_dash_strike()
				_enter_dash_return()
		"return":
			_dash_phase_timer = maxf(_dash_phase_timer - delta, 0.0)
			# Lerp do ponto do strike (_dash_target_pos) até a posição na
			# patrulha (origin_x, patrol_y). t cresce de 0→1 conforme o timer
			# decrementa de dash_return_duration→0.
			var t: float = 1.0 - clampf(_dash_phase_timer / maxf(dash_return_duration, 0.001), 0.0, 1.0)
			var eased: float = ease(t, 0.5)  # easeOut-ish
			global_position.x = lerpf(_dash_target_pos.x, _dash_return_origin.x, eased)
			global_position.y = lerpf(_dash_target_pos.y, patrol_y, eased)
			if _dash_phase_timer <= 0.0:
				global_position = Vector2(_dash_return_origin.x, patrol_y)
				# Double dash: se ainda restam strikes, dispara o próximo dash
				# imediatamente em vez de encerrar. Sem reset de _dash_use_rect_strike
				# pra manter a hitbox retangular na 2ª passada.
				if _dash_strikes_remaining > 0:
					_start_single_dash()
					return
				_dash_phase = ""
				_dash_use_rect_strike = false
				# Restaura collision_mask original — boss volta a colidir com mundo.
				collision_mask = _default_collision_mask
				if sprite != null:
					sprite.play("idle")
				_power_cd = randf_range(power_cooldown_min, power_cooldown_max)


func _enter_dash_telegraph() -> void:
	_dash_phase = "telegraph"
	_dash_phase_timer = dash_telegraph_duration
	if sprite != null:
		sprite.play("attack")
	_spawn_dash_indicator()


func _enter_dash_return() -> void:
	_dash_phase = "return"
	_dash_phase_timer = dash_return_duration
	if _dash_indicator != null and is_instance_valid(_dash_indicator):
		_dash_indicator.queue_free()
		_dash_indicator = null


func _spawn_dash_indicator() -> void:
	# Indicador branco semi-transparente no chão. Forma depende da variante:
	#   single (círculo): aproximado com 20 lados, raio = dash_attack_radius.
	#   double (retângulo orientado): orientado na direção do dash, longo pra
	#     frente / fino pros lados.
	var indicator := Node2D.new()
	indicator.z_index = -1  # abaixo da boss / inimigos
	var poly := Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	if _dash_use_rect_strike:
		# Retângulo em local coords (eixo X = forward), depois rotaciona pra
		# alinhar com a direção do dash.
		var fh: float = dash_rect_forward * 0.5
		var sh: float = dash_rect_side
		pts.append(Vector2(-fh, -sh))
		pts.append(Vector2( fh, -sh))
		pts.append(Vector2( fh,  sh))
		pts.append(Vector2(-fh,  sh))
		indicator.rotation = _dash_direction.angle()
	else:
		var segments: int = 20
		for i in segments:
			var ang: float = TAU * float(i) / float(segments)
			pts.append(Vector2(cos(ang), sin(ang)) * dash_attack_radius)
	poly.polygon = pts
	poly.color = Color(1.0, 1.0, 1.0, 0.45)
	indicator.add_child(poly)
	_get_world().add_child(indicator)
	indicator.global_position = _dash_target_pos
	# Pulse alpha 0.25 ↔ 0.65 durante o telegraph (loops).
	var t := indicator.create_tween().set_loops()
	t.tween_property(poly, "color:a", 0.65, 0.18)
	t.tween_property(poly, "color:a", 0.25, 0.18)
	_dash_indicator = indicator


func _apply_dash_strike() -> void:
	# AoE: círculo (single) ou retângulo orientado (double). Dano FLAT, sem
	# damage_mult da wave. Som de impacto sempre toca (feedback do golpe).
	_play_one_shot(load(MELEE_HIT_SOUND_PATH) as AudioStream, _dash_target_pos, melee_hit_sound_volume_db)
	_dash_strikes_remaining = maxi(_dash_strikes_remaining - 1, 0)
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not (player is Node2D):
		return
	var player_pos: Vector2 = (player as Node2D).global_position
	var hit: bool = false
	if _dash_use_rect_strike:
		# Retângulo orientado: transforma player_pos pro espaço local da hitbox
		# (eixo X = direção do dash, eixo Y = perpendicular). Dentro de
		# [-forward/2, forward/2] × [-side, side] = hit.
		var local: Vector2 = (player_pos - _dash_target_pos).rotated(-_dash_direction.angle())
		hit = absf(local.x) <= dash_rect_forward * 0.5 and absf(local.y) <= dash_rect_side
	else:
		hit = player_pos.distance_to(_dash_target_pos) <= dash_attack_radius
	if not hit:
		return
	if player.has_method("take_damage"):
		# Single: 80 flat. Double: 60 por hit (120 total se ambos conectam).
		var dmg: float = dash_double_damage if _dash_use_rect_strike else dash_attack_damage
		player.take_damage(dmg, "duskrose_dash")


func _spawn_one_vine(world: Node, vx: float) -> void:
	var vine: Node2D = vine_scene.instantiate()
	# Propaga damage_mult da boss pro tick de dano da vinha.
	if "damage_mult" in vine:
		vine.damage_mult = damage_mult
	# Target Y final (até onde a vinha cresce).
	if "target_bottom_y" in vine:
		vine.target_bottom_y = vine_target_bottom_y
	# Spawn em Y FIXO (topo do mapa), não na posição da boss — a vinha cobre
	# a coluna vertical inteira do mapa independente de onde a boss está.
	# IMPORTANTE: position ANTES do add_child. _ready() da vinha calcula o
	# número de segmentos baseado em (target_bottom_y - global_position.y);
	# se add_child rodar com position=(0,0), a vinha sai curta.
	vine.position = Vector2(vx, vine_top_y)
	world.add_child(vine)


func _flash_white(duration: float) -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.6, 1.4, 1.8, 1.0)  # roxo/branco
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, duration)


# === Damage / death ===

func take_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	# DoT (burn/curse/poison tick): -30% dano. Detecção via metadata setada
	# pelo caller (BurnDoT/CurseDebuff) antes do take_damage. Remove em seguida
	# pra não vazar pro próximo hit que pode ser direto.
	if has_meta("_dot_damage_pending"):
		amount *= 0.7
		remove_meta("_dot_damage_pending")
	# Vulnerável durante melee/dash: 2× dano. Aplica sobre o valor já reduzido
	# pelo DoT (DoT + dash = 1.4× final).
	if not _dash_phase.is_empty():
		amount *= 2.0
	# Glass shield ativo: reduz dano em `shield_damage_reduction` (80% default,
	# então só 20% do dano passa). Aplica POR ÚLTIMO — shield protege de tudo.
	# Notify_damage_dealt usa o valor REDUZIDO pra estatística refletir o que
	# realmente saiu do HP.
	if _shield_active:
		amount *= (1.0 - shield_damage_reduction)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("notify_damage_dealt"):
		p.notify_damage_dealt(amount)
	hp = maxf(hp - amount, 0.0)
	# Float dust clamp (mesmo pattern do mage_monkey).
	if hp < 1.0:
		hp = 0.0
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	var died := hp <= 0.0
	_play_damage_sound(1.5 if died else 0.7)
	if died:
		var p2 := get_tree().get_first_node_in_group("player")
		if p2 != null and p2.has_method("notify_enemy_killed"):
			p2.notify_enemy_killed()
		# Boss kill — registra pro SkinLoadout (unlock da skin Rosa_Onyx).
		if p2 != null and p2.has_method("notify_boss_killed"):
			p2.notify_boss_killed("duskrose")
		# Avisa wave_manager pra fazer cleanup/magnet de fim de wave.
		var wm := get_tree().get_first_node_in_group("wave_manager")
		if wm != null and wm.has_method("notify_boss_died"):
			wm.notify_boss_died()
		_drop_gold()
		_spawn_kill_effect()
		_spawn_death_silhouette()
		# Cleanup do indicador do dash se a boss morreu mid-telegraph.
		if _dash_indicator != null and is_instance_valid(_dash_indicator):
			_dash_indicator.queue_free()
			_dash_indicator = null
		# Mata todas as rose_monsters vivas junto com o boss (mesma pattern do
		# mage_monkey que mata os minions).
		for r in get_tree().get_nodes_in_group("rose_monster"):
			if is_instance_valid(r):
				(r as Node).queue_free()
		queue_free()


func _drop_gold() -> void:
	if gold_scene == null or randf() > gold_drop_chance:
		return
	var count: int = randi_range(gold_drop_min, gold_drop_max)
	for i in count:
		var g: Node2D = gold_scene.instantiate()
		_get_world().add_child(g)
		# Espalha em volta do boss.
		g.global_position = global_position + Vector2(
			randf_range(-30.0, 30.0),
			randf_range(-10.0, 30.0)
		)


func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var flash_color: Color = CritFeedback.CRIT_FLASH_COLOR if _crit_pending else Color(1.5, 0.3, 0.3, 1.0)
	sprite.modulate = flash_color
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
		_crit_pending = false
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	if _crit_pending and "color_override" in num:
		num.color_override = CritFeedback.CRIT_NUMBER_COLOR
	num.position = global_position + Vector2(0, -40)
	get_tree().current_scene.add_child(num)
	_crit_pending = false


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
	t.tween_property(ghost, "modulate:a", 0.0, 1.4)
	t.tween_callback(ghost.queue_free)


func _play_damage_sound(duration: float = 0.7) -> void:
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = 1.0
	add_child(p)
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func apply_knockback(_dir: Vector2, _strength: float) -> void:
	# Boss não toma knockback (cc_immune).
	pass


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _play_one_shot(sound: AudioStream, pos: Vector2, volume_db: float) -> void:
	# Spawna AudioStreamPlayer2D no mundo (não filho da boss) — sobrevive se
	# a boss morrer durante o som. Auto-cleanup no finished.
	if sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = sound
	p.volume_db = volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	_get_world().add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
