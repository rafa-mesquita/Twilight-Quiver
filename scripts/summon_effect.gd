extends Node2D

# Efeito de invocação lilás: anel expansivo + flash de luz + estilhaços girando.
# Tudo construído via tweens em runtime; não precisa de spritesheet.

@export var duration: float = 0.7
@export var color: Color = Color(0.78, 0.55, 0.95, 1.0)
# Origem do node fica no chão; visual fica acima (mesmo padrão do projétil pra Y-sort).
const VISUAL_OFFSET_Y: float = -16.0

@onready var ring_outer: Polygon2D = $Visual/RingOuter
@onready var ring_inner: Polygon2D = $Visual/RingInner
@onready var burst_light: PointLight2D = $Visual/BurstLight
@onready var shards: Node2D = $Visual/Shards


func _ready() -> void:
	# Anel externo expande forte e some.
	var t1 := create_tween().set_parallel(true)
	t1.tween_property(ring_outer, "scale", Vector2(2.6, 2.6), duration).from(Vector2(0.2, 0.2))
	t1.tween_property(ring_outer, "modulate:a", 0.0, duration).from(0.85)

	# Anel interno expande mais devagar pra dar profundidade.
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(ring_inner, "scale", Vector2(1.8, 1.8), duration * 0.85).from(Vector2(0.4, 0.4))
	t2.tween_property(ring_inner, "modulate:a", 0.0, duration * 0.85).from(1.0)

	# Flash de luz: pico no início, fade rápido.
	var t3 := create_tween()
	t3.tween_property(burst_light, "energy", 2.4, duration * 0.25).from(0.0)
	t3.tween_property(burst_light, "energy", 0.0, duration * 0.75)

	# Estilhaços giram e se afastam do centro (já posicionados nos filhos).
	var t4 := create_tween().set_parallel(true)
	t4.tween_property(shards, "rotation", TAU * 0.6, duration).from(0.0)
	t4.tween_property(shards, "scale", Vector2(2.2, 2.2), duration).from(Vector2(0.3, 0.3))
	t4.tween_property(shards, "modulate:a", 0.0, duration).from(1.0)

	get_tree().create_timer(duration).timeout.connect(queue_free)
