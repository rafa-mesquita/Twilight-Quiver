extends Area2D

# Pickup de pétala (meta-moeda). Drop raro de mob (via PetalDrop). Bem mais
# simples que o gold: sem magnet/slow/fenda/boss-lock. Dura ~19s (= moeda sob
# Chuva de Coins L2) e pisca no fim antes de sumir. Coletar → player.add_petals.
# Visual = placeholder rosa desenhado por código (trocável por sprite depois,
# sem mexer na lógica).

@export var value: int = 1
@export var lifetime: float = 19.0
@export var blink_warn_duration: float = 2.5

const VISUAL_OFFSET_Y: float = -6.0
const HOP_HEIGHT: float = 8.0
const HOP_DURATION: float = 0.4
const PETAL_TEXTURE: Texture2D = preload("res://assets/Hud/petals.png")
const PETAL_SCALE: float = 0.6   # 18px → ~11px (perto do tamanho da moeda)
const BLINK_BRIGHT: Color = Color(1.9, 1.9, 1.9, 1.0)  # flash claro no aviso
const NORMAL_MOD: Color = Color(1, 1, 1, 1)

@onready var visual: Node2D = $Visual

var _elapsed: float = 0.0
var _bob_phase: float = 0.0
var _picked: bool = false
var _petal_sprite: Sprite2D = null


func _ready() -> void:
	add_to_group("petal")
	body_entered.connect(_on_body_entered)
	# Phase random pra pétalas dropadas juntas não pulsarem em sync.
	_bob_phase = randf() * TAU
	visual.position.y = VISUAL_OFFSET_Y
	_build_placeholder_visual()


func _build_placeholder_visual() -> void:
	# Sombra no chão (atrás de tudo).
	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.25)
	shadow.polygon = PackedVector2Array([Vector2(4, 0), Vector2(0, 1.5), Vector2(-4, 0), Vector2(0, -1.5)])
	shadow.position = Vector2(0, 1.5)
	shadow.z_index = -1
	add_child(shadow)
	# Sprite da pétala (assets/Hud/petals.png).
	var s := Sprite2D.new()
	s.texture = PETAL_TEXTURE
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(PETAL_SCALE, PETAL_SCALE)
	visual.add_child(s)
	_petal_sprite = s


func _process(delta: float) -> void:
	if _picked:
		return
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	# Hop inicial (parábola) + bobbing contínuo.
	var hop_offset: float = 0.0
	if _elapsed < HOP_DURATION:
		var t: float = _elapsed / HOP_DURATION
		hop_offset = -HOP_HEIGHT * 4.0 * t * (1.0 - t)
	_bob_phase += delta * 4.0
	var bob_offset: float = sin(_bob_phase) * 1.5
	visual.position.y = VISUAL_OFFSET_Y + bob_offset + hop_offset
	# Blink de aviso nos últimos segundos (pétala dá flash claro).
	if _petal_sprite == null:
		return
	var time_left: float = lifetime - _elapsed
	if time_left <= blink_warn_duration:
		var ratio: float = 1.0 - time_left / blink_warn_duration  # 0 → 1
		var freq: float = lerp(4.0, 14.0, ratio)
		var on_flash: bool = fmod(_elapsed * freq, 1.0) < lerp(0.4, 0.8, ratio)
		_petal_sprite.modulate = BLINK_BRIGHT if on_flash else NORMAL_MOD
	else:
		_petal_sprite.modulate = NORMAL_MOD


# Chamado pelo wave_manager no fim do round: a pétala voa até o player e é coletada
# (mesmo espírito do magnet do gold). Garante que pétalas no chão não se percam.
func magnet_to_player(target_callable: Callable) -> void:
	if _picked:
		return
	_picked = true   # trava lifetime/blink e o pickup por colisão (evita double)
	var start: Vector2 = global_position
	var tw := create_tween()
	tw.tween_method(func(t: float) -> void:
		var tgt: Vector2 = (target_callable.call() if target_callable.is_valid() else start)
		global_position = start.lerp(tgt, t)
	, 0.0, 1.0, 0.5)
	tw.tween_callback(_magnet_collect)


func _magnet_collect() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and player.has_method("add_petals"):
		player.add_petals(value, global_position)
		MenuAudio.play_drop()
	queue_free()


func _on_body_entered(body: Node) -> void:
	if _picked or not body.is_in_group("player") or not body.has_method("add_petals"):
		return
	# Fenda Crepuscular: não coleta em trânsito (mesmo guard do gold).
	if body.get("_fenda_teleporting") == true:
		return
	_picked = true
	body.add_petals(value, global_position)
	# Mesmo som do drop de item do inventário ao catar a pétala (MenuAudio é autoload).
	MenuAudio.play_drop()
	# Anim de coleta: sobe e some.
	var t := create_tween().set_parallel(true)
	t.tween_property(visual, "position:y", VISUAL_OFFSET_Y - 12.0, 0.2)
	t.tween_property(visual, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(queue_free)
