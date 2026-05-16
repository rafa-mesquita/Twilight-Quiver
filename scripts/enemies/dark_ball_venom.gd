extends Area2D

# Poça de veneno dropada pela Dark Ball no momento do ataque. Tem 2 fases:
#
# 1. PREVIEW (0..SPAWN_DELAY): silhueta branca translúcida, SEM colisão e SEM
#    dano. Serve de telegraph — o player vê onde a fumaça vai surgir e tem
#    tempo de sair (cobre o caso "tomei dano logo após dodgar o hit").
#
# 2. ACTIVE (SPAWN_DELAY em diante): sprite normal, colisão ativa, ticka
#    dano direto via player.take_damage("dark_ball_venom") a cada TICK_INTERVAL
#    enquanto o player está dentro. Primeiro tick é aplicado imediatamente
#    no body_entered — assim mesmo passar rápido garante 1 tick.

const LIFETIME: float = 3.0
const FADE_DURATION: float = 0.5
const TICK_INTERVAL: float = 0.5
# Tempo de silhueta branca antes do veneno ficar ativo. Funciona como
# "wind-up" do efeito — player consegue dodge após o impacto e sair antes
# da fumaça materializar.
const SPAWN_DELAY: float = 0.4
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
const PREVIEW_MODULATE: Color = Color(1, 1, 1, 0.55)

@export var dps: float = 3.0

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var collision: CollisionShape2D = $CollisionShape2D

var _player_inside: Node = null
var _life_remaining: float = LIFETIME
var _spawn_delay_remaining: float = SPAWN_DELAY
var _tick_accum: float = 0.0
var _is_active: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Stagger frame pra múltiplas poças não pulsarem em sync.
	if sprite.sprite_frames != null:
		var fc: int = sprite.sprite_frames.get_frame_count("default")
		if fc > 1:
			sprite.frame = randi() % fc
			sprite.frame_progress = randf()
	# Inicia em modo PREVIEW: silhueta branca, colisão desativada.
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	sprite.material = mat
	sprite.modulate = PREVIEW_MODULATE
	collision.set_deferred("disabled", true)


func _process(delta: float) -> void:
	if not _is_active:
		_spawn_delay_remaining -= delta
		if _spawn_delay_remaining <= 0.0:
			_activate()
		return
	# Active phase
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		queue_free()
		return
	if _player_inside == null or not is_instance_valid(_player_inside):
		return
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick()


func _activate() -> void:
	_is_active = true
	# Remove shader/modulate de preview → volta visual normal.
	sprite.material = null
	sprite.modulate = Color.WHITE
	# Ativa colisão (deferred pra evitar erro de "in/out signals during physics").
	collision.set_deferred("disabled", false)
	# Tween de fade pros últimos FADE_DURATION segundos da vida ativa.
	var tw := create_tween()
	tw.tween_interval(LIFETIME - FADE_DURATION)
	tw.tween_property(self, "modulate:a", 0.0, FADE_DURATION)


func _apply_tick() -> void:
	if _player_inside == null or not is_instance_valid(_player_inside):
		return
	if not _player_inside.has_method("take_damage"):
		return
	var amount: float = dps * TICK_INTERVAL
	_player_inside.take_damage(amount, "dark_ball_venom")


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = body
		# Primeiro tick imediato — passar de raspão garante 1 instância de dano.
		# Subsequentes seguem TICK_INTERVAL via _process.
		_apply_tick()
		_tick_accum = 0.0


func _on_body_exited(body: Node) -> void:
	if body == _player_inside:
		_player_inside = null
		_tick_accum = 0.0
