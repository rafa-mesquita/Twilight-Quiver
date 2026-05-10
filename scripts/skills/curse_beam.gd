extends Node2D

# Raio roxo gigante (skill Q da Maldição lv4). Atravessa o mapa pelos DOIS lados
# do player numa direção fixa. Ignora walls. Damage por tick + CurseDebuff.
#
# **Visual editável na cena** ([scenes/curse_beam.tscn](scenes/curse_beam.tscn)):
#   - GlowUnderlay/{Outer, Mid, Inner} — Polygon2D rectangulares (width 64,
#     scaleados horizontalmente em runtime pelo script). Edita cor/altura
#     direto no editor.
#   - ChargeOrb/{Outer, Mid, Core, Glow} — Polygon2D circulares + PointLight2D.
#     Aparece pulsando girando no warmup. Edita cor/raio direto no editor.
#   - TileTemplate — AnimatedSprite2D template (invisível). Script duplica pra
#     cada posição ao longo do beam. Edita sprite_frames/anim/filter no editor.
#   - LightTemplate — PointLight2D template. Script duplica ao longo do beam.
#     Edita color/texture/scale no editor; energy do template define energia
#     final dos lights spawnados.
#   - BeamSound — AudioStreamPlayer2D com o som do raio. Edita stream/volume
#     no editor; script aciona play+loop ao spawnar.

@export var damage_per_tick: float = 8.0
@export var max_range_per_side: float = 1000.0
@export var curse_dps: float = 8.0
@export var curse_duration: float = 4.0
@export var curse_slow_factor: float = 0.45
@export var hit_radius: float = 33.0
# Offset Y aproximado do "centro do corpo" dos enemies em relação aos pés
# (que é onde global_position está). Usado pro hit check ser feito do corpo,
# não dos pés — assim o player pode mirar no sprite e o beam acerta.
@export var enemy_body_offset: Vector2 = Vector2(0, -12)
@export var lifetime: float = 5.0
@export var warmup_duration: float = 0.85
@export var tick_interval: float = 0.4
@export var fade_duration: float = 1.0  # fade visual + audio nos últimos N segundos
# Tween final pra glow underlay (em fração do warmup_duration × silhouette).
@export var orb_final_scale: Vector2 = Vector2(2.0, 2.0)
# Quando true, o beam vem de um inimigo (ex: boss). Em vez de bater em
# enemies, fere o player + tank_ally + structure. Não aplica curse (curse é
# mecânica do player, não faria sentido enemy converter o player em ally).
@export var is_enemy_source: bool = false
# Offset do "centro do corpo" do player — usado pra hit check fazer mira no
# torso e não nos pés. Diferente de enemy_body_offset porque o player tem
# tamanho próprio.
@export var player_body_offset: Vector2 = Vector2(0, -12)

const FRAME_SIZE: int = 32
const TILE_FADE_IN: float = 0.18
const SILHOUETTE_FRACTION: float = 0.65
const SILHOUETTE_COLOR: Color = Color(0.42, 0.18, 0.62, 1.0)
const FULL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const TILE_FRAME_COUNT: int = 3
# Largura dos polygons do GlowUnderlay no .tscn (edita lá → mantém aqui consistente).
const GLOW_UNDERLAY_BASE_WIDTH: float = 64.0

@onready var beam_sound: AudioStreamPlayer2D = $BeamSound
@onready var glow_underlay: Node2D = $GlowUnderlay
@onready var charge_orb: Node2D = $ChargeOrb
@onready var tile_template: AnimatedSprite2D = $TileTemplate
@onready var light_template: PointLight2D = $LightTemplate

var _player_pos: Vector2 = Vector2.ZERO
var _start: Vector2 = Vector2.ZERO  # ponta de trás
var _end: Vector2 = Vector2.ZERO  # ponta da frente
var _direction: Vector2 = Vector2.RIGHT
var _warmup_remaining: float = 0.0
var _active_remaining: float = 0.0
var _tick_accum: float = 0.0
var _beam_sound_initial_db: float = -10.0  # capturado no _ready do volume seteado no .tscn


func setup(player_pos: Vector2, dir: Vector2) -> void:
	# Setup é chamado pelo player APÓS add_child — _ready já rodou e os @onready
	# estão prontos. Build_visual fica aqui pra usar a direção/posição corretas
	# (no _ready elas ainda estão nos defaults).
	_player_pos = player_pos
	_direction = dir.normalized()
	_start = _player_pos - _direction * max_range_per_side
	_end = _player_pos + _direction * max_range_per_side
	_build_visual()


func _ready() -> void:
	_warmup_remaining = warmup_duration
	_active_remaining = lifetime
	_start_beam_loop_sound()


func _start_beam_loop_sound() -> void:
	if beam_sound == null or beam_sound.stream == null:
		return
	_beam_sound_initial_db = beam_sound.volume_db
	# Loop via re-play no signal `finished` — funciona com qualquer AudioStream.
	beam_sound.finished.connect(beam_sound.play)
	beam_sound.play()


func _process(delta: float) -> void:
	# Fase WARMUP: sem damage.
	if _warmup_remaining > 0.0:
		_warmup_remaining -= delta
		return
	# Fase ACTIVE.
	_active_remaining -= delta
	if _active_remaining <= 0.0:
		queue_free()
		return
	# Fase FADE — visual + áudio fade out juntos nos últimos `fade_duration` seg.
	if _active_remaining < fade_duration:
		var fade_t: float = clampf(_active_remaining / fade_duration, 0.0, 1.0)
		modulate.a = fade_t
		# Som: lerp do volume original (do .tscn) → -60dB (praticamente inaudível).
		if beam_sound != null and is_instance_valid(beam_sound):
			beam_sound.volume_db = lerp(-60.0, _beam_sound_initial_db, fade_t)
	_tick_accum += delta
	while _tick_accum >= tick_interval:
		_tick_accum -= tick_interval
		_apply_tick()


func _apply_tick() -> void:
	var dir: Vector2 = _direction
	var beam_len: float = _start.distance_to(_end)
	# Lista de alvos: player + ally + structure quando vem de inimigo, senão
	# todos os enemies (skill do player).
	var targets: Array = []
	var apply_curse_on_hit: bool = true
	if is_enemy_source:
		apply_curse_on_hit = false  # boss não aplica curse no player
		var p := get_tree().get_first_node_in_group("player")
		if p != null and is_instance_valid(p):
			targets.append(p)
		for t in get_tree().get_nodes_in_group("tank_ally"):
			targets.append(t)
		for s in get_tree().get_nodes_in_group("structure"):
			targets.append(s)
	else:
		targets = get_tree().get_nodes_in_group("enemy")
	for e in targets:
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if not e.has_method("take_damage"):
			continue
		# Hit check no centro do corpo (não nos pés). Player tem offset diferente
		# de enemies por ter tamanho/altura próprios.
		var body_offset: Vector2 = player_body_offset if (e as Node).is_in_group("player") else enemy_body_offset
		var target_pos: Vector2 = (e as Node2D).global_position + body_offset
		var rel: Vector2 = target_pos - _start
		var along: float = rel.dot(dir)
		if along < 0.0 or along > beam_len:
			continue
		var perp: float = absf(rel.x * dir.y - rel.y * dir.x)
		if perp > hit_radius:
			continue
		# Curse ANTES do take_damage — pra try_convert_on_death enxergar o debuff
		# se o tick matar o enemy. Pulado quando boss é o source.
		if apply_curse_on_hit:
			_apply_curse_to(e)
		e.take_damage(damage_per_tick)


func _apply_curse_to(target: Node) -> void:
	for child in target.get_children():
		if child is CurseDebuff:
			(child as CurseDebuff).refresh(curse_duration, curse_dps, curse_slow_factor)
			return
	var deb := CurseDebuff.new()
	deb.dps = curse_dps
	deb.duration = curse_duration
	deb.slow_factor = curse_slow_factor
	target.add_child(deb)


func _build_visual() -> void:
	# Rota o root pra alinhar com a direção. Origem do root = posição do player.
	position = _player_pos
	rotation = _direction.angle()
	var num_per_side: int = int(ceilf(max_range_per_side / float(FRAME_SIZE)))
	var silhouette_phase: float = warmup_duration * SILHOUETTE_FRACTION
	var animate_phase: float = warmup_duration - silhouette_phase
	var stagger_step: float = 0.0
	if num_per_side > 1:
		stagger_step = (silhouette_phase - TILE_FADE_IN) / float(num_per_side - 1)
	stagger_step = maxf(stagger_step, 0.0)
	# Glow underlay: estica pra cobrir todo o beam (polygons base têm width
	# GLOW_UNDERLAY_BASE_WIDTH no .tscn).
	if glow_underlay != null:
		var total_len: float = max_range_per_side * 2.0
		glow_underlay.scale.x = total_len / GLOW_UNDERLAY_BASE_WIDTH
		glow_underlay.position = Vector2.ZERO
		var tw_glow: Tween = glow_underlay.create_tween()
		tw_glow.tween_property(glow_underlay, "modulate:a", 1.0, silhouette_phase * 0.85)
	# Charge orb.
	_animate_charge_orb()
	# Tiles do beam pros 2 lados.
	if tile_template != null and tile_template.sprite_frames != null:
		for i in num_per_side:
			var x_front: float = float(i) * FRAME_SIZE + FRAME_SIZE * 0.5
			var x_back: float = -(float(i) * FRAME_SIZE + FRAME_SIZE * 0.5)
			_spawn_tile_from_template(Vector2(x_front, 0), i, stagger_step,
				silhouette_phase, animate_phase)
			_spawn_tile_from_template(Vector2(x_back, 0), i, stagger_step,
				silhouette_phase, animate_phase)
	# PointLights ao longo do beam (lighting real). Quantidade modesta — o glow
	# visual já vem do underlay contínuo.
	if light_template != null:
		var lights_per_side: int = maxi(2, num_per_side / 6)
		for i in lights_per_side:
			var t: float = float(i + 1) / float(lights_per_side + 1)
			var dist: float = max_range_per_side * t
			_spawn_light_from_template(Vector2(dist, 0), t, silhouette_phase)
			_spawn_light_from_template(Vector2(-dist, 0), t, silhouette_phase)
	z_index = 10


func _animate_charge_orb() -> void:
	if charge_orb == null:
		return
	# Mostra o orb (no .tscn começa com modulate.a = 0 pra não aparecer no editor).
	charge_orb.modulate.a = 1.0
	var tw: Tween = charge_orb.create_tween().set_parallel(true)
	tw.tween_property(charge_orb, "scale", orb_final_scale, warmup_duration)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(charge_orb, "rotation", TAU, warmup_duration)
	tw.tween_property(charge_orb, "modulate:a", 0.0, warmup_duration * 0.55)\
		.set_delay(warmup_duration * 0.45)


func _spawn_tile_from_template(local_pos: Vector2, tile_index: int,
		stagger_step: float, silhouette_phase: float, animate_phase: float) -> void:
	var tile := tile_template.duplicate() as AnimatedSprite2D
	tile.visible = true
	tile.position = local_pos
	tile.frame = tile_index % TILE_FRAME_COUNT
	tile.frame_progress = randf() * 0.3
	tile.modulate = Color(0, 0, 0, 0)
	tile.pause()
	add_child(tile)
	# Fase 1: fade-in pra silhueta (cor escura) — sem animação rolando.
	var delay_in: float = float(tile_index) * stagger_step
	var tw1: Tween = tile.create_tween()
	tw1.tween_interval(delay_in)
	tw1.tween_property(tile, "modulate", SILHOUETTE_COLOR, TILE_FADE_IN)
	# Fase 2: após silhouette_phase, transição pra cor cheia + start anim.
	var tw2: Tween = tile.create_tween()
	tw2.tween_interval(silhouette_phase)
	tw2.tween_callback(tile.play.bind("default"))
	tw2.tween_property(tile, "modulate", FULL_COLOR, animate_phase)


func _spawn_light_from_template(local_pos: Vector2, t_along: float, silhouette_phase: float) -> void:
	var target_energy: float = light_template.energy
	var light := light_template.duplicate() as PointLight2D
	light.visible = true
	light.energy = 0.0
	light.position = local_pos
	add_child(light)
	# Aparece junto com a silhueta proporcional à posição no beam.
	var lt: Tween = light.create_tween()
	lt.tween_interval(t_along * silhouette_phase * 0.85)
	lt.tween_property(light, "energy", target_energy, 0.25)
