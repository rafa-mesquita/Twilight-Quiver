extends Node2D

# Birthday ambient fireworks — programmatic CPUParticles2D setup.
# Usado no main_menu e wave_shop durante a janela do evento.
#
# Por que CPUParticles2D? Projeto roda em renderer GL Compatibility
# (project.godot rendering_method="gl_compatibility"), onde GPUParticles2D
# tem suporte limitado. CPU é confiável e suficiente pra ambient leve.
#
# Tudo configurado em código pra fácil tuning. mouse_filter via Control
# wrappers não é necessário — Node2D não bloqueia input por padrão.

const COLORS: Array[Color] = [
	Color(1.0, 0.35, 0.45, 1.0),  # pink
	Color(1.0, 0.78, 0.20, 1.0),  # gold
	Color(0.45, 0.85, 1.0, 1.0),  # cyan
	Color(0.65, 1.0, 0.45, 1.0),  # green
	Color(0.85, 0.55, 1.0, 1.0),  # purple
	Color(1.0, 1.0, 1.0, 1.0),    # white twinkle
]

@export var emission_width: float = 480.0
@export var amount: int = 80
# Lifetime longo + gravity forte pra particles atravessarem a tela toda
# (1080px de viewport). Cobertura ambiente até o fim da tela.
@export var lifetime: float = 6.0


func _ready() -> void:
	# Cria um CPUParticles2D pra cada cor — varia look sem precisar de
	# color_ramp (que adiciona overhead). Cada um emite no mesmo Y mas
	# pontos X randômicos diferentes.
	for color in COLORS:
		add_child(_make_emitter(color))


func _make_emitter(color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.emitting = true
	p.amount = max(1, int(amount / COLORS.size()))
	p.lifetime = lifetime
	p.preprocess = lifetime  # já começa "no meio" pra não ter delay inicial
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.local_coords = false
	p.one_shot = false
	# Emissão em linha horizontal no topo da viewport.
	# Em CPUParticles2D (2D) o enum é RECTANGLE (BOX é só pra 3D) e o property
	# correspondente é emission_rect_extents (Vector2, não Vector3).
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(emission_width * 0.5, 2.0)
	# Direção: pra baixo com bastante spread (full 360 dá um sparkle look).
	p.direction = Vector2(0, 1)
	p.spread = 180.0
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	# Gravity forte pra particles atingirem o fundo (1080px) dentro do lifetime.
	p.gravity = Vector2(0, 220.0)
	# Tamanho pequeno (pixel art vibe) com leve variação.
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	# Fade in/out + twinkle via color_ramp implícito? Não — alpha tem curve.
	p.color = color
	# Alpha fade: usa angular_velocity? Não, usa scale curve + alpha by lifetime
	# manualmente via modulate da textura. Mais simples: deixa o particle morrer
	# com alpha cheio mas dá uma escala que diminui (twinkle-out feeling).
	# scale_amount_curve em CPUParticles2D aceita Curve direto (não CurveTexture
	# — CurveTexture é só pra GPUParticles2D que usa shader).
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.0))
	curve.add_point(Vector2(0.15, 1.0))
	curve.add_point(Vector2(0.85, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = curve
	# Angular: leve rotação pra dar movimento.
	p.angular_velocity_min = -90.0
	p.angular_velocity_max = 90.0
	# Damping leve pra "twinkle" desacelerar.
	p.damping_min = 8.0
	p.damping_max = 18.0
	return p
