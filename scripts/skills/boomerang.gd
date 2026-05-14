extends Area2D

# Boomerang: skill passiva de cast automático. Vai na direção setada até atingir
# `travel_distance`, vira e volta perseguindo o player vivo. Atravessa todos os
# inimigos. Cada inimigo pode tomar dano 1× por fase (ida + volta = 2 hits max).
# Enemies parados perto do ponto de virada naturalmente recebem 2× dano (são
# atingidos na ida E na volta).

@export var damage: float = 20.0
@export var travel_distance: float = 150.0
# Velocidade base (em px/s). A velocidade efetiva é modulada por SPEED_MIN_FACTOR
# nas extremidades (apex out + início inbound) pra simular o "freio" da volta.
@export var speed: float = 180.0
# Velocidade de rotação visual (rad/s). 28 rad/s ≈ 4.5 voltas/s.
@export var rotation_speed: float = 28.0
# Fator mínimo da velocidade (no apex). 1.0 = sem desaceleração; 0.4 = 60% mais lento.
const SPEED_MIN_FACTOR: float = 0.4
# Distância máxima do player pra considerar "voltou" (despawn).
const RETURN_DISTANCE_THRESHOLD: float = 12.0
const MAX_LIFETIME: float = 6.0
# Catch-up boost: se a fase INBOUND durar mais que X segundos (player rápido),
# começa a acelerar progressivamente pra garantir que o boomerang alcance.
# Sem isso, com player no Esquivando lv4 + skill, o boomerang nunca alcança.
const INBOUND_BOOST_DELAY: float = 1.5
const INBOUND_BOOST_RATE: float = 1.5  # +150% velocidade por segundo após delay
const INBOUND_BOOST_MAX: float = 5.0   # cap em 5× pra não teleportar

# Rastro: Line2D adicionado dinamicamente no _ready, top-level pra não rotacionar
# junto com o sprite. Cor branca translúcida, renderizado ABAIXO do sprite via
# z_index negativo (z_as_relative=false desacopla do parent).
const TRAIL_COLOR: Color = Color(1.0, 1.0, 1.0, 0.45)
const TRAIL_WIDTH: float = 4.0
const TRAIL_MAX_POINTS: int = 14
const TRAIL_Z_INDEX: int = -1

enum Phase { OUTBOUND, INBOUND }

var direction: Vector2 = Vector2.RIGHT
var source: Node = null  # player ref pra notify telemetria
var _phase: int = Phase.OUTBOUND
var _start_pos: Vector2 = Vector2.ZERO
var _hit_outbound: Array[Node] = []
var _hit_inbound: Array[Node] = []
var _bodies_inside: Array[Node] = []
var _life: float = 0.0
var _arrow_damage_mult: float = 1.0  # capturado no spawn
var _trail: Line2D = null
# Distância total da volta no momento da virada — usada pra calcular o progresso
# da fase INBOUND (que vai de 0 no apex até 1 no player).
var _inbound_total_dist: float = 0.0
# Tempo acumulado na fase INBOUND — base do catch-up boost.
var _inbound_time: float = 0.0


func setup(start_pos: Vector2, dir: Vector2, player_node: Node) -> void:
	global_position = start_pos
	_start_pos = start_pos
	direction = dir.normalized()
	source = player_node
	if source != null and "arrow_damage_multiplier" in source:
		_arrow_damage_mult = float(source.arrow_damage_multiplier)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_setup_trail()
	_setup_fly_sound()


func _setup_fly_sound() -> void:
	# Toca o whoosh UMA vez no spawn. Defensive: força loop=false no AudioStreamMP3
	# caso código antigo tenha contaminado o resource cacheado em runtime anterior.
	var fly: AudioStreamPlayer2D = get_node_or_null("FlySound") as AudioStreamPlayer2D
	if fly == null or fly.stream == null:
		return
	if fly.stream is AudioStreamMP3:
		(fly.stream as AudioStreamMP3).loop = false
	fly.play()


func _setup_trail() -> void:
	# Trail é top_level pra ficar no espaço global (não rotaciona com o sprite).
	# Gradient: cauda transparente → cabeça opaca. Não adiciona ponto inicial
	# aqui — _ready roda ANTES do setup() (que define a posição correta), então
	# o primeiro ponto é adicionado no primeiro _update_trail (já com pos certa).
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, 0.0),
		TRAIL_COLOR,
	])
	_trail = Line2D.new()
	_trail.top_level = true
	_trail.width = TRAIL_WIDTH
	_trail.default_color = TRAIL_COLOR
	_trail.gradient = grad
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	# Renderiza ABAIXO do sprite — z_index negativo absoluto (z_as_relative=false
	# pra ignorar o z_index do parent).
	_trail.z_as_relative = false
	_trail.z_index = TRAIL_Z_INDEX
	add_child(_trail)


func _physics_process(delta: float) -> void:
	_life += delta
	if _life > MAX_LIFETIME:
		queue_free()
		return
	rotation += rotation_speed * delta
	var step: Vector2
	if _phase == Phase.OUTBOUND:
		var dist_traveled: float = global_position.distance_to(_start_pos)
		var t: float = clampf(dist_traveled / travel_distance, 0.0, 1.0)
		# Quadratic ease-in da desaceleração: speed plena no começo, vai
		# desacelerando exponencialmente conforme se aproxima do apex.
		var factor: float = lerpf(1.0, SPEED_MIN_FACTOR, t * t)
		step = direction * speed * factor * delta
		global_position += step
		if dist_traveled + step.length() >= travel_distance:
			_switch_to_inbound()
	else:
		if source == null or not is_instance_valid(source) or not (source is Node2D):
			queue_free()
			return
		var src2d: Node2D = source
		var to_player: Vector2 = src2d.global_position - global_position
		var dist_remaining: float = to_player.length()
		if dist_remaining < RETURN_DISTANCE_THRESHOLD:
			queue_free()
			return
		_inbound_time += delta
		# Acelera saindo do apex: começa em SPEED_MIN_FACTOR, retorna a 1.0
		# rapidamente via sqrt (acelera forte no início, suaviza no fim).
		var t_in: float = 0.0
		if _inbound_total_dist > 0.0:
			t_in = clampf(1.0 - (dist_remaining / _inbound_total_dist), 0.0, 1.0)
		var factor_in: float = lerpf(SPEED_MIN_FACTOR, 1.0, sqrt(t_in))
		# Catch-up boost: se o player tá fugindo mais rápido que o boomerang
		# consegue voltar, depois de INBOUND_BOOST_DELAY segundos começa a
		# acelerar progressivamente até alcançar (cap em INBOUND_BOOST_MAX).
		var boost: float = 1.0
		if _inbound_time > INBOUND_BOOST_DELAY:
			boost = 1.0 + (_inbound_time - INBOUND_BOOST_DELAY) * INBOUND_BOOST_RATE
			boost = minf(boost, INBOUND_BOOST_MAX)
		step = to_player.normalized() * speed * factor_in * boost * delta
		global_position += step
	_update_trail()


func _update_trail() -> void:
	if _trail == null:
		return
	# Bootstrap: primeiro frame de _physics_process já tem a posição correta
	# (setup() já rodou antes do tick), então adiciona o primeiro ponto aqui.
	if _trail.get_point_count() == 0:
		_trail.add_point(global_position)
		return
	# Adiciona ponto novo se distância suficiente desde o último (~3px) — evita
	# overfill em frames rápidos. Mantém máximo de TRAIL_MAX_POINTS.
	var last_pt: Vector2 = _trail.get_point_position(_trail.get_point_count() - 1)
	if last_pt.distance_to(global_position) >= 3.0:
		_trail.add_point(global_position)
		while _trail.get_point_count() > TRAIL_MAX_POINTS:
			_trail.remove_point(0)


func _switch_to_inbound() -> void:
	_phase = Phase.INBOUND
	# Calcula distância total da volta no momento da virada — base pra curva
	# de aceleração na fase INBOUND. Se o player se mexer, a curva ainda
	# funciona (re-relativa à distância atual).
	if source != null and is_instance_valid(source) and source is Node2D:
		_inbound_total_dist = global_position.distance_to((source as Node2D).global_position)
	# Inimigos AINDA dentro da área no momento da virada levam dano da volta
	# imediatamente — é o "double hit" pro alvo no apex (na prática enemies
	# parados ali pegam o dmg da ida e da volta).
	for b in _bodies_inside.duplicate():
		_try_hit(b)


func _on_body_entered(body: Node) -> void:
	if not _bodies_inside.has(body):
		_bodies_inside.append(body)
	_try_hit(body)


func _on_body_exited(body: Node) -> void:
	_bodies_inside.erase(body)


func _try_hit(body: Node) -> void:
	if not is_instance_valid(body):
		return
	# Só inimigos vivos (skipa estruturas, aliados, paredes).
	if not body.is_in_group("enemy"):
		return
	if body.is_queued_for_deletion():
		return
	if "hp" in body and float(body.hp) <= 0.0:
		return
	if not body.has_method("take_damage"):
		return
	# Boss shieldado não toma dano — não conta como hit (não estraga o painel TAB).
	if body.is_in_group("boss_shielded"):
		return
	var hit_list: Array[Node] = _hit_outbound if _phase == Phase.OUTBOUND else _hit_inbound
	if hit_list.has(body):
		return
	hit_list.append(body)
	var dmg: float = damage * _arrow_damage_mult
	# Crit roll por hit do boomerang. Cada hit rola independente.
	var crit_info: Dictionary = {"crit": false, "mult": 1.0}
	if source != null and is_instance_valid(source) and source.has_method("roll_crit"):
		crit_info = source.roll_crit()
	if bool(crit_info.get("crit", false)):
		dmg *= float(crit_info.get("mult", 1.0))
		CritFeedback.mark_next_hit_crit(body)
	var was_alive: bool = (not ("hp" in body)) or float(body.hp) > 0.0
	# Silencia damage_sound do macaco especificamente — workaround pro bug
	# de loop quando boomerang fica re-acertando o mesmo alvo.
	if body.is_in_group("monkey") and "_suppress_damage_sound_once" in body:
		body._suppress_damage_sound_once = true
	body.take_damage(dmg)
	_notify_player_dmg(dmg, was_alive, body)
	_play_impact_sound()


func _play_impact_sound() -> void:
	# Hit effect do boomerang — toca a cada inimigo atingido (em ambas as fases
	# ida + volta). Sem dedupe — múltiplos sons em sequência são esperados.
	var impact: AudioStreamPlayer2D = get_node_or_null("ImpactSound") as AudioStreamPlayer2D
	if impact == null or impact.stream == null:
		return
	impact.play()


func _notify_player_dmg(amount: float, was_alive: bool, target: Node) -> void:
	if source == null or not is_instance_valid(source):
		return
	if source.has_method("notify_damage_dealt_by_source"):
		source.notify_damage_dealt_by_source(amount, "boomerang")
	if was_alive and source.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			source.notify_kill_by_source("boomerang")
