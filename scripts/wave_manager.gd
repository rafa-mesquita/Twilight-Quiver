extends Node2D

@export var monkey_scene: PackedScene
@export var enemies_per_wave: int = 2
@export var spawn_delay: float = 1.0
# Limites do mapa onde inimigos podem spawnar.
@export var spawn_min_x: float = 32.0
@export var spawn_max_x: float = 448.0
@export var spawn_min_y: float = 32.0
@export var spawn_max_y: float = 240.0
@export var min_distance_from_player: float = 80.0

var wave_number: int = 0
var spawning: bool = false


func _ready() -> void:
	_spawn_wave.call_deferred()


func _process(_delta: float) -> void:
	if spawning:
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	if enemies.size() == 0:
		_spawn_wave()


func _spawn_wave() -> void:
	if spawning:
		return
	spawning = true
	wave_number += 1
	if spawn_delay > 0.0:
		await get_tree().create_timer(spawn_delay).timeout
	if monkey_scene == null:
		spawning = false
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		spawning = false
		return
	var player := get_tree().get_first_node_in_group("player")
	for i in range(enemies_per_wave):
		var spawn_pos: Vector2 = _pick_spawn_position(player)
		var monkey := monkey_scene.instantiate()
		world.add_child(monkey)
		monkey.global_position = spawn_pos
	spawning = false


func _pick_spawn_position(player: Node) -> Vector2:
	# Tenta achar uma posição longe do player. Se não conseguir em 20 tentativas, usa qualquer.
	for _attempt in range(20):
		var x: float = randf_range(spawn_min_x, spawn_max_x)
		var y: float = randf_range(spawn_min_y, spawn_max_y)
		var pos: Vector2 = Vector2(x, y)
		if player == null or not is_instance_valid(player):
			return pos
		var player_pos: Vector2 = (player as Node2D).global_position
		if pos.distance_to(player_pos) >= min_distance_from_player:
			return pos
	return Vector2(spawn_min_x, spawn_min_y)
