extends CharacterBody2D

# Capivara Joe (aliado pet, 4 níveis).
# Sem HP, NÃO é alvejada por inimigos. Vagueia em 75% do mapa interno.
# A cada drop_interval, para, toca anim "drop", e ao terminar spawna
# um cogumelo na posição. Volta a vaguear.
#
# L1: drop a cada 14s. Cogumelo só de buff (cura ou speed).
# L2: drop a cada 7s. Alterna buff/dano (purple) — o de dano explode
#     quando inimigo passa, AoE roxa 40 dmg em 5s.
# L3: cogumelo de buff dá AMBOS efeitos (cura + speed) + atk speed
#     +50% por 3s (resolvido em capivara_mushroom.gd lendo lvl).
# L4: 2 capivaras (gerenciado pelo player).

@export var speed: float = 50.0
@export var drop_interval: float = 14.0
@export var mushroom_scene: PackedScene
# Bounds do wander (75% do mapa interno). Capivara só anda dentro disso.
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
# Distância em que considera "chegou" no waypoint (sorteia outro).
@export var arrive_dist: float = 6.0
# Som tocado ao começar a anim de drop.
@export var drop_sound: AudioStream
@export var drop_sound_volume_db: float = -14.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _waypoint: Vector2 = Vector2.ZERO
var _drop_cd: float = 0.0
var _drop_counter: int = 0  # alterna buff/dano no L2+
var _is_dropping: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()


func _ready() -> void:
	add_to_group("ally")
	add_to_group("capivara_joe")
	sprite.animation_finished.connect(_on_anim_finished)
	_pick_new_waypoint()
	_drop_cd = drop_interval
	sprite.play("walk")


# Drenagem de cooldown acelerada pela Essência Vital do player (1.0 se sem item).
func _cd_drain_mult() -> float:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("cooldown_drain_mult"):
		return p.cooldown_drain_mult()
	return 1.0


func _physics_process(delta: float) -> void:
	# Entre waves (shop, intro de raid, cinematic do boss): capivara para.
	# Sem isso, ela continuava o ciclo e dropava cogumelos durante o tempo da
	# loja — o set inicial da próxima wave é definido por
	# wave_manager._spawn_capivara_starter_mushrooms.
	if not _is_wave_active():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Cooldown do drop.
	if _drop_cd > 0.0:
		_drop_cd = maxf(_drop_cd - delta * _cd_drain_mult(), 0.0)
	# Durante a animação de drop fica parada.
	if _is_dropping:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Hora de dropar?
	if _drop_cd <= 0.0:
		_start_drop()
		return
	# Wander: vai pro waypoint atual.
	var to_wp: Vector2 = _waypoint - global_position
	var dist: float = to_wp.length()
	if dist <= arrive_dist:
		_pick_new_waypoint()
		to_wp = _waypoint - global_position
		dist = to_wp.length()
	var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_wp / dist
	# Anti-stuck: se preso em árvore/parede, redireciona lateral pro waypoint.
	if dir.length_squared() > 0.001:
		dir = _anti_stuck.resolve(dir, delta)
	velocity = dir * speed
	move_and_slide()
	_anti_stuck.update(self, _waypoint, dir.length_squared() > 0.001, delta)
	if absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0
	if sprite.animation != "walk":
		sprite.play("walk")


func _pick_new_waypoint() -> void:
	_waypoint = Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _start_drop() -> void:
	_is_dropping = true
	_play_drop_sound()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("drop"):
		sprite.play("drop")
	else:
		# Fallback (sprite sem anim drop): spawna direto.
		_finish_drop()


func _play_drop_sound() -> void:
	if drop_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = drop_sound
	p.volume_db = drop_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _on_anim_finished() -> void:
	if sprite.animation == "drop":
		_finish_drop()


func _finish_drop() -> void:
	_spawn_mushroom()
	_drop_counter += 1
	_drop_cd = drop_interval
	_is_dropping = false
	_pick_new_waypoint()
	sprite.play("walk")


func _spawn_mushroom() -> void:
	if mushroom_scene == null:
		return
	# Anim de drop pode ter começado pouco antes do fim da wave e disparado o
	# animation_finished durante a loja — segura o spawn fora da wave.
	if not _is_wave_active():
		return
	var mush: Node2D = mushroom_scene.instantiate()
	# L2+: alterna buff (par) e damage (ímpar).
	var lvl: int = _capivara_level()
	var is_damage: bool = lvl >= 2 and (_drop_counter % 2 == 1)
	if "is_damage_variant" in mush:
		mush.is_damage_variant = is_damage
	# Wave 14: wave14_map é um Node2D y_sort_enabled separado da Entities
	# (world group). Pra cogumelo y-sort com o poste/cerca/etc. do mapa, ele
	# precisa ser FILHO do wave14_map. Senão renderiza acima/abaixo do mapa
	# inteiro (não respeita ordering com props individuais).
	var spawn_parent: Node = _get_world()
	for n in get_tree().get_nodes_in_group("duskrose_decoration"):
		if n is Node2D and (n as Node).scene_file_path == "res://scenes/world/wave14_map.tscn":
			spawn_parent = n
			break
	spawn_parent.add_child(mush)
	# Posição: tenta a posição da capivara; se cair dentro de fumaça letal da
	# Duskrose, desloca pro ponto seguro mais próximo (anel de 60px ao redor).
	mush.global_position = _find_safe_mushroom_position(global_position)


# Raio efetivo da nuvem de fumaça (CircleShape2D radius=32 no smoke.tscn) +
# pequena margem pra cogumelo não pegar dano logo no spawn.
const _SMOKE_AVOID_RADIUS: float = 38.0
const _SAFE_SEARCH_OFFSETS: Array[Vector2] = [
	Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60),
	Vector2(42, 42), Vector2(-42, 42), Vector2(42, -42), Vector2(-42, -42),
	Vector2(90, 0), Vector2(-90, 0), Vector2(0, 90), Vector2(0, -90),
]


func _find_safe_mushroom_position(base: Vector2) -> Vector2:
	# Coleta todas as fumaças vivas. Se base não está em nenhuma, usa base mesmo.
	# Senão, varre offsets predefinidos e retorna o primeiro safe.
	var smokes: Array = get_tree().get_nodes_in_group("duskrose_smoke")
	if smokes.is_empty():
		return base
	if _is_position_safe(base, smokes):
		return base
	for off in _SAFE_SEARCH_OFFSETS:
		var candidate: Vector2 = base + off
		if _is_position_safe(candidate, smokes):
			return candidate
	# Fallback: nenhum spot ao redor está limpo — usa o original (cogumelo
	# vai tomar dano, mas é melhor que não spawnar nada).
	return base


func _is_position_safe(pos: Vector2, smokes: Array) -> bool:
	var r_sq: float = _SMOKE_AVOID_RADIUS * _SMOKE_AVOID_RADIUS
	for s in smokes:
		if not is_instance_valid(s) or not (s is Node2D):
			continue
		if (s as Node2D).global_position.distance_squared_to(pos) <= r_sq:
			return false
	return true


func _is_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return true
	return bool(wm.get("wave_active"))


func _capivara_level() -> int:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("get_upgrade_count"):
		return int(p.get_upgrade_count("capivara_joe"))
	return 1


func _get_world() -> Node:
	var w: Node = get_tree().get_first_node_in_group("world")
	if w == null:
		w = get_tree().current_scene
	return w
