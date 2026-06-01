extends Node2D

# Relógio "pizza" flutuante — mostra um cooldown/tempo restante como uma fatia
# circular que esvazia. Usado em cima do Pai do Verde pra indicar quanto falta
# pra ele parar de correr (ver scripts/allies/arbusto.gd).
#
# Billboard plano acima da cabeça (sem Y-squash isométrico): é um indicador de
# UI, não uma marcação no chão. Quem usa chama set_ratio(1..0) — 1 = cheio,
# 0 = vazio (vai parar). Esconde via `visible` quando não há corrida ativa.

@export var radius: float = 3.5
# Verde lima na mesma família da HP bar (Color(0.463, 0.655, 0.298)). Alpha
# reduzido pra ficar discreto — é um indicador, não pode roubar a cena.
@export var fill_color: Color = Color(0.55, 0.85, 0.35, 0.65)
@export var face_color: Color = Color(0.08, 0.12, 0.08, 0.4)
@export var border_color: Color = Color(0.0, 0.0, 0.0, 0.22)
@export var outline_color: Color = Color(1.0, 1.0, 1.0, 0.32)
# Segmentos do arco da fatia — 24 é suave o suficiente num raio de ~5px.
const SEGMENTS: int = 24

var _ratio: float = 1.0


func set_ratio(ratio: float) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	if is_equal_approx(clamped, _ratio):
		return
	_ratio = clamped
	queue_redraw()


func _draw() -> void:
	# Sombra/borda externa pra destacar do fundo.
	draw_circle(Vector2.ZERO, radius + 1.0, border_color)
	# Face vazia (o "mostrador" sem tempo).
	draw_circle(Vector2.ZERO, radius, face_color)
	# Fatia cheia: fan de pontos a partir do centro, começando no topo (12h,
	# -PI/2) varrendo no sentido horário por TAU * _ratio.
	if _ratio > 0.001:
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		var start: float = -PI / 2.0
		var sweep: float = TAU * _ratio
		for i in SEGMENTS + 1:
			var ang: float = start + sweep * float(i) / float(SEGMENTS)
			pts.append(Vector2(cos(ang), sin(ang)) * radius)
		draw_colored_polygon(pts, fill_color)
	# Contorno do mostrador.
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, outline_color, 1.0)
