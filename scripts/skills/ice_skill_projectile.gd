extends Node2D

# Bola de gelo lançada em arco pelo Ice Mage. Sai do mago, sobe e desce em
# parábola até pousar no `target_position`, onde spawna uma IceSlowArea.
# Mesmo padrão do fire_skill_projectile, mas pousa numa área de slow em vez
# de campo de fogo. Visual: tons de azul claro/branco.

const ARC_DURATION: float = 0.65
const ARC_HEIGHT: float = 70.0

@export var ice_slow_area_scene: PackedScene
@export var slow_multiplier: float = 0.75  # 25% slow (player.speed × 0.75)
@export var area_lifetime: float = 6.0
@export var area_scale: float = 1.0
# True quando spawnado por enemy (slow atinge player+ally). False quando
# spawnado por curse-ally (slow atinge enemy).
@export var is_enemy_source: bool = true

var _start: Vector2 = Vector2.ZERO
var _target: Vector2 = Vector2.ZERO
var _elapsed: float = 0.0


func setup(start_pos: Vector2, target_pos: Vector2) -> void:
	_start = start_pos
	_target = target_pos
	global_position = start_pos


func _ready() -> void:
	# Pulse de cor: tween infinito no Visual.modulate alternando branco/ciano/
	# azul claro pra o "shimmer" do gelo.
	var visual := get_node_or_null("Visual") as Node2D
	if visual != null:
		var tw := visual.create_tween().set_loops()
		tw.tween_property(visual, "modulate", Color(0.7, 0.95, 1.5, 1), 0.12)
		tw.tween_property(visual, "modulate", Color(1.1, 1.3, 1.6, 1), 0.12)
		tw.tween_property(visual, "modulate", Color(1.4, 1.5, 1.6, 1), 0.10)


func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / ARC_DURATION, 0.0, 1.0)
	var lin: Vector2 = _start.lerp(_target, t)
	var arc_offset: float = -ARC_HEIGHT * 4.0 * t * (1.0 - t)
	global_position = lin + Vector2(0, arc_offset)
	if t >= 1.0:
		_land()


func _land() -> void:
	if ice_slow_area_scene != null:
		var area: Node = ice_slow_area_scene.instantiate()
		if "slow_multiplier" in area:
			area.slow_multiplier = slow_multiplier
		if "lifetime" in area:
			area.lifetime = area_lifetime
		if "is_enemy_source" in area:
			area.is_enemy_source = is_enemy_source
		var world := get_tree().get_first_node_in_group("world")
		if world != null:
			world.add_child(area)
		else:
			get_tree().current_scene.add_child(area)
		if area is Node2D:
			var a2d: Node2D = area
			a2d.global_position = _target
			if not is_equal_approx(area_scale, 1.0):
				a2d.scale = Vector2(area_scale, area_scale)
	queue_free()
