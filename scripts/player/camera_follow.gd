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
var _saved_zoom: Vector2 = Vector2.ONE
var _transition_tween: Tween


func _ready() -> void:
	make_current()


func _process(_delta: float) -> void:
	if overview_mode:
		return
	if player == null or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node2D
		if player == null:
			return
	global_position = player.global_position + follow_offset


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
