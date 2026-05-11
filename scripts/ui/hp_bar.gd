extends Node2D

@export var trail_delay: float = 0.35
@export var trail_speed: float = 5.0
@export var fg_color: Color = Color(0.463, 0.655, 0.298, 1)
# Squash visual ao tomar dano: comprime horizontal, estica vertical, volta ao normal.
@export var squash_x: float = 0.85
@export var squash_y: float = 1.6
@export var squash_duration: float = 0.2
# Largura do polygon da barra (16 nas .tscn padrão), usado pra compensar o offset
# horizontal e manter a barra centralizada durante o squash.
@export var bar_width: float = 16.0

@onready var fg: Polygon2D = $Fg
@onready var trail: Polygon2D = $Trail

var current_ratio: float = 1.0
var trail_ratio: float = 1.0
var trail_timer: float = 0.0

var _base_position: Vector2 = Vector2.ZERO
# Scale inicial da barra no .tscn (alguns inimigos escalam, ex: boss tem 2×).
# Squash usa esse valor como referência pra não perder o scale customizado.
var _base_scale: Vector2 = Vector2.ONE
var _squash_tween: Tween


func _ready() -> void:
	fg.color = fg_color
	fg.scale.x = current_ratio
	trail.scale.x = trail_ratio
	_base_position = position
	_base_scale = scale


func set_ratio(ratio: float) -> void:
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio < current_ratio:
		# Tomou dano — trail mantém o valor anterior e segura por trail_delay antes de cair.
		trail_timer = trail_delay
		_squash()
	else:
		# Curou (ou set inicial maior) — trail acompanha imediatamente.
		trail_ratio = ratio
	current_ratio = ratio
	fg.scale.x = current_ratio
	trail.scale.x = trail_ratio


func _squash() -> void:
	if _squash_tween != null and _squash_tween.is_valid():
		_squash_tween.kill()
	# Aplica squash MULTIPLICATIVAMENTE sobre o _base_scale (preserva o scale
	# customizado do .tscn — boss usa 2× pra barra ficar maior, e a barra
	# voltava pra 1× perdendo o tamanho após o primeiro hit).
	scale = _base_scale * Vector2(squash_x, squash_y)
	# Compensa horizontalmente pra manter a barra centralizada (polygon vai de x=0 a x=16
	# da origem do node, então scaling muda só o lado direito sem compensação).
	var compensate_x: float = (bar_width * 0.5) * _base_scale.x * (1.0 - squash_x)
	position = _base_position + Vector2(compensate_x, 0)
	_squash_tween = create_tween()
	_squash_tween.set_parallel(true)
	_squash_tween.tween_property(self, "scale", _base_scale, squash_duration)
	_squash_tween.tween_property(self, "position", _base_position, squash_duration)


func _process(delta: float) -> void:
	if trail_ratio > current_ratio:
		if trail_timer > 0.0:
			trail_timer -= delta
			return
		# Exponential decay: framerate-independent ease-out, naturalmente smooth.
		trail_ratio = lerp(trail_ratio, current_ratio, 1.0 - exp(-trail_speed * delta))
		if absf(trail_ratio - current_ratio) < 0.002:
			trail_ratio = current_ratio
		trail.scale.x = trail_ratio
