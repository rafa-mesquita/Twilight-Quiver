extends Area2D

@export var speed: float = 140.0
@export var lifetime: float = 3.0
@export var damage: float = 8.0
@export var poison_damage_total: float = 18.0
@export var poison_duration: float = 3.0
# Slow probabilístico: 40% de chance de aplicar no contato, com os valores
# antigos (pré-remoção): 50% de slow durante 2s. slow_multiplier multiplica a
# speed do player; slow_duration controla quanto tempo dura.
@export var slow_multiplier: float = 0.5
@export var slow_duration: float = 2.0
@export_range(0.0, 1.0) var slow_chance: float = 0.4
@export var trail_max_points: int = 12
@export var hit_effect_scene: PackedScene

# Origem no chão pra Y-sort certo; visual fica acima.
const VISUAL_OFFSET: Vector2 = Vector2(0, -22)
const PLAYER_NODE_TARGET_OFFSET: Vector2 = Vector2(0, 12)

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var trail: Line2D = get_node_or_null("Trail")

var direction: Vector2 = Vector2.RIGHT
# Maldição: setado pelo inseto convertido. Inverte alvo (bate em enemy, ignora player/ally).
var is_ally_source: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(lifetime).timeout.connect(_die)
	# Inseto convertido (ally): muda mask pra detectar enemies (layer 4) em vez
	# de player (layer 1). Mantém walls (layer 2). _on_body_entered filtra allies
	# (que também ficam no layer 4 após conversão) via group check.
	if is_ally_source:
		collision_mask = 6  # 4 (enemy/ally body) + 2 (walls)


func set_direction(dir: Vector2) -> void:
	direction = dir.normalized()
	if sprite != null:
		sprite.rotation = direction.angle()
	if trail != null:
		trail.clear_points()
		trail.add_point(global_position + VISUAL_OFFSET)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	if trail != null:
		trail.add_point(global_position + VISUAL_OFFSET)
		while trail.get_point_count() > trail_max_points:
			trail.remove_point(0)


func _on_body_entered(body: Node) -> void:
	if is_ally_source:
		# Inseto convertido pela maldição: bate em enemy. Aplica damage + slow
		# + poison (habilidade natural do inseto). Curse-on-hit fica bloqueado
		# (curse_ally_helper já filtra is_ally_source) — converted allies não
		# propagam maldição.
		if body.is_in_group("enemy"):
			CurseAllyHelper.apply_ally_curse_on_damage(body, self)  # no-op: bloqueado
			_apply_ally_poison_slow(body)
			if body.has_method("take_damage"):
				body.take_damage(damage)
			_spawn_hit_effect()
			_die()
		return
	# Inseto original: bate só no player (slow + poison existentes).
	if body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		if body.has_method("apply_slow") and slow_duration > 0.0 and randf() < slow_chance:
			body.apply_slow(slow_multiplier, slow_duration)
		if body.has_method("apply_poison"):
			body.apply_poison(poison_damage_total, poison_duration)
	_spawn_hit_effect()
	_die()


func _apply_ally_poison_slow(target: Node) -> void:
	# Inseto aliado: aplica slow temporário (modifica enemy.speed) + DoT via
	# BurnDoT. Reusa BurnDoT pra não criar componente novo — funciona como
	# poison pro enemy (take_damage normal a cada 0.5s).
	if not is_instance_valid(target):
		return
	if "speed" in target and slow_duration > 0.0:
		var orig_speed: float = float(target.speed)
		target.speed = orig_speed * slow_multiplier
		# Restaura speed após slow_duration. Evita stomp se outro slow mais
		# forte foi aplicado depois (pega o min entre o restore e o atual).
		var ref: Node = target
		target.get_tree().create_timer(slow_duration).timeout.connect(
			func() -> void:
				if not is_instance_valid(ref) or not ("speed" in ref):
					return
				if float(ref.speed) < orig_speed:
					ref.speed = orig_speed
		)
	if poison_duration > 0.0 and poison_damage_total > 0.0:
		var dot := BurnDoT.new()
		dot.dps = poison_damage_total / poison_duration
		dot.duration = poison_duration
		target.add_child(dot)


func _spawn_hit_effect() -> void:
	if hit_effect_scene == null:
		return
	var fx := hit_effect_scene.instantiate()
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(fx)
	fx.global_position = global_position + VISUAL_OFFSET


func _die() -> void:
	if is_inside_tree():
		queue_free()
