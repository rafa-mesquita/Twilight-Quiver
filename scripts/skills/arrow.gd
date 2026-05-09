extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: float = 25.0
@export var trail_max_points: int = 10
@export var hit_effect_scene: PackedScene
@export var stick_surface_duration: float = 7.5
@export var stick_enemy_duration: float = 2.0
@export var fade_duration: float = 0.5
@export var stick_pullback: float = 5.0
@export var impact_sound: AudioStream
@export var object_impact_sound: AudioStream
@export var sound_volume_db: float = -12.0
@export var knockback_strength: float = 80.0

@onready var trail: Line2D = get_node_or_null("Trail")
@onready var shoot_sound: AudioStreamPlayer2D = get_node_or_null("ShootSound")

var direction: Vector2 = Vector2.RIGHT
var is_stuck: bool = false
# Flecha perfurante: atravessa todos os inimigos E objetos sem cravar.
# Setado pelo player ANTES de add_child quando proca (a cada 3 ataques).
var is_piercing: bool = false
var hitbox_scale: float = 1.0  # > 1 aumenta colisão e sprite (level 2+ da perfuração)
# Multi Arrow: só a flecha principal da volley toca o som de tiro pra evitar
# acúmulo de db quando múltiplas flechas saem juntas. Setado pelo player.
var play_shoot_sound: bool = true
# Cadeia de Raios: setado pelo player ANTES de add_child. Quando > 0, a flecha
# procca raios em N inimigos próximos ao acertar um inimigo válido.
var chain_count: int = 0
var chain_dmg_pct: float = 0.0
# Chance [0..1] de cadeiar num alvo adicional além dos `chain_count` garantidos
# (usado no lv2 da cadeia, que tem 30% de chance de pegar um 3º inimigo).
var chain_bonus_chance: float = 0.0
# Elemental Fogo: visual vermelho/animado + aplica BurnDoT em inimigos.
# Setado pelo player ANTES de add_child quando has_fire_arrow.
var is_fire: bool = false
var burn_dps: float = 5.0
var burn_duration: float = 3.0
var burn_final_bonus: float = 0.0  # dano extra no fim do burn (último tick)
# Elemental Maldição: visual roxo + aplica CurseDebuff (slow + DoT toxic) em inimigos.
# Setado pelo player ANTES de add_child quando curse_arrow_level > 0.
var is_curse: bool = false
var curse_dps: float = 4.0
var curse_duration: float = 4.0
var curse_slow_factor: float = 0.65  # 0.65 = 35% slow no inimigo
# Flecha de Ricochete: setado pelo player ANTES de add_child quando ricochet
# proca (cada 3 ataques no L1, cada 2 no L2+). Ao bater em inimigo, em vez de
# cravar, redireciona pra inimigo aleatório próximo. Pode dividir em 2 (L2+/L4).
var is_ricochet: bool = false
var ricochet_hops_remaining: int = 0   # quantos ricochetes ainda pode fazer
var ricochet_splits_remaining: int = 0  # de quantos ricochetes ainda divide em 2
const RICOCHET_RADIUS: float = 220.0
const RICOCHET_PUSH: float = 12.0  # empurra a flecha pra fora do alvo após ricochete
const RICOCHET_DAMAGE_FALLOFF: float = 0.80  # cada ricochete corta 20% do dano
# Graviton: setado pelo player quando o counter procca (a cada 3 ataques no L1,
# a cada 2 no L2+). Ao bater em enemy/objeto, spawna um GravitonPulse no ponto
# de impacto. Combina com perfuração: pulso é gerado em CADA objeto atravessado
# e em CADA inimigo morto pela passagem da flecha (spec do excalidraw).
var is_graviton: bool = false
var graviton_radius: float = 60.0
var graviton_lifetime: float = 3.0
var graviton_slow_factor: float = 0.7
var graviton_explosion_damage: float = 0.0
const GRAVITON_PULSE_SCENE: PackedScene = preload("res://scenes/skills/graviton_pulse.tscn")
# Fogo lv2: rastro de chamas no caminho da flecha (DPS area).
var fire_trail_enabled: bool = false
var fire_trail_dps: float = 4.0
var fire_trail_scale: float = 1.0  # lv4 do Fogo aumenta a área dos segmentos
const FIRE_TRAIL_SCENE: PackedScene = preload("res://scenes/skills/fire_trail.tscn")
const FIRE_TRAIL_SPACING: float = 18.0
# Delay inicial pro rastro não sair colado na flecha — dá um espaço entre o
# muzzle e o primeiro segmento, fica mais natural.
const FIRE_TRAIL_START_DELAY: float = 0.08
var _fire_trail_last_pos: Vector2 = Vector2.ZERO
var _fire_trail_initialized: bool = false
var _fire_trail_delay_remaining: float = FIRE_TRAIL_START_DELAY
const CHAIN_RADIUS: float = 85.0
const CHAIN_SOUND: AudioStream = preload("res://audios/upgrades/cadeia de raios/Cadeia de raios effect.mp3")
const CHAIN_SOUND_THROTTLE_MS: int = 80
const CHAIN_SOUND_VOLUME_DB: float = -10.0
# Throttle global do som de chain — várias flechas (multi arrow) podem proccar
# no mesmo frame e somar dB. Compartilhado entre todas as instâncias da arrow.
static var _last_chain_sound_msec: int = -1000
# Quem disparou a flecha. Usado pra ignorar colisão com o próprio shooter
# (ex: torre não atira em si mesma, mas colide com flecha do player).
var source: Node = null
var _hit_bodies: Array[Node] = []
var _pierce_hits: int = 0  # quantos targets a flecha perfurante já atravessou
# Multiplicador de dano aplicado SÓ no primeiro alvo (perfuracao bonus). 2º
# alvo leva dano cheio, 3º+ leva PIERCE_LATE_DMG_MULT do dano base.
var pierce_first_dmg_mult: float = 1.0
const PIERCE_LATE_DMG_MULT: float = 0.85


func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_hit)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)
	# Defer pra detachar/tocar o som DEPOIS do spawner setar a posição da flecha.
	if shoot_sound != null:
		if play_shoot_sound:
			_setup_shoot_sound.call_deferred()
		else:
			shoot_sound.queue_free()
	if is_piercing:
		_apply_piercing_visuals()
	if hitbox_scale != 1.0:
		_apply_hitbox_scale()
	if is_fire:
		_apply_fire_visuals()
	if is_curse:
		_apply_curse_visuals()
	if is_ricochet:
		_apply_ricochet_visuals()


const PIERCING_BASE_SCALE: float = 1.1


func _apply_piercing_visuals() -> void:
	# Tint dourado + trail laranja + sprite/trail 1.1× pra destacar.
	var sprite_node := get_node_or_null("Sprite2D")
	if sprite_node is CanvasItem:
		(sprite_node as CanvasItem).modulate = Color(1.7, 1.25, 0.45, 1.0)
	if sprite_node is Node2D:
		(sprite_node as Node2D).scale = Vector2.ONE * PIERCING_BASE_SCALE
	if trail != null:
		trail.default_color = Color(1.0, 0.7, 0.2, 1.0)
		trail.width *= PIERCING_BASE_SCALE


func _try_spawn_fire_trail() -> void:
	# Spawna 1 segmento na primeira chamada e depois 1 a cada FIRE_TRAIL_SPACING
	# px percorridos. Cada segmento tem seu próprio lifetime/fade independente,
	# então o primeiro spawnado é o primeiro a sumir (fade gradual ao longo do
	# caminho).
	if not _fire_trail_initialized:
		_fire_trail_initialized = true
		_fire_trail_last_pos = global_position
		_spawn_fire_trail_segment()
		return
	if global_position.distance_to(_fire_trail_last_pos) >= FIRE_TRAIL_SPACING:
		_fire_trail_last_pos = global_position
		_spawn_fire_trail_segment()


func _spawn_fire_trail_segment() -> void:
	if FIRE_TRAIL_SCENE == null:
		return
	var seg: Node = FIRE_TRAIL_SCENE.instantiate()
	if "damage_per_second" in seg:
		seg.damage_per_second = fire_trail_dps
	_get_world().add_child(seg)
	if seg is Node2D:
		var s2d: Node2D = seg
		s2d.global_position = global_position
		if not is_equal_approx(fire_trail_scale, 1.0):
			s2d.scale = Vector2(fire_trail_scale, fire_trail_scale)


func _apply_fire_visuals() -> void:
	# Esconde sprite normal, mostra a flecha de fogo animada, e troca o gradient
	# do trail por um suave 4-stop fogo (transparente→vermelho→laranja→amarelo)
	# pra ficar smooth ao invés de cor sólida abrupta.
	var normal_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if normal_sprite != null:
		normal_sprite.visible = false
	var fire_sprite := get_node_or_null("FireSprite") as AnimatedSprite2D
	if fire_sprite != null:
		fire_sprite.visible = true
		fire_sprite.modulate = Color.WHITE
	if trail != null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
		grad.colors = PackedColorArray([
			Color(0.85, 0.18, 0.10, 0.0),  # tail: vermelho-escuro transparente
			Color(0.95, 0.30, 0.15, 0.55), # core: vermelho
			Color(1.00, 0.55, 0.20, 0.85), # mid: laranja
			Color(1.00, 0.85, 0.35, 0.95)  # head: amarelo-laranja brilhante
		])
		trail.gradient = grad
		trail.default_color = Color.WHITE  # com gradient, default_color só multiplica
		trail.width = 2.2  # um tico mais grosso pra ficar tipo "glow"


func _apply_ricochet_visuals() -> void:
	# Tint ciano-claro discreto + trail ciano. Não sobrescreve fire/curse —
	# multiplica pra não anular o visual elemental quando combinado.
	var sprite_node := get_node_or_null("Sprite2D") as Sprite2D
	if sprite_node != null:
		var current: Color = sprite_node.modulate
		# Mantém o tom original mas puxa pra ciano (+ no canal B/G).
		sprite_node.modulate = Color(current.r * 0.85, current.g * 1.05, current.b * 1.4, current.a)
	if trail != null and trail.gradient == null:
		# Só sobrescreve trail se ainda não tem gradient elemental (fogo/maldição).
		trail.default_color = Color(0.55, 0.95, 1.0, 0.85)
		trail.width = max(trail.width, 1.8)


func _apply_curse_visuals() -> void:
	# Tinge sprite normal de roxo + trail roxo com gradient suave (transparente
	# → violeta escuro → roxo brilhante). Mantém o sprite original (não swap).
	# Compatível com piercing — multiplica o modulate em vez de sobrescrever.
	var normal_sprite := get_node_or_null("Sprite2D") as Sprite2D
	if normal_sprite != null:
		# Se já tem tint dourado do piercing, mistura — mas pra clareza visual
		# da maldição, força o roxo (piercing curse = ainda visual de maldição).
		normal_sprite.modulate = Color(1.5, 0.7, 1.8, 1.0)
	if trail != null:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.4, 0.75, 1.0])
		grad.colors = PackedColorArray([
			Color(0.30, 0.05, 0.45, 0.0),  # tail: roxo-escuro transparente
			Color(0.45, 0.15, 0.70, 0.55), # core: violeta
			Color(0.70, 0.30, 1.00, 0.85), # mid: roxo brilhante
			Color(0.90, 0.65, 1.00, 0.95)  # head: lavanda clara
		])
		trail.gradient = grad
		trail.default_color = Color.WHITE
		trail.width = 2.2


func _apply_hitbox_scale() -> void:
	# Multiplica sobre o scale base do piercing (1.1) se já foi aplicado.
	var col := get_node_or_null("CollisionShape2D")
	if col is Node2D:
		(col as Node2D).scale = Vector2(hitbox_scale, hitbox_scale)
	var sprite_node := get_node_or_null("Sprite2D")
	if sprite_node is Node2D:
		var current: Vector2 = (sprite_node as Node2D).scale
		(sprite_node as Node2D).scale = current * hitbox_scale


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)


func _physics_process(delta: float) -> void:
	if is_stuck:
		return
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)
	if fire_trail_enabled:
		if _fire_trail_delay_remaining > 0.0:
			_fire_trail_delay_remaining -= delta
		else:
			_try_spawn_fire_trail()


func _on_hit(body: Node) -> void:
	if is_stuck:
		return
	# Ignora colisão SÓ com o próprio shooter (ex: flecha da torre passa pela torre).
	# Outras flechas (ex: do player) colidem normalmente com aliados.
	if source != null and _is_descendant_of(body, source):
		return
	# Evita re-acertar o mesmo body enquanto perfurando.
	if body in _hit_bodies:
		return
	_hit_bodies.append(body)

	# Sobe o parent chain pra achar quem tem take_damage — o body que entra na
	# colisão pode ser um StaticBody2D filho (caso da torre).
	var target: Node = _find_damageable(body)
	# Aliado móvel (woodwarden tem "tank_ally"): flecha passa silenciosa pra não
	# atrapalhar mira do player em inimigos atrás dele.
	if target != null and target.is_in_group("tank_ally"):
		_hit_bodies.erase(body)
		return
	# Estrutura estática aliada (torre tem "structure" + "ally" mas NÃO tank_ally):
	# bloqueia flecha como parede (não causa dano).
	if target != null and target.is_in_group("structure"):
		_play_oneshot(object_impact_sound, global_position, sound_volume_db, 0.7)
		# Graviton: pulso ao bater na estrutura. Com perfuração também procca em
		# cada estrutura atravessada (a flecha continua e pode bater em outra).
		if is_graviton:
			_spawn_graviton_pulse()
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		# Ricochete em estrutura: redireciona pra próximo enemy (igual em walls).
		if is_ricochet and ricochet_hops_remaining > 0:
			if _perform_ricochet(target):
				return
		_stick_in_place(stick_surface_duration)
		return
	# Outros aliados (futuros, ex: aliados convertidos pela maldição): passa também.
	if target != null and target.is_in_group("ally"):
		_hit_bodies.erase(body)
		return
	if target != null:
		# Aplica curse ANTES do take_damage — se o dano matar, o try_convert_on_death
		# precisa enxergar o CurseDebuff anexado pra rolar a chance de virar aliado.
		# Burn pode ficar antes ou depois (não tem mecânica de conversão).
		if is_curse:
			_apply_curse_to(target)
		# Curva de dano da perfuração:
		#   1º alvo  → damage * pierce_first_dmg_mult (bonus do upgrade)
		#   2º alvo  → damage cru (100%)
		#   3º+ alvo → damage × 0.85 (-15% por atravessar muita gente)
		var dmg_to_apply: float = damage
		if _pierce_hits == 0:
			dmg_to_apply *= pierce_first_dmg_mult
		elif _pierce_hits >= 2:
			dmg_to_apply *= PIERCE_LATE_DMG_MULT
		# Sinaliza pro stone_cube que esse hit é de flecha (cancela ataque dele).
		# Ticks/aliados/estruturas não setam o flag e não cancelam.
		if target.is_in_group("stone_cube"):
			target._arrow_hit_flag = true
		target.take_damage(dmg_to_apply)
		if target.has_method("apply_knockback"):
			target.apply_knockback(direction, knockback_strength)
		_play_oneshot(impact_sound, global_position, sound_volume_db, 0.7)
		_proc_chain_lightning(target)
		if is_fire and is_instance_valid(target):
			_apply_burn_to(target)
		# Graviton: pulso no ponto de impacto. Com perfuração: spawna apenas se o
		# enemy morreu nesse hit (spec — "inimigos que morrerem"). Sem perfuração:
		# spawna sempre que cravar (caso normal abaixo, antes do _stick_in_body).
		if is_graviton:
			if is_piercing:
				if not is_instance_valid(target) or (("hp" in target) and float(target.hp) <= 0.0):
					_spawn_graviton_pulse()
			else:
				_spawn_graviton_pulse()
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		# Ricochete: redireciona pra próximo alvo em vez de cravar. Se não acha
		# candidato, fallback pra stick normal.
		if is_ricochet and ricochet_hops_remaining > 0:
			if _perform_ricochet(target):
				return
		_stick_in_body(body, stick_enemy_duration)
	else:
		# Superfície sólida sem take_damage (parede, tronco).
		_play_oneshot(object_impact_sound, global_position, sound_volume_db, 0.7)
		# Graviton: pulso ao bater na parede. Com perfuração, procca em CADA
		# objeto atravessado (flecha continua viva).
		if is_graviton:
			_spawn_graviton_pulse()
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		# Ricochete em parede/objeto: redireciona pra próximo enemy.
		if is_ricochet and ricochet_hops_remaining > 0:
			if _perform_ricochet(null):
				return
		_stick_in_place(stick_surface_duration)


func _stick_in_place(visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	# Z-index direcional: se a flecha voava p/ sul (bateu na parede NORTE do objeto),
	# fica atrás. Se voava p/ norte ou lateral (bateu na parede sul/leste/oeste),
	# fica na frente do objeto. Threshold 0.5 = mais de ~30° de inclinação sul.
	if direction.y > 0.5:
		pass  # mantém z_index = -1 do voo (atrás)
	else:
		z_index = 1  # na frente
	# Recua na direção oposta ao movimento pra:
	# 1. A flecha ficar "encostada" na superfície em vez de enterrada
	# 2. Garantir que arrow.y fique consistentemente do lado certo do alvo pro y-sort
	position -= direction * stick_pullback
	_schedule_fade_out(visible_duration)


func _stick_in_body(body: Node, visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	z_index = 1
	# Defer reparent pra evitar mexer na árvore de cenas durante callback de física.
	_reparent_to.call_deferred(body)
	_schedule_fade_out(visible_duration)


func _begin_stick() -> void:
	is_stuck = true
	set_deferred("monitoring", false)
	if trail != null:
		trail.clear_points()


func _reparent_to(new_parent: Node) -> void:
	if not is_inside_tree() or not is_instance_valid(new_parent) or not new_parent.is_inside_tree():
		return
	var gp := global_position
	var gr := global_rotation
	var current_parent := get_parent()
	if current_parent != null:
		current_parent.remove_child(self)
	new_parent.add_child(self)
	global_position = gp
	global_rotation = gr


func _schedule_fade_out(visible_duration: float) -> void:
	var t := create_tween()
	t.tween_interval(visible_duration)
	t.tween_property(self, "modulate:a", 0.0, fade_duration)
	t.tween_callback(_die)


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var n: Node = node
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.has_method("take_damage"):
			return n
		n = n.get_parent()
	return null


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position


# Efeito específico de perfuração. No 3º hit, fica maior e dourado pra
# sinalizar que foi uma perfuração "potente".
func _spawn_pierce_hit_effect(is_third: bool) -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position
	if is_third and fx is Node2D:
		var fx2d: Node2D = fx
		fx2d.scale = Vector2(2.2, 2.2)
		fx2d.modulate = Color(1.6, 1.1, 0.3, 1.0)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_lifetime_expired() -> void:
	# Se já cravou, ignora — o stick timer cuida da remoção.
	if not is_stuck:
		_die()


func _die() -> void:
	if is_inside_tree():
		queue_free()


func _setup_shoot_sound() -> void:
	if shoot_sound == null or not is_instance_valid(shoot_sound):
		return
	if shoot_sound.get_parent() != self:
		return  # já foi detachado
	# Salva posição (já setada pelo spawner agora) e detacha pro World.
	var sound_global_pos: Vector2 = shoot_sound.global_position
	remove_child(shoot_sound)
	_get_world().add_child(shoot_sound)
	shoot_sound.global_position = sound_global_pos
	shoot_sound.volume_db = sound_volume_db
	shoot_sound.play()
	# Lambda captura o ref direto — sobrevive mesmo se a flecha for liberada cedo
	# (ex: inimigo morre e a flecha some como filha dele antes dos 0.7s).
	var sound_ref: AudioStreamPlayer2D = shoot_sound
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(sound_ref):
			sound_ref.stop()
			sound_ref.queue_free()
	)


func _apply_burn_to(target: Node) -> void:
	# Re-aplica DoT existente (refresh duration) ou cria novo BurnDoT como child.
	for child in target.get_children():
		if child is BurnDoT:
			(child as BurnDoT).refresh(burn_duration, burn_dps)
			# Atualiza bonus final pro maior valor (mesma lógica do dps).
			if burn_final_bonus > (child as BurnDoT).final_bonus_damage:
				(child as BurnDoT).final_bonus_damage = burn_final_bonus
			return
	var dot := BurnDoT.new()
	dot.dps = burn_dps
	dot.duration = burn_duration
	dot.final_bonus_damage = burn_final_bonus
	target.add_child(dot)


func _apply_curse_to(target: Node) -> void:
	# Re-aplica debuff existente (refresh) ou cria novo CurseDebuff como child.
	# Inimigo precisa ter `speed` pra slow funcionar (todos têm); take_damage pro DoT.
	for child in target.get_children():
		if child is CurseDebuff:
			(child as CurseDebuff).refresh(curse_duration, curse_dps, curse_slow_factor)
			return
	var deb := CurseDebuff.new()
	deb.dps = curse_dps
	deb.duration = curse_duration
	deb.slow_factor = curse_slow_factor
	target.add_child(deb)


func _perform_ricochet(hit_target: Node = null) -> bool:
	# Chamado depois de aplicar dano/efeitos. Encontra próximo enemy aleatório
	# no raio (excluindo já hitados), spawna clone se splits disponíveis, e
	# redireciona ESTA flecha pro alvo. `hit_target` pode ser null (ricochete
	# em parede/objeto sem damageable). Retorna false se não há candidatos.
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if hit_target != null and e == hit_target:
			continue
		if e in _hit_bodies:
			continue
		if not e.has_method("take_damage"):
			continue
		if e.is_queued_for_deletion():
			continue
		if "hp" in e and float(e.hp) <= 0.0:
			continue
		# Limita ao raio — sem isso ricochete vira aimbot global.
		if (e as Node2D).global_position.distance_squared_to(global_position) > RICOCHET_RADIUS * RICOCHET_RADIUS:
			continue
		candidates.append(e)
	# Sem inimigos no raio — ricochete vai pra direção aleatória (mas ainda
	# consome o hop, pra evitar voar pelo mapa todo procurando alvo).
	var new_dir: Vector2
	var primary: Node2D = null
	var secondary: Node2D = null
	var will_split: bool = ricochet_splits_remaining > 0
	if candidates.is_empty():
		# Direção aleatória dentro de ±150° da direção atual (mais natural que
		# 360° puro — flecha não dá ré completa).
		var random_angle: float = randf_range(-2.6, 2.6)
		new_dir = direction.rotated(random_angle)
		# Sem alvos = sem split (não tem clone pra spawnar nem alvo pro split).
		will_split = false
	else:
		candidates.shuffle()
		primary = candidates[0] as Node2D
		new_dir = (primary.global_position - global_position).normalized()
		if will_split:
			secondary = (candidates[1] as Node2D) if candidates.size() >= 2 else primary
	var new_hops: int = ricochet_hops_remaining - 1
	var new_splits: int = maxi(ricochet_splits_remaining - (1 if will_split else 0), 0)
	# Damage falloff: cada ricochete corta 20% do dano. Aplica ANTES de spawnar
	# o clone — clone herda o dano já reduzido (ele "nasce" do ricochete, então
	# também perdeu 20% do dano original).
	damage *= RICOCHET_DAMAGE_FALLOFF
	if will_split and secondary != null:
		_spawn_ricochet_clone(secondary, new_hops, new_splits)
	ricochet_hops_remaining = new_hops
	ricochet_splits_remaining = new_splits
	if new_dir.length() < 0.01:
		return false
	# Visual: ring ciano no ponto de impacto (claro pra ver que ricocheteou).
	_spawn_ricochet_hit_effect()
	# "Salto" — empurra a flecha pra fora do alvo na nova direção, pra evitar
	# que ela continue colidindo com o body atual e perca tempo voltando.
	# Sem isso, ela demora 2-3 frames dentro do enemy antes de sair, fica feio.
	global_position += new_dir * RICOCHET_PUSH
	direction = new_dir
	rotation = direction.angle()
	# Limpa trail pra novo segmento sair limpo da posição atual.
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)
	return true


func _spawn_graviton_pulse() -> void:
	if GRAVITON_PULSE_SCENE == null:
		return
	var pulse: Node = GRAVITON_PULSE_SCENE.instantiate()
	if "radius" in pulse:
		pulse.radius = graviton_radius
	if "lifetime" in pulse:
		pulse.lifetime = graviton_lifetime
	if "slow_factor" in pulse:
		pulse.slow_factor = graviton_slow_factor
	if "explosion_damage" in pulse:
		pulse.explosion_damage = graviton_explosion_damage
	if "source" in pulse:
		pulse.source = source
	_get_world().add_child(pulse)
	if pulse is Node2D:
		(pulse as Node2D).global_position = global_position


func _spawn_ricochet_hit_effect() -> void:
	# Ring ciano que expande e fade — feedback visual claro do ricochete.
	var ring := Polygon2D.new()
	var pts := PackedVector2Array()
	var segs: int = 20
	for i in segs:
		var ang: float = TAU * float(i) / float(segs)
		pts.append(Vector2(cos(ang), sin(ang)) * 6.0)
	ring.polygon = pts
	ring.color = Color(0.55, 0.95, 1.0, 0.9)
	ring.global_position = global_position
	ring.z_as_relative = false
	ring.z_index = 5
	_get_world().add_child(ring)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(3.5, 3.5), 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(ring.queue_free)


func _spawn_ricochet_clone(target: Node2D, hops: int, splits: int) -> void:
	# Clone herda dano, fire/curse/chain flags e estado de ricochete reduzido.
	# NÃO toca shoot sound (evita stack de db). NÃO inclui o is_piercing (ricochete
	# e perfuração são exclusivos por design).
	var scene_path: String = scene_file_path
	if scene_path == "":
		return
	var scene := load(scene_path) as PackedScene
	if scene == null:
		return
	var clone: Area2D = scene.instantiate() as Area2D
	if clone == null:
		return
	clone.global_position = global_position
	# Configura ANTES de add_child pra _ready do clone enxergar os flags.
	if "play_shoot_sound" in clone:
		clone.play_shoot_sound = false
	if "damage" in clone:
		clone.damage = damage
	if "is_fire" in clone:
		clone.is_fire = is_fire
		clone.burn_dps = burn_dps
		clone.burn_duration = burn_duration
	if "is_curse" in clone:
		clone.is_curse = is_curse
		clone.curse_dps = curse_dps
		clone.curse_duration = curse_duration
		clone.curse_slow_factor = curse_slow_factor
	if "chain_count" in clone:
		clone.chain_count = chain_count
		clone.chain_dmg_pct = chain_dmg_pct
		clone.chain_bonus_chance = chain_bonus_chance
	if "is_ricochet" in clone:
		clone.is_ricochet = true
		clone.ricochet_hops_remaining = hops
		clone.ricochet_splits_remaining = splits
	if "source" in clone:
		clone.source = source
	_get_world().add_child(clone)
	if clone.has_method("set_direction"):
		var d: Vector2 = (target.global_position - global_position).normalized()
		if d.length() < 0.01:
			d = direction
		clone.set_direction(d)


func _proc_chain_lightning(origin: Node) -> void:
	# Procca quando flecha do player acerta inimigo. Encontra os N inimigos mais
	# próximos no raio, dá dano % e desenha raios. Combos: cada flecha de uma
	# volley multi-arrow procca seu próprio chain (audio é throttled).
	if chain_count <= 0 or chain_dmg_pct <= 0.0:
		return
	if not (origin is Node2D):
		return
	var origin2d: Node2D = origin
	var origin_pos: Vector2 = origin2d.global_position
	var candidates: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if e == origin or not is_instance_valid(e) or not (e is Node2D):
			continue
		if not e.has_method("take_damage"):
			continue
		var d: float = (e as Node2D).global_position.distance_to(origin_pos)
		if d <= CHAIN_RADIUS:
			candidates.append({"node": e, "dist": d})
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])
	var n: int = mini(chain_count, candidates.size())
	# Bônus probabilístico: tenta um alvo extra além dos garantidos (lv2 = 30%).
	if chain_bonus_chance > 0.0 and candidates.size() > n and randf() < chain_bonus_chance:
		n += 1
	var chain_dmg: float = damage * chain_dmg_pct
	for i in n:
		var enemy: Node = candidates[i]["node"]
		if not is_instance_valid(enemy):
			continue
		# Curse ANTES do take_damage — pra try_convert_on_death enxergar o debuff.
		if is_curse:
			_apply_curse_to(enemy)
		enemy.take_damage(chain_dmg)
		if is_fire:
			_apply_burn_to(enemy)
		_spawn_lightning_visual(origin_pos, (enemy as Node2D).global_position)
	_play_chain_sound(origin_pos)


func _spawn_lightning_visual(from: Vector2, to: Vector2) -> void:
	var dir: Vector2 = to - from
	if dir.length() < 0.01:
		return
	var perp: Vector2 = Vector2(-dir.y, dir.x).normalized()
	var line := Line2D.new()
	line.width = 2.5
	# Amarelo elétrico saturado (R/G altos, B baixo) — modulate > 1 pra brilho extra.
	line.default_color = Color(2.2, 1.9, 0.4, 1.0)
	line.z_index = 10
	# Zigue-zague: 7 segmentos com offset perpendicular randômico nos pontos do meio.
	var segments: int = 7
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var p: Vector2 = from.lerp(to, t)
		if i > 0 and i < segments:
			p += perp * randf_range(-7.0, 7.0)
		line.add_point(p)
	_get_world().add_child(line)
	line.global_position = Vector2.ZERO  # add_point usa coords absolutas
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.18)
	tw.tween_callback(line.queue_free)


func _play_chain_sound(pos: Vector2) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_chain_sound_msec < CHAIN_SOUND_THROTTLE_MS:
		return
	_last_chain_sound_msec = now
	var p := AudioStreamPlayer2D.new()
	p.stream = CHAIN_SOUND
	p.volume_db = CHAIN_SOUND_VOLUME_DB
	_get_world().add_child(p)
	p.global_position = pos
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _play_oneshot(stream: AudioStream, pos: Vector2, vol_db: float, max_duration: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = vol_db
	_get_world().add_child(player)
	player.global_position = pos
	player.play()
	if max_duration > 0.0:
		var ref: AudioStreamPlayer2D = player
		get_tree().create_timer(max_duration).timeout.connect(func() -> void:
			if is_instance_valid(ref):
				ref.stop()
				ref.queue_free()
		)
