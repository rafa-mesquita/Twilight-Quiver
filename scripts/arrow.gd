extends Area2D

@export var speed: float = 220.0
@export var lifetime: float = 1.5
@export var damage: float = 25.0
@export var trail_max_points: int = 10
@export var hit_effect_scene: PackedScene
@export var stick_surface_duration: float = 7.5
@export var stick_enemy_duration: float = 2.0
@export var fade_duration: float = 0.5
@export var stick_pullback: float = 5.0
@export var impact_sound: AudioStream
@export var object_impact_sound: AudioStream
@export var sound_volume_db: float = -12.0
@export var knockback_strength: float = 80.0

@onready var trail: Line2D = get_node_or_null("Trail")
@onready var shoot_sound: AudioStreamPlayer2D = get_node_or_null("ShootSound")

var direction: Vector2 = Vector2.RIGHT
var is_stuck: bool = false
# Flecha perfurante: atravessa todos os inimigos E objetos sem cravar.
# Setado pelo player ANTES de add_child quando proca (a cada 3 ataques).
var is_piercing: bool = false
var hitbox_scale: float = 1.0  # > 1 aumenta colisão e sprite (level 2+ da perfuração)
# Quem disparou a flecha. Usado pra ignorar colisão com o próprio shooter
# (ex: torre não atira em si mesma, mas colide com flecha do player).
var source: Node = null
var _hit_bodies: Array[Node] = []
var _pierce_hits: int = 0  # quantos targets a flecha perfurante já atravessou


func _ready() -> void:
	rotation = direction.angle()
	body_entered.connect(_on_hit)
	get_tree().create_timer(lifetime).timeout.connect(_on_lifetime_expired)
	# Defer pra detachar/tocar o som DEPOIS do spawner setar a posição da flecha.
	if shoot_sound != null:
		_setup_shoot_sound.call_deferred()
	if is_piercing:
		_apply_piercing_visuals()
	if hitbox_scale != 1.0:
		_apply_hitbox_scale()


const PIERCING_BASE_SCALE: float = 1.1


func _apply_piercing_visuals() -> void:
	# Tint dourado + trail laranja + sprite/trail 1.1× pra destacar.
	var sprite_node := get_node_or_null("Sprite2D")
	if sprite_node is CanvasItem:
		(sprite_node as CanvasItem).modulate = Color(1.7, 1.25, 0.45, 1.0)
	if sprite_node is Node2D:
		(sprite_node as Node2D).scale = Vector2.ONE * PIERCING_BASE_SCALE
	if trail != null:
		trail.default_color = Color(1.0, 0.7, 0.2, 1.0)
		trail.width *= PIERCING_BASE_SCALE


func _apply_hitbox_scale() -> void:
	# Multiplica sobre o scale base do piercing (1.1) se já foi aplicado.
	var col := get_node_or_null("CollisionShape2D")
	if col is Node2D:
		(col as Node2D).scale = Vector2(hitbox_scale, hitbox_scale)
	var sprite_node := get_node_or_null("Sprite2D")
	if sprite_node is Node2D:
		var current: Vector2 = (sprite_node as Node2D).scale
		(sprite_node as Node2D).scale = current * hitbox_scale


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position)


func _physics_process(delta: float) -> void:
	if is_stuck:
		return
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_hit(body: Node) -> void:
	if is_stuck:
		return
	# Ignora colisão SÓ com o próprio shooter (ex: flecha da torre passa pela torre).
	# Outras flechas (ex: do player) colidem normalmente com aliados.
	if source != null and _is_descendant_of(body, source):
		return
	# Evita re-acertar o mesmo body enquanto perfurando.
	if body in _hit_bodies:
		return
	_hit_bodies.append(body)

	# Sobe o parent chain pra achar quem tem take_damage — o body que entra na
	# colisão pode ser um StaticBody2D filho (caso da torre).
	var target: Node = _find_damageable(body)
	# Aliados (torres, futuras estruturas amigas): flecha do player/torre é uma
	# arrow.gd — friendly fire bloqueado. Bate como parede sem causar dano.
	if target != null and target.is_in_group("ally"):
		_play_oneshot(object_impact_sound, global_position, sound_volume_db, 0.7)
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		_stick_in_place(stick_surface_duration)
		return
	if target != null:
		target.take_damage(damage)
		if target.has_method("apply_knockback"):
			target.apply_knockback(direction, knockback_strength)
		_play_oneshot(impact_sound, global_position, sound_volume_db, 0.7)
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		_stick_in_body(body, stick_enemy_duration)
	else:
		# Superfície sólida sem take_damage (parede, tronco).
		_play_oneshot(object_impact_sound, global_position, sound_volume_db, 0.7)
		if is_piercing:
			_pierce_hits += 1
			_spawn_pierce_hit_effect(_pierce_hits == 3)
			return
		_stick_in_place(stick_surface_duration)


func _stick_in_place(visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	# Z-index direcional: se a flecha voava p/ sul (bateu na parede NORTE do objeto),
	# fica atrás. Se voava p/ norte ou lateral (bateu na parede sul/leste/oeste),
	# fica na frente do objeto. Threshold 0.5 = mais de ~30° de inclinação sul.
	if direction.y > 0.5:
		pass  # mantém z_index = -1 do voo (atrás)
	else:
		z_index = 1  # na frente
	# Recua na direção oposta ao movimento pra:
	# 1. A flecha ficar "encostada" na superfície em vez de enterrada
	# 2. Garantir que arrow.y fique consistentemente do lado certo do alvo pro y-sort
	position -= direction * stick_pullback
	_schedule_fade_out(visible_duration)


func _stick_in_body(body: Node, visible_duration: float) -> void:
	_begin_stick()
	_spawn_hit_effect()
	z_index = 1
	# Defer reparent pra evitar mexer na árvore de cenas durante callback de física.
	_reparent_to.call_deferred(body)
	_schedule_fade_out(visible_duration)


func _begin_stick() -> void:
	is_stuck = true
	set_deferred("monitoring", false)
	if trail != null:
		trail.clear_points()


func _reparent_to(new_parent: Node) -> void:
	if not is_inside_tree() or not is_instance_valid(new_parent) or not new_parent.is_inside_tree():
		return
	var gp := global_position
	var gr := global_rotation
	var current_parent := get_parent()
	if current_parent != null:
		current_parent.remove_child(self)
	new_parent.add_child(self)
	global_position = gp
	global_rotation = gr


func _schedule_fade_out(visible_duration: float) -> void:
	var t := create_tween()
	t.tween_interval(visible_duration)
	t.tween_property(self, "modulate:a", 0.0, fade_duration)
	t.tween_callback(_die)


func _is_descendant_of(node: Node, ancestor: Node) -> bool:
	var n: Node = node
	while n != null:
		if n == ancestor:
			return true
		n = n.get_parent()
	return false


func _find_damageable(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n.has_method("take_damage"):
			return n
		n = n.get_parent()
	return null


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position


# Efeito específico de perfuração. No 3º hit, fica maior e dourado pra
# sinalizar que foi uma perfuração "potente".
func _spawn_pierce_hit_effect(is_third: bool) -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	_get_world().add_child(fx)
	fx.global_position = global_position
	if is_third and fx is Node2D:
		var fx2d: Node2D = fx
		fx2d.scale = Vector2(2.2, 2.2)
		fx2d.modulate = Color(1.6, 1.1, 0.3, 1.0)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_lifetime_expired() -> void:
	# Se já cravou, ignora — o stick timer cuida da remoção.
	if not is_stuck:
		_die()


func _die() -> void:
	if is_inside_tree():
		queue_free()


func _setup_shoot_sound() -> void:
	if shoot_sound == null or not is_instance_valid(shoot_sound):
		return
	if shoot_sound.get_parent() != self:
		return  # já foi detachado
	# Salva posição (já setada pelo spawner agora) e detacha pro World.
	var sound_global_pos: Vector2 = shoot_sound.global_position
	remove_child(shoot_sound)
	_get_world().add_child(shoot_sound)
	shoot_sound.global_position = sound_global_pos
	shoot_sound.volume_db = sound_volume_db
	shoot_sound.play()
	# Lambda captura o ref direto — sobrevive mesmo se a flecha for liberada cedo
	# (ex: inimigo morre e a flecha some como filha dele antes dos 0.7s).
	var sound_ref: AudioStreamPlayer2D = shoot_sound
	get_tree().create_timer(0.7).timeout.connect(func() -> void:
		if is_instance_valid(sound_ref):
			sound_ref.stop()
			sound_ref.queue_free()
	)


func _play_oneshot(stream: AudioStream, pos: Vector2, vol_db: float, max_duration: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = vol_db
	_get_world().add_child(player)
	player.global_position = pos
	player.play()
	if max_duration > 0.0:
		var ref: AudioStreamPlayer2D = player
		get_tree().create_timer(max_duration).timeout.connect(func() -> void:
			if is_instance_valid(ref):
				ref.stop()
				ref.queue_free()
		)
