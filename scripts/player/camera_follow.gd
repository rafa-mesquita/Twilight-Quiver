extends Camera2D

# Câmera top-level (não filha do Player) — segue o player em _process. Usado pra
# tirar o Camera2D de dentro de World no editor e deixar a edição do mapa limpa.
# Suporta "overview mode" pra zoom out total (usado em placement de estruturas).

@export var follow_offset: Vector2 = Vector2(0, -16)
# Modo overview: usado durante placement de estruturas pra mostrar mapa inteiro.
@export var overview_zoom: Vector2 = Vector2(2.1, 2.1)
@export var overview_position: Vector2 = Vector2(250, 150)
@export var overview_transition: float = 0.4

var player: Node2D
var overview_mode: bool = false
# Cinematic: bloqueia o follow do player pra script externo controlar
# manualmente a global_position (boss intro, etc).
var cinematic_mode: bool = false
var _saved_zoom: Vector2 = Vector2.ONE
var _transition_tween: Tween
# Screen shake (ex: Terremoto da Pedra). Offset random somado ao follow,
# decaindo linearmente até o fim da duração.
var _shake_remaining: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	if overview_mode or cinematic_mode:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return
	var pos: Vector2 = player.global_position + follow_offset
	if _shake_remaining > 0.0:
		_shake_remaining -= delta
		var amt: float = _shake_strength * (_shake_remaining / _shake_duration) if _shake_duration > 0.0 else 0.0
		pos += Vector2(randf_range(-amt, amt), randf_range(-amt, amt))
	global_position = pos


func shake(duration: float, strength: float) -> void:
	# Dispara (ou reforça) um tremor de tela. Pega o maior dos dois pra não
	# cortar um shake mais forte já em andamento.
	_shake_duration = maxf(duration, 0.01)
	_shake_remaining = maxf(_shake_remaining, duration)
	_shake_strength = maxf(_shake_strength, strength)


# Pan suave da câmera pra uma posição mundo (usado no fim da cinematic do
# boss pra ir do boss → player). Não desliga cinematic_mode — caller que
# decide quando "soltar" a câmera.
func pan_to(target_world_pos: Vector2, duration: float = 1.0) -> Tween:
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.tween_property(self, "global_position", target_world_pos, duration)
	return _transition_tween


func set_overview_mode(active: bool) -> void:
	if active == overview_mode:
		return
	if _transition_tween != null and _transition_tween.is_valid():
		_transition_tween.kill()
	if active:
		# Salva zoom atual pra restaurar depois.
		_saved_zoom = zoom
	overview_mode = active
	_transition_tween = create_tween().set_parallel(true)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if active:
		_transition_tween.tween_property(self, "zoom", overview_zoom, overview_transition)
		_transition_tween.tween_property(self, "global_position", overview_position, overview_transition)
	else:
		_transition_tween.tween_property(self, "zoom", _saved_zoom, overview_transition)
		var p := get_tree().get_first_node_in_group("player") as Node2D
		if p != null:
			_transition_tween.tween_property(self, "global_position",
				p.global_position + follow_offset, overview_transition)
