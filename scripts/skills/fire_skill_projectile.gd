extends Node2D

# Bola de fogo lançada em arco pela skill direita do Fogo lv3.
# Sai do player, sobe e desce em parábola até bater no `target_position`,
# onde spawna um FireField. Visual: círculo procedural pulsando branco/laranja/
# vermelho com PointLight2D de glow.

const ARC_HEIGHT: float = 80.0  # peak height da parábola — maior agora pra arc mais visível

@export var fire_field_scene: PackedScene
@export var field_dps: float = 12.0
@export var field_duration: float = 6.0
@export var field_scale: float = 1.0  # lv4 do Fogo aumenta área pra 1.25
# Tempo (s) de voo até pousar. Player usa 1.05 (rápido); fire_mage sobe pra
# ~2.0 pra dar tempo de esquivar com o indicador no chão.
@export var arc_duration: float = 1.05
# Quando true, propaga `is_enemy_source = true` pro FireField que spawnar
# (vem de um inimigo, machuca player/ally/structure em vez de enemies).
@export var is_enemy_source: bool = false
# Source id propagado pro FireField → player.take_damage. Usado pelo death
# screen pra creditar a morte (sem isso aparece "causa desconhecida").
@export var source_id: String = ""
# Indicador branco no chão mostrando onde o campo vai pousar (estilo dash
# da Duskrose). Usado pelo fire_mage pra telegrafar o ataque.
@export var show_landing_indicator: bool = false

var _start: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0
var _landing_indicator: Node2D = null


func setup(start_pos: Vector2, target_pos: Vector2) -> void:
	_start = start_pos
	_target = target_pos
	global_position = start_pos
	if show_landing_indicator:
		_spawn_landing_indicator()


func _spawn_landing_indicator() -> void:
	# Elipse branca semi-transparente no chão alinhada com o footprint do
	# FireField (CircleShape r=57 com scale (1, 0.55) → ~57x31). Aplica
	# field_scale pra acompanhar lv4 do Fogo (1.25).
	var radius_x: float = 57.0 * field_scale
	var radius_y: float = 31.0 * field_scale
	var indicator := Node2D.new()
	indicator.top_level = true  # ignora transform do projétil (fica fixo no chão)
	indicator.z_index = -1
	var poly := Polygon2D.new()
	var pts: PackedVector2Array = PackedVector2Array()
	var segments: int = 20
	for i in segments:
		var ang: float = TAU * float(i) / float(segments)
		pts.append(Vector2(cos(ang) * radius_x, sin(ang) * radius_y))
	poly.polygon = pts
	poly.color = Color(1.0, 1.0, 1.0, 0.36)
	indicator.add_child(poly)
	add_child(indicator)
	indicator.global_position = _target
	# Pulse alpha 0.20 ↔ 0.52 (20% mais transparente que o telegraph da Duskrose).
	var t := indicator.create_tween().set_loops()
	t.tween_property(poly, "color:a", 0.52, 0.18)
	t.tween_property(poly, "color:a", 0.20, 0.18)
	_landing_indicator = indicator


func _ready() -> void:
	# Pulse de cor: tween infinito no Visual.modulate. Player usa laranja/amarelo/
	# branco; mago (is_enemy_source) usa vermelho/carmim/rosa pra player distinguir
	# visualmente do próprio fogo (mesma lógica do tint do FireField).
	var visual := get_node_or_null("Visual") as Node2D
	if visual != null:
		var tw := visual.create_tween().set_loops()
		if is_enemy_source:
			tw.tween_property(visual, "modulate", Color(1.6, 0.2, 0.25, 1), 0.12)
			tw.tween_property(visual, "modulate", Color(1.7, 0.4, 0.45, 1), 0.12)
			tw.tween_property(visual, "modulate", Color(1.7, 0.75, 0.75, 1), 0.10)
		else:
			tw.tween_property(visual, "modulate", Color(1.4, 0.55, 0.18, 1), 0.12)
			tw.tween_property(visual, "modulate", Color(1.5, 0.95, 0.4, 1), 0.12)
			tw.tween_property(visual, "modulate", Color(1.6, 1.4, 1.1, 1), 0.10)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / arc_duration, 0.0, 1.0)
	# Posição linear interpolada + offset parabólico vertical pra simular arco.
	var lin: Vector2 = _start.lerp(_target, t)
	var arc_offset: float = -ARC_HEIGHT * 4.0 * t * (1.0 - t)
	global_position = lin + Vector2(0, arc_offset)
	if t >= 1.0:
		_land()


func _land() -> void:
	if fire_field_scene != null:
		var field: Node = fire_field_scene.instantiate()
		if "damage_per_second" in field:
			field.damage_per_second = field_dps
		if "duration" in field:
			field.duration = field_duration
		if "is_enemy_source" in field:
			field.is_enemy_source = is_enemy_source
		if "source_id" in field:
			field.source_id = source_id
		var world := get_tree().get_first_node_in_group("world")
		if world != null:
			world.add_child(field)
		else:
			get_tree().current_scene.add_child(field)
		if field is Node2D:
			var f2d: Node2D = field
			f2d.global_position = _target
			if not is_equal_approx(field_scale, 1.0):
				f2d.scale = Vector2(field_scale, field_scale)
	queue_free()
