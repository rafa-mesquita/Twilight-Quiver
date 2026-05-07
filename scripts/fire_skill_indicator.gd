extends Node2D

# Indicador de mira da skill direita do Fogo lv3:
# - Round range: círculo grande seguindo o player (área válida pro alvo)
# - Reticle: círculo menor seguindo o cursor, clampeado ao range
# Nó controlado pelo player (que faz follow_player + clamp_to_range em _process).

@export var range_radius: float = 200.0
@export var area_radius: float = 32.0
# Achata o Y pra dar visual isométrico (LoL-style) — circle vira elipse no plano
# do chão. O cálculo de range/clamp continua usando o raio real (3D-equivalente),
# só o visual é projetado.
const Y_SQUASH: float = 0.55

@onready var range_circle: Polygon2D = $RangeCircle
@onready var range_ring: Line2D = $RangeRing
@onready var reticle: Node2D = $Reticle


func _ready() -> void:
	# Constrói os polígonos de círculo dinamicamente baseado nos raios exportados.
	_build_circle(range_circle, range_radius, 48)
	_build_ring(range_ring, range_radius, 64)
	var area_circle := reticle.get_node("AreaCircle") as Polygon2D
	var area_ring := reticle.get_node("AreaRing") as Line2D
	_build_circle(area_circle, area_radius, 32)
	_build_ring(area_ring, area_radius, 40)


func get_clamped_target(player_pos: Vector2, mouse_pos: Vector2) -> Vector2:
	# Clamp na ELIPSE visual (não no círculo "real"). Trick: transforma pro
	# espaço-círculo dividindo Y por Y_SQUASH, faz clamp circular ali, e
	# transforma de volta multiplicando Y por Y_SQUASH. Resultado: o reticle
	# só pode ir até onde a elipse desenhada permite.
	var rel: Vector2 = mouse_pos - player_pos
	var rel_circle: Vector2 = Vector2(rel.x, rel.y / Y_SQUASH)
	var dist: float = rel_circle.length()
	if dist <= range_radius:
		return mouse_pos
	var clamped: Vector2 = rel_circle.normalized() * range_radius
	return player_pos + Vector2(clamped.x, clamped.y * Y_SQUASH)


func update_positions(player_pos: Vector2, target_pos: Vector2) -> void:
	global_position = player_pos
	reticle.global_position = target_pos


func _build_circle(poly: Polygon2D, radius: float, segments: int) -> void:
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in segments:
		var ang: float = TAU * float(i) / float(segments)
		pts[i] = Vector2(cos(ang) * radius, sin(ang) * radius * Y_SQUASH)
	poly.polygon = pts


func _build_ring(line: Line2D, radius: float, segments: int) -> void:
	line.clear_points()
	for i in segments + 1:
		var ang: float = TAU * float(i) / float(segments)
		line.add_point(Vector2(cos(ang) * radius, sin(ang) * radius * Y_SQUASH))
