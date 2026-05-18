extends CanvasLayer

# Universal birthday confetti — autoload que fica EM CIMA de tudo (HUD, menus,
# gameplay) durante a janela do evento. Inspiração: Terraria, em que o
# aniversário cobre a tela toda com confete caindo.
#
# Por que CanvasLayer autoload? Assim não precisa instanciar manualmente em
# cada cena. Layer alto (100) garante que renderiza sobre HUD/dev panel.
# CPUParticles2D pelos mesmos motivos do fireworks (renderer gl_compatibility).
#
# Para ativar/desativar runtime (dev toggle): chame
# `Confetti.refresh_active_state()` após mexer em `BirthdayEvent.dev_force_active`.

const COLORS: Array[Color] = [
	Color(1.0, 0.35, 0.45, 1.0),  # pink
	Color(1.0, 0.78, 0.20, 1.0),  # gold
	Color(0.45, 0.85, 1.0, 1.0),  # cyan
	Color(0.65, 1.0, 0.45, 1.0),  # green
	Color(0.85, 0.55, 1.0, 1.0),  # purple
	Color(1.0, 0.55, 0.35, 1.0),  # orange
	Color(1.0, 1.0, 1.0, 1.0),    # white
]

# Viewport fixo (project.godot trava 1920x1080 + stretch viewport).
const VIEWPORT_WIDTH := 1920.0
const AMOUNT_PER_COLOR := 28

var _emitters: Array[CPUParticles2D] = []
var _confetti_texture: Texture2D = null


func _ready() -> void:
	# Layer 95: acima de HUD (10), wave shop (50), HUD editor (99) parcialmente —
	# mas ABAIXO de cursor/dev panel/version label (100) pra não tapar UI crítica.
	layer = 95
	# Roda mesmo durante pause (pause menu, game over, etc.) — efeito ambiente.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_confetti_texture = _make_confetti_texture()
	for color in COLORS:
		var p := _make_emitter(color)
		add_child(p)
		_emitters.append(p)
	refresh_active_state()


# Re-checa estado do evento. Útil pra dev toggle ligar/desligar sem reload,
# e pra reagir quando o nick é setado pela primeira vez no main menu.
# Gating: janela + nick alvo (eliyeolio), OU dev toggle ON.
func refresh_active_state() -> void:
	var active := BirthdayEvent.is_party_active_for_current_user()
	for p in _emitters:
		if p == null:
			continue
		p.emitting = active


# 4x2 pixel branco — cor real é multiplicada pelo CPUParticles2D.color. Pequeno
# o suficiente pra parecer "confete" (tirinha retangular) e não bola.
func _make_confetti_texture() -> Texture2D:
	var img := Image.create(4, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 1))
	return ImageTexture.create_from_image(img)


func _make_emitter(color: Color) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _confetti_texture
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.amount = AMOUNT_PER_COLOR
	# Lifetime longo + gravity baixa = queda lenta como Terraria. preprocess
	# garante que ao abrir o jogo a tela já tá com confete no meio do caminho.
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.local_coords = false
	p.one_shot = false
	# Faixa horizontal no topo cobrindo a viewport inteira.
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(VIEWPORT_WIDTH * 0.5, 4.0)
	p.position = Vector2(VIEWPORT_WIDTH * 0.5, -8.0)
	# Direção: pra baixo com leve spread (não 360 — confete só desce).
	p.direction = Vector2(0, 1)
	p.spread = 20.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 120.0
	# Gravity bem suave — confete flutua, não despenca.
	p.gravity = Vector2(0, 55.0)
	# Tamanho com leve variação pra dar profundidade visual.
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.5
	p.color = color
	# Spin rápido — característica de confete real virando no ar.
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	# Drift lateral suave (sway) — acel tangencial dá movimento de zig-zag.
	p.linear_accel_min = -25.0
	p.linear_accel_max = 25.0
	p.tangential_accel_min = -30.0
	p.tangential_accel_max = 30.0
	# Damping pra cair com "resistência do ar"
	p.damping_min = 2.0
	p.damping_max = 6.0
	p.emitting = true
	return p
