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
# Stone Earthquake (lv4 da Pedra): treme a tela, stuna todos os mobs vivos e
# causa grande dano em área em volta do player.
signal stone_skill_unlocked
signal stone_skill_cooldown_changed(remaining: float, total: float)
# Perfuração: HUD mostra contador 1/2/3 (próximo tiro perfurante a cada 3 ataques
# nos lv1-3; sempre ativo no lv4). Emitido em cada release_arrow e no apply_upgrade.
signal perfuracao_counter_changed(counter: int, level: int)
signal ricochet_counter_changed(counter: int, level: int)
# Disparado a cada compra/aquisição de upgrade. HUD escuta pra atualizar a
# coluna de upgrades adquiridos.
signal upgrade_applied(id: String, level: int)

@export var speed: float = 61.0
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
@export var poison_number_color: Color = Color(0.75, 0.35, 1.0, 1.0)

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
# Computado de armor_level. Slow reduction = damage reduction (igualadas).
var armor_level: int = 0
var damage_reduction_pct: float = 0.0
var slow_resistance_pct: float = 0.0
# Stun: bloqueia movimento + ataques + força sprite "idle". Usado pelas
# vinhas da Duskrose. O visual de stun (stun_visual.gd) lê _stun_remaining
# via reflection — qualquer node com esse campo pode ser stunado igual.
var _stun_remaining: float = 0.0
const STUN_VISUAL_SCRIPT: GDScript = preload("res://scripts/effects/stun_visual.gd")
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
var stone_arrow_level: int = 0  # elemental Pedra / "Disparo de Pedra" (lv1-4)
# Referência à Frostwisp spawnada no L3 (1 só por run).
const FROSTWISP_SCENE: PackedScene = preload("res://scenes/allies/frostwisp.tscn")
var _frostwisp: Node2D = null
var claudio_druida_level: int = 0  # aliado tank — cada compra "uppa" stats e custo
# Tracking dos claudio_druidas com respawn nativo (não usa o sistema de structure
# do wave_manager). Cada entry: {"instance", "last_pos", "dead_for"}.
const CLAUDIO_DRUIDA_SCENE: PackedScene = preload("res://scenes/enemies/claudio_druida.tscn")
const CLAUDIO_DRUIDA_SPAWN_FX_SCENE: PackedScene = preload("res://scenes/enemies/claudio_druida_spawn_effect.tscn")
const CLAUDIO_DRUIDA_RESPAWN_DELAY: float = 15.5
var _claudio_druidas: Array[Dictionary] = []
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
const MINI_MAGO_SCENE: PackedScene = preload("res://scenes/allies/mini_mago.tscn")
# Mini Mago: framework preparado, upgrades a desenhar. Placeholder = 1 instância
# por compra, sem level-specific behavior ainda.
var mini_mago_level: int = 0
var _mini_magos: Array[Node2D] = []
# Arbusto Carrara (aliado wanderer). Corre pelo mapa, para em IDLE, e quando
# o player encosta vira hide spot por 3s (buff: +12% atk speed, +5 dmg on-hit,
# tint verde nas flechas, perde aggro de macacos se não tiver macaco dentro).
const ARBUSTO_SCENE: PackedScene = preload("res://scenes/allies/arbusto.tscn")
const MINI_ARBUSTO_SCENE: PackedScene = preload("res://scenes/allies/mini_arbusto.tscn")
# Respawn do mini_arbusto: 3s após morrer, na posição do big arbusto pareado.
const MINI_ARBUSTO_RESPAWN_DELAY: float = 3.0
var arbusto_level: int = 0
var _arbustos: Array[Node2D] = []
# Mini arbustos pareados 1-pra-1 com os _arbustos (mesmo índice). Quando morrem
# o slot fica null e o timer do _mini_arbusto_respawn_timers conta até spawnar
# um novo na posição do big arbusto correspondente.
var _mini_arbustos: Array[Node2D] = []
var _mini_arbusto_respawn_timers: Array[float] = []
# Buffs ativos enquanto o player está escondido no arbusto. Aplica em todas
# as flechas (multiplicador de atk speed + bonus flat de dano + tint verde).
var arbusto_hide_active: bool = false
var arbusto_hide_atk_speed_bonus: float = 0.0
var arbusto_hide_arrow_bonus_damage: float = 0.0
# L4: cada hit que o player acerta enquanto hidden cura essa quantidade.
# Setado pelo arbusto.gd no enter_hide, zerado no exit_hide.
var arbusto_hide_heal_per_hit: float = 0.0
# Contador de magos mortos na wave atual — torreta do Ting ganha +1% atk speed
# por mago morto. Reset no _ready de cada wave pelo wave_manager.
var _mages_killed_this_wave: int = 0
# Fire skill (botão direito a partir do lv3 do Fogo).
const FIRE_SKILL_COOLDOWN: float = 7.0
const FIRE_SKILL_DPS: float = 12.0
const FIRE_SKILL_DURATION: float = 6.0
const FIRE_SKILL_PROJECTILE_SCENE: PackedScene = preload("res://scenes/skills/fire_skill_projectile.tscn")
var _fire_skill_cd_remaining: float = 0.0

# Último Desejo (joker card do shop): uso único por run. Filtra a carta do
# pool depois que o player usar uma vez. Setado pelo wave_shop quando o
# player escolhe um upgrade no modal pós-compra. Resetado por new run via
# reset dos demais campos do player na criação do node.
var joker_used: bool = false

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
# Stone Earthquake (Q a partir do lv4 da Pedra): treme a tela, stuna TODOS os
# mobs vivos no momento e causa grande dano em área em volta do player (onda
# sísmica saindo do player). Alto cooldown.
const STONE_SKILL_COOLDOWN: float = 28.0
const STONE_QUAKE_RADIUS: float = 150.0
const STONE_QUAKE_DAMAGE: float = 80.0
const STONE_QUAKE_STUN: float = 2.5
const STONE_QUAKE_KNOCKBACK: float = 120.0
const STONE_QUAKE_SHAKE_DURATION: float = 0.6
const STONE_QUAKE_SHAKE_STRENGTH: float = 7.0
const STONE_AOE_QUAKE_SCRIPT: GDScript = preload("res://scripts/skills/stone_aoe.gd")
const STONE_QUAKE_STUN_VISUAL: GDScript = preload("res://scripts/effects/stun_visual.gd")
const STONE_QUAKE_SOUND: AudioStream = preload("res://assets/effects/Rock Arrow/terremoto sismico.mp3")
const STONE_QUAKE_VOLUME_DB: float = -6.0
var _stone_skill_cd_remaining: float = 0.0
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
const BOOMERANG_CD_BY_LEVEL: Array[float] = [5.0, 4.0, 3.4, 3.0]
# Garras de Tigre: autocast que dá 2 arranhadas em N inimigos aleatórios
# dentro de TIGER_CLAWS_RADIUS. Cada arranhada aplica damage_per_scratch.
const TIGER_CLAWS_VFX_SCENE: PackedScene = preload("res://scenes/skills/tiger_claws_vfx.tscn")
const TIGER_CLAWS_CD_BY_LEVEL: Array[float] = [0.0, 7.0, 7.0, 4.8, 4.0]
const TIGER_CLAWS_TARGETS_BY_LEVEL: Array[int] = [0, 1, 2, 3, 4]
const TIGER_CLAWS_DMG_PER_SCRATCH_BY_LEVEL: Array[float] = [0.0, 25.0, 27.0, 40.0, 48.0]
const TIGER_CLAWS_RADIUS: float = 180.0
var tiger_claws_level: int = 0
var _tiger_claws_cd_remaining: float = 0.0
const BOOMERANG_DAMAGE_BY_LEVEL: Array[float] = [15.0, 20.0, 32.0, 42.0]
const BOOMERANG_RANGE_BY_LEVEL: Array[float] = [140.0, 140.0, 160.0, 160.0]
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
# Screenshot do viewport no momento da morte — usado como background no replay
# pra dar contexto visual do cenário onde a morte aconteceu.
var death_screenshot: ImageTexture = null
# Replay da morte: ring buffer dos últimos 3.5s capturado a 20fps (70 snapshots).
# Cada snapshot é um Dictionary com:
#   {player_pos: Vector2, entities: [{id, sprite_frames, pos, anim, frame, flip_h, modulate, z_index}, ...]}
# Captura no _physics_process via _record_replay_snapshot. Congela quando o
# player morre — HUD lê via stats_replay_snapshots no botão de replay.
const REPLAY_DURATION_SECONDS: float = 3.5
const REPLAY_RECORD_INTERVAL: float = 0.05  # 20fps
const REPLAY_MAX_SNAPSHOTS: int = 70  # ~3.5s × 20fps
const REPLAY_RECORD_RADIUS: float = 260.0  # entidades dentro desse raio do player entram no snapshot
var stats_replay_snapshots: Array = []
var _replay_record_accum: float = 0.0
var locked_aim_dir: Vector2 = Vector2.RIGHT
var locked_facing_left: bool = false
var start_position: Vector2 = Vector2.ZERO

# Status effects (slow + poison DoT). Slow só rastreia o multiplicador mais forte ativo.
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0
var _poison_dps: float = 0.0
var _poison_remaining: float = 0.0
var _poison_tick_accum: float = 0.0
# Source ID que o poison vai atribuir no breakdown / morte. Default "insect_poison"
# (uso original), mas a dark_ball sobrescreve via apply_poison(...,"dark_ball").
var _poison_source_id: String = "insect_poison"
# Cor do damage number do poison/burn ativo. Default = verde (poison_number_color);
# dark_ball troca pra roxo via apply_poison(...,...,...,Color(...))
var _poison_number_color_override: Color = Color(0, 0, 0, 0)  # alpha 0 = sem override
# Se true, cada tick toca o damage_audio (mesmo som de "ai!" do hit normal).
# Default false (insect poison é silencioso por design); dark_ball seta true
# pra dar feedback audível enquanto o player tá em cima da poça.
var _poison_plays_sound: bool = false

# Run stats — exibidos na tela de morte. Tudo zerado em _ready.
var _run_start_msec: int = 0
var stats_enemies_killed: int = 0
var stats_allies_made: int = 0
# Macaquinhos (grupo "monkey") convertidos pelo disparo profano — desbloqueia
# a skin Linked aos 200 totais acumulados entre runs.
var stats_monkeys_cursed: int = 0
# Segundos de stun causados em inimigos nesta run (unlock da skin Terracota).
var stats_stun_seconds: float = 0.0
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
	# Birthday event: chapéu de festa pro eliyeolio durante a janela do evento.
	_apply_birthday_hat()


func _apply_birthday_hat() -> void:
	var hat: Node = get_node_or_null("PartyHat")
	if hat == null:
		return
	var nick: String = BirthdayEvent.load_current_nickname()
	(hat as CanvasItem).visible = BirthdayEvent.should_show_hat_for(nick)


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)
	# Stun: trava player completamente (sem movimento, sem auto-cast de skills,
	# sem ataque). Mantém anim "idle" + ícone de stun acima da cabeça. Checa
	# ANTES dos _update_*_skill pra autocasts não dispararem durante stun.
	if _stun_remaining > 0.0:
		velocity = Vector2.ZERO
		move_and_slide()
		if sprite != null and sprite.animation != &"idle":
			sprite.play("idle")
		_ensure_stun_visual()
		return
	_update_dash(delta)
	_update_esquivando(delta)
	_update_fire_skill(delta)
	_update_chain_lightning_skill(delta)
	_update_boomerang(delta)
	_update_tiger_claws(delta)
	_tick_replay_recorder(delta)
	_update_curse_skill(delta)
	_update_time_freeze(delta)
	_update_stone_skill(delta)
	_update_player_fire_trail()
	_check_claudio_druida_respawns(delta)
	_check_mini_arbusto_respawns(delta)
	_tick_capivara_buffs(delta)
	_tick_post_bush_grace(delta)
	_update_invuln_visual(delta)
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
	velocity = _apply_corner_slide(velocity, delta)
	move_and_slide()

	_update_facing(input_vec)
	_update_animation(input_vec)


func apply_stun(duration: float) -> void:
	# Trava movimento + ataques + força sprite "idle" por `duration` segundos.
	# Usado pelas vinhas da Duskrose. Mesmo visual usado pelo Claudio nos
	# macacos — stun_visual.gd anexa ícone acima da cabeça enquanto ativo.
	if is_dead:
		return
	_stun_remaining = maxf(_stun_remaining, duration)
	_ensure_stun_visual()


func _ensure_stun_visual() -> void:
	# Anexa o ícone de stun se ainda não existe. Stun_visual auto-destroi
	# quando _stun_remaining zera.
	for c in get_children():
		if c is Node and (c as Node).is_in_group("stun_visual"):
			return
	var v: Node = STUN_VISUAL_SCRIPT.new()
	add_child(v)


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


func apply_poison(total_damage: float, duration: float, source_id: String = "insect_poison", number_color_override: Color = Color(0, 0, 0, 0), plays_sound: bool = false, tick_delay: float = 0.0) -> void:
	# Sobrescreve poison ativo se o novo for mais forte (DPS maior) ou refresca duração.
	# source_id controla atribuição no breakdown + death screen ("insect_poison"
	# por default; dark_ball passa "dark_ball" pra ficar agrupado com o impacto).
	# number_color_override (alpha > 0) substitui a cor verde padrão do número.
	# plays_sound = true: cada tick toca o damage_audio do player (dark_ball usa).
	# tick_delay > 0: atrasa o PRIMEIRO tick por X segundos (dá janela pro
	# player dodgar/dashar e escapar antes de começar a tickar). Duration
	# continua decrementando durante o delay (perde tempo de tick efetivo).
	if is_dead or duration <= 0.0:
		return
	var new_dps: float = total_damage / duration
	if new_dps > _poison_dps or _poison_remaining <= 0.0:
		_poison_dps = new_dps
		_poison_source_id = source_id
		_poison_number_color_override = number_color_override
		_poison_plays_sound = plays_sound
		# Reseta o accum pra negativo do delay — primeiro tick só fira após
		# atingir POISON_TICK_INTERVAL, então delay + 0.5s no total.
		if tick_delay > 0.0:
			_poison_tick_accum = -tick_delay
	_poison_remaining = maxf(_poison_remaining, duration)


func _update_status_effects(delta: float) -> void:
	if _stun_remaining > 0.0:
		_stun_remaining = maxf(_stun_remaining - delta, 0.0)
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
	# Por default silencioso (insect): só hp-, hp_bar, damage number. Com
	# _poison_plays_sound = true (dark_ball), toca damage_audio a cada tick.
	if is_dead or amount <= 0.0:
		return
	# Dev godmode: ignora ticks de poison/burn (mesmo gate da take_damage).
	if GameState.dev_godmode:
		return
	# Escondido no Pai do Verde / Verde: invulnerável a TODO dano, incluindo
	# ticks de poison/burn já ativos (mesmo gate da take_damage). Sem isso o
	# veneno do mosquito furava a invencibilidade do arbusto.
	if is_in_group("bush_hidden"):
		return
	hp = maxf(hp - amount, 0.0)
	# Mesmo clamp da take_damage — ticks de poison costumam ser fracionários
	# (dps * tick_interval com float), então sub-1 HP é morte certa.
	if hp < 1.0:
		hp = 0.0
	notify_damage_taken(amount, _poison_source_id)
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_spawn_poison_number(amount)
	if _poison_plays_sound and damage_audio != null:
		damage_audio.play()
	if hp <= 0.0:
		stats_killed_by = _poison_source_id
		_die()


func _spawn_poison_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	# Source overrides cor; senão default verde (poison clássico do inseto).
	num.modulate = _poison_number_color_override if _poison_number_color_override.a > 0.0 else poison_number_color
	num.position = global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(num)


func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	# Stun: bloqueia inputs de ataque + skills + cast. Player só fica olhando.
	if _stun_remaining > 0.0:
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
		elif stone_arrow_level >= 4:
			_cast_earthquake()
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
	# Arbusto: enquanto escondido, +12% atk speed.
	var atk_mult: float = attack_speed_multiplier + _capivara_atk_speed_buff_amount + _esquivando_atk_buff() + arbusto_hide_atk_speed_bonus
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
	# Chain lightning: novo ataque libera o token global (primeira flecha que
	# acertar proca; demais multi-arrow/ricochete não procam mais).
	reset_chain_attack_token()
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
	if ricochet_arrow_level > 0:
		ricochet_counter_changed.emit(_ricochet_shot_counter, ricochet_arrow_level)
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
			# Lambda c/ guard pra cobrir player morto entre o cast e o tick do
			# timer (ex: boss matou no mesmo frame do dash auto-attack).
			var shot_dir: Vector2 = shot["dir"]
			var shot_mult: float = float(shot["dmg_mult"])
			get_tree().create_timer(delay).timeout.connect(
				func() -> void:
					if is_dead or not is_inside_tree():
						return
					_spawn_arrow(shot_dir, shot_mult, is_pierce, false, false, is_ricochet, is_graviton)
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
			# 3 flechas em ±30°. Laterais a 30% — tier de entrada bem fraco.
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(30.0)), "dmg_mult": 0.3})
			shots.append({"dir": primary.rotated(deg_to_rad(-30.0)), "dmg_mult": 0.3})
		2:
			# 3 flechas em ±30°. Laterais sobem pra 65%.
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(30.0)), "dmg_mult": 0.65})
			shots.append({"dir": primary.rotated(deg_to_rad(-30.0)), "dmg_mult": 0.65})
		3:
			# 3 flechas em ±30°ainda — L3 não adiciona flechas, só sobe pra 75%.
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(30.0)), "dmg_mult": 0.75})
			shots.append({"dir": primary.rotated(deg_to_rad(-30.0)), "dmg_mult": 0.75})
		_:
			# L4: 5 flechas em ±15° e ±45° (não mais 10 in-the-round). Extras 85%.
			shots.append({"dir": primary, "dmg_mult": 1.0})
			shots.append({"dir": primary.rotated(deg_to_rad(15.0)), "dmg_mult": 0.85})
			shots.append({"dir": primary.rotated(deg_to_rad(-15.0)), "dmg_mult": 0.85})
			shots.append({"dir": primary.rotated(deg_to_rad(45.0)), "dmg_mult": 0.85})
			shots.append({"dir": primary.rotated(deg_to_rad(-45.0)), "dmg_mult": 0.85})
	return shots


# Flechas Duplas — alternativo do Multi Arrow. Clusters apertados (±0.5 a ±2°)
# com contagem aleatória por roll. Counter de 3 ataques só conta a partir do NV2.
# Spec atual (post-buff 0.5.7):
#   NV1: 50% chance de 2 flechas. Secundária a 70% dano.
#   NV2: 60% chance de 2 flechas. Ambas dano total.
#   NV3: 75% chance de 2 + 45% chance de 3 → maior prevalece. 3-flechas dá +15%
#        dano em TODAS (recompensa burst).
#   NV4: 90% chance de 2 + 60% chance de 3 + 5% chance de 5 → maior prevalece.
#        3-flechas = +15%, 5-flechas = +30% em TODAS.
func _build_double_arrows_volley(primary: Vector2) -> Array:
	var shots: Array = []
	var lvl: int = double_arrows_level
	var count: int = 1
	match lvl:
		1:
			if randf() < 0.50:
				count = 2
		2:
			if randf() < 0.60:
				count = 2
		3:
			if randf() < 0.75:
				count = maxi(count, 2)
			if randf() < 0.45:
				count = maxi(count, 3)
		4:
			if randf() < 0.90:
				count = maxi(count, 2)
			if randf() < 0.60:
				count = maxi(count, 3)
			if randf() < 0.05:
				count = maxi(count, 5)
	# Dano da extra: NV1 a 70% (era 50% pré-buff); NV2+ a 100%.
	var extra_dmg: float = 0.70 if lvl == 1 else 1.0
	# Burst bonus: 3 flechas dão +15% em TODAS; 5 flechas dão +30%. Reforça o
	# feel de "lucky strike" quando o roll grande sai.
	var burst_bonus: float = 1.0
	if count >= 5:
		burst_bonus = 1.30
	elif count >= 3:
		burst_bonus = 1.15
	# Delay entre flechas extras (burst rápido pra cada uma ser distinta no spawn).
	# Com a Pedra, o delay é maior — a 2ª flecha sai mais separada (dois estouros
	# pesados saindo colados ficava estranho).
	var DELAY_PER_EXTRA: float = 0.14 if stone_arrow_level > 0 else 0.04
	# Ângulos APERTADOS: 1° de diferença entre flechas adjacentes — quase a mesma
	# mira, mas separação suficiente pra não sobrepor visualmente no spawn.
	if count == 1:
		shots.append({"dir": primary, "dmg_mult": 1.0 * burst_bonus})
	elif count == 2:
		shots.append({"dir": primary.rotated(deg_to_rad(-0.5)), "dmg_mult": 1.0 * burst_bonus})
		shots.append({"dir": primary.rotated(deg_to_rad(0.5)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA})
	elif count == 3:
		shots.append({"dir": primary, "dmg_mult": 1.0 * burst_bonus})
		shots.append({"dir": primary.rotated(deg_to_rad(1.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA})
		shots.append({"dir": primary.rotated(deg_to_rad(-1.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA * 2})
	elif count == 5:
		shots.append({"dir": primary, "dmg_mult": 1.0 * burst_bonus})
		shots.append({"dir": primary.rotated(deg_to_rad(1.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA})
		shots.append({"dir": primary.rotated(deg_to_rad(-1.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA * 2})
		shots.append({"dir": primary.rotated(deg_to_rad(2.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA * 3})
		shots.append({"dir": primary.rotated(deg_to_rad(-2.0)), "dmg_mult": extra_dmg * burst_bonus, "delay_sec": DELAY_PER_EXTRA * 4})
	return shots


func _spawn_arrow(dir: Vector2, dmg_mult: float, is_pierce: bool, play_sound: bool, is_primary: bool = true, is_ricochet: bool = false, is_graviton: bool = false) -> void:
	var arrow := arrow_scene.instantiate()
	# Configura ANTES de add_child pra _ready() já enxergar os flags.
	arrow.global_position = muzzle.global_position
	if "play_shoot_sound" in arrow:
		arrow.play_shoot_sound = play_sound
	if "damage" in arrow:
		arrow.damage = arrow.damage * arrow_damage_multiplier * dmg_mult
		# Arbusto hide: +5 dmg flat por flecha enquanto escondido. Aplicado APÓS
		# multiplicador pra não ser amplificado pelo arrow_damage_multiplier (é
		# um buff fixo da mecânica do hide, não um stat status).
		if arbusto_hide_active and arbusto_hide_arrow_bonus_damage > 0.0:
			arrow.damage += arbusto_hide_arrow_bonus_damage
		# L4: stampa o heal-on-hit na flecha. Cada hit dessa flecha cura o
		# player no impacto. Stamp no disparo (e não check no hit) garante que
		# o heal aplica mesmo se o player sair do bush antes do projétil chegar.
		if arbusto_hide_active and arbusto_hide_heal_per_hit > 0.0 and "arbusto_heal_on_hit" in arrow:
			arrow.arbusto_heal_on_hit = arbusto_hide_heal_per_hit
	# Tint verde nas flechas durante o hide do arbusto.
	if arbusto_hide_active and arrow is CanvasItem:
		(arrow as CanvasItem).modulate = Color(0.6, 1.2, 0.6, 1.0)
	if is_pierce:
		if "is_piercing" in arrow:
			arrow.is_piercing = true
		# Bonus de dano da perfuração entra como multiplicador do PRIMEIRO alvo
		# atingido. Os demais que a flecha atravessar recebem `damage` base.
		# Flechas extras do Multi Arrow aplicam só 60% do bônus (alinha com a
		# regra de "efeitos ao contato em 60%" das extras).
		if "pierce_first_dmg_mult" in arrow:
			var pierce_bonus_scale: float = 1.0 if is_primary else 0.60
			arrow.pierce_first_dmg_mult = 1.0 + _perf_damage_bonus() * pierce_bonus_scale
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
		# Flechas extras do Multi Arrow aplicam efeitos ao contato em 60% da
		# eficácia — padrão único pra burn/curse/freeze + fire trail.
		var burn_scale: float = 1.0 if is_primary else 0.60
		var trail_scale: float = 1.0 if is_primary else 0.60
		if "burn_dps" in arrow:
			arrow.burn_dps = _fire_burn_dps() * burn_scale
		if "burn_duration" in arrow:
			arrow.burn_duration = _fire_burn_duration()
		if "burn_final_bonus" in arrow:
			# Último tick do burn dá um dano extra fixo (ignora burn_scale —
			# bonus pequeno, não vale a pena dividir entre flechas extras).
			arrow.burn_final_bonus = 5.0
		# Stacks de burn escalam com fire_arrow_level (L1=1, L2=2, L3=3, L4=4).
		# Cada hit no mesmo inimigo soma +1 stack até o cap, multiplicando o
		# dano por tick. Flechas extras carregam o mesmo cap (sem nerf).
		if "burn_max_stacks" in arrow:
			arrow.burn_max_stacks = clampi(fire_arrow_level, 1, 4)
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
		# Multi Arrow combo: flechas extras com curse reduzido (mesmo 60% do burn).
		var curse_scale: float = 1.0 if is_primary else 0.60
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
		# Flechas extras do Multi Arrow aplicam freeze DPS a 60% também
		# (alinhado com burn/curse). Duração do freeze não é afetada.
		var freeze_scale: float = 1.0 if is_primary else 0.60
		if "freeze_dps" in arrow:
			arrow.freeze_dps = _ice_freeze_dps() * freeze_scale
		# Lv2+: spawna área nevada no impacto (reaproveita o IceSlowArea do mago).
		if ice_arrow_level >= 2:
			if "ice_area_enabled" in arrow:
				arrow.ice_area_enabled = true
			if "ice_area_slow_factor" in arrow:
				arrow.ice_area_slow_factor = _ice_area_slow_factor()
			if "ice_area_lifetime" in arrow:
				arrow.ice_area_lifetime = _ice_area_lifetime()
	if stone_arrow_level > 0:
		if "is_stone" in arrow:
			arrow.is_stone = true
		# Range curto E lento (pedra "pesada"). COM perfuração o range vira longo
		# (atravessa a tela) — combo full-power que proca AoE+stun em cada inimigo.
		if "speed" in arrow:
			arrow.speed = _stone_speed()
		if "lifetime" in arrow:
			if is_pierce:
				arrow.lifetime = _stone_pierce_lifetime()
			elif is_primary:
				arrow.lifetime = _stone_lifetime()
			else:
				# 2ª flecha (Flechas Duplas / extras do Multi): range um pouco maior.
				arrow.lifetime = _stone_extra_lifetime()
		# +dano direto da pedra (aplicado sobre o damage já calculado acima).
		if "damage" in arrow:
			arrow.damage *= _stone_direct_dmg_mult()
		if "stone_aoe_radius" in arrow:
			arrow.stone_aoe_radius = _stone_radius()
		# Referência de dano do AoE = o dano direto da flecha (já inclui o +dano
		# direto da pedra E a redução das flechas extras do Multi Arrow). O AoE
		# aplica uma % disso por gatilho: 50% splash no hit direto / 80% em todos
		# quando cai no fim do range ou bate em estrutura/parede.
		if "stone_aoe_damage" in arrow:
			arrow.stone_aoe_damage = arrow.damage
		if "stone_aoe_knockback" in arrow:
			arrow.stone_aoe_knockback = _stone_knockback()
		if "stone_stun_duration" in arrow:
			arrow.stone_stun_duration = _stone_stun_duration()
		if "stone_size_scale" in arrow:
			arrow.stone_size_scale = _stone_size_scale()
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
		# Explosão final do graviton é flat (não escala com arrow.damage),
		# então precisa do scale explícito pra ficar em 60% nas extras.
		if "graviton_explosion_damage" in arrow:
			var grav_scale: float = 1.0 if is_primary else 0.60
			arrow.graviton_explosion_damage = _graviton_explosion_damage() * grav_scale
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
	# Escala com o stat "Dano" (arrow_damage_multiplier) — é skill do player.
	if graviton_level >= 4:
		return _apply_dmg_pct_to_dps(20.0)
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
	# Garante incremento mínimo de +1 POR STACK comprado de "Dano" — DoTs de
	# base baixa (ex: curse lv1 = 3 dps × 1.20 = 3.6) sentiriam pouco do stat
	# sem isso. Sem stacks (damage_upgrades = 0), retorna base sem mudança.
	if base <= 0.0 or damage_upgrades <= 0:
		return base
	var scaled: float = base * arrow_damage_multiplier
	var min_scaled: float = base + float(damage_upgrades)
	if scaled < min_scaled:
		scaled = min_scaled
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


# ---------- Pedra (Disparo de Pedra) ----------
# Range curto E lento; +dano direto; AoE (dano + knockback + stun) no impacto/
# queda/estrutura. Com perfuração o range vira longo e o AoE proca em cada
# inimigo perfurado. (Lv3 skill Q e Lv4 escombros vêm na próxima etapa.)

func _stone_speed() -> float:
	# "Pesada" — bem mais devagar que a flecha normal (220). Dá pra ver vindo.
	return 150.0


func _stone_lifetime() -> float:
	# 150 × 0.7 ≈ 105px de alcance (flecha normal = 330px → ~-68%).
	return 0.7


func _stone_extra_lifetime() -> float:
	# 2ª flecha / extras (Flechas Duplas / Multi): range um pouco maior (150 ×
	# 0.9 ≈ 135px) pra não cair em cima da primeira.
	return 0.9


func _stone_pierce_lifetime() -> float:
	# Com perfuração o alcance vira longo (atravessa a tela): 150 × 5 = 750px.
	return 5.0


func _stone_direct_dmg_mult() -> float:
	# +dano direto da pedra (sobre o dano da flecha). Escala por nível.
	match stone_arrow_level:
		1: return 1.50
		2: return 1.65
		3: return 1.80
		4: return 2.00
	return 1.0


func _stone_radius() -> float:
	# +5px na área do stun a partir do L2.
	match stone_arrow_level:
		1: return 31.0
		2: return 36.0
		3: return 36.0
		4: return 36.0
	return 31.0


func _stone_size_scale() -> float:
	# L2+: pedra maior (visual + hitbox) — fica mais fácil de acertar.
	return 1.35 if stone_arrow_level >= 2 else 1.0


func _stone_knockback() -> float:
	return 70.0


func _stone_stun_duration() -> float:
	# Mesmo tempo do freeze do Gelo (2.0s) no Lv1; escala suave por nível.
	# (Crítico ainda multiplica em cima disso no impacto.)
	match stone_arrow_level:
		1: return 2.0
		2: return 2.3
		3: return 2.6
		4: return 3.0
	return 2.0


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


# Gate global: cada ATAQUE (volley inteiro) só proca cadeia uma vez. Resetado
# em _release_arrow e na dash auto-attack quando uma volley nova começa.
# Primeira flecha que acertar (multi-arrow, ricochete, ou flecha base) consome
# o token; as outras do mesmo ataque não procam mais.
var _chain_attack_used: bool = false


func consume_chain_proc_token() -> bool:
	# Retorna true se este hit deve gerar chain lightning. Gate global por
	# ataque — primeira flecha do volley que conectar reserva a cadeia.
	if chain_lightning_level <= 0:
		return false
	if _chain_attack_used:
		return false
	_chain_attack_used = true
	return true


func reset_chain_attack_token() -> void:
	# Chamado por _release_arrow (e dash auto-attack) quando uma volley nova
	# começa — libera o token pra próxima cadeia.
	_chain_attack_used = false


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
		# Skill do player escala com stat "Dano" + bônus L4 do Fogo.
		proj.field_dps = _apply_dmg_pct_to_dps(FIRE_SKILL_DPS) * _fire_burn_multiplier()
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
			# Skill do player escala com stat "Dano".
			bolt.damage = _apply_dmg_pct_to_dps(CHAIN_LIGHTNING_SKILL_BOLT_DAMAGE) * dmg_mult
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


func _update_tiger_claws(delta: float) -> void:
	if tiger_claws_level <= 0 or is_dead:
		return
	if _tiger_claws_cd_remaining > 0.0:
		_tiger_claws_cd_remaining = maxf(_tiger_claws_cd_remaining - delta, 0.0)
		return
	# Tenta castar. Sem inimigo no raio → cd não dispara, retenta no próximo frame.
	if _try_cast_tiger_claws():
		_tiger_claws_cd_remaining = TIGER_CLAWS_CD_BY_LEVEL[tiger_claws_level]


func _try_cast_tiger_claws() -> bool:
	var candidates: Array[Node2D] = []
	var rsq: float = TIGER_CLAWS_RADIUS * TIGER_CLAWS_RADIUS
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var enemy_node: Node2D = e as Node2D
		# Pula tank_ally (claudio_druida, mini_arbusto decoy) — só enemy real.
		if enemy_node.is_in_group("ally"):
			continue
		# Boss shieldado não toma dano — pular pra não desperdiçar cast.
		if enemy_node.is_in_group("boss_shielded"):
			continue
		if enemy_node.global_position.distance_squared_to(global_position) <= rsq:
			candidates.append(enemy_node)
	if candidates.is_empty():
		return false
	# Embaralha e pega N (max = candidates.size()).
	candidates.shuffle()
	var target_count: int = mini(TIGER_CLAWS_TARGETS_BY_LEVEL[tiger_claws_level], candidates.size())
	# Skill do player escala com stat "Dano".
	var dmg: float = _apply_dmg_pct_to_dps(TIGER_CLAWS_DMG_PER_SCRATCH_BY_LEVEL[tiger_claws_level])
	for i in target_count:
		_spawn_tiger_claws_vfx(candidates[i], dmg)
	return true


func _capture_clean_death_screenshot() -> void:
	# Esconde entidades dinâmicas por 1 frame, captura o viewport, restaura.
	# Resulta num screenshot só com chão/decoração — base limpa pro replay.
	var hidden_nodes: Array[CanvasItem] = []
	var groups: Array[String] = ["enemy", "ally", "arrow", "mage_projectile", "boomerang", "tank_ally", "mini_arbusto", "arbusto"]
	for group_name in groups:
		for n in get_tree().get_nodes_in_group(group_name):
			if n is CanvasItem and (n as CanvasItem).visible:
				hidden_nodes.append(n as CanvasItem)
				(n as CanvasItem).visible = false
	# Player também (o ghost vai ocupar o lugar no replay).
	var was_visible: bool = visible
	visible = false
	# Espera o próximo frame ser desenhado COM os nós escondidos.
	await RenderingServer.frame_post_draw
	var vp_img: Image = get_viewport().get_texture().get_image()
	if vp_img != null:
		death_screenshot = ImageTexture.create_from_image(vp_img)
	# Restaura visibilidade — a death sequence ainda precisa renderizar alguns
	# desses nós antes do blackout final.
	for n in hidden_nodes:
		if is_instance_valid(n):
			n.visible = true
	visible = was_visible


func _tick_replay_recorder(delta: float) -> void:
	# Captura snapshot a cada REPLAY_RECORD_INTERVAL pra alimentar o ring buffer.
	# Para quando is_dead — o último snapshot é capturado em _die().
	if is_dead:
		return
	_replay_record_accum += delta
	if _replay_record_accum < REPLAY_RECORD_INTERVAL:
		return
	_replay_record_accum -= REPLAY_RECORD_INTERVAL
	_record_replay_snapshot()


func _record_replay_snapshot() -> void:
	# Snapshot do player + entidades próximas. Mantém só os últimos
	# REPLAY_MAX_SNAPSHOTS (ring buffer).
	var entities: Array = []
	# Player primeiro — id reservado 0 + flag is_player pro replay instanciar
	# o player_preview com SkinLoadout em vez de um sprite genérico.
	var player_entry: Dictionary = _snapshot_entity(self, 0)
	player_entry["is_player"] = true
	entities.append(player_entry)
	var rsq: float = REPLAY_RECORD_RADIUS * REPLAY_RECORD_RADIUS
	# Grupos relevantes pro replay (entidades que aparecem visualmente perto).
	for group_name in ["enemy", "ally", "arrow", "mage_projectile", "boomerang", "tank_ally"]:
		for n in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			if n == self:
				continue
			var node2d: Node2D = n as Node2D
			if node2d.global_position.distance_squared_to(global_position) > rsq:
				continue
			var entry: Dictionary = _snapshot_entity(node2d, node2d.get_instance_id())
			# Evita duplicatas (ex: tank_ally também tá em ally).
			var dup: bool = false
			for existing in entities:
				if int(existing.get("id", -1)) == int(entry.get("id", -2)):
					dup = true
					break
			if not dup:
				entities.append(entry)
	stats_replay_snapshots.append({
		"player_pos": global_position,
		"entities": entities,
	})
	if stats_replay_snapshots.size() > REPLAY_MAX_SNAPSHOTS:
		stats_replay_snapshots.pop_front()


func _snapshot_entity(node: Node2D, id: int) -> Dictionary:
	var sprite_frames: SpriteFrames = null
	var anim_name: String = ""
	var frame_idx: int = 0
	var flip_h: bool = false
	var sprite_node: Node = node.get_node_or_null("AnimatedSprite2D")
	if sprite_node == null:
		# Player tem o sprite em outro lugar (Skin/Body). Procura recursivo.
		sprite_node = _find_first_animated_sprite(node)
	if sprite_node is AnimatedSprite2D:
		var asprite: AnimatedSprite2D = sprite_node as AnimatedSprite2D
		sprite_frames = asprite.sprite_frames
		anim_name = String(asprite.animation)
		frame_idx = asprite.frame
		flip_h = asprite.flip_h
	return {
		"id": id,
		"sprite_frames": sprite_frames,
		"sprite_offset": Vector2.ZERO if sprite_node == null else (sprite_node as Node2D).position,
		"pos": node.global_position,
		"anim": anim_name,
		"frame": frame_idx,
		"flip_h": flip_h,
		"modulate": node.modulate if node is CanvasItem else Color.WHITE,
		"z_index": node.z_index if node is CanvasItem else 0,
	}


func _find_first_animated_sprite(node: Node) -> Node:
	if node is AnimatedSprite2D:
		return node
	for child in node.get_children():
		var found: Node = _find_first_animated_sprite(child)
		if found != null:
			return found
	return null


func _spawn_tiger_claws_vfx(target: Node2D, damage_per_scratch: float) -> void:
	var vfx: Node = TIGER_CLAWS_VFX_SCENE.instantiate()
	if "damage_per_scratch" in vfx:
		vfx.damage_per_scratch = damage_per_scratch
	if "target" in vfx:
		vfx.target = target
	_get_world().add_child(vfx)
	if vfx is Node2D:
		(vfx as Node2D).global_position = target.global_position


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
		# Skill do player escala com stat "Dano".
		beam.damage_per_tick = _apply_dmg_pct_to_dps(CURSE_SKILL_DAMAGE_PER_TICK)
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


# ---------- Stone Earthquake (Q a partir do lv4 da Pedra) ----------

func _cast_earthquake() -> void:
	if _stone_skill_cd_remaining > 0.0:
		return
	_play_earthquake_sound()
	# Treme a tela.
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.has_method("shake"):
		cam.shake(STONE_QUAKE_SHAKE_DURATION, STONE_QUAKE_SHAKE_STRENGTH)
	# Stun em TODOS os mobs vivos no momento (cc_immune — boss/cubo — resistem
	# via apply_stun próprio, mas ainda levam o dano da área se estiverem nela).
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e.has_method("apply_stun"):
			e.apply_stun(STONE_QUAKE_STUN)
			_ensure_quake_stun_visual(e)
	# Grande dano + knockback + onda sísmica em volta do player (reusa o StoneAoE
	# com raio grande, centrado no player). damage_pct 1.0 = dano cheio.
	var quake: Node2D = STONE_AOE_QUAKE_SCRIPT.new()
	quake.radius = STONE_QUAKE_RADIUS
	quake.damage = STONE_QUAKE_DAMAGE * arrow_damage_multiplier
	quake.damage_pct = 1.0
	quake.knockback_strength = STONE_QUAKE_KNOCKBACK
	quake.stun_duration = STONE_QUAKE_STUN
	quake.source = self
	quake.origin = global_position
	_get_world().add_child(quake)
	_stone_skill_cd_remaining = STONE_SKILL_COOLDOWN
	stone_skill_cooldown_changed.emit(_stone_skill_cd_remaining, STONE_SKILL_COOLDOWN)


func _ensure_quake_stun_visual(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not ("_stun_remaining" in target) or float(target._stun_remaining) <= 0.0:
		return
	for c in target.get_children():
		if c is Node and (c as Node).is_in_group("stun_visual"):
			return
	target.add_child(STONE_QUAKE_STUN_VISUAL.new())


func _update_stone_skill(delta: float) -> void:
	if _stone_skill_cd_remaining > 0.0:
		_stone_skill_cd_remaining = maxf(_stone_skill_cd_remaining - delta, 0.0)
		stone_skill_cooldown_changed.emit(_stone_skill_cd_remaining, STONE_SKILL_COOLDOWN)


func _play_earthquake_sound() -> void:
	# Não-posicional (AudioStreamPlayer): sai centralizado/igual nos dois lados,
	# como um terremoto. Adicionado ao world pra sobreviver mesmo se o player sair.
	if STONE_QUAKE_SOUND == null:
		return
	var snd := AudioStreamPlayer.new()
	snd.bus = &"SFX"
	snd.stream = STONE_QUAKE_SOUND
	snd.volume_db = STONE_QUAKE_VOLUME_DB
	_get_world().add_child(snd)
	snd.play()
	var ref: AudioStreamPlayer = snd
	snd.finished.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


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


func apply_freeze_pause_if_active(node: Node) -> void:
	# Chamado pelo wave_manager logo após spawnar um inimigo: se o Time Freeze
	# está ativo, pausa o recém-chegado pra ele não andar/atacar no meio do
	# congelamento. Sem efeito se não há freeze ativo.
	if _time_freeze_active_remaining <= 0.0:
		return
	_pause_node_for_freeze(node)


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
	# Chain lightning: novo ataque libera o token global.
	reset_chain_attack_token()
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
			# Lambda c/ guard pra cobrir player morto entre o cast e o tick do
			# timer (ex: boss matou no mesmo frame do dash auto-attack).
			var shot_dir: Vector2 = shot["dir"]
			var shot_mult: float = float(shot["dmg_mult"])
			get_tree().create_timer(delay).timeout.connect(
				func() -> void:
					if is_dead or not is_inside_tree():
						return
					_spawn_arrow(shot_dir, shot_mult, is_pierce, false, false, is_ricochet, is_graviton)
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
	# Cura usada pelo coração de Life Steal, capivara, claudio druida e
	# qualquer outra fonte. Spawna +N verde acima do player como feedback.
	if is_dead or amount <= 0.0:
		return
	var before: float = hp
	hp = minf(hp + amount, max_hp)
	var actual: float = hp - before
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	if actual > 0.0:
		_spawn_heal_number(actual)


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
			# Slow resistance IGUAL à redução de dano (equalizado) — antes era metade.
			slow_resistance_pct = damage_reduction_pct
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
			# +23% por stack (aditivo). Aplica imediatamente — próximo ataque
			# já usa o novo wait_time/speed_scale via _start_attack.
			attack_speed_multiplier += 0.23
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
		"stone_arrow":
			# Elemental Pedra ("Disparo de Pedra"). Lv1: pedra (range curto+lento)
			# + AoE dano/knockback/stun. Lv2: mais dano + pedra/stun maiores.
			# Lv3: começa o round com 3 Stone Cubes aliados (wave_manager).
			# Lv4: skill Q "Terremoto" (treme tela + stun em todos + dano em área).
			var was_below_4_stone: bool = stone_arrow_level < 4
			stone_arrow_level = mini(stone_arrow_level + 1, 4)
			if was_below_4_stone and stone_arrow_level >= 4:
				_stone_skill_cd_remaining = 0.0
				stone_skill_unlocked.emit()
				stone_skill_cooldown_changed.emit(0.0, STONE_SKILL_COOLDOWN)
		"leno":
			leno_level = mini(leno_level + 1, 4)
			_refresh_lenos()
		"capivara_joe":
			capivara_joe_level = mini(capivara_joe_level + 1, 4)
			_refresh_capivaras()
		"ting":
			ting_level = mini(ting_level + 1, 4)
			_refresh_tings()
		"mini_mago":
			mini_mago_level = mini(mini_mago_level + 1, 4)
			_refresh_mini_magos()
		"arbusto":
			arbusto_level = mini(arbusto_level + 1, 4)
			_refresh_arbustos()
		"claudio_druida":
			# Cada compra: +1 level (max 4). Sobe stats em todos os existentes
			# e spawna 1 novo claudio_druida no player se ainda não tem todos.
			claudio_druida_level = mini(claudio_druida_level + 1, 4)
			_refresh_claudio_druidas()
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
			ricochet_counter_changed.emit(_ricochet_shot_counter, ricochet_arrow_level)
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
		"tiger_claws":
			# Lv1-4. Autocast: arranha 2× em N inimigos aleatórios no raio.
			# L1: 1 alvo, 25/scratch, cd 4.5s. L2: 2 alvos, 27/scratch.
			# L3: 2 alvos, 35/scratch, cd 3s. L4: 3 alvos, 35/scratch.
			tiger_claws_level = mini(tiger_claws_level + 1, 4)
			_tiger_claws_cd_remaining = 0.0  # próximo cast imediato
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
		"stone_arrow": return stone_arrow_level
		"claudio_druida": return claudio_druida_level
		"leno": return leno_level
		"capivara_joe": return capivara_joe_level
		"ting": return ting_level
		"arbusto": return arbusto_level
		"mini_mago": return mini_mago_level
		"gold_magnet": return gold_magnet_level
		"dash": return dash_level
		"esquivando": return esquivando_level
		"ricochet_arrow": return ricochet_arrow_level
		"graviton": return graviton_level
		"boomerang": return boomerang_level
		"tiger_claws": return tiger_claws_level
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


# Arbusto: chamado pelo Arbusto Carrara quando o player entra no idle dele.
# Ativa o buff de hide (atk speed + bonus dmg flat + tint nas flechas + heal/hit L4).
# Aggro shield é gerido via group "bush_hidden" — o próprio arbusto adiciona/remove.
func arbusto_enter_hide(atk_speed_bonus: float, arrow_bonus_dmg: float, heal_per_hit: float = 0.0) -> void:
	arbusto_hide_active = true
	arbusto_hide_atk_speed_bonus = atk_speed_bonus
	arbusto_hide_arrow_bonus_damage = arrow_bonus_dmg
	arbusto_hide_heal_per_hit = heal_per_hit


func arbusto_exit_hide() -> void:
	arbusto_hide_active = false
	arbusto_hide_atk_speed_bonus = 0.0
	arbusto_hide_arrow_bonus_damage = 0.0
	arbusto_hide_heal_per_hit = 0.0


# Janela de iframes pós-saída do bush: buffs já caíram, mas o group
# bush_hidden persiste por N segundos pro player escapar/reposicionar sem
# levar dano. Ticka em _process; quando zerar, remove o group.
var _post_bush_grace_remaining: float = 0.0


func arbusto_grant_iframe_grace(seconds: float) -> void:
	# Garante que o player tá no group (caso tenha saído do bush antes do mini
	# morrer) e arma o timer. Não acumula — sempre usa o maior valor.
	if not is_in_group("bush_hidden"):
		add_to_group("bush_hidden")
	_post_bush_grace_remaining = maxf(_post_bush_grace_remaining, seconds)


func _tick_post_bush_grace(delta: float) -> void:
	if _post_bush_grace_remaining <= 0.0:
		return
	_post_bush_grace_remaining = maxf(_post_bush_grace_remaining - delta, 0.0)
	if _post_bush_grace_remaining <= 0.0 and is_in_group("bush_hidden"):
		remove_from_group("bush_hidden")


# Visual de invulnerabilidade: bolha protetora estilo "Protect" do Pokémon —
# domo azul translúcido em volta do player, segue o movimento, leve pulsação
# de scale pra dar vida. Aparece quando bush_hidden ativo, some quando sai.
const INVULN_BUBBLE_RADIUS: float = 18.0
const INVULN_BUBBLE_FILL_COLOR: Color = Color(0.5, 0.8, 1.0, 0.18)
const INVULN_BUBBLE_RING_COLOR: Color = Color(0.55, 0.85, 1.0, 0.75)
const INVULN_BUBBLE_PULSE_PERIOD: float = 1.2
var _invuln_bubble: Node2D = null
var _invuln_bubble_active: bool = false


func _update_invuln_visual(_delta: float) -> void:
	# Liga/desliga a bolha conforme entrada/saída do bush_hidden. Mantém estado
	# pra não recriar a bolha toda frame.
	var hidden: bool = is_in_group("bush_hidden")
	if hidden and not _invuln_bubble_active:
		_create_invuln_bubble()
		_invuln_bubble_active = true
	elif not hidden and _invuln_bubble_active:
		_destroy_invuln_bubble()
		_invuln_bubble_active = false


func _create_invuln_bubble() -> void:
	# Bolha = Node2D root + Polygon2D filled (interior translúcido) + Line2D
	# fechada (anel de borda mais brilhante). Filho do player, segue movimento.
	# Pulse de scale 0.95-1.05 em loop pra parecer "viva" sem ficar exagerado.
	if _invuln_bubble != null and is_instance_valid(_invuln_bubble):
		_invuln_bubble.queue_free()
	var root := Node2D.new()
	root.position = Vector2(0, -10)  # centro do corpo do player
	root.z_index = 8
	# Interior translúcido.
	var fill := Polygon2D.new()
	var sides: int = 28
	var points := PackedVector2Array()
	for i in sides:
		var ang: float = TAU * float(i) / float(sides)
		points.append(Vector2(cos(ang), sin(ang)) * INVULN_BUBBLE_RADIUS)
	fill.polygon = points
	fill.color = INVULN_BUBBLE_FILL_COLOR
	root.add_child(fill)
	# Borda mais brilhante.
	var ring := Line2D.new()
	ring.width = 1.5
	ring.default_color = INVULN_BUBBLE_RING_COLOR
	ring.closed = true
	ring.joint_mode = 2
	ring.points = points
	root.add_child(ring)
	add_child(root)
	_invuln_bubble = root
	# Pulse loop: scale 0.95 ↔ 1.05, ease in-out, infinito.
	var t := root.create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(root, "scale", Vector2(1.05, 1.05), INVULN_BUBBLE_PULSE_PERIOD * 0.5).from(Vector2(0.95, 0.95))
	t.tween_property(root, "scale", Vector2(0.95, 0.95), INVULN_BUBBLE_PULSE_PERIOD * 0.5)


func _destroy_invuln_bubble() -> void:
	if _invuln_bubble != null and is_instance_valid(_invuln_bubble):
		# Fade out rápido antes de queue_free pra não sumir bruscamente.
		var node := _invuln_bubble
		var fade := node.create_tween()
		fade.tween_property(node, "modulate:a", 0.0, 0.15)
		fade.tween_callback(node.queue_free)
	_invuln_bubble = null


func _refresh_arbustos() -> void:
	# L1: 1 arbusto. L2-L4 TBD — placeholder: continua 1 instância até definir.
	var target_count: int = 1 if arbusto_level >= 1 else 0
	# Limpa entries inválidos.
	var alive: Array[Node2D] = []
	for a in _arbustos:
		if is_instance_valid(a):
			alive.append(a)
	_arbustos = alive
	while _arbustos.size() < target_count:
		var arb: Node2D = ARBUSTO_SCENE.instantiate()
		_arbustos.append(arb)
		_get_world().add_child(arb)
		if "wander_bounds" in arb:
			var b: Rect2 = arb.wander_bounds
			arb.global_position = Vector2(
				randf_range(b.position.x, b.position.x + b.size.x),
				randf_range(b.position.y, b.position.y + b.size.y)
			)
	while _arbustos.size() > target_count:
		var extra: Node2D = _arbustos.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	# Mini arbustos: L1/L2 tem 1 mini por big, L3+ tem 2 minis por big.
	var minis_per_big: int = 2 if arbusto_level >= 3 else 1
	var target_mini_count: int = _arbustos.size() * minis_per_big
	while _mini_arbustos.size() < target_mini_count:
		_mini_arbustos.append(null)
		_mini_arbusto_respawn_timers.append(0.0)
		_spawn_mini_arbusto_for_slot(_mini_arbustos.size() - 1)
	while _mini_arbustos.size() > target_mini_count:
		var extra_mini: Node2D = _mini_arbustos.pop_back()
		_mini_arbusto_respawn_timers.pop_back()
		if is_instance_valid(extra_mini):
			extra_mini.queue_free()


func _spawn_mini_arbusto_for_slot(i: int) -> void:
	# Spawna um mini arbusto na posição do big arbusto correspondente.
	# Quando há mais minis que bigs (L3+: 2 minis por big), cicla pelo array
	# de bigs (slot i → big[i % bigs]). Garante que o mini sempre nasce em
	# cima de um big vivo.
	var pos: Vector2 = Vector2.ZERO
	if not _arbustos.is_empty():
		var big_idx: int = i % _arbustos.size()
		if is_instance_valid(_arbustos[big_idx]):
			pos = (_arbustos[big_idx] as Node2D).global_position
	var mini: Node2D = MINI_ARBUSTO_SCENE.instantiate()
	_get_world().add_child(mini)
	mini.global_position = pos
	_mini_arbustos[i] = mini
	_mini_arbusto_respawn_timers[i] = 0.0


func _check_mini_arbusto_respawns(delta: float) -> void:
	# Respawn de mini arbustos 3s após a morte, na posição do big arbusto
	# correspondente. Só conta o tempo durante wave ativa.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	var wave_active: bool = wm == null or bool(wm.get("wave_active"))
	if not wave_active:
		return
	for i in _mini_arbustos.size():
		var inst: Node2D = _mini_arbustos[i]
		if inst != null and is_instance_valid(inst):
			_mini_arbusto_respawn_timers[i] = 0.0
			continue
		_mini_arbustos[i] = null
		_mini_arbusto_respawn_timers[i] += delta
		if _mini_arbusto_respawn_timers[i] >= MINI_ARBUSTO_RESPAWN_DELAY:
			_spawn_mini_arbusto_for_slot(i)


func _cleanup_arbustos() -> void:
	for a in _arbustos:
		if is_instance_valid(a):
			a.queue_free()
	_arbustos.clear()
	for m in _mini_arbustos:
		if is_instance_valid(m):
			m.queue_free()
	_mini_arbustos.clear()
	_mini_arbusto_respawn_timers.clear()
	# Limpa o estado do hide caso o cleanup aconteça no meio do buff.
	arbusto_exit_hide()


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


# Mini Mago — 1 instância sempre. Por nível:
#   L1: cast 8s, 1 macaco, sem buff.
#   L2: cast 6s, 1 macaco, +25% HP/dano/atk speed/move speed nos macacos.
#   L3: cast 6s, 2 macacos, mesmos buffs.
#   L4: cast 6s, 3 macacos, mesmos buffs.
func _refresh_mini_magos() -> void:
	var target_count: int = 1 if mini_mago_level >= 1 else 0
	var summon_interval: float = 8.0 if mini_mago_level <= 1 else 6.0
	var monkey_count: int = 1
	if mini_mago_level >= 4:
		monkey_count = 3
	elif mini_mago_level >= 3:
		monkey_count = 2
	var buff_mult: float = 1.0 if mini_mago_level <= 1 else 1.25
	var alive: Array[Node2D] = []
	for m in _mini_magos:
		if is_instance_valid(m):
			alive.append(m)
	_mini_magos = alive
	while _mini_magos.size() < target_count:
		var mm: Node2D = MINI_MAGO_SCENE.instantiate()
		_mini_magos.append(mm)
		_get_world().add_child(mm)
		if "wander_bounds" in mm:
			var b: Rect2 = mm.wander_bounds
			mm.global_position = Vector2(
				randf_range(b.position.x, b.position.x + b.size.x),
				randf_range(b.position.y, b.position.y + b.size.y)
			)
	while _mini_magos.size() > target_count:
		var extra: Node2D = _mini_magos.pop_back()
		if is_instance_valid(extra):
			extra.queue_free()
	# Aplica stats nas instâncias existentes (upgrade mid-game reflete no próximo cast).
	for m in _mini_magos:
		if "summon_interval" in m:
			m.summon_interval = summon_interval
		if "monkey_count" in m:
			m.monkey_count = monkey_count
		if "monkey_buff_mult" in m:
			m.monkey_buff_mult = buff_mult


func _cleanup_mini_magos() -> void:
	for m in _mini_magos:
		if is_instance_valid(m):
			m.queue_free()
	_mini_magos.clear()


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


func _refresh_claudio_druidas() -> void:
	# Spawna claudio_druidas faltantes pra match o level. Atualiza stats em todos
	# os vivos. Spawn em volta do player (offset random pra não empilhar).
	# L1-L2 = 1 warden, L3+ = 2 wardens (foco tank/utilidade).
	var target_count: int = _claudio_druida_target_count()
	# Limpa entries totalmente sem instance + sem timer (raro — só edge case
	# em que ainda não foi spawnado).
	while _claudio_druidas.size() < target_count:
		var ww: Node2D = CLAUDIO_DRUIDA_SCENE.instantiate()
		var spawn_pos: Vector2 = global_position + Vector2(randf_range(-32.0, 32.0), randf_range(-16.0, 16.0))
		_get_world().add_child(ww)
		ww.global_position = spawn_pos
		# Stats DEPOIS do add_child — HpBar (filha do ww) precisa do _ready
		# pra inicializar @onready var fg/trail antes de set_ratio.
		_apply_claudio_druida_stats(ww)
		_claudio_druidas.append({"instance": ww, "last_pos": spawn_pos, "dead_for": 0.0})
	# Atualiza stats em todos os vivos. Variável untyped (raw) + is_instance_valid
	# antes do acesso pra evitar "Trying to assign invalid previously freed
	# instance" quando uma entrada do array aponta pra um warden já liberado
	# (morreu, queue_free pendente). Mesmo padrão do _remove_time_freeze_world_pause.
	for entry in _claudio_druidas:
		var raw = entry.get("instance")
		if raw == null or not is_instance_valid(raw):
			continue
		_apply_claudio_druida_stats(raw)


func _apply_claudio_druida_stats(ww: Node) -> void:
	# Foco em tank/utilidade + escudo humano (absorve projéteis de mago no raio):
	# - L1-L3: base_hp 424, damage 60, cooldown 5.0s (stun em área + dano leve).
	# - L4: +150 hp (=574), damage 160, cooldown 4.5s (passa a dar dano forte).
	# +40 hp / +60 dmg em todos os níveis pra compensar o desgaste do escudo humano.
	# Heal pro player no ataque é decidido em claudio_druida._apply_hit via get_upgrade_count.
	if not ("max_hp" in ww and "damage" in ww):
		return
	var lvl: int = claudio_druida_level
	if lvl <= 0:
		return
	var base_hp: float = 424.0  # 384 + 40 (buff escudo humano)
	var extra_hp: float = 150.0 if lvl >= 4 else 0.0
	ww.max_hp = base_hp + extra_hp
	if lvl >= 4:
		ww.damage = 160.0  # 100 + 60
		if "attack_cooldown" in ww:
			ww.attack_cooldown = 4.5
	else:
		ww.damage = 60.0  # antes era 0
		if "attack_cooldown" in ww:
			ww.attack_cooldown = 5.0
	if "hp" in ww:
		ww.hp = ww.max_hp
	if ww.has_node("HpBar"):
		var bar: Node = ww.get_node("HpBar")
		if bar.has_method("set_ratio"):
			bar.set_ratio(1.0)


func _claudio_druida_target_count() -> int:
	if claudio_druida_level <= 0:
		return 0
	if claudio_druida_level <= 2:
		return 1
	return 2


func _check_claudio_druida_respawns(delta: float) -> void:
	# Respawn nativo: 15.5s após claudio_druida morrer, spawna novo na última posição.
	# Sem sistema de structure do wave_manager (mantém só pra torres).
	for entry in _claudio_druidas:
		var inst: Variant = entry.get("instance")
		var alive: bool = inst != null and is_instance_valid(inst) and (inst as Node).is_inside_tree()
		if alive:
			if inst is Node2D:
				entry["last_pos"] = (inst as Node2D).global_position
			entry["dead_for"] = 0.0
			continue
		var dead_for: float = float(entry.get("dead_for", 0.0)) + delta
		entry["dead_for"] = dead_for
		if dead_for < CLAUDIO_DRUIDA_RESPAWN_DELAY:
			continue
		var spawn_pos: Vector2 = entry.get("last_pos", global_position)
		_spawn_claudio_druida_portal_fx(spawn_pos)
		var ww: Node2D = CLAUDIO_DRUIDA_SCENE.instantiate()
		_get_world().add_child(ww)
		ww.global_position = spawn_pos
		# Stats DEPOIS do add_child — HpBar precisa do _ready pra resolver @onready.
		_apply_claudio_druida_stats(ww)
		entry["instance"] = ww
		entry["dead_for"] = 0.0


func _spawn_claudio_druida_portal_fx(pos: Vector2) -> void:
	if CLAUDIO_DRUIDA_SPAWN_FX_SCENE == null:
		return
	var fx: Node2D = CLAUDIO_DRUIDA_SPAWN_FX_SCENE.instantiate()
	_get_world().add_child(fx)
	fx.global_position = pos


func reposition_claudio_druidas_near_player() -> void:
	# Chamado pelo wave_manager em boss waves DEPOIS do player ser teleportado.
	# Sem isso, claudios vivos ficavam parados na arena anterior (no caso da wave
	# 14, fora do wave14_map que tem bounds diferentes do main map). Move vivos
	# pra perto do player e atualiza last_pos pra respawns futuros caírem aqui.
	for entry in _claudio_druidas:
		var new_pos: Vector2 = global_position + Vector2(randf_range(-32.0, 32.0), randf_range(-16.0, 16.0))
		entry["last_pos"] = new_pos
		var inst: Variant = entry.get("instance")
		if inst == null or not is_instance_valid(inst):
			continue
		if inst is Node2D:
			(inst as Node2D).global_position = new_pos


func reset_claudio_druidas_hp() -> void:
	# Chamado pelo wave_manager no início de cada wave: claudio_druidas vivos voltam
	# full HP (mesma lógica do owned_structures pra torres). Mortos seguem o
	# timer de respawn nativo.
	for entry in _claudio_druidas:
		var inst: Variant = entry.get("instance")
		if inst == null or not is_instance_valid(inst):
			continue
		if "max_hp" in inst and "hp" in inst:
			inst.hp = inst.max_hp
			if (inst as Node).has_node("HpBar"):
				var bar: Node = (inst as Node).get_node("HpBar")
				if bar.has_method("set_ratio"):
					bar.set_ratio(1.0)


func _cleanup_claudio_druidas() -> void:
	for entry in _claudio_druidas:
		var inst: Variant = entry.get("instance")
		if inst != null and is_instance_valid(inst):
			(inst as Node).queue_free()
	_claudio_druidas.clear()


func _cleanup_lenos() -> void:
	for l in _lenos:
		if is_instance_valid(l):
			l.queue_free()
	_lenos.clear()


# Reset completo de um pet (vendido na shop). Zera o level + remove todas as
# instâncias spawnadas. Refund de gold é responsabilidade do shop.
func reset_pet(id: String) -> void:
	match id:
		"claudio_druida":
			claudio_druida_level = 0
			_cleanup_claudio_druidas()
		"leno":
			leno_level = 0
			_cleanup_lenos()
		"capivara_joe":
			capivara_joe_level = 0
			_cleanup_capivaras()
		"ting":
			ting_level = 0
			_cleanup_tings()
		"mini_mago":
			mini_mago_level = 0
			_cleanup_mini_magos()
		"arbusto":
			arbusto_level = 0
			_cleanup_arbustos()


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
	if perfuracao_level > 0:
		perfuracao_counter_changed.emit(0, perfuracao_level)


func reset_ricochet_counter() -> void:
	# Mesma lógica do reset_perf_counter, pro contador do ricochete.
	_ricochet_shot_counter = 0
	if ricochet_arrow_level > 0:
		ricochet_counter_changed.emit(0, ricochet_arrow_level)


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
	_tiger_claws_cd_remaining = 0.0
	# Frostwisp (L3 do Gelo): força delay inicial de 7s antes do primeiro
	# cast da wave — evita que ela já comece bombardeando enquanto o player
	# nem se posicionou ainda.
	if _frostwisp != null and is_instance_valid(_frostwisp):
		if _frostwisp.has_method("set_initial_cooldown"):
			_frostwisp.set_initial_cooldown(7.0)


func take_damage(amount: float, source_id: String = "") -> void:
	if is_dead:
		return
	# Dev godmode: ignora dano (toggle no DevPanel). Persiste em GameState.
	if GameState.dev_godmode:
		return
	# Escondido no Pai do Verde / Verde: invulnerável a TODO dano (direto, AoE,
	# projétil em voo, DoT/burn/poison/curse já ativos). O aggro já é gerido por
	# group "bush_hidden" no targeting dos enemies, mas projéteis em voo e DoTs
	# ativos continuam batendo — esse gate fecha o último vão.
	if is_in_group("bush_hidden"):
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
	# Clamp de float dust: dano fracionário (ex: armor 12% reduzindo 10 → 8.8)
	# pode deixar hp em valores tipo 0.2 — UI mostra "0" mas o check de morte
	# (== 0.0) nunca dispara. Sub-1 HP é morte certa.
	if hp < 1.0:
		hp = 0.0
	notify_damage_taken(reduced, source_id)
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(reduced)
	if damage_audio != null:
		damage_audio.play()
	if hp <= 0.0:
		stats_killed_by = source_id if not source_id.is_empty() else "unknown"
		_die()


func _die() -> void:
	# Snapshot final do ring buffer (todos os ghosts pra o replay).
	_record_replay_snapshot()
	is_dead = true
	is_attacking = false
	is_drawing = false
	# Captura screenshot do CENÁRIO sem os bonecos — esconde player/enemy/ally/
	# projétil por 1 frame, captura, restaura. Sem isso, o fundo do replay
	# fica com tudo congelado e atrapalha entender o que aconteceu.
	await _capture_clean_death_screenshot()
	if sprite != null:
		sprite.stop()
	if hp_bar != null:
		hp_bar.visible = false
	# Lenos morrem com o player (spec do excalidraw).
	_cleanup_lenos()
	_cleanup_claudio_druidas()
	_cleanup_capivaras()
	_cleanup_tings()
	_cleanup_mini_magos()
	_cleanup_arbustos()
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


# Cor verde do heal number — usado por todas as fontes de cura
# (life steal hearts, capivara, claudio druida, arbusto L4, qualquer outra).
const HEAL_NUMBER_COLOR: Color = Color(0.4, 1.0, 0.4, 1.0)


func _spawn_heal_number(amount: float) -> void:
	if damage_number_scene == null or amount <= 0.0:
		return
	var num := damage_number_scene.instantiate()
	num.text_override = "+%d" % int(round(amount))
	num.color_override = HEAL_NUMBER_COLOR
	num.position = global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


# Corner sliding: quando o player anda RETO contra um canto/objeto, dá um
# leve empurrão perpendicular pra deslizar e passar — locomoção fluida.
# Só aplica em input axis-aligned (HORZ ou VERT puro); diagonal o move_and_slide
# já desliza naturalmente.
#
# Lógica: testa o motion direto. Se colide, testa motion + perp*PROBE pros 2
# lados. Se um lado tá livre, injeta uma componente perpendicular pra criar
# uma diagonal — o move_and_slide faz o resto contornando o canto.
const CORNER_SLIDE_PROBE_DIST: float = 8.0
const CORNER_SLIDE_FORCE: float = 0.7


func _apply_corner_slide(desired_vel: Vector2, delta: float) -> Vector2:
	if desired_vel.length_squared() < 0.01:
		return desired_vel
	var dir: Vector2 = desired_vel.normalized()
	# Diagonal? Sai — move_and_slide já trata.
	if absf(dir.x) > 0.05 and absf(dir.y) > 0.05:
		return desired_vel
	var motion: Vector2 = desired_vel * delta
	# Path direto livre? Sem nudge.
	if not test_move(global_transform, motion):
		return desired_vel
	# Bloqueado: probe perpendicular pros dois lados.
	var perp: Vector2 = Vector2(-dir.y, dir.x)
	var probe_left: Vector2 = perp * CORNER_SLIDE_PROBE_DIST + motion
	var probe_right: Vector2 = -perp * CORNER_SLIDE_PROBE_DIST + motion
	var blocked_left: bool = test_move(global_transform, probe_left)
	var blocked_right: bool = test_move(global_transform, probe_right)
	if blocked_left and blocked_right:
		return desired_vel  # canto fechado, nada a fazer
	var slide_dir: Vector2 = perp if not blocked_left else -perp
	return desired_vel + slide_dir * desired_vel.length() * CORNER_SLIDE_FORCE


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


# Segundos de stun que o player causou em inimigos nesta run (qualquer fonte:
# claudio druida, pedra, terremoto, gelo). Acumula pro unlock da skin Terracota.
func notify_stun_applied(duration: float) -> void:
	if duration > 0.0:
		stats_stun_seconds += duration


func notify_damage_dealt(amount: float) -> void:
	if amount > 0.0:
		stats_damage_dealt += amount


# Arbusto L4: cura o player por uma flat amount. Chamado por arrow.gd no hit
# (com o valor armado pelo player no momento do disparo — assim cada flecha
# que sai de dentro do bush garante o heal mesmo se o player sair antes do
# projétil chegar).
func arbusto_heal_on_arrow_hit(amount: float) -> void:
	if amount <= 0.0 or is_dead:
		return
	var before: float = hp
	hp = minf(hp + amount, max_hp)
	var actual: float = hp - before
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	if actual > 0.0:
		_spawn_heal_number(actual)


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
