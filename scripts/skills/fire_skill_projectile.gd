extends Node2D

# Bola de fogo lançada em arco pela skill direita do Fogo lv3.
# Sai do player, sobe e desce em parábola até bater no `target_position`,
# onde spawna um FireField. Visual: círculo procedural pulsando branco/laranja/
# vermelho com PointLight2D de glow.

const ARC_DURATION: float = 1.05
const ARC_HEIGHT: float = 80.0  # peak height da parábola — maior agora pra arc mais visível

@export var fire_field_scene: PackedScene
@export var field_dps: float = 12.0
@export var field_duration: float = 6.0
@export var field_scale: float = 1.0  # lv4 do Fogo aumenta área pra 1.25

var _start: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func setup(start_pos: Vector2, target_pos: Vector2) -> void:
	_start = start_pos
	_target = target_pos
	global_position = start_pos


func _ready() -> void:
	# Pulse de cor: tween infinito no Visual.modulate alternando branco/laranja/vermelho.
	var visual := get_node_or_null("Visual") as Node2D
	if visual != null:
		var tw := visual.create_tween().set_loops()
		tw.tween_property(visual, "modulate", Color(1.4, 0.55, 0.18, 1), 0.12)
		tw.tween_property(visual, "modulate", Color(1.5, 0.95, 0.4, 1), 0.12)
		tw.tween_property(visual, "modulate", Color(1.6, 1.4, 1.1, 1), 0.10)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / ARC_DURATION, 0.0, 1.0)
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
