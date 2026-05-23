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
@export var patrol_speed: float = 75.0
@export var patrol_y: float = 0.0  # bem alto no mapa pra lançar tudo pra baixo
@export var patrol_x_min: float = 60.0
@export var patrol_x_max: float = 460.0
# Tempo parado nos extremos antes de inverter — janela onde player pode mirar.
@export var edge_pause: float = 0.6
# Duração em que boss fica PARADA enquanto casta um poder (telegraph corporal).
@export var cast_pause_duration: float = 1.2

# === Sistema de poderes (pesos táticos) ===
# Boss escolhe um poder a cada `power_cooldown` segundos. Pesos por poder
# variam com a situação (ex: poucas roses → summon prioritário).
# Range maior pra variação de ritmo (~4-7s) — poderes não saem em cadência
# fixa, dá sensação de aleatoriedade orgânica. Overlap ainda acontece porque
# smoke dura 5s e vines duram 6s.
@export var power_cooldown_min: float = 4.0
@export var power_cooldown_max: float = 7.0
# Delay inicial antes do primeiro poder (deixa player se posicionar).
@export var initial_attack_delay: float = 4.0
# Primeiro cast SEMPRE invocação com count especial pra encher o mapa
# com mobs logo de cara. Depois o sistema de pesos toma conta.
@export var initial_summon_count: int = 6

# === Summon de Rosa Monstro ===
@export var rose_monster_scene: PackedScene
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

# IDs dos poderes (constantes pra referência consistente)
const POWER_SUMMON: String = "summon"
const POWER_SMOKE: String = "smoke"
const POWER_VINES: String = "vines"

# Sons dos poderes — load() lazy pra tolerar mp3 sem .import.
const SUMMON_SOUND_PATH: String = "res://assets/enemies/duskrose/cast rosa monstro.mp3"
const VINE_SOUND_PATH: String = "res://assets/enemies/duskrose/vinhas espinhocas cast or hit.mp3"
const SHIELD_SOUND_PATH: String = "res://assets/enemies/duskrose/cast shield.mp3"
@export var summon_sound_volume_db: float = -20.0
@export var vine_sound_volume_db: float = -8.0
@export var shield_sound_volume_db: float = -10.0

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
	_play_one_shot(load(SHIELD_SOUND_PATH) as AudioStream, global_position, shield_sound_volume_db)


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

	# Shield tick: ativo decrementa, ao zerar desliga shield + reset cd.
	# Quando inativo, cd ticks até zerar, daí ativa shield.
	if _shield_active:
		_shield_remaining = maxf(_shield_remaining - delta, 0.0)
		if _shield_remaining <= 0.0:
			_deactivate_shield()
	else:
		_shield_cd_remaining = maxf(_shield_cd_remaining - delta, 0.0)
		if _shield_cd_remaining <= 0.0:
			_activate_shield()

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
		velocity = Vector2(_direction * patrol_speed, 0.0)
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
		else:
			var power_id: String = _pick_next_power()
			_cast_power(power_id)
			_last_power = power_id
		_cast_remaining = cast_pause_duration  # boss para imediatamente após cast
		_power_cd = randf_range(power_cooldown_min, power_cooldown_max)


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


func _compute_power_weights() -> Dictionary:
	# Pesos base: cada poder começa com 1.0. Modificadores aplicados conforme estado.
	# Adicione novos poderes aqui quando o sprite/sistema estiver pronto.
	var weights: Dictionary = {
		POWER_SUMMON: 1.0,
		POWER_SMOKE: 1.0,
		POWER_VINES: 1.0,
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


func _spawn_one_vine(world: Node, vx: float) -> void:
	var vine: Node2D = vine_scene.instantiate()
	# Propaga damage_mult da boss pro tick de dano da vinha.
	if "damage_mult" in vine:
		vine.damage_mult = damage_mult
	# Target Y final (até onde a vinha cresce).
	if "target_bottom_y" in vine:
		vine.target_bottom_y = vine_target_bottom_y
	world.add_child(vine)
	# Spawn em Y FIXO (topo do mapa), não na posição da boss — a vinha cobre
	# a coluna vertical inteira do mapa independente de onde a boss está.
	vine.global_position = Vector2(vx, vine_top_y)


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
	# Glass shield ativo: reduz dano em `shield_damage_reduction` (80% default,
	# então só 20% do dano passa). Notify_damage_dealt usa o valor REDUZIDO
	# pra estatística refletir o que realmente saiu do HP.
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
		# Avisa wave_manager pra fazer cleanup/magnet de fim de wave.
		var wm := get_tree().get_first_node_in_group("wave_manager")
		if wm != null and wm.has_method("notify_boss_died"):
			wm.notify_boss_died()
		_drop_gold()
		_spawn_kill_effect()
		_spawn_death_silhouette()
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
