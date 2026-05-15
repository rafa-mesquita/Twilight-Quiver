extends CharacterBody2D

signal hp_changed(current: float, maximum: float)
signal gold_changed(total: int)
signal died
# Dash: emitido ao comprar o upgrade (HUD mostra a barra) e a cada frame
# durante o cooldown (HUD atualiza progress).
signal dash_unlocked
signal dash_cooldown_changed(remaining: float, total: float)
# Esquivando (compartilha slot/arte do dash — mutuamente exclusivos). Lv2+ ganha
# uma skill no espaço (+30% move speed). HUD reusa a mesma barra do dash.
signal esquivando_unlocked
signal esquivando_cooldown_changed(remaining: float, total: float)
# Stack count + cap atual (cap varia por nível: 3 nos lv1-3, 4 no lv4). HUD
# escuta pra atualizar o ícone perto dos outros skill icons.
signal esquivando_stacks_changed(stacks: int, cap: int)
# Ability ativa/inativa (skill do espaço lv2+, +50% move por 3s). HUD muda o
# modulate do ícone enquanto tá ativo pra dar feedback visual claro.
signal esquivando_ability_active_changed(active: bool)
# Fire Skill (lv3 do elemental Fogo): emitido ao chegar no lv3 (HUD mostra ícone)
# e a cada frame durante o cooldown.
signal fire_skill_unlocked
signal fire_skill_cooldown_changed(remaining: float, total: float)
signal chain_lightning_skill_unlocked
signal chain_lightning_skill_cooldown_changed(remaining: float, total: float)
# Curse Skill (lv4 do elemental Maldição): raio roxo em linha reta, cd 3s.
signal curse_skill_unlocked
signal curse_skill_cooldown_changed(remaining: float, total: float)
# Ice Time Freeze Skill (lv4 do elemental Gelo): pausa mundo inteiro 3s, cd 30s.
signal time_freeze_skill_unlocked
signal time_freeze_skill_cooldown_changed(remaining: float, total: float)
# Perfuração: HUD mostra contador 1/2/3 (próximo tiro perfurante a cada 3 ataques
# nos lv1-3; sempre ativo no lv4). Emitido em cada release_arrow e no apply_upgrade.
signal perfuracao_counter_changed(counter: int, level: int)
# Disparado a cada compra/aquisição de upgrade. HUD escuta pra atualizar a
# coluna de upgrades adquiridos.
signal upgrade_applied(id: String, level: int)

@export var speed: float = 60.961  # base 55 + 1.5% + 4% + 5% = 60.961
@export var attack_cooldown: float = 0.90  # ~+11% atk speed sobre o base 1.0
@export var arrow_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var max_hp: float = 100.0
@export var muzzle_offset_x: float = 8.0
@export var death_freeze_duration: float = 0.4  # tempo parado antes da animação de morte
@export var death_fadeout_duration: float = 0.4  # tempo do sprite sumir após kill_effect
@export var death_blackout_duration: float = 0.3  # tempo da tela ficar preta
@export var kill_effect_scene: PackedScene = preload("res://scenes/effects/kill_effect.tscn")
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
# Armor (status): reduz % do dano recebido E % do slow recebido (resistência).
# Computado de armor_level. Slow reduction é metade da damage reduction.
var armor_level: int = 0
var damage_reduction_pct: float = 0.0
var slow_resistance_pct: float = 0.0
var damage_upgrades: int = 0
var perfuracao_level: int = 0  # capa em 4 (níveis 1-4)
var attack_speed_level: int = 0
var multi_arrow_level: int = 0  # capa em 4 (níveis 1-4)
var double_arrows_level: int = 0  # capa em 4 (níveis 1-4) — mutuamente exclusivo com multi_arrow
var chain_lightning_level: int = 0  # capa em 4 (níveis 1-4)
var move_speed_level: int = 0
var life_steal_level: int = 0  # cada stack +5% chance e +10% heal nos drops de coração
var fire_arrow_level: int = 0  # elemental Fogo (excalidraw lv1-4)
var curse_arrow_level: int = 0  # elemental Maldição (excalidraw lv1, escala lv1-4)
var ice_arrow_level: int = 0  # elemental Gelo / "Fica Frio" (excalidraw lv1-4)
# Referência à Frostwisp spawnada no L3 (1 só por run).
const FROSTWISP_SCENE: PackedScene = preload("res://scenes/allies/frostwisp.tscn")
var _frostwisp: Node2D = null
var woodwarden_level: int = 0  # aliado tank — cada compra "uppa" stats e custo
# Tracking dos woodwardens com respawn nativo (não usa o sistema de structure
# do wave_manager). Cada entry: {"instance", "last_pos", "dead_for"}.
const WOODWARDEN_SCENE: PackedScene = preload("res://scenes/enemies/woodwarden.tscn")
const WOODWARDEN_SPAWN_FX_SCENE: PackedScene = preload("res://scenes/enemies/woodwarden_spawn_effect.tscn")
const WOODWARDEN_RESPAWN_DELAY: float = 15.5
var _woodwardens: Array[Dictionary] = []
# Leno (aliado voador, 4 níveis). Sem HP, orbita o player, dispara projétil
# com slow area no impacto. L1=1 leno (20 dmg), L2=1 leno (50 dmg + atk speed),
# L3=2 lenos, L4=3 lenos. Lenos morrem quando o player morre.
const LENO_SCENE: PackedScene = preload("res://scenes/allies/leno.tscn")
var leno_level: int = 0
var _lenos: Array[Node2D] = []
# Capivara Joe (aliado pet, 4 níveis). Sem HP, vagueia e dropa cogumelos.
# L1: 1 capivara, drop a cada 14s (só buff). L2: 7s alterna buff/dano.
# L3: buff dá ambos efeitos + atk speed. L4: 2 capivaras.
const CAPIVARA_JOE_SCENE: PackedScene = preload("res://scenes/allies/capivara_joe.tscn")
var capivara_joe_level: int = 0
var _capivaras: Array[Node2D] = []
# Buffs temporários aplicados pelo cogumelo da Capivara.
var _capivara_speed_buff_amount: float = 0.0
var _capivara_speed_buff_remaining: float = 0.0
var _capivara_atk_speed_buff_amount: float = 0.0
var _capivara_atk_speed_buff_remaining: float = 0.0
# Mecânico Ting (esquilo aliado, 4 níveis). Sem HP, vagueia e constroi torretas.
# L1: 1 ting, deploy a cada 15s, torreta dura 8s, atk 2s.
# L2: torreta dá 10% AoE + dura 9s. L3: deploy a cada 13s, atk 1.7s. L4: 2 tings.
const TING_SCENE: PackedScene = preload("res://scenes/allies/ting.tscn")
var ting_level: int = 0
var _tings: Array[Node2D] = []
# Contador de magos mortos na wave atual — torreta do Ting ganha +1% atk speed
# por mago morto. Reset no _ready de cada wave pelo wave_manager.
var _mages_killed_this_wave: int = 0
# Fire skill (botão direito a partir do lv3 do Fogo).
const FIRE_SKILL_COOLDOWN: float = 7.0
const FIRE_SKILL_DPS: float = 12.0
const FIRE_SKILL_DURATION: float = 6.0
const FIRE_SKILL_PROJECTILE_SCENE: PackedScene = preload("res://scenes/skills/fire_skill_projectile.tscn")
var _fire_skill_cd_remaining: float = 0.0

# Chain Lightning lv3: skill ativa que invoca um raio (lightning_bolt do
# electric_mage) no ponto alvo. Cast instantâneo na posição do cursor.
# Lv4 buffa o dano do raio em +20%.
const CHAIN_LIGHTNING_SKILL_COOLDOWN: float = 7.0
const CHAIN_LIGHTNING_SKILL_AREA_RADIUS: float = 28.0
const CHAIN_LIGHTNING_SKILL_BOLT_DAMAGE: float = 60.0
const CHAIN_LIGHTNING_LV4_DAMAGE_MULT: float = 1.20
const CHAIN_LIGHTNING_BOLT_SCENE: PackedScene = preload("res://scenes/skills/lightning_bolt.tscn")
var _chain_lightning_skill_cd_remaining: float = 0.0
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
const CURSE_BEAM_SCENE: PackedScene = preload("res://scenes/skills/curse_beam.tscn")
var _curse_skill_cd_remaining: float = 0.0
# Ice Time Freeze (Q a partir do lv4 do Gelo): pausa todos os inimigos, aliados
# e projéteis por 3s. Player continua se movendo/atirando normal. Overlay azul
# em tela inteira pra reforçar a sensação de "tudo congelado".
const TIME_FREEZE_DURATION: float = 3.0
const TIME_FREEZE_COOLDOWN: float = 28.0
const TIME_FREEZE_OVERLAY_COLOR: Color = Color(0.45, 0.75, 1.0, 0.25)
var _time_freeze_cd_remaining: float = 0.0
var _time_freeze_active_remaining: float = 0.0
# Lista de nodes pausados durante o freeze + modo anterior pra restaurar.
# Format: [{"node": Node, "prev_mode": int}]
var _time_freeze_paused: Array = []
var _time_freeze_overlay: CanvasLayer = null
# Lv4 do Fogo: rastro passivo do player + 30% global em queimaduras + 25% área lv2/lv3.
const FIRE_LV4_BURN_MULTIPLIER: float = 1.30
const FIRE_LV4_AREA_SCALE: float = 1.25
const PLAYER_FIRE_TRAIL_SCENE: PackedScene = preload("res://scenes/player/player_fire_trail.tscn")
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
const DASH_COOLDOWNS_BY_LEVEL: Array[float] = [6.3, 5.3, 4.8, 4.3]
var dash_level: int = 0
var has_dash: bool = false
var dash_distance: float = 45.0
var dash_duration: float = 0.22
var dash_cooldown: float = 5.0
var _dash_cd_remaining: float = 0.0
var _is_dashing: bool = false
var _dash_velocity: Vector2 = Vector2.ZERO
var _dash_time_left: float = 0.0
# I-frames concedidos ao iniciar o dash (player imune a dano por X segundos).
const DASH_IFRAMES_DURATION: float = 0.3
var _iframes_remaining: float = 0.0
# Flags derivadas de dash_level:
# - has_dash_auto_attack: dash_level >= 3
# - has_dash_double_arrow: dash_level >= 4
var has_dash_auto_attack: bool = false
var has_dash_double_arrow: bool = false

# === Esquivando (mutuamente exclusivo com dash — compartilham slot de mov.) ===
# Lv1: primeira flecha do volley que acerta inimigo dá +5% atk speed e +5% move
#   speed por 2s. Cap 3 stacks. 2% dodge.
# Lv2: buff vira 8%. Coin pickup também conta como hit (sem volley restriction).
# Lv3: dodge vira 5% (substitui 2%). Skill no espaço: +30% move speed por 3s,
#   cd 15s.
# Lv4: cd da skill vira 10s. Buff vira 10%. Cap 4. CADA hit de CADA flecha
#   stacka (pierce/ricochet/multi-arrow individual).
const ESQUIVANDO_LEVEL_MAX: int = 4
const ESQUIVANDO_STACK_DURATION: float = 2.0
const ESQUIVANDO_STACK_PCT_BY_LEVEL: Array[float] = [0.05, 0.06, 0.09, 0.11]
const ESQUIVANDO_MAX_STACKS_BY_LEVEL: Array[int] = [3, 3, 4, 5]
const ESQUIVANDO_DODGE_BY_LEVEL: Array[float] = [0.02, 0.02, 0.05, 0.05]
const ESQUIVANDO_ABILITY_MIN_LEVEL: int = 2
const ESQUIVANDO_ABILITY_BUFF: float = 0.50
const ESQUIVANDO_ABILITY_DURATION: float = 3.0
const ESQUIVANDO_ABILITY_CD_BY_LEVEL: Array[float] = [15.0, 15.0, 12.5, 10.0]
var esquivando_level: int = 0
var has_esquivando: bool = false
var _esquivando_stacks: int = 0
var _esquivando_stack_remaining: float = 0.0
# ID monotônico da volley atual — incrementa em cada _release_arrow. Arrows
# da MESMA volley compartilham o id, então no lv1-3 só a 1ª flecha que acerta
# gera o stack (as outras viram no-op pela checagem de volley_id).
var _esquivando_volley_id: int = 0
var _esquivando_last_stack_volley: int = -1
# Buff da skill do espaço (lv3+): +50% move speed temporário.
var _esquivando_ability_cd: float = 0.0
var _esquivando_ability_buff_remaining: float = 0.0
# Rastro branco durante a ability — spawna um blob a cada N pixels percorridos
# pelo player, cada um fade-out em ESQUIVANDO_TRAIL_FADE segundos.
const ESQUIVANDO_TRAIL_SPACING: float = 9.0
const ESQUIVANDO_TRAIL_FADE: float = 0.35
const ESQUIVANDO_TRAIL_OFFSET_Y: float = -6.0
var _esquivando_trail_last_pos: Vector2 = Vector2.ZERO
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
# Boomerang (skill passiva, 4 níveis). Cast automático no inimigo mais próximo
# a cada CD do nível. L3 = 2 boomerangs (alvo + oposto). L4 = 4 boomerangs
# (alvo + oposto + 2 perpendiculares).
const BOOMERANG_SCENE: PackedScene = preload("res://scenes/skills/boomerang.tscn")
const BOOMERANG_CD_BY_LEVEL: Array[float] = [5.0, 4.0, 4.0, 4.0]
const BOOMERANG_DAMAGE_BY_LEVEL: Array[float] = [15.0, 20.0, 25.0, 30.0]
const BOOMERANG_RANGE_BY_LEVEL: Array[float] = [140.0, 140.0, 140.0, 140.0]
var boomerang_level: int = 0
var _boomerang_cd_remaining: float = 0.0
# Flecha Crítica (4 níveis). Aplica em flechas + skills (skill Q de fogo, chain
# lightning skill, curse beam, boomerang). Não aplica em DoTs (burn/curse tick)
# nem em dano de aliados/torres.
# L1: 30% chance, +50% dano + knockback bonus em flechas
# L2: 50% chance, +50% dano
# L3: 70% chance, +60% dano
# L4: 100% chance, +65% dano
const CRIT_CHANCE_BY_LEVEL: Array[float] = [0.30, 0.50, 0.70, 1.00]
const CRIT_DAMAGE_BONUS_BY_LEVEL: Array[float] = [0.50, 0.50, 0.60, 0.65]
const CRIT_KNOCKBACK_MULT: float = 2.0  # arrows on crit recebem 2× knockback
var critical_chance_level: int = 0


func roll_crit() -> Dictionary:
	# Helper público: cada damage site chama isso pra decidir se o hit é crit.
	# Retorna {"crit": bool, "mult": float}. mult=1.0 quando não crita.
	if critical_chance_level <= 0:
		return {"crit": false, "mult": 1.0}
	var lvl: int = mini(critical_chance_level - 1, 3)
	if randf() < CRIT_CHANCE_BY_LEVEL[lvl]:
		return {"crit": true, "mult": 1.0 + CRIT_DAMAGE_BONUS_BY_LEVEL[lvl]}
	return {"crit": false, "mult": 1.0}


func crit_knockback_mult() -> float:
	# Bonus de knockback em flechas quando crit. Ler em arrow.gd antes de
	# apply_knockback (não global — só flechas, não skills).
	return CRIT_KNOCKBACK_MULT


func roll_crit_dot(base_dmg: float) -> Dictionary:
	# Versão pra DoTs: garante bônus MÍNIMO de +1 dano quando crita (sem isso
	# DoTs pequenos com bônus % < 1 ficariam invisíveis no crit). Retorna
	# {"crit": bool, "dmg": float} (dmg final pronto pra aplicar).
	if critical_chance_level <= 0 or base_dmg <= 0.0:
		return {"crit": false, "dmg": base_dmg}
	var lvl: int = mini(critical_chance_level - 1, 3)
	if randf() < CRIT_CHANCE_BY_LEVEL[lvl]:
		var bonus: float = base_dmg * CRIT_DAMAGE_BONUS_BY_LEVEL[lvl]
		if bonus < 1.0:
			bonus = 1.0
		return {"crit": true, "dmg": base_dmg + bonus}
	return {"crit": false, "dmg": base_dmg}
# Trilha de poder do dash: spawna um segmento a cada N px percorridos durante
# o dash. Cada segmento dura 3s e dá DPS roxo em inimigos na área.
# DPS escala com dash_level: lv2+ ativa o trail, lv3 e lv4 aumentam dano.
const DASH_TRAIL_SCENE: PackedScene = preload("res://scenes/player/dash_trail.tscn")
const DASH_TRAIL_SPACING: float = 14.0
const DASH_TRAIL_DPS_BASE: float = 5.0
const DASH_TRAIL_DPS_PER_STACK: float = 2.5
var _dash_last_trail_pos: Vector2 = Vector2.ZERO
# Delay antes da primeira flecha auto-disparada pelo dash (1.3).
const DASH_FIRST_ARROW_DELAY: float = 0.60
# Delay entre 1ª e 2ª flecha (1.3.1) — referente ao tempo da primeira.
const DASH_DOUBLE_ARROW_DELAY: float = 0.40
var arrow_damage_multiplier: float = 1.0  # aplicado ao dano da arrow no spawn
var attack_speed_multiplier: float = 1.0  # 1.0 base, +0.27 por stack
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
# Macaquinhos (grupo "monkey") convertidos pelo disparo profano — desbloqueia
# a skin Linked aos 200 totais acumulados entre runs.
var stats_monkeys_cursed: int = 0
var stats_damage_dealt: float = 0.0
var stats_damage_taken: float = 0.0
# Breakdown de dano recebido por tipo de fonte (source_id passado em take_damage).
# Ex: { "melee": 120.5, "mage": 200.0, "monkey": 80.0, "insect": 40.0 }
# Enviado em run_end pra analytics ver qual inimigo mais machuca.
var stats_damage_taken_by_source: Dictionary = {}
# Source_id do golpe final que matou o player (empty se ainda vivo / suicide).
# Capturado em take_damage / _apply_poison_tick quando hp chega a 0.
var stats_killed_by: String = ""
# Breakdown de dano CAUSADO pelo player por fonte (upgrade/skill/aliado).
# Ex: { "arrow_base": 1500, "fire_arrow": 800, "graviton": 400 }
var stats_damage_dealt_by_source: Dictionary = {}
# Mesmo breakdown mas zera no início de cada wave. Lido pelo painel TAB do HUD
# pra mostrar contribuição de cada fonte na wave atual (ou na wave que acabou,
# enquanto o shop está aberto — reset só acontece quando a próxima wave começa).
var wave_damage_by_source: Dictionary = {}
# Breakdown de kills por fonte. Ex: { "arrow_base": 12, "fire_arrow": 5 }
var stats_kills_by_source: Dictionary = {}
# Lista de IDs de bosses mortos nesta run. Usada pelo skin_loadout.record_run
# pra detectar unlocks de skins do tipo `boss_killed`.
var stats_bosses_killed: Array[String] = []


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
	# Aplica skin salva (peças layered em cima do body). Sem efeito até o
	# usuário ter peças configuradas em assets/player/skin_parts/ e selecionadas
	# pela UI de skin.
	SkinLoadout.apply_to(self)


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)
	_update_dash(delta)
	_update_esquivando(delta)
	_update_fire_skill(delta)
	_update_chain_lightning_skill(delta)
	_update_boomerang(delta)
	_update_curse_skill(delta)
	_update_time_freeze(delta)
	_update_player_fire_trail()
	_check_woodwarden_respawns(delta)
	_tick_capivara_buffs(delta)
	# Dash trigger lê via polling pra garantir que o cooldown decrementa ANTES
	# do check, e que múltiplas pressões na mesma frame só viram 1 dash.
	# Espaço serve dash OU esquivando (mutuamente exclusivos). Esquivando só
	# responde a partir do lv3, antes disso o espaço é no-op se o player não
	# tem dash.
	if not is_dead and Input.is_action_just_pressed("dash"):
		if has_dash:
			_try_start_dash()
		elif esquivando_level >= ESQUIVANDO_ABILITY_MIN_LEVEL:
			_try_start_esquivando_ability()
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

	velocity = input_vec * speed * _slow_factor * (move_speed_multiplier + _capivara_speed_buff_amount + _esquivando_move_buff())
	move_and_slide()

	_update_facing(input_vec)
	_update_animation(input_vec)


func apply_slow(multiplier: float, duration: float) -> void:
	# Pega o slow mais forte ativo (multiplier mais baixo) e estende a duração se necessário.
	if is_dead:
		return
	# Armor reduz a intensidade do slow recebido: lerp do multiplier rumo a 1.0
	# pela slow_resistance_pct. Ex: slow 50% (mult=0.5) com 10% res → mult final
	# = 0.5 + (1.0 - 0.5) × 0.10 = 0.55 (45% slow em vez de 50%).
	if slow_resistance_pct > 0.0 and multiplier < 1.0:
		multiplier = lerp(multiplier, 1.0, clampf(slow_resistance_pct, 0.0, 1.0))
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
	notify_damage_taken(amount, "insect_poison")
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_spawn_poison_number(amount)
	if hp == 0.0:
		stats_killed_by = "insect_poison"
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
	if is_dead:
		return
	if event.is_action_pressed("attack") and can_attack:
		_start_attack()
	elif event.is_action_pressed("skill"):
		_use_skill()
	elif event.is_action_pressed("fire_cast"):
		# Q dispatcha pra QUALQUER skill elemental ativa disponível, em ordem
		# de prioridade: Fogo lv3+ → Chain Lightning lv3+ → Maldição lv4+.
		# Como por design o player tem só 1 elemental por run, geralmente cai
		# direto no que ele tem. Dev mode (com várias) usa essa ordem.
		if fire_arrow_level >= 3:
			_handle_fire_skill_press()
		elif chain_lightning_level >= 3:
			_handle_chain_lightning_skill_press()
		elif curse_arrow_level >= 4:
			_cast_curse_beam()
		elif ice_arrow_level >= 4:
			_trigger_time_freeze()
	elif event.is_action_pressed("lightning_cast"):
		# E é atalho alternativo específico pra Chain Lightning (lv3+).
		if chain_lightning_level >= 3:
			_handle_chain_lightning_skill_press()


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
	# Time Freeze (Q do Gelo lv4) ativo: player só pode se mover, não atira.
	# Movimento livre dá um window tático de reposicionamento, sem DPS.
	if _time_freeze_active_remaining > 0.0:
		return
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
	# Capivara L3+: cogumelo de buff dá +50% atk speed temporário (some no fim).
	var atk_mult: float = attack_speed_multiplier + _capivara_atk_speed_buff_amount + _esquivando_atk_buff()
	attack_timer.wait_time = attack_cooldown / atk_mult
	sprite.speed_scale = atk_mult
	attack_timer.start()
	sprite.play("attack")


func _release_arrow() -> void:
	is_drawing = false
	if arrow_scene == null:
		return
	# Esquivando: cada release_arrow = 1 volley nova. Todas as flechas spawnadas
	# nesse ataque (incluindo as delayed do double_arrows) compartilham o id —
	# lv1-3 do Esquivando bloqueia stacks adicionais do mesmo volley_id.
	_esquivando_volley_id += 1
	# Decisão de pierce é feita UMA VEZ por ataque — a volley inteira de
	# Multiple Arrows compartilha o mesmo flag (ex: lv perfuração 1 + multi lv1
	# = a cada 3º ataque, as 3 flechas perfuram juntas).
	var is_pierce: bool = _is_piercing_shot()
	if is_pierce:
		_perf_shot_counter = 0
	elif perfuracao_level > 0:
		# Só incrementa se a perfurante foi comprada. Sem isso, o counter
		# acumula a partida inteira e ao comprar o upgrade aparece em 100+
		# até resetar no 1º hit.
		_perf_shot_counter += 1
	if perfuracao_level > 0:
		perfuracao_counter_changed.emit(_perf_shot_counter, perfuracao_level)
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
		var delay: float = float(shot.get("delay_sec", 0.0))
		if delay > 0.0:
			get_tree().create_timer(delay).timeout.connect(
				_spawn_arrow.bind(shot["dir"], shot["dmg_mult"], is_pierce, false, false, is_ricochet, is_graviton)
			)
		else:
			_spawn_arrow(shot["dir"], shot["dmg_mult"], is_pierce, i == 0, i == 0, is_ricochet, is_graviton)


# Cada entrada da volley = {dir: Vector2, dmg_mult: float} (relativo ao dmg base).
# Multi Arrow combina com perfuração/elementais aplicando o mesmo flag em todas.
func _build_volley() -> Array:
	var primary: Vector2 = locked_aim_dir
	var shots: Array = []
	if multi_arrow_level == 0 and double_arrows_level > 0:
		return _build_double_arrows_volley(primary)
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


# Flechas Duplas — alternativo do Multi Arrow. Clusters mais apertados (±12/20/32°)
# e contagem decidida por rolls. Counter de 3 ataques só conta a partir do NV2.
# Resolução: roll 5-flechas (1%, só NV4) → roll 3-flechas (NV3 30% / NV4 60%) →
# garantia/30% de duplas. Extras = 0.75x dano da primária.
func _build_double_arrows_volley(primary: Vector2) -> Array:
	# Spec por nível (cada roll independente; "maior contagem prevalece"):
	#   NV1: 30% duplas. Secundária dá 50% dano.
	#   NV2: 30% duplas. Ambas dano total.
	#   NV3: 60% duplas + 30% triplas → maior prevalece (≤3 flechas).
	#   NV4: 90% duplas + 60% triplas + 1% quíntuplas → maior prevalece (≤5).
	var shots: Array = []
	var lvl: int = double_arrows_level
	var count: int = 1
	match lvl:
		1:
			if randf() < 0.30:
				count = 2
		2:
			if randf() < 0.30:
				count = 2
		3:
			if randf() < 0.60:
				count = maxi(count, 2)
			if randf() < 0.30:
				count = maxi(count, 3)
		4:
			if randf() < 0.90:
				count = maxi(count, 2)
			if randf() < 0.60:
				count = maxi(count, 3)
			if randf() < 0.01:
				count = maxi(count, 5)
	# Dano: NV1 secundária a 50%; NV2+ todas a 100%.
	var extra_dmg: float = 0.5 if lvl == 1 else 1.0
	# Delay entre flechas extras (burst rápido pra cada uma ser distinta no spawn).
	const DELAY_PER_EXTRA: float = 0.04
	# Ângulos APERTADOS: 1° de diferença entre flechas adjacentes — quase a mesma
	# mira, mas separação suficiente pra não sobrepor visualmente no spawn.
	if count == 1:
		shots.append({"dir": primary, "dmg_mult": 1.0})
	elif count == 2:
		shots.append({"dir": primary.rotated(deg_to_rad(-0.5)), "dmg_mult": 1.0})
		shots.append({"dir": primary.rotated(deg_to_rad(0.5)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA})
	elif count == 3:
		shots.append({"dir": primary, "dmg_mult": 1.0})
		shots.append({"dir": primary.rotated(deg_to_rad(1.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA})
		shots.append({"dir": primary.rotated(deg_to_rad(-1.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA * 2})
	elif count == 5:
		shots.append({"dir": primary, "dmg_mult": 1.0})
		shots.append({"dir": primary.rotated(deg_to_rad(1.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA})
		shots.append({"dir": primary.rotated(deg_to_rad(-1.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA * 2})
		shots.append({"dir": primary.rotated(deg_to_rad(2.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA * 3})
		shots.append({"dir": primary.rotated(deg_to_rad(-2.0)), "dmg_mult": extra_dmg, "delay_sec": DELAY_PER_EXTRA * 4})
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
		if "burn_final_bonus" in arrow:
			# Último tick do burn dá um dano extra fixo (ignora burn_scale —
			# bonus pequeno, não vale a pena dividir entre flechas extras).
			arrow.burn_final_bonus = 5.0
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
	if ice_arrow_level > 0:
		if "is_ice" in arrow:
			arrow.is_ice = true
		if "freeze_duration" in arrow:
			arrow.freeze_duration = _ice_freeze_duration()
		if "freeze_dps" in arrow:
			arrow.freeze_dps = _ice_freeze_dps()
		# Lv2+: spawna área nevada no impacto (reaproveita o IceSlowArea do mago).
		if ice_arrow_level >= 2:
			if "ice_area_enabled" in arrow:
				arrow.ice_area_enabled = true
			if "ice_area_slow_factor" in arrow:
				arrow.ice_area_slow_factor = _ice_area_slow_factor()
			if "ice_area_lifetime" in arrow:
				arrow.ice_area_lifetime = _ice_area_lifetime()
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
	# Fora do `if is_graviton:` — source e volley_id valem pra TODA flecha do
	# player (não só as graviton). Bug pré-existente: estavam aninhados na
	# graviton, impedindo notify_esquivando_hit em flechas normais.
	if "source" in arrow:
		arrow.source = self
	# Esquivando: tagga a flecha com o volley_id atual pra o helper saber
	# qual volley já gerou stack (lv1-3) — lv4 ignora isso.
	if "volley_id" in arrow:
		arrow.volley_id = _esquivando_volley_id
	# Breakdown de dano por fonte (painel TAB): flechas extras (não-primárias)
	# são atribuídas ao upgrade que as gerou. Multi e Duplas são mutex.
	if "is_primary_arrow" in arrow:
		arrow.is_primary_arrow = is_primary
	if "telemetry_source_id_extra" in arrow:
		if multi_arrow_level > 0:
			arrow.telemetry_source_id_extra = "multi_arrow"
		elif double_arrows_level > 0:
			arrow.telemetry_source_id_extra = "double_arrows"
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
	# L1-L2 = 45, L3-L4 = 50. Raio compacto pra ficar bem contido no chão.
	match graviton_level:
		1: return 45.0
		2: return 45.0
		3: return 50.0
		4: return 50.0
	return 45.0


func _graviton_lifetime() -> float:
	# L1 mais curto (1.3s) pra equilibrar o slow leve. L2+ mantém 3s.
	if graviton_level == 1:
		return 1.3
	return 3.0


func _graviton_slow_factor() -> float:
	# L1 = 20% slow (factor 0.8). L2+ = 30% slow (factor 0.7).
	if graviton_level == 1:
		return 0.8
	return 0.7


func _graviton_explosion_damage() -> float:
	# Só L4 dá dano AoE no fim (20). L1-L3 são puro CC/slow.
	# O throttle de 3s/inimigo é aplicado no graviton_pulse pra evitar que
	# múltiplos pulsos (volley/ataques em sequência) empilhem dano no mesmo alvo.
	if graviton_level >= 4:
		return 20.0
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
	return _apply_dmg_pct_to_dps(base * _fire_burn_multiplier())


func _fire_burn_duration() -> float:
	# Tempo total do fogo (tick_interval=0.5s no BurnDoT, então cada +0.5s = +1 tick).
	# 5.0s → 10 ticks por fogo.
	return 5.0


func _fire_trail_dps() -> float:
	# Lv2+ : DPS do rastro de fogo da flecha × multiplier global.
	var base: float = 0.0
	match fire_arrow_level:
		2: base = 4.0
		3: base = 5.0
		4: base = 7.0
	return _apply_dmg_pct_to_dps(base * _fire_burn_multiplier())


func _curse_dps() -> float:
	# DoT toxic da maldição. Spec só define lv1 — escalei levemente pra
	# diferenciar níveis sem mudar o design (lv2-4 focam na conversão de aliados).
	# Lv1 = 3 dps × 4s = 12 total dmg. Mesmo gate do fogo: sem dano, arrow(25)
	# + DoT(12) = 37 não mata macaco wave 1 (40 HP); com dano, arrow(30) +
	# DoT(12) = 42 mata via DoT.
	var base: float = 0.0
	match curse_arrow_level:
		1: base = 3.0
		2: base = 4.0
		3: base = 6.0
		4: base = 8.0
	return _apply_dmg_pct_to_dps(base)


func _apply_dmg_pct_to_dps(base: float) -> float:
	# Aplica o arrow_damage_multiplier (stat "Dano") no dps de DoT.
	# Garante incremento mínimo de +1 quando há % de dano ativo — DoTs de base
	# baixa (ex: curse lv1 = 3 dps × 1.20 = 3.6) sentiriam pouco do stat sem isso.
	if base <= 0.0 or arrow_damage_multiplier <= 1.0:
		return base
	var scaled: float = base * arrow_damage_multiplier
	if scaled - base < 1.0:
		scaled = base + 1.0
	return scaled


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


func _ice_freeze_duration() -> float:
	# Lv1: 2s de freeze ao contato. Níveis 2-4 ainda não implementados — placeholders
	# pra escalar duração se quisermos no futuro (atualmente todos 2s).
	if ice_arrow_level <= 0:
		return 0.0
	return 2.0


func _ice_freeze_dps() -> float:
	# DoT contínuo enquanto congelado. Lv1=4 dps (8 total em 2s). Lv2+=8 dps
	# (16 total em 2s — dobra como upgrade do L2). Escala com o stat "Dano"
	# (arrow_damage_multiplier) via _apply_dmg_pct_to_dps — mesmo padrão de
	# burn/curse, garante que stacks de Dano também buffem o gelo.
	if ice_arrow_level <= 0:
		return 0.0
	var base: float = 8.0 if ice_arrow_level >= 2 else 4.0
	return _apply_dmg_pct_to_dps(base)


func _spawn_frostwisp() -> void:
	# Spawna a Frostwisp 1 vez (L3 do Gelo) e mantém a referência. Se já existe
	# uma viva, no-op. Spawnada no world (Entities) pra ficar no mesmo bucket
	# de spawn dos outros aliados.
	if _frostwisp != null and is_instance_valid(_frostwisp):
		return
	if FROSTWISP_SCENE == null:
		return
	var wisp: Node = FROSTWISP_SCENE.instantiate()
	_get_world().add_child(wisp)
	if wisp is Node2D:
		(wisp as Node2D).global_position = global_position + Vector2(48, -40)
	_frostwisp = wisp as Node2D


func _ice_area_slow_factor() -> float:
	# Lv2: 37% slow na área (igual mage). Lv3-4 pode ficar mais forte no futuro.
	return 0.63


func _ice_area_lifetime() -> float:
	# Lv2: área dura 5.5s. Refresh aplicado por outras flechas que pousem
	# na mesma região (cada uma spawna sua própria área, sobrepondo).
	return 5.5


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


# Contador global de hits pra gating de proc do chain L1 (proca a cada 2 hits).
# Global em vez de per-arrow pra que volleys multi-arrow não driblem o gate.
var _chain_proc_counter: int = 0


func consume_chain_proc_token() -> bool:
	# Retorna true se este hit deve gerar chain lightning. L1 = a cada 2 hits;
	# L2+ = todo hit. Chamado pelo arrow antes de procar.
	if chain_lightning_level <= 0:
		return false
	if chain_lightning_level >= 2:
		return true
	_chain_proc_counter += 1
	if _chain_proc_counter >= 2:
		_chain_proc_counter = 0
		return true
	return false


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
	# Cast direto na posição do cursor — sem targeter, sem range clamp. Range
	# efetivo = tela inteira (igual ao Chain Lightning skill).
	if _fire_skill_cd_remaining > 0.0:
		return
	var target: Vector2 = get_global_mouse_position()
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
	# Só tick do cooldown — cast é instantâneo, sem targeting state.
	if _fire_skill_cd_remaining > 0.0:
		_fire_skill_cd_remaining = maxf(_fire_skill_cd_remaining - delta, 0.0)
		fire_skill_cooldown_changed.emit(_fire_skill_cd_remaining, FIRE_SKILL_COOLDOWN)


# ---------- Chain Lightning lv3+ skill ativa ----------

func _handle_chain_lightning_skill_press() -> void:
	# Cast direto na posição do cursor — sem range indicator, sem confirm.
	# Cooldown padrão segura spam.
	if _chain_lightning_skill_cd_remaining > 0.0:
		return
	var target: Vector2 = get_global_mouse_position()
	if CHAIN_LIGHTNING_BOLT_SCENE != null:
		var bolt: Node = CHAIN_LIGHTNING_BOLT_SCENE.instantiate()
		var dmg_mult: float = CHAIN_LIGHTNING_LV4_DAMAGE_MULT if chain_lightning_level >= 4 else 1.0
		if "damage" in bolt:
			bolt.damage = CHAIN_LIGHTNING_SKILL_BOLT_DAMAGE * dmg_mult
		if "damage_radius" in bolt:
			bolt.damage_radius = CHAIN_LIGHTNING_SKILL_AREA_RADIUS
		if "is_enemy_source" in bolt:
			bolt.is_enemy_source = false
		_get_world().add_child(bolt)
		if bolt is Node2D:
			(bolt as Node2D).global_position = target
	_chain_lightning_skill_cd_remaining = CHAIN_LIGHTNING_SKILL_COOLDOWN
	chain_lightning_skill_cooldown_changed.emit(_chain_lightning_skill_cd_remaining, CHAIN_LIGHTNING_SKILL_COOLDOWN)


func _update_chain_lightning_skill(delta: float) -> void:
	# Só tick do cooldown — cast é instantâneo agora, sem targeting state.
	if _chain_lightning_skill_cd_remaining > 0.0:
		_chain_lightning_skill_cd_remaining = maxf(_chain_lightning_skill_cd_remaining - delta, 0.0)
		chain_lightning_skill_cooldown_changed.emit(_chain_lightning_skill_cd_remaining, CHAIN_LIGHTNING_SKILL_COOLDOWN)


# ---------- Boomerang (skill passiva auto-cast) ----------

func _update_boomerang(delta: float) -> void:
	if boomerang_level <= 0 or is_dead:
		return
	if _boomerang_cd_remaining > 0.0:
		_boomerang_cd_remaining = maxf(_boomerang_cd_remaining - delta, 0.0)
		return
	# Tenta castar. Se não tem inimigo, mantém cd zerado e tenta de novo no
	# próximo frame até aparecer alvo.
	if _try_cast_boomerang():
		_boomerang_cd_remaining = BOOMERANG_CD_BY_LEVEL[mini(boomerang_level - 1, 3)]


func _try_cast_boomerang() -> bool:
	# Encontra inimigo mais próximo. Sem alvo = sem cast (cd não dispara).
	var nearest: Node2D = _find_nearest_enemy()
	if nearest == null:
		return false
	var rng: float = BOOMERANG_RANGE_BY_LEVEL[mini(boomerang_level - 1, 3)]
	# Skipa o cast se o inimigo mais próximo tá além do range — boomerang nunca
	# alcançaria. CD não dispara, tenta de novo nos próximos frames quando algum
	# inimigo entrar no raio.
	if nearest.global_position.distance_squared_to(global_position) > rng * rng:
		return false
	var primary_dir: Vector2 = (nearest.global_position - global_position).normalized()
	if primary_dir.length_squared() < 0.001:
		primary_dir = Vector2.RIGHT
	var dmg: float = BOOMERANG_DAMAGE_BY_LEVEL[mini(boomerang_level - 1, 3)]
	# L1-L2: 1 boomerang. L3: 2 (alvo + 180°). L4: 4 (alvo + 180° + 90° + 270°).
	_spawn_boomerang(primary_dir, dmg, rng)
	if boomerang_level >= 3:
		_spawn_boomerang(-primary_dir, dmg, rng)
	if boomerang_level >= 4:
		_spawn_boomerang(primary_dir.rotated(PI / 2.0), dmg, rng)
		_spawn_boomerang(primary_dir.rotated(-PI / 2.0), dmg, rng)
	return true


func _spawn_boomerang(dir: Vector2, dmg: float, rng: float) -> void:
	var boom: Node = BOOMERANG_SCENE.instantiate()
	if "damage" in boom:
		boom.damage = dmg
	if "travel_distance" in boom:
		boom.travel_distance = rng
	_get_world().add_child(boom)
	if boom.has_method("setup"):
		boom.setup(global_position, dir, self)


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


# ---------- Ice Time Freeze (Q a partir do lv4 do Gelo) ----------

func _trigger_time_freeze() -> void:
	# Cast direto: pausa tudo que não é o player nem suas flechas + mostra
	# overlay azul. Sem targeter, sem warmup. Ativa 3s + cd 30s.
	if _time_freeze_cd_remaining > 0.0 or _time_freeze_active_remaining > 0.0:
		return
	_apply_time_freeze_world_pause()
	_show_freeze_overlay()
	_time_freeze_active_remaining = TIME_FREEZE_DURATION
	_time_freeze_cd_remaining = TIME_FREEZE_COOLDOWN
	time_freeze_skill_cooldown_changed.emit(_time_freeze_cd_remaining, TIME_FREEZE_COOLDOWN)


func _update_time_freeze(delta: float) -> void:
	# Decai o timer ativo (pausa expira → restaura mundo + esconde overlay).
	# Cooldown decai depois — começa a contar junto com a ativação (igual ao
	# fire skill), então 27s após o freeze expirar a skill volta a estar pronta.
	if _time_freeze_active_remaining > 0.0:
		_time_freeze_active_remaining = maxf(_time_freeze_active_remaining - delta, 0.0)
		if _time_freeze_active_remaining <= 0.0:
			_remove_time_freeze_world_pause()
			_hide_freeze_overlay()
	if _time_freeze_cd_remaining > 0.0:
		_time_freeze_cd_remaining = maxf(_time_freeze_cd_remaining - delta, 0.0)
		time_freeze_skill_cooldown_changed.emit(_time_freeze_cd_remaining, TIME_FREEZE_COOLDOWN)


func _apply_time_freeze_world_pause() -> void:
	# Itera o tree e pausa via process_mode = DISABLED todo node que NÃO seja
	# o player nem suas flechas (arrow.source == self). Guarda o modo anterior
	# pra restaurar depois sem alterar valores customizados.
	_time_freeze_paused.clear()
	# Inimigos + projéteis deles + estruturas/aliados/objetos animados.
	for n in get_tree().get_nodes_in_group("enemy"):
		_pause_node_for_freeze(n)
	for n in get_tree().get_nodes_in_group("ally"):
		_pause_node_for_freeze(n)
	for n in get_tree().get_nodes_in_group("tank_ally"):
		_pause_node_for_freeze(n)
	# Projéteis genéricos: varre o world e pega tudo que é Area2D que NÃO é
	# do player (arrow.source != self). Cobre mage_projectile, insect_projectile,
	# lightning_bolt, fire_field, ice_slow_area, etc.
	var world := _get_world()
	if world != null:
		for child in world.get_children():
			if child == self:
				continue
			if "source" in child and child.source == self:
				continue  # flecha do player — deixa passar
			if not (child is Area2D or child is Node2D):
				continue
			# Skip se já pausamos via grupo acima.
			if _is_node_in_pause_list(child):
				continue
			# Skip nodes estáticos sem _process (otimização — process_mode disabled
			# em static decor não faz nada útil, mas tampouco quebra. Skip via
			# group check pra evitar duplicatas e ruído.)
			if child.is_in_group("static_decoration"):
				continue
			_pause_node_for_freeze(child)


func _pause_node_for_freeze(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node == self:
		return
	# freeze_immune: aliados/projeteis "do gelo" (Frostwisp + projeteis dela)
	# continuam ativos durante o Time Freeze pra dar dano no mundo congelado.
	if node.is_in_group("freeze_immune"):
		return
	if node.process_mode == Node.PROCESS_MODE_DISABLED:
		return
	_time_freeze_paused.append({"node": node, "prev_mode": node.process_mode})
	node.process_mode = Node.PROCESS_MODE_DISABLED


func _is_node_in_pause_list(node: Node) -> bool:
	for entry in _time_freeze_paused:
		if entry["node"] == node:
			return true
	return false


func _remove_time_freeze_world_pause() -> void:
	# Usa variável untyped + is_instance_valid antes do acesso pra evitar
	# "Trying to assign invalid previously freed instance" quando um inimigo
	# foi queue_free durante o freeze (ex: DoT terminou de matar antes do
	# freeze acabar, ou pickup foi coletado).
	for entry in _time_freeze_paused:
		var raw = entry.get("node")
		if raw == null or not is_instance_valid(raw):
			continue
		raw.process_mode = entry["prev_mode"]
	_time_freeze_paused.clear()


func _show_freeze_overlay() -> void:
	# CanvasLayer + ColorRect cobrindo a tela inteira. Layer alto pra ficar
	# acima do mundo, abaixo da HUD (HUD usa layer ~5+, time freeze fica em 3).
	# Tween de fade-in rápido pra não estourar bruto.
	if _time_freeze_overlay != null and is_instance_valid(_time_freeze_overlay):
		return
	var layer := CanvasLayer.new()
	layer.layer = 3
	var rect := ColorRect.new()
	rect.color = TIME_FREEZE_OVERLAY_COLOR
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.modulate.a = 0.0
	layer.add_child(rect)
	get_tree().current_scene.add_child(layer)
	_time_freeze_overlay = layer
	var tw := rect.create_tween()
	tw.tween_property(rect, "modulate:a", 1.0, 0.15)


func _hide_freeze_overlay() -> void:
	if _time_freeze_overlay == null or not is_instance_valid(_time_freeze_overlay):
		return
	var layer: CanvasLayer = _time_freeze_overlay
	var rect: ColorRect = null
	if layer.get_child_count() > 0:
		rect = layer.get_child(0) as ColorRect
	_time_freeze_overlay = null
	if rect != null:
		var tw := rect.create_tween()
		tw.tween_property(rect, "modulate:a", 0.0, 0.25)
		tw.tween_callback(layer.queue_free)
	else:
		layer.queue_free()


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
	_iframes_remaining = DASH_IFRAMES_DURATION
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
	p.bus = &"SFX"
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
	if _iframes_remaining > 0.0:
		_iframes_remaining = maxf(_iframes_remaining - delta, 0.0)


# === Esquivando: helpers, stack tick, ability ===

func _esquivando_stack_pct() -> float:
	if esquivando_level <= 0:
		return 0.0
	return ESQUIVANDO_STACK_PCT_BY_LEVEL[mini(esquivando_level - 1, ESQUIVANDO_LEVEL_MAX - 1)]


func _esquivando_max_stacks() -> int:
	if esquivando_level <= 0:
		return 0
	return ESQUIVANDO_MAX_STACKS_BY_LEVEL[mini(esquivando_level - 1, ESQUIVANDO_LEVEL_MAX - 1)]


func _esquivando_dodge_chance() -> float:
	if esquivando_level <= 0:
		return 0.0
	return ESQUIVANDO_DODGE_BY_LEVEL[mini(esquivando_level - 1, ESQUIVANDO_LEVEL_MAX - 1)]


func _esquivando_ability_cd_total() -> float:
	if esquivando_level < ESQUIVANDO_ABILITY_MIN_LEVEL:
		return 0.0
	return ESQUIVANDO_ABILITY_CD_BY_LEVEL[mini(esquivando_level - 1, ESQUIVANDO_LEVEL_MAX - 1)]


# Buff combinado de move speed do Esquivando (stacks + skill do espaço).
func _esquivando_move_buff() -> float:
	if esquivando_level <= 0:
		return 0.0
	var stack_buff: float = float(_esquivando_stacks) * _esquivando_stack_pct()
	var ability_buff: float = ESQUIVANDO_ABILITY_BUFF if _esquivando_ability_buff_remaining > 0.0 else 0.0
	return stack_buff + ability_buff


# Buff de atk speed do Esquivando (só stacks — a skill do espaço é só move).
func _esquivando_atk_buff() -> float:
	if esquivando_level <= 0:
		return 0.0
	return float(_esquivando_stacks) * _esquivando_stack_pct()


# Chamado pelo arrow ao bater num inimigo. Lv1-3: só 1 stack por volley
# (primeiro arrow.volley_id novo). Lv4: cada hit stacka. Cap variável por nível.
func notify_esquivando_hit(arrow: Node) -> void:
	if esquivando_level <= 0 or is_dead:
		return
	if esquivando_level >= ESQUIVANDO_LEVEL_MAX:
		_apply_esquivando_stack()
		return
	if arrow == null or not is_instance_valid(arrow):
		return
	# Lv1-3: bloqueia se a flecha já stackou (perfurante: 1 stack para a flecha
	# inteira) OU se a volley já stackou (multi-arrow: 1 stack pra volley toda).
	if "gave_esquivando_stack" in arrow and bool(arrow.gave_esquivando_stack):
		return
	var vid: int = int(arrow.get("volley_id")) if "volley_id" in arrow else -1
	if vid >= 0 and vid == _esquivando_last_stack_volley:
		return
	_apply_esquivando_stack()
	if "gave_esquivando_stack" in arrow:
		arrow.gave_esquivando_stack = true
	if vid >= 0:
		_esquivando_last_stack_volley = vid


# Coin pickup também conta como hit no lv2+ (sem volley restriction).
func notify_esquivando_coin_pickup() -> void:
	if esquivando_level < 2 or is_dead:
		return
	_apply_esquivando_stack()


func _apply_esquivando_stack() -> void:
	var cap: int = _esquivando_max_stacks()
	_esquivando_stacks = mini(_esquivando_stacks + 1, cap)
	_esquivando_stack_remaining = ESQUIVANDO_STACK_DURATION
	esquivando_stacks_changed.emit(_esquivando_stacks, cap)


func _try_start_esquivando_ability() -> void:
	if esquivando_level < ESQUIVANDO_ABILITY_MIN_LEVEL or is_dead:
		return
	if _esquivando_ability_cd > 0.0:
		return
	_esquivando_ability_buff_remaining = ESQUIVANDO_ABILITY_DURATION
	_esquivando_ability_cd = _esquivando_ability_cd_total()
	_iframes_remaining = maxf(_iframes_remaining, DASH_IFRAMES_DURATION)
	_esquivando_trail_last_pos = global_position
	# Spawna o primeiro blob na hora pra dar feedback imediato (sem esperar
	# percorrer ESQUIVANDO_TRAIL_SPACING).
	_spawn_esquivando_trail_segment()
	esquivando_cooldown_changed.emit(_esquivando_ability_cd, _esquivando_ability_cd_total())
	esquivando_ability_active_changed.emit(true)


func _update_esquivando(delta: float) -> void:
	if esquivando_level <= 0:
		return
	# Duração dos stacks: se acabar, zera tudo (perde os stacks acumulados).
	if _esquivando_stacks > 0:
		_esquivando_stack_remaining -= delta
		if _esquivando_stack_remaining <= 0.0:
			_esquivando_stacks = 0
			_esquivando_stack_remaining = 0.0
			_esquivando_last_stack_volley = -1
			esquivando_stacks_changed.emit(0, _esquivando_max_stacks())
	# Skill do espaço: tick do buff temporário + cooldown. Quando o buff
	# terminar, sinaliza HUD pra apagar o "glow" do ícone.
	if _esquivando_ability_buff_remaining > 0.0:
		var was_active: bool = true
		_esquivando_ability_buff_remaining = maxf(_esquivando_ability_buff_remaining - delta, 0.0)
		# Rastro: spawna blob branco a cada N pixels percorridos enquanto ativa.
		var moved: float = global_position.distance_to(_esquivando_trail_last_pos)
		if moved >= ESQUIVANDO_TRAIL_SPACING:
			_spawn_esquivando_trail_segment()
			_esquivando_trail_last_pos = global_position
		if was_active and _esquivando_ability_buff_remaining <= 0.0:
			esquivando_ability_active_changed.emit(false)
	if _esquivando_ability_cd > 0.0:
		_esquivando_ability_cd = maxf(_esquivando_ability_cd - delta, 0.0)
		esquivando_cooldown_changed.emit(_esquivando_ability_cd, _esquivando_ability_cd_total())


# Blob branco que fica no chão por ESQUIVANDO_TRAIL_FADE segundos. Visual only,
# sem colisão. Spawnado periodicamente no _update_esquivando enquanto a ability
# do espaço (+50% move) está ativa.
func _spawn_esquivando_trail_segment() -> void:
	var blob := Polygon2D.new()
	var radius: float = 4.5
	var pts := PackedVector2Array()
	var segments: int = 14
	for i in segments:
		var ang: float = TAU * float(i) / float(segments)
		# Achatado verticalmente pra dar sensação isométrica de "pegada no chão".
		pts.append(Vector2(cos(ang) * radius, sin(ang) * radius * 0.5))
	blob.polygon = pts
	blob.color = Color(1.0, 1.0, 1.0, 0.55)
	blob.z_index = -1  # atrás de entidades, em cima do chão
	blob.z_as_relative = false
	var world := _get_world()
	if world == null:
		return
	world.add_child(blob)
	blob.global_position = global_position + Vector2(0, ESQUIVANDO_TRAIL_OFFSET_Y)
	var tw := blob.create_tween()
	tw.tween_property(blob, "modulate:a", 0.0, ESQUIVANDO_TRAIL_FADE)
	tw.tween_callback(blob.queue_free)


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
	var best_dist_sq: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		if "hp" in e and float(e.hp) <= 0.0:
			continue
		# Boss shieldado não toma dano — pular pra não desperdiçar cast/aim.
		if (e as Node).is_in_group("boss_shielded"):
			continue
		var d: float = (e as Node2D).global_position.distance_squared_to(global_position)
		if d < best_dist_sq:
			nearest = e
			best_dist_sq = d
	return nearest


func _dash_auto_attack_volley() -> void:
	# Auto-attack durante dash: usa todos os efeitos de upgrade (multi/chain/dmg)
	# mas NÃO incrementa _perf_shot_counter (excalidraw: "não conta como +1
	# ataque para o terceiro do perfurante").
	if arrow_scene == null:
		return
	# Time Freeze do Gelo lv4 ativo: bloqueia auto-attack do dash também.
	if _time_freeze_active_remaining > 0.0:
		return
	# Cada auto-attack do dash = uma volley separada pro Esquivando. (Mesmo
	# acontecendo durante dash, é mecanicamente um disparo "novo" — não compartilha
	# id com a volley manual anterior.)
	_esquivando_volley_id += 1
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
		var delay: float = float(shot.get("delay_sec", 0.0))
		if delay > 0.0:
			get_tree().create_timer(delay).timeout.connect(
				_spawn_arrow.bind(shot["dir"], shot["dmg_mult"], is_pierce, false, false, is_ricochet, is_graviton)
			)
		else:
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
	# Telemetria: registra upgrade adquirido. Wave atual entra como propriedade.
	if has_node("/root/Telemetry"):
		var wm := get_tree().get_first_node_in_group("wave_manager")
		var wave_num: int = int(wm.wave_number) if wm != null and "wave_number" in wm else 0
		get_node("/root/Telemetry").track("upgrade_acquired", {
			"id": upgrade_id,
			"wave": wave_num,
		})
	match upgrade_id:
		"hp":
			hp_upgrades += 1
			# Curva por nível: L1=+18, L2=+20, L3=+22, L4+=+25.
			var hp_gain: float = 25.0
			match hp_upgrades:
				1: hp_gain = 18.0
				2: hp_gain = 20.0
				3: hp_gain = 22.0
				_: hp_gain = 25.0
			max_hp += hp_gain
			hp = min(hp + hp_gain, max_hp)
			hp_changed.emit(hp, max_hp)
			if hp_bar != null:
				hp_bar.set_ratio(hp / max_hp)
		"armor":
			armor_level += 1
			damage_reduction_pct = _compute_damage_reduction(armor_level)
			slow_resistance_pct = damage_reduction_pct * 0.5
		"damage":
			damage_upgrades += 1
			# +24% no dano da flecha por stack (equalizado com atk_speed pra DPS
			# idêntico por nível — ambos somam 0.24 ao multiplier).
			arrow_damage_multiplier += 0.24
		"perfuracao":
			perfuracao_level = mini(perfuracao_level + 1, 4)
			perfuracao_counter_changed.emit(_perf_shot_counter, perfuracao_level)
		"attack_speed":
			attack_speed_level += 1
			# +24% por stack (aditivo). Aplica imediatamente — próximo ataque
			# já usa o novo wait_time/speed_scale via _start_attack.
			# Equalizado com damage pra DPS idêntico por nível.
			attack_speed_multiplier += 0.24
		"multi_arrow":
			multi_arrow_level = mini(multi_arrow_level + 1, 4)
		"double_arrows":
			double_arrows_level = mini(double_arrows_level + 1, 4)
		"chain_lightning":
			var prev_cl: int = chain_lightning_level
			chain_lightning_level = mini(chain_lightning_level + 1, 4)
			# Lv3: destrava skill ativa (mesma lógica do Fogo). Só emite na 1ª transição.
			if prev_cl < 3 and chain_lightning_level >= 3:
				chain_lightning_skill_unlocked.emit()
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
		"ice_arrow":
			# Elemental Gelo ("Fica Frio"). Lv1: congela 2s + 4 dps + cubo derretendo.
			# Lv2: dobra dps (8) + área nevada com slow 37% por 5.5s.
			# Lv3: spawn Frostwisp (aliada de bombardeio a cada 15s).
			# Lv4: destrava skill Q (Time Freeze — pausa mundo 3s, cd 28s).
			var was_below_3_ice: bool = ice_arrow_level < 3
			var was_below_4_ice: bool = ice_arrow_level < 4
			ice_arrow_level = mini(ice_arrow_level + 1, 4)
			if was_below_3_ice and ice_arrow_level >= 3:
				_spawn_frostwisp()
			if was_below_4_ice and ice_arrow_level >= 4:
				_time_freeze_cd_remaining = 0.0
				time_freeze_skill_unlocked.emit()
				time_freeze_skill_cooldown_changed.emit(0.0, TIME_FREEZE_COOLDOWN)
		"leno":
			leno_level = mini(leno_level + 1, 4)
			_refresh_lenos()
		"capivara_joe":
			capivara_joe_level = mini(capivara_joe_level + 1, 4)
			_refresh_capivaras()
		"ting":
			ting_level = mini(ting_level + 1, 4)
			_refresh_tings()
		"woodwarden":
			# Cada compra: +1 level (max 4). Sobe stats em todos os existentes
			# e spawna 1 novo woodwarden no player se ainda não tem todos.
			woodwarden_level = mini(woodwarden_level + 1, 4)
			_refresh_woodwardens()
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
			# Mutex defensivo com esquivando — shop/welcome pool já filtram.
			if esquivando_level > 0:
				return
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
		"boomerang":
			# Lv1-4. Skill passiva auto-cast — mecânica em boomerang.gd.
			# L1: 1 boomerang cd 5s. L2: range +50. L3: 2 boomerangs (alvo + 180°).
			# L4: 4 boomerangs (alvo + 3 direções) cd 3s.
			boomerang_level = mini(boomerang_level + 1, 4)
			_boomerang_cd_remaining = 0.0  # próximo cast imediato
		"critical_chance":
			# Lv1-4. Chance % de crit em flechas + skills. Aplica multiplicador
			# de dano + visual amarelo (damage number + flash do enemy).
			critical_chance_level = mini(critical_chance_level + 1, 4)
		"esquivando":
			# Lv1-4. Mutuamente exclusivo com dash (mesma categoria movimentação)
			# — shop e welcome pool já filtram, defensivo aqui contra dev panel.
			if dash_level > 0:
				return
			if esquivando_level >= ESQUIVANDO_LEVEL_MAX:
				return
			esquivando_level = mini(esquivando_level + 1, ESQUIVANDO_LEVEL_MAX)
			if esquivando_level == 1:
				has_esquivando = true
				esquivando_unlocked.emit()
			# Lv3 destrava a skill do espaço — reseta cd, sinaliza pra HUD mostrar
			# a barra (que ficou escondida nos lv1-2 sem ability).
			if esquivando_level == ESQUIVANDO_ABILITY_MIN_LEVEL:
				_esquivando_ability_cd = 0.0
				esquivando_unlocked.emit()
				esquivando_cooldown_changed.emit(0.0, _esquivando_ability_cd_total())
			# Lv4 muda o cd total — re-emit pra HUD recalcular o ratio.
			if esquivando_level >= ESQUIVANDO_ABILITY_MIN_LEVEL:
				esquivando_cooldown_changed.emit(_esquivando_ability_cd, _esquivando_ability_cd_total())
			# Refresca label de stacks (cap muda 3→4 no lv4) — sem isso o "0/3"
			# antigo persiste até o próximo stack/expire.
			esquivando_stacks_changed.emit(_esquivando_stacks, _esquivando_max_stacks())
	# Notifica HUD/listeners. Emitido SEMPRE no fim, independente do match.
	upgrade_applied.emit(upgrade_id, get_upgrade_count(upgrade_id))


func get_upgrade_count(upgrade_id: String) -> int:
	match upgrade_id:
		"hp": return hp_upgrades
		"armor": return armor_level
		"damage": return damage_upgrades
		"perfuracao": return perfuracao_level
		"attack_speed": return attack_speed_level
		"multi_arrow": return multi_arrow_level
		"double_arrows": return double_arrows_level
		"chain_lightning": return chain_lightning_level
		"move_speed": return move_speed_level
		"life_steal": return life_steal_level
		"fire_arrow": return fire_arrow_level
		"curse_arrow": return curse_arrow_level
		"ice_arrow": return ice_arrow_level
		"woodwarden": return woodwarden_level
		"leno": return leno_level
		"capivara_joe": return capivara_joe_level
		"ting": return ting_level
		"gold_magnet": return gold_magnet_level
		"dash": return dash_level
		"esquivando": return esquivando_level
		"ricochet_arrow": return ricochet_arrow_level
		"graviton": return graviton_level
		"boomerang": return boomerang_level
		"critical_chance": return critical_chance_level
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


func _refresh_capivaras() -> void:
	# L1-L3: 1 capivara. L4: 2. Drop interval: L1=19.5s, L2+=10.75s
	# (+2s em todos os níveis pra balancear o uptime de buff).
	var target_count: int = 2 if capivara_joe_level >= 4 else (1 if capivara_joe_level >= 1 else 0)
	var interval: float = 10.75 if capivara_joe_level >= 2 else 19.5
	# Limpa entries inválidos.
	var alive: Array[Node2D] = []
	for c in _capivaras:
		if is_instance_valid(c):
			alive.append(c)
	_capivaras = alive
	while _capivaras.size() < target_count:
		var capi: Node2D = CAPIVARA_JOE_SCENE.instantiate()
		_capivaras.append(capi)
		_get_world().add_child(capi)
		# Spawn longe do player pra começar vagueando — usa um waypoint
		# random dentro dos bounds da capivara.
		if "wander_bounds" in capi:
			var b: Rect2 = capi.wander_bounds
			capi.global_position = Vector2(
				randf_range(b.position.x, b.position.x + b.size.x),
				randf_range(b.position.y, b.position.y + b.size.y)
			)
	while _capivaras.size() > target_count:
		var extra: Node2D = _capivaras.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	# Atualiza interval em todas.
	for c in _capivaras:
		if "drop_interval" in c:
			c.drop_interval = interval


func _cleanup_capivaras() -> void:
	for c in _capivaras:
		if is_instance_valid(c):
			c.queue_free()
	_capivaras.clear()


func _refresh_tings() -> void:
	# L1-L3 = 1 ting, L4 = 2. Stats da torreta variam por nível:
	#   L1: deploy 15s, turret lifetime 8s, atk cd 2.0s, aoe 0%
	#   L2: deploy 15s, turret lifetime 9s, atk cd 2.0s, aoe 10%
	#   L3+: deploy 13s, turret lifetime 9s, atk cd 1.7s, aoe 10%
	var target_count: int = 2 if ting_level >= 4 else (1 if ting_level >= 1 else 0)
	var deploy_interval: float = 13.0 if ting_level >= 3 else 15.0
	var turret_lifetime: float = 8.0 if ting_level <= 1 else 9.0
	var turret_atk_cd: float = 1.7 if ting_level >= 3 else 2.0
	var turret_aoe_pct: float = 0.10 if ting_level >= 2 else 0.0
	# Limpa entries inválidos.
	var alive: Array[Node2D] = []
	for t in _tings:
		if is_instance_valid(t):
			alive.append(t)
	_tings = alive
	while _tings.size() < target_count:
		var ting: Node2D = TING_SCENE.instantiate()
		_tings.append(ting)
		_get_world().add_child(ting)
		# Spawn random dentro do wander_bounds.
		if "wander_bounds" in ting:
			var b: Rect2 = ting.wander_bounds
			ting.global_position = Vector2(
				randf_range(b.position.x, b.position.x + b.size.x),
				randf_range(b.position.y, b.position.y + b.size.y)
			)
	while _tings.size() > target_count:
		var extra: Node2D = _tings.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	# Aplica stats em todas as instâncias (inclui as existentes — se subir de
	# nível com o ting já no mapa, próximo deploy usa os novos números).
	for t in _tings:
		if "deploy_interval" in t:
			t.deploy_interval = deploy_interval
		if "turret_lifetime" in t:
			t.turret_lifetime = turret_lifetime
		if "turret_attack_cooldown" in t:
			t.turret_attack_cooldown = turret_atk_cd
		if "turret_aoe_pct" in t:
			t.turret_aoe_pct = turret_aoe_pct


func _cleanup_tings() -> void:
	for t in _tings:
		if is_instance_valid(t):
			t.queue_free()
	_tings.clear()


func get_mages_killed_this_wave() -> int:
	return _mages_killed_this_wave


func notify_mage_killed() -> void:
	_mages_killed_this_wave += 1


func reset_mages_killed_this_wave() -> void:
	# Chamado pelo wave_manager no início de cada wave — contador zera por turno
	# pra escalada da torreta do Ting começar do zero a cada raid.
	_mages_killed_this_wave = 0


func apply_capivara_speed_buff(amount: float, duration: float) -> void:
	# Soma um buff temporário ao move_speed. Refresh: pega o maior amount ativo
	# e estende a duração.
	if amount > _capivara_speed_buff_amount or _capivara_speed_buff_remaining <= 0.0:
		_capivara_speed_buff_amount = amount
	_capivara_speed_buff_remaining = maxf(_capivara_speed_buff_remaining, duration)


func apply_capivara_atk_speed_buff(amount: float, duration: float) -> void:
	if amount > _capivara_atk_speed_buff_amount or _capivara_atk_speed_buff_remaining <= 0.0:
		_capivara_atk_speed_buff_amount = amount
	_capivara_atk_speed_buff_remaining = maxf(_capivara_atk_speed_buff_remaining, duration)


func _tick_capivara_buffs(delta: float) -> void:
	if _capivara_speed_buff_remaining > 0.0:
		_capivara_speed_buff_remaining -= delta
		if _capivara_speed_buff_remaining <= 0.0:
			_capivara_speed_buff_amount = 0.0
	if _capivara_atk_speed_buff_remaining > 0.0:
		_capivara_atk_speed_buff_remaining -= delta
		if _capivara_atk_speed_buff_remaining <= 0.0:
			_capivara_atk_speed_buff_amount = 0.0
			# Re-aplica timer/sprite scale sem o buff.
			attack_timer.wait_time = attack_cooldown / attack_speed_multiplier
			sprite.speed_scale = attack_speed_multiplier


func _refresh_woodwardens() -> void:
	# Spawna woodwardens faltantes pra match o level. Atualiza stats em todos
	# os vivos. Spawn em volta do player (offset random pra não empilhar).
	# L1-L2 = 1 warden, L3+ = 2 wardens (foco tank/utilidade).
	var target_count: int = _woodwarden_target_count()
	# Limpa entries totalmente sem instance + sem timer (raro — só edge case
	# em que ainda não foi spawnado).
	while _woodwardens.size() < target_count:
		var ww: Node2D = WOODWARDEN_SCENE.instantiate()
		var spawn_pos: Vector2 = global_position + Vector2(randf_range(-32.0, 32.0), randf_range(-16.0, 16.0))
		_get_world().add_child(ww)
		ww.global_position = spawn_pos
		# Stats DEPOIS do add_child — HpBar (filha do ww) precisa do _ready
		# pra inicializar @onready var fg/trail antes de set_ratio.
		_apply_woodwarden_stats(ww)
		_woodwardens.append({"instance": ww, "last_pos": spawn_pos, "dead_for": 0.0})
	# Atualiza stats em todos os vivos.
	for entry in _woodwardens:
		var inst: Node = entry.get("instance")
		if inst != null and is_instance_valid(inst):
			_apply_woodwarden_stats(inst)


func _apply_woodwarden_stats(ww: Node) -> void:
	# Foco em tank/utilidade:
	# - L1-L3: base_hp +20% (=384), damage=0, cooldown 3.5s (ataque só stuna em área).
	# - L4: +150 hp (=534), damage=100, cooldown 3.0s (passa a dar dano).
	# Heal pro player no ataque é decidido em woodwarden._apply_hit via get_upgrade_count.
	if not ("max_hp" in ww and "damage" in ww):
		return
	var lvl: int = woodwarden_level
	if lvl <= 0:
		return
	var base_hp: float = 384.0  # 320 × 1.20
	var extra_hp: float = 150.0 if lvl >= 4 else 0.0
	ww.max_hp = base_hp + extra_hp
	if lvl >= 4:
		ww.damage = 100.0
		if "attack_cooldown" in ww:
			ww.attack_cooldown = 4.5
	else:
		ww.damage = 0.0
		if "attack_cooldown" in ww:
			ww.attack_cooldown = 5.0
	if "hp" in ww:
		ww.hp = ww.max_hp
	if ww.has_node("HpBar"):
		var bar: Node = ww.get_node("HpBar")
		if bar.has_method("set_ratio"):
			bar.set_ratio(1.0)


func _woodwarden_target_count() -> int:
	if woodwarden_level <= 0:
		return 0
	if woodwarden_level <= 2:
		return 1
	return 2


func _check_woodwarden_respawns(delta: float) -> void:
	# Respawn nativo: 15.5s após woodwarden morrer, spawna novo na última posição.
	# Sem sistema de structure do wave_manager (mantém só pra torres).
	for entry in _woodwardens:
		var inst: Variant = entry.get("instance")
		var alive: bool = inst != null and is_instance_valid(inst) and (inst as Node).is_inside_tree()
		if alive:
			if inst is Node2D:
				entry["last_pos"] = (inst as Node2D).global_position
			entry["dead_for"] = 0.0
			continue
		var dead_for: float = float(entry.get("dead_for", 0.0)) + delta
		entry["dead_for"] = dead_for
		if dead_for < WOODWARDEN_RESPAWN_DELAY:
			continue
		var spawn_pos: Vector2 = entry.get("last_pos", global_position)
		_spawn_woodwarden_portal_fx(spawn_pos)
		var ww: Node2D = WOODWARDEN_SCENE.instantiate()
		_get_world().add_child(ww)
		ww.global_position = spawn_pos
		# Stats DEPOIS do add_child — HpBar precisa do _ready pra resolver @onready.
		_apply_woodwarden_stats(ww)
		entry["instance"] = ww
		entry["dead_for"] = 0.0


func _spawn_woodwarden_portal_fx(pos: Vector2) -> void:
	if WOODWARDEN_SPAWN_FX_SCENE == null:
		return
	var fx: Node2D = WOODWARDEN_SPAWN_FX_SCENE.instantiate()
	_get_world().add_child(fx)
	fx.global_position = pos


func reset_woodwardens_hp() -> void:
	# Chamado pelo wave_manager no início de cada wave: woodwardens vivos voltam
	# full HP (mesma lógica do owned_structures pra torres). Mortos seguem o
	# timer de respawn nativo.
	for entry in _woodwardens:
		var inst: Variant = entry.get("instance")
		if inst == null or not is_instance_valid(inst):
			continue
		if "max_hp" in inst and "hp" in inst:
			inst.hp = inst.max_hp
			if (inst as Node).has_node("HpBar"):
				var bar: Node = (inst as Node).get_node("HpBar")
				if bar.has_method("set_ratio"):
					bar.set_ratio(1.0)


func _cleanup_woodwardens() -> void:
	for entry in _woodwardens:
		var inst: Variant = entry.get("instance")
		if inst != null and is_instance_valid(inst):
			(inst as Node).queue_free()
	_woodwardens.clear()


func _cleanup_lenos() -> void:
	for l in _lenos:
		if is_instance_valid(l):
			l.queue_free()
	_lenos.clear()


# Reset completo de um pet (vendido na shop). Zera o level + remove todas as
# instâncias spawnadas. Refund de gold é responsabilidade do shop.
func reset_pet(id: String) -> void:
	match id:
		"woodwarden":
			woodwarden_level = 0
			_cleanup_woodwardens()
		"leno":
			leno_level = 0
			_cleanup_lenos()
		"capivara_joe":
			capivara_joe_level = 0
			_cleanup_capivaras()
		"ting":
			ting_level = 0
			_cleanup_tings()


func _compute_damage_reduction(level: int) -> float:
	# Armor: L1=12%, L2=18%, L3=22%, L4=25%, L5+=+3% por stack após L4. Cap em
	# 75% pra evitar invencibilidade absoluta. Curva front-loaded pra dar valor
	# real no early game (insetos/melee de wave 1-3 perdem peso desde L1).
	match level:
		0: return 0.0
		1: return 0.12
		2: return 0.18
		3: return 0.22
		4: return 0.25
	return minf(0.25 + 0.03 * float(level - 4), 0.75)


func reset_perf_counter() -> void:
	# Chamado pelo wave_manager no início de cada wave pra evitar que o counter
	# persistente faça a 1ª flecha do round virar perfurante.
	_perf_shot_counter = 0


func reset_all_cooldowns() -> void:
	# Zera todos os cooldowns de skills ao iniciar uma nova wave. Player começa
	# cada round com todo o kit pronto. Inclui Time Freeze: se estava ativo
	# durante o shop, força encerrar (restaura mundo).
	_dash_cd_remaining = 0.0
	dash_cooldown_changed.emit(0.0, dash_cooldown)
	_fire_skill_cd_remaining = 0.0
	if fire_arrow_level >= 3:
		fire_skill_cooldown_changed.emit(0.0, FIRE_SKILL_COOLDOWN)
	_chain_lightning_skill_cd_remaining = 0.0
	if chain_lightning_level >= 3:
		chain_lightning_skill_cooldown_changed.emit(0.0, CHAIN_LIGHTNING_SKILL_COOLDOWN)
	_curse_skill_cd_remaining = 0.0
	if curse_arrow_level >= 4:
		curse_skill_cooldown_changed.emit(0.0, CURSE_SKILL_TOTAL_CYCLE)
	# Time Freeze: força encerrar se ativo + zera CD.
	if _time_freeze_active_remaining > 0.0:
		_time_freeze_active_remaining = 0.0
		_remove_time_freeze_world_pause()
		_hide_freeze_overlay()
	_time_freeze_cd_remaining = 0.0
	if ice_arrow_level >= 4:
		time_freeze_skill_cooldown_changed.emit(0.0, TIME_FREEZE_COOLDOWN)
	_boomerang_cd_remaining = 0.0
	# Frostwisp (L3 do Gelo): força delay inicial de 7s antes do primeiro
	# cast da wave — evita que ela já comece bombardeando enquanto o player
	# nem se posicionou ainda.
	if _frostwisp != null and is_instance_valid(_frostwisp):
		if _frostwisp.has_method("set_initial_cooldown"):
			_frostwisp.set_initial_cooldown(7.0)


func take_damage(amount: float, source_id: String = "") -> void:
	if is_dead:
		return
	# I-frames do dash: ignora dano (inclui DoT/curse/burn que chamem take_damage).
	if _iframes_remaining > 0.0:
		return
	# Esquivando: % de chance de esquivar o ataque inteiro (2% lv1-2, 5% lv3-4).
	# Nota: DoT/poison/burn também passam por aqui — esquivar um tick de DoT é
	# ok como design (cada tick é um "ataque" independente).
	if esquivando_level > 0 and randf() < _esquivando_dodge_chance():
		_spawn_miss_number()
		return
	# Armor: reduz dano antes de aplicar — número/notify usam o valor reduzido,
	# pra a UI mostrar o que de fato saiu do HP do player.
	var reduced: float = amount * (1.0 - damage_reduction_pct)
	hp = maxf(hp - reduced, 0.0)
	notify_damage_taken(reduced, source_id)
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(reduced)
	if damage_audio != null:
		damage_audio.play()
	if hp == 0.0:
		stats_killed_by = source_id if not source_id.is_empty() else "unknown"
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
	_cleanup_woodwardens()
	_cleanup_capivaras()
	_cleanup_tings()
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
	p.bus = &"SFX"
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
	# O player "real" no mundo é escondido — o player_preview na HUD que aparece.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("play_death_sequence"):
		return
	# Esconde toda a estrutura visual do player no mundo (body + layers + bow back
	# + dash effect). Senão eles continuariam visíveis na posição do player real.
	if sprite != null:
		sprite.visible = false
	var skin := get_node_or_null("Skin")
	if skin != null:
		skin.visible = false
	var bow_back := get_node_or_null("BowBackSprite")
	if bow_back != null:
		bow_back.visible = false
	var dash_fx := get_node_or_null("DashEffectSprite")
	if dash_fx != null:
		dash_fx.visible = false
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


func _spawn_miss_number() -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.text_override = tr("HUD_DODGE_MISS")
	num.position = global_position + Vector2(0, -26)
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


func notify_boss_killed(boss_id: String) -> void:
	# Bosses mortos nesta run — usado pelo SkinLoadout.record_run no death pra
	# detectar unlocks (e gravar persistente). Permite repetições (matar 2x o
	# mesmo boss numa run conta 2 no total, mas no set único só uma vez).
	if boss_id.is_empty():
		return
	stats_bosses_killed.append(boss_id)
	# Telemetria: evento individual pra time-to-kill analysis (com time_ms auto).
	if has_node("/root/Telemetry"):
		var wm := get_tree().get_first_node_in_group("wave_manager")
		var wave_num: int = int(wm.wave_number) if wm != null and "wave_number" in wm else 0
		get_node("/root/Telemetry").track("boss_killed", {
			"boss_id": boss_id,
			"wave": wave_num,
		})


func notify_ally_made() -> void:
	stats_allies_made += 1


func notify_monkey_cursed() -> void:
	stats_monkeys_cursed += 1


func notify_damage_dealt(amount: float) -> void:
	if amount > 0.0:
		stats_damage_dealt += amount


func notify_damage_dealt_by_source(amount: float, source_id: String) -> void:
	if amount <= 0.0 or source_id.is_empty():
		return
	var cur: float = float(stats_damage_dealt_by_source.get(source_id, 0.0))
	stats_damage_dealt_by_source[source_id] = cur + amount
	var wave_cur: float = float(wave_damage_by_source.get(source_id, 0.0))
	wave_damage_by_source[source_id] = wave_cur + amount


func reset_wave_damage_breakdown() -> void:
	# Chamado pelo wave_manager no início de cada wave — limpa o breakdown da
	# wave anterior pra o painel TAB mostrar só a wave atual.
	wave_damage_by_source.clear()


func notify_kill_by_source(source_id: String) -> void:
	if source_id.is_empty():
		return
	var cur: int = int(stats_kills_by_source.get(source_id, 0))
	stats_kills_by_source[source_id] = cur + 1


func notify_damage_taken(amount: float, source_id: String = "") -> void:
	if amount > 0.0:
		stats_damage_taken += amount
		var key: String = source_id if not source_id.is_empty() else "unknown"
		var cur: float = float(stats_damage_taken_by_source.get(key, 0.0))
		stats_damage_taken_by_source[key] = cur + amount


func get_run_time_msec() -> int:
	return Time.get_ticks_msec() - _run_start_msec
