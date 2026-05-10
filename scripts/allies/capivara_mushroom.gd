extends Area2D

# Cogumelo dropado pela Capivara Joe.
# Duas variantes:
#   BUFF (default): pickup pelo player. Se HP<50% cura 100%, senão move
#   speed buff. L3+: dá AMBOS efeitos + atk speed +50% por 3s.
#   DAMAGE (is_damage_variant=true, tint roxo): trigger por inimigo passando
#   por cima — explode AoE roxa que dá 40 dano em 5s.

@export var is_damage_variant: bool = false
@export var aoe_scene: PackedScene
# Buff de speed (variante buff): adiciona +X ao move_speed_multiplier do player
# por buff_duration segundos. (X é grande pra ser "forte" como pediu o design.)
@export var buff_speed_amount: float = 0.80  # +80% durante o buff
@export var buff_duration: float = 1.3
# L3+: atk speed também (mesma duração).
@export var l3_atk_speed_amount: float = 0.50  # +50%
# Threshold de HP pra escolher cura vs speed.
@export var heal_threshold_pct: float = 0.50
# Cura fixa do cogumelo (HP) — usada quando o player está abaixo do threshold.
@export var heal_amount: float = 36.75
# Som tocado quando o player coleta (mesmo do coração do Life Steal).
@export var pickup_sound: AudioStream
# Som tocado quando o inimigo pisa no cogumelo de dano.
@export var explode_sound: AudioStream
@export var explode_sound_volume_db: float = -10.0

const PURPLE_TINT: Color = Color(0.78, 0.45, 0.95, 1.0)
# L1/L2: chance de o cogumelo dar os dois buffs (cura + speed) num único pickup.
const BLESSED_MUSHROOM_CHANCE: float = 0.05
const PICKUP_ANIM_DURATION: float = 0.22
const EXPLODE_ANIM_DURATION: float = 0.28
const EXPLODE_SCALE_TARGET: float = 2.6

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var collision: CollisionShape2D = get_node_or_null("CollisionShape2D")

var _spent: bool = false


func _ready() -> void:
	add_to_group("capivara_mushroom")
	body_entered.connect(_on_body_entered)
	if sprite != null:
		if is_damage_variant:
			sprite.modulate = PURPLE_TINT
		sprite.play("idle")


func _on_body_entered(body: Node) -> void:
	if _spent:
		return
	if is_damage_variant:
		# Cogumelo de dano: só dispara em inimigo. Player não interage.
		if not body.is_in_group("enemy"):
			return
		_trigger_damage_explosion()
	else:
		# Cogumelo de buff: só player coleta.
		if not body.is_in_group("player"):
			return
		_apply_buff_to_player(body)


func _apply_buff_to_player(player: Node) -> void:
	_spent = true
	# Desativa colisão pra não disparar de novo durante a anim.
	if collision != null:
		collision.set_deferred("disabled", true)
	var lvl: int = _capivara_level(player)
	var hp_ratio: float = _player_hp_ratio(player)
	var should_heal: bool = hp_ratio < heal_threshold_pct
	var should_speed: bool = not should_heal
	# L1/L2: 5% de chance de dropar um cogumelo "abençoado" que dá os DOIS efeitos
	# (sem o atk speed, que continua exclusivo do L3+).
	if lvl < 3 and randf() < BLESSED_MUSHROOM_CHANCE:
		should_heal = true
		should_speed = true
	# L3+: dá os DOIS efeitos sempre + atk speed buff.
	if lvl >= 3:
		should_heal = true
		should_speed = true
	if should_heal and player.has_method("heal"):
		player.heal(heal_amount)
	if should_speed and player.has_method("apply_capivara_speed_buff"):
		player.apply_capivara_speed_buff(buff_speed_amount, buff_duration)
	if lvl >= 3 and player.has_method("apply_capivara_atk_speed_buff"):
		player.apply_capivara_atk_speed_buff(l3_atk_speed_amount, buff_duration)
	_play_pickup_sound()
	_play_pickup_anim()


func _trigger_damage_explosion() -> void:
	_spent = true
	if collision != null:
		collision.set_deferred("disabled", true)
	if aoe_scene != null:
		var aoe: Node2D = aoe_scene.instantiate()
		var world: Node = get_tree().get_first_node_in_group("world")
		if world == null:
			world = get_tree().current_scene
		world.add_child(aoe)
		aoe.global_position = global_position
	_play_explode_sound()
	_play_explode_anim()


func _play_pickup_anim() -> void:
	# Sobe + fade out (igual padrão do coração).
	if sprite == null:
		queue_free()
		return
	var t := create_tween().set_parallel(true)
	t.tween_property(sprite, "offset:y", sprite.offset.y - 12.0, PICKUP_ANIM_DURATION)
	t.tween_property(self, "modulate:a", 0.0, PICKUP_ANIM_DURATION)
	t.chain().tween_callback(queue_free)


func _play_explode_anim() -> void:
	# Cogumelo "explode": o sprite escala pra fora e desbota rápido.
	if sprite == null:
		queue_free()
		return
	var target_scale: Vector2 = sprite.scale * EXPLODE_SCALE_TARGET
	var t := create_tween().set_parallel(true)
	t.tween_property(sprite, "scale", target_scale, EXPLODE_ANIM_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, EXPLODE_ANIM_DURATION)
	t.chain().tween_callback(queue_free)


func _play_pickup_sound() -> void:
	if pickup_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = pickup_sound
	p.volume_db = -14.0
	p.pitch_scale = randf_range(0.95, 1.1)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _play_explode_sound() -> void:
	if explode_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = explode_sound
	p.volume_db = explode_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	get_tree().current_scene.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _capivara_level(player: Node) -> int:
	if player != null and player.has_method("get_upgrade_count"):
		return int(player.get_upgrade_count("capivara_joe"))
	return 1


func _player_hp_ratio(player: Node) -> float:
	if "max_hp" in player and "hp" in player and float(player.max_hp) > 0.0:
		return float(player.hp) / float(player.max_hp)
	return 1.0
