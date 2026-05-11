extends CharacterBody2D

# Mage Monkey — boss da wave 7. Fica parado no centro do mapa usando duas
# skills (volley de tiros + curse beam predictivo). Tem shield enquanto
# houver minions ("boss_minion") vivos. Quando todos morrem fica VULNERÁVEL
# por X segundos, depois invoca nova horda e o shield volta.

# === Stats principais ===
@export var max_hp: float = 1600.0
@export var damage_mult: float = 1.0  # setado pelo wave_manager
@export var hp_mult: float = 1.0  # idem

# === Janela de vulnerabilidade / invocação ===
@export var vulnerable_window: float = 12.0  # segundos parado vulnerável até invocar nova horda
@export var minion_horde_size: int = 10  # quantos minions invocar de cada vez
# Delay inicial de combate — boss não ataca os primeiros N segundos do round
# pra dar tempo do player se posicionar e engajar.
@export var initial_attack_delay: float = 10.0
# Janela de espera no início pra o wave_manager terminar de spawnar a horda
# inicial (do config) antes do boss decidir se invoca a 1ª horda própria.
@export var initial_horde_grace: float = 6.0
# Wave_manager seta isso pra TRUE antes de add_child quando a cinematic
# do boss tá rodando — pula a animação de pop-in (a cinematic É a entrada).
var skip_entrance_animation: bool = false

# === Skill 1: volley de tiros ===
@export var projectile_scene: PackedScene  # mage_projectile
# Tamanho da PRIMEIRA rajada. Cada par de rajadas subsequente ganha +1 tiro
# (rajada 1-2: volley_size, rajada 3-4: volley_size+1, etc).
@export var volley_size: int = 11
# Cada N rajadas, +1 tiro. Antes era a cada 2 (escalava muito rápido).
@export var volley_size_growth_period: int = 5
@export var volley_size_growth_amount: int = 1
@export var volley_interval: float = 0.3  # tempo entre tiros da rajada
@export var volley_rest: float = 7.0  # respiro após acabar a rajada
# Som tocado UMA VEZ no começo de cada rajada (não em cada tiro).
@export var cast_sound: AudioStream
@export var cast_sound_volume_db: float = -10.0

# === Skill 2: curse beam predictivo ===
@export var curse_beam_scene: PackedScene
@export var curse_beam_interval: float = 20.0
# CD do PRIMEIRO beam (depois do initial_attack_delay). Setado pra 3s pra
# que o primeiro beam saia ~13s de round (10s delay + 3s warmup do CD).
@export var first_beam_delay: float = 3.0
@export var curse_beam_lookahead: float = 0.6  # quanto à frente prevê o player
@export var curse_beam_damage: float = 6.0
@export var curse_beam_warmup: float = 1.2  # tempo do warmup do beam (player vê e desvia)

# === Skill 3: invocação de minions ===
@export var minion_mage_scene: PackedScene
@export var minion_summoner_scene: PackedScene
@export var minion_fire_mage_scene: PackedScene
@export var summon_effect_scene: PackedScene
@export var summon_radius: float = 90.0
# Delay do cast antes da invocação acontecer (segundos). Durante esse tempo o
# boss toca a animação "cast" em loop — período de telegrafia onde o player
# pode bater no boss livremente (já está vulnerável).
@export var summon_cast_delay: float = 2.0
@export var summon_sound: AudioStream
@export var summon_sound_volume_db: float = -10.0
# Skip dos primeiros N seg do mp3 (intro silenciosa). Stop em final-N seg
# (corta o tail). User pediu 0.9s skip + para em 4.0s = 3.1s tocando.
const SUMMON_SOUND_START: float = 0.9
const SUMMON_SOUND_END: float = 4.0

# === Drops + efeitos ===
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var kill_effect_scene: PackedScene
@export var damage_sound: AudioStream
@export var damage_sound_volume_db: float = -14.0
@export var gold_scene: PackedScene
@export var gold_drop_chance: float = 1.0
@export var gold_drop_min: int = 9
@export var gold_drop_max: int = 12
@export var heart_scene: PackedScene
@export var death_silhouette_duration: float = 1.4

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const BODY_CENTER_OFFSET: Vector2 = Vector2(0, -32)
# Projétil do boss é diferente do mage normal: alcance infinito (lifetime
# alto pra perseguir o player até bater), sprite/hitbox maior pra parecer
# uma "esfera mágica" perigosa, e audio mais baixo (não estoura ouvido com
# a rajada de 8 tiros).
const BOSS_PROJ_LIFETIME: float = 999.0
const BOSS_PROJ_SPRITE_SCALE: float = 1.4
const BOSS_PROJ_HITBOX_SCALE: float = 1.5
const BOSS_PROJ_AUDIO_REDUCTION_DB: float = 14.0
# Tiro extra gigante: 40% de chance no fim de cada rajada, 2× maior que os
# outros tiros (multiplica por cima da escala já-aplicada do boss).
const BOSS_GIANT_SHOT_CHANCE: float = 0.4
const BOSS_GIANT_SHOT_SCALE_MULT: float = 2.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar
@onready var muzzle: Marker2D = $Muzzle

var hp: float
var player: Node2D = null
var _minions: Array[Node] = []  # tracking dos minions invocados (filtra por validade)
var _is_shielded: bool = true
# Timers
var _vulnerable_remaining: float = 0.0
var _volley_remaining_shots: int = 0
var _volley_shot_cd: float = 0.0
var _volley_rest_cd: float = 0.0
var _volley_count: int = 0  # quantas rajadas o boss já começou (incl. atual)
var _giant_shot_queued: bool = false  # tiro extra gigante já roladoado pra essa rajada
var _next_shot_giant: bool = false  # marca o próximo disparo como gigante
var _initial_delay_remaining: float = 0.0
var _beam_cd: float = 0.0
# Flag pra evitar re-trigger de _summon_horde durante o cast (vulnerable
# countdown segue rodando senão dispararia múltiplas vezes nos 2s do cast).
var _is_casting: bool = false
# Conta quantas hordas o boss já invocou (incluindo a 1ª). A cada nova horda
# os minions ficam mais fortes — escala progressiva pra não trivializar
# loops longos de "mata minions, fica vulnerável, repete".
var _horde_count: int = 0
@export var horde_hp_growth: float = 0.20  # +20% HP por horda subsequente
@export var horde_damage_growth: float = 0.15  # +15% damage
# Stun/CC: boss é imune (igual stone cube), mas mantemos as funções pra arrow.gd não crashar.
var _flash_tween: Tween


func _ready() -> void:
	add_to_group("enemy")
	add_to_group("mage_monkey")
	add_to_group("boss")
	# Cogumelos da Capivara Joe somem ao entrar a wave de boss — limpa o mapa
	# pra o boss fight ficar focado (sem buffs/dano residual de cogumelos).
	_clear_capivara_mushrooms()
	# Boss é imune a CC: knockback/stun/slow/pull não fazem nada (mesma flag do stone_cube).
	add_to_group("cc_immune")
	# Reposiciona pro centro da arena: se houver node em grupo "boss_arena_center"
	# no main.tscn, usa ele. Senão fica no spawn point passado pelo wave_manager.
	var center := get_tree().get_first_node_in_group("boss_arena_center")
	if center is Node2D:
		global_position = (center as Node2D).global_position
	# wave_manager._apply_wave_scaling já multiplicou max_hp por hp_mult ANTES
	# desse _ready (pré-add_child). Então só copia direto. hp_mult fica
	# armazenado pra propagar pros minions invocados.
	hp = max_hp
	if hp_bar != null and hp_bar.has_method("set_ratio"):
		hp_bar.set_ratio(1.0)
	player = get_tree().get_first_node_in_group("player")
	# Sprite começa em "defense" (sem minions ainda invocou na 1ª horda — _ready
	# da wave passa pra invocação inicial via _start_initial_horde abaixo).
	sprite.play("defense")
	# Default state inicial: shielded até _initial_minion_check rodar. Marca o
	# grupo pra pets já saberem de cara que não devem atacar.
	add_to_group("boss_shielded")
	# Anima entrada do boss: pop in com scale + summon effect roxo grande.
	# Pulado quando o boss vem da cinematic da wave (skip_entrance_animation
	# setado pelo wave_manager) — a cinematic já É a entrada visual.
	if not skip_entrance_animation:
		_play_entrance_animation()
	# Cooldowns iniciais — primeiro beam usa first_beam_delay (curto). Beams
	# subsequentes voltam ao curse_beam_interval normal.
	_beam_cd = first_beam_delay
	_volley_rest_cd = 0.0
	# Delay inicial de combate (zero se desabilitado).
	_initial_delay_remaining = maxf(initial_attack_delay, 0.0)
	# Espera o wave_manager spawnar a horda inicial de magos da config (rolam
	# com spawn_delay de 0.5s cada → ~7s pra completar 14 magos). Se depois
	# desse tempo ainda não houver minions adotáveis, boss invoca 1ª horda
	# própria. call_deferred direto dispararia frame seguinte, ANTES do
	# wave_manager spawnar 1 minion sequer → boss invocaria full-HP minions
	# ignorando os "trash mobs" de 1 HP da config.
	get_tree().create_timer(initial_horde_grace).timeout.connect(_initial_minion_check)


const ENTRANCE_DURATION: float = 0.9
const ENTRANCE_FX_SCALE: float = 2.4
# Fração dos minions invocados que aparecem perto do boss (resto vai pros
# spawn points mais longes do player).
const BOSS_SPAWN_NEARBY_CHANCE: float = 0.25


func _play_entrance_animation() -> void:
	# Summon effect grande no boss (roxo).
	if summon_effect_scene != null:
		var fx: Node2D = summon_effect_scene.instantiate()
		_get_world().add_child(fx)
		fx.global_position = global_position + BODY_CENTER_OFFSET
		fx.scale = Vector2.ONE * ENTRANCE_FX_SCALE
		_tint_summon_effect_purple(fx)
	# 4. Áudio do summon (mesmo das hordas).
	_play_summon_sound()
	# 3. Sprite pop-in: parte invisível e pequeno → cresce com elastic ease.
	if sprite != null:
		var orig_scale: Vector2 = sprite.scale
		sprite.scale = orig_scale * 0.2
		sprite.modulate.a = 0.0
		var t := sprite.create_tween().set_parallel(true)
		t.tween_property(sprite, "scale", orig_scale, ENTRANCE_DURATION)\
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		t.tween_property(sprite, "modulate:a", 1.0, ENTRANCE_DURATION * 0.5)


func _initial_minion_check() -> void:
	# Se já há minions vivos (spawnados pelo wave_manager pela config inicial),
	# adota eles. Senão invoca a primeira horda.
	_collect_existing_minions()
	if _minions.is_empty():
		_summon_horde()
	_update_state()


func _physics_process(delta: float) -> void:
	# Boss não anda — fica fixo no spawn point. Velocity zerada pra qualquer
	# colisão/separation não mexer ele.
	velocity = Vector2.ZERO
	move_and_slide()
	# Re-coleta minions: novos magos podem ter sido spawnados pelo wave_manager
	# ao longo da wave (totais não vêm todos de uma vez), e o boss precisa tratar
	# todos como shield.
	_collect_existing_minions()
	# Limpa minions inválidos. Também remove os que foram convertidos em
	# curse_ally pela flecha profana do player — eles saem do grupo "enemy",
	# não machucam mais o boss, então não devem manter o shield ativo.
	_minions = _minions.filter(func(m): return is_instance_valid(m) and (m as Node).is_in_group("enemy"))
	# Atualiza estado (SHIELDED ↔ VULNERABLE) baseado na contagem.
	_update_state()
	# Vulnerable countdown → invoca nova horda quando chega a 0. Não decrementa
	# durante o cast (já está em transição pra summon, evita re-trigger).
	if not _is_shielded and not _is_casting:
		_vulnerable_remaining -= delta
		if _vulnerable_remaining <= 0.0:
			_summon_horde()
	# Delay inicial: boss não ataca nos primeiros N segundos do round (pra
	# player ter tempo de se posicionar). State machine + invocação rolam normal.
	if _initial_delay_remaining > 0.0:
		_initial_delay_remaining -= delta
		return
	# Skills: rodam em qualquer estado (depois do delay inicial).
	_tick_volley(delta)
	_tick_beam(delta)


func _update_state() -> void:
	var now_shielded: bool = not _minions.is_empty()
	if now_shielded == _is_shielded:
		return
	_is_shielded = now_shielded
	if _is_shielded:
		sprite.play("defense")
		# Marca como untargetable pra pets/torres não gastarem ataques no shield.
		if not is_in_group("boss_shielded"):
			add_to_group("boss_shielded")
	else:
		sprite.play("idle")
		if is_in_group("boss_shielded"):
			remove_from_group("boss_shielded")
		# Reseta janela vulnerável.
		_vulnerable_remaining = vulnerable_window


func _collect_existing_minions() -> void:
	# Adopta como minion qualquer enemy vivo que NÃO seja o próprio boss. Isso
	# inclui os magos pré-spawnados pelo wave_manager + os que o boss invoca,
	# e qualquer mago novo que o wave_manager adicione ao longo da wave.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if e == self or (e as Node).is_in_group("mage_monkey"):
			continue
		if e in _minions:
			continue
		_minions.append(e)
		# Marca no grupo boss_minion pra outros sistemas (ex: cleanup) reconhecerem.
		if not (e as Node).is_in_group("boss_minion"):
			(e as Node).add_to_group("boss_minion")


# ---------- Skill 1: volley de tiros ----------

func _tick_volley(delta: float) -> void:
	if projectile_scene == null:
		return
	# Em rest: contagem regressiva, não atira.
	if _volley_rest_cd > 0.0:
		_volley_rest_cd -= delta
		if _volley_rest_cd <= 0.0:
			_start_new_volley()
		return
	# Em rajada: atira a cada volley_interval seg.
	if _volley_remaining_shots > 0:
		_volley_shot_cd -= delta
		if _volley_shot_cd <= 0.0:
			_fire_one_shot(_next_shot_giant)
			_next_shot_giant = false
			_volley_remaining_shots -= 1
			_volley_shot_cd = volley_interval
			if _volley_remaining_shots == 0:
				# 40% de chance de adicionar um tiro gigante extra no fim da rajada.
				if not _giant_shot_queued and randf() < BOSS_GIANT_SHOT_CHANCE:
					_giant_shot_queued = true
					_next_shot_giant = true
					_volley_remaining_shots = 1
				else:
					_volley_rest_cd = volley_rest
		return
	# Não está em rest nem em rajada — começa rajada nova.
	_start_new_volley()


func _start_new_volley() -> void:
	# A cada `volley_size_growth_period` rajadas o boss ganha
	# `volley_size_growth_amount` tiros. Default: a cada 5 → +1.
	_volley_count += 1
	var period: int = maxi(volley_size_growth_period, 1)
	var bonus: int = ((_volley_count - 1) / period) * volley_size_growth_amount
	_volley_remaining_shots = volley_size + bonus
	_volley_shot_cd = 0.0
	_giant_shot_queued = false
	_next_shot_giant = false
	# Som de cast no início da rajada (uma vez, não em cada tiro).
	_play_cast_sound()


func _play_cast_sound() -> void:
	if cast_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = cast_sound
	p.volume_db = cast_sound_volume_db
	add_child(p)
	p.play()
	# Auto-cleanup quando o stream acabar.
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func _fire_one_shot(giant: bool = false) -> void:
	if projectile_scene == null:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	var proj := projectile_scene.instantiate()
	if "source_id" in proj:
		proj.source_id = "mage_monkey"
	if "damage" in proj and damage_mult != 1.0:
		proj.damage = float(proj.damage) * damage_mult
	# Range infinito: lifetime altíssimo + redirect padrão do mage_projectile
	# já segue o player → vira míssil rastreador até bater.
	if "lifetime" in proj:
		proj.lifetime = BOSS_PROJ_LIFETIME
	# Atravessa objetos (paredes, árvores, casas — tudo na layer 2). Mask = 5
	# (1+4) = bate só em player + tank_ally/structure (filtro de grupo no script
	# do projétil decide o resto).
	if "collision_mask" in proj:
		proj.collision_mask = 5
	# Boss atravessa aliados/estruturas — só player toma o tiro.
	if "pierce_allies" in proj:
		proj.pierce_allies = true
	# is_ally_source NÃO é setado (default false) → projétil é "do enemy",
	# bate em player/structure/tank_ally e ignora outros enemies (inclui os
	# minions do boss).
	_get_world().add_child(proj)
	# Tiro gigante: multiplica por cima da escala-base do boss.
	var sprite_mult: float = BOSS_PROJ_SPRITE_SCALE
	var hitbox_mult: float = BOSS_PROJ_HITBOX_SCALE
	if giant:
		sprite_mult *= BOSS_GIANT_SHOT_SCALE_MULT
		hitbox_mult *= BOSS_GIANT_SHOT_SCALE_MULT
	# Visual e hitbox maiores pra parecer mágica forte do boss.
	var proj_sprite: Node = proj.get_node_or_null("AnimatedSprite2D")
	if proj_sprite is Node2D:
		(proj_sprite as Node2D).scale *= sprite_mult
	var proj_glow: Node = proj.get_node_or_null("GlowLight")
	if proj_glow is Node2D:
		(proj_glow as Node2D).scale *= sprite_mult
	var proj_coll: Node = proj.get_node_or_null("CollisionShape2D")
	if proj_coll is CollisionShape2D:
		(proj_coll as CollisionShape2D).scale *= hitbox_mult
	# Audio menor — boss atira muito, não pode estourar ouvido.
	var proj_sound: Node = proj.get_node_or_null("ShootSound")
	if proj_sound is AudioStreamPlayer2D:
		(proj_sound as AudioStreamPlayer2D).volume_db -= BOSS_PROJ_AUDIO_REDUCTION_DB
	var spawn: Vector2 = muzzle.global_position
	proj.global_position = spawn
	var target_pos: Vector2 = player.global_position + Vector2(0, -12)
	var dir: Vector2 = (target_pos - spawn).normalized()
	if proj.has_method("set_direction"):
		proj.set_direction(dir)


# ---------- Skill 2: curse beam predictivo ----------

func _tick_beam(delta: float) -> void:
	_beam_cd -= delta
	if _beam_cd > 0.0:
		return
	if curse_beam_scene == null:
		_beam_cd = curse_beam_interval
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			_beam_cd = curse_beam_interval
			return
	_cast_curse_beam()
	_beam_cd = curse_beam_interval


func _cast_curse_beam() -> void:
	# Beam é castado ATRAVESSANDO o player na direção em que ele está andando.
	# Origin = posição atual do player (centro do beam). Direction = velocity
	# normalizada (player parado: usa direção boss→player como fallback).
	# Player tem warmup_duration pra desviar mudando de direção.
	var origin: Vector2 = player.global_position
	var dir: Vector2 = Vector2.RIGHT
	if "velocity" in player and (player.velocity as Vector2).length_squared() > 1.0:
		dir = (player.velocity as Vector2).normalized()
	else:
		# Player parado: aponta o beam saindo do boss em direção ao player
		# (atravessa o player).
		var to_p: Vector2 = player.global_position - global_position
		if to_p.length_squared() > 0.001:
			dir = to_p.normalized()
	var beam: Node2D = curse_beam_scene.instantiate()
	if "is_enemy_source" in beam:
		beam.is_enemy_source = true
	if "warmup_duration" in beam:
		beam.warmup_duration = curse_beam_warmup
	if "damage_per_tick" in beam:
		beam.damage_per_tick = curse_beam_damage * damage_mult
	# Hitbox do beam do boss é levemente menor que o do player (-2) — visual
	# do beam é o mesmo, mas tolera mais miss perto da borda pro player
	# conseguir desviar.
	if "hit_radius" in beam:
		beam.hit_radius = maxf(beam.hit_radius - 2.0, 1.0)
	_get_world().add_child(beam)
	if beam.has_method("setup"):
		beam.setup(origin, dir)


# ---------- Skill 3: invocação ----------

func _summon_horde() -> void:
	# Entry point da invocação: começa cast de `summon_cast_delay` segundos,
	# durante o qual o boss toca "cast" em loop (visual de canalização). Depois
	# do timer, _do_summon_horde rola a invocação real. Boss continua vulnerável
	# durante o cast (player pode bater livremente).
	if _is_casting:
		return
	_is_casting = true
	if sprite != null:
		sprite.play("cast")
	if summon_cast_delay > 0.0:
		get_tree().create_timer(summon_cast_delay).timeout.connect(_do_summon_horde)
	else:
		_do_summon_horde()


func _do_summon_horde() -> void:
	# Spawn de minions: 75% vão pros 2 spawn points padrão MAIS LONGES do
	# player no momento da invocação (alternando entre eles), 25% spawnam
	# aleatoriamente PERTO do boss pra criar pressão central também.
	# Mistura tipos: 60% mage normal, 25% fire mage, 15% summoner mage. Cada
	# horda subsequente os minions ficam mais fortes (horde_hp_growth × horde_count etc).
	_is_casting = false
	# Boss pode ter morrido durante o cast — aborta se não estiver mais no tree.
	if not is_inside_tree():
		return
	_horde_count += 1
	var horde_hp_mult: float = 1.0 + horde_hp_growth * float(_horde_count - 1)
	var horde_dmg_mult: float = 1.0 + horde_damage_growth * float(_horde_count - 1)
	# Cada invocação subsequente adiciona +1 minion aleatório (escalada de
	# pressão). Horda 1 = minion_horde_size, horda 2 = +1, horda 3 = +2, ...
	var current_horde_size: int = minion_horde_size + (_horde_count - 1)
	# Pega 2 spawn points mais longes do player. Fallback: posição do boss.
	var spawn_anchors: Array[Vector2] = []
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("get_farthest_spawn_points_from_player"):
		spawn_anchors = wm.get_farthest_spawn_points_from_player(2)
	if spawn_anchors.is_empty():
		spawn_anchors.append(global_position)
	# Flash de tela tipo raio (cor preta) — sinaliza que o boss tá invocando.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud != null and hud.has_method("flash_screen"):
		hud.flash_screen()
	# Efeito grande no centro do boss (um burst só pra dramatizar a invocação).
	if summon_effect_scene != null:
		var fx_center: Node2D = summon_effect_scene.instantiate()
		_get_world().add_child(fx_center)
		fx_center.global_position = global_position + BODY_CENTER_OFFSET
		_tint_summon_effect_purple(fx_center)
	# Áudio do cast (skip intro silenciosa + corta tail).
	_play_summon_sound()
	# Index separado pra alternância dos 2 spawn points longes — só incrementa
	# quando o minion vai pra um anchor (pulado quando spawna perto do boss).
	var anchor_idx: int = 0
	for i in current_horde_size:
		var pos: Vector2
		if randf() < BOSS_SPAWN_NEARBY_CHANCE:
			# 25% — spawna perto do boss em ângulo aleatório (radius variável).
			var boss_angle: float = randf() * TAU
			var boss_radius: float = randf_range(summon_radius * 0.5, summon_radius)
			pos = global_position + Vector2(cos(boss_angle), sin(boss_angle)) * boss_radius
		else:
			# 75% — alterna entre os 2 spawn anchors, com pequeno offset.
			var anchor: Vector2 = spawn_anchors[anchor_idx % spawn_anchors.size()]
			var off: Vector2 = Vector2(randf_range(-22.0, 22.0), randf_range(-22.0, 22.0))
			pos = anchor + off
			anchor_idx += 1
		var roll: float = randf()
		var scn: PackedScene = minion_mage_scene
		if roll < 0.15 and minion_summoner_scene != null:
			scn = minion_summoner_scene
		elif roll < 0.40 and minion_fire_mage_scene != null:
			scn = minion_fire_mage_scene
		if scn == null:
			continue
		# Mesma anim que o mago invocador faz quando spawna inseto: efeito por
		# minion na posição que ele vai aparecer.
		if summon_effect_scene != null:
			var fx_minion: Node2D = summon_effect_scene.instantiate()
			_get_world().add_child(fx_minion)
			fx_minion.global_position = pos
			_tint_summon_effect_purple(fx_minion)
		var minion: Node2D = scn.instantiate()
		# Propaga scaling: hp_mult/damage_mult da wave + bônus progressivo da horda.
		if "max_hp" in minion:
			minion.max_hp = float(minion.max_hp) * hp_mult * horde_hp_mult
		if "damage_mult" in minion:
			minion.damage_mult = damage_mult * horde_dmg_mult
		# Minions invocados pelo boss não dropam gold/heart — único drop da
		# wave 7 vem do próprio boss ao morrer.
		if "gold_drop_chance" in minion:
			minion.gold_drop_chance = 0.0
		if "heart_scene" in minion:
			minion.heart_scene = null
		_get_world().add_child(minion)
		minion.global_position = pos
		# Marca como minion do boss pra _update_state contar.
		minion.add_to_group("boss_minion")
		_minions.append(minion)
	# Volta a SHIELDED no próximo _update_state (já que _minions foi populado).
	sprite.play("defense")


# A summon_effect.tscn foi recolorida pra verde (paleta do summoner mage).
# Pro boss queremos roxo (paleta original) — usa modulate >1 nos canais R/B
# pra deslocar a base verde (~0.55, 0.95, 0.45) pra roxo (~0.78, 0.55, 0.95).
const SUMMON_FX_PURPLE_TINT: Color = Color(1.42, 0.56, 2.1, 1.0)


func _play_summon_sound() -> void:
	if summon_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = summon_sound
	p.volume_db = summon_sound_volume_db
	add_child(p)
	# play(from_position) começa do segundo X — pula a intro silenciosa.
	p.play(SUMMON_SOUND_START)
	# Corta no segundo SUMMON_SOUND_END do áudio (tempo real = end - start).
	var play_duration: float = maxf(SUMMON_SOUND_END - SUMMON_SOUND_START, 0.1)
	get_tree().create_timer(play_duration).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.stop()
			p.queue_free()
	)


func _tint_summon_effect_purple(fx: Node2D) -> void:
	if fx == null:
		return
	# modulate é multiplicativo — vale tanto pros Polygon2D quanto pro
	# PointLight2D do BurstLight. Aplica no root, propaga pra todos os filhos.
	fx.modulate = SUMMON_FX_PURPLE_TINT


# ---------- Damage / morte ----------

func take_damage(amount: float) -> void:
	# SHIELDED: ignora completamente o dano. Só mostra um pequeno flash branco
	# pra dar feedback de "tem shield".
	if _is_shielded:
		_flash_shielded()
		return
	# VULNERABLE: aceita dano normal.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("notify_damage_dealt"):
		p.notify_damage_dealt(amount)
	hp = maxf(hp - amount, 0.0)
	if hp_bar != null and hp_bar.has_method("set_ratio"):
		hp_bar.set_ratio(hp / max_hp if max_hp > 0.0 else 0.0)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	_play_damage_sound()
	if hp <= 0.0:
		_die()


func _die() -> void:
	# Mata todos os minions pra wave acabar limpo.
	for m in _minions:
		if is_instance_valid(m) and m.has_method("take_damage"):
			m.take_damage(99999.0)
	# Drops generosos.
	if gold_scene != null and gold_drop_chance > 0.0:
		GoldDrop.try_drop(_get_world(), gold_scene, global_position,
			gold_drop_chance, gold_drop_min, gold_drop_max)
	if heart_scene != null:
		HeartDrop.try_drop(_get_world(), heart_scene, global_position)
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("notify_enemy_killed"):
		p.notify_enemy_killed()
	# Notifica boss kill — adiciona "mage_monkey" ao set persistente no death,
	# usado pra desbloquear a skin Bluey (SKIN_QUESTS type=boss_killed).
	if p != null and p.has_method("notify_boss_killed"):
		p.notify_boss_killed("mage_monkey")
	# Avisa o wave_manager pra segurar o fim da wave 2s extras (boss_kill_hold)
	# pras moedas dropadas saltarem/ficarem visíveis e o player coletar.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("notify_boss_died"):
		wm.notify_boss_died()
	_spawn_kill_effect()
	_spawn_death_silhouette()
	queue_free()


# ---------- Helpers ----------

func _clear_capivara_mushrooms() -> void:
	# Remove TODOS os cogumelos da Capivara Joe do mapa — boss fight rola sem
	# buff/dano residual no chão. Cogumelos novos podem ser spawnados depois
	# pela própria capivara aliada se o player tiver, mas a tela começa limpa.
	for m in get_tree().get_nodes_in_group("capivara_mushroom"):
		if is_instance_valid(m):
			m.queue_free()


# ---------- Visuais / sons ----------

func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.6, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.22)


func _flash_shielded() -> void:
	# Feedback sutil quando atacado com shield: tinta cyan/branco rápido.
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.4, 1.4, 1.8, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.15)


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
	if "amount" in num:
		num.amount = int(round(amount))
	num.position = global_position + Vector2(0, -56)
	get_tree().current_scene.add_child(num)


func _play_damage_sound() -> void:
	if damage_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = damage_sound
	p.volume_db = damage_sound_volume_db
	p.pitch_scale = randf_range(0.92, 1.08)
	add_child(p)
	p.play()
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	# Boss morreu: spawna várias kill effects pra dramatizar.
	for i in 4:
		var fx := kill_effect_scene.instantiate()
		_get_world().add_child(fx)
		var off := Vector2(randf_range(-32.0, 32.0), randf_range(-50.0, -12.0))
		fx.global_position = global_position + off
		if fx is Node2D:
			(fx as Node2D).scale = Vector2.ONE * randf_range(1.1, 1.6)


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
	ghost.modulate.a = 0.7
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, death_silhouette_duration)
	t.tween_callback(ghost.queue_free)


# ---------- CC handlers (no-op, boss é imune) ----------

func apply_knockback(_dir: Vector2, _strength: float) -> void:
	pass


func apply_stun(_duration: float) -> void:
	pass


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene
