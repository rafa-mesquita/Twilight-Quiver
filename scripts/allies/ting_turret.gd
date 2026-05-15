extends Node2D

# Torreta dropada pelo Mecânico Ting. Sem HP, não-targetável por inimigos.
# - Pega o enemy mais próximo dentro de attack_range
# - Atira a cada cooldown segundos (base 2s, reduzido por mages_killed_this_wave)
# - Damage = base_arrow_damage × arrow_damage_multiplier do player (escala com
#   o status "Dano" comprado na loja)
# - L2+: passa aoe_damage_pct/aoe_radius pro projétil pra dano em área
# - Auto-destroi após lifetime — pop-in/pop-out visual

@export var lifetime: float = 8.0
@export var attack_range: float = 180.0
# Cooldown base (L1/L2 = 2.0s; L3+ Ting baixa pra 1.7s via export quando dropa).
@export var attack_cooldown_base: float = 2.0
@export var projectile_scene: PackedScene
# AoE secundário do projétil. L1 = 0 (single target). L2+ = 0.10 (10% do
# damage primário em todos enemies dentro de aoe_radius).
@export var aoe_damage_pct: float = 0.0
@export var aoe_radius: float = 32.0
@export var attack_sound: AudioStream
@export var attack_sound_volume_db: float = -22.0

# Dano base do arco (replica BASE_ARROW_DAMAGE do arrow.gd). Multiplicado pelo
# arrow_damage_multiplier do player no momento do disparo — sem hard-coupling.
const BASE_ARROW_DAMAGE: float = 25.0
const ATTACK_SOUND_DURATION: float = 1.0
# Fade-out começa nesse tempo antes do _die — visual de "torreta sumindo".
const FADE_OUT_DURATION: float = 0.5

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle

var _attack_cd_remaining: float = 0.0
var _is_attacking: bool = false
var _player: Node = null
var _locked_target: Node2D = null


func _ready() -> void:
	add_to_group("ting_turret")
	add_to_group("ally")
	_player = get_tree().get_first_node_in_group("player")
	if sprite != null:
		sprite.animation_finished.connect(_on_anim_finished)
		sprite.play("idle")
	# Pop-in: começa pequena e cresce até scale 1.
	scale = Vector2(0.3, 0.3)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Fade nos últimos 0.5s antes do _die.
	var fade_at: float = maxf(lifetime - FADE_OUT_DURATION, 0.0)
	get_tree().create_timer(fade_at).timeout.connect(_start_fade)
	get_tree().create_timer(lifetime).timeout.connect(_die)


func _physics_process(delta: float) -> void:
	if _attack_cd_remaining > 0.0:
		_attack_cd_remaining = maxf(_attack_cd_remaining - delta, 0.0)
	if _is_attacking:
		return
	if _attack_cd_remaining > 0.0:
		return
	var target: Node2D = _pick_target()
	if target == null:
		return
	_locked_target = target
	_is_attacking = true
	_attack_cd_remaining = _current_cooldown()
	# Flip pra mirar o alvo (sprite default olha pra direita). O Muzzle tem
	# posição local fixa no lado da boca; quando o sprite flipa, precisa
	# espelhar o X dele também — senão o tiro sai do lado errado (bunda).
	if sprite != null:
		var facing_left: bool = (target.global_position.x - global_position.x) < 0.0
		sprite.flip_h = facing_left
		if muzzle != null:
			muzzle.position.x = -absf(muzzle.position.x) if facing_left else absf(muzzle.position.x)
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("shoot"):
		sprite.play("shoot")
	else:
		_fire()
		_is_attacking = false


func _on_anim_finished() -> void:
	if sprite.animation == "shoot":
		_fire()
		_is_attacking = false
		sprite.play("idle")


func _fire() -> void:
	if projectile_scene == null:
		return
	var aim_target: Node2D = _locked_target
	if aim_target == null or not is_instance_valid(aim_target):
		aim_target = _pick_target()
	if aim_target == null:
		return
	# Posição visual de onde o tiro deve sair (= muzzle, "boca" da torreta).
	var muzzle_visual_pos: Vector2 = muzzle.global_position if muzzle != null else global_position
	# Mira visual no peito do inimigo (consistente com mage projectile).
	var aim_visual_pos: Vector2 = aim_target.global_position + Vector2(0, -12)
	var dir: Vector2 = (aim_visual_pos - muzzle_visual_pos).normalized()
	if dir.length_squared() < 0.001:
		return
	var proj: Node2D = projectile_scene.instantiate()
	if "damage" in proj:
		proj.damage = _current_damage()
	if "aoe_radius" in proj:
		proj.aoe_radius = aoe_radius if aoe_damage_pct > 0.0 else 0.0
	if "aoe_damage_pct" in proj:
		proj.aoe_damage_pct = aoe_damage_pct
	if "source" in proj:
		proj.source = _player
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(proj)
	# Compensa o VISUAL_OFFSET (0,-24) do projétil: o NÓ vai 24px abaixo do
	# muzzle pra o sprite (renderizado 24px acima do nó) sair exatamente da
	# "boca" onde o user posicionou o Muzzle.
	proj.global_position = muzzle_visual_pos + Vector2(0, 24)
	if proj.has_method("set_target"):
		proj.set_target(aim_target, dir)
	_play_attack_sound()


func _pick_target() -> Node2D:
	var nearest: Node2D = null
	var best: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		if (e as Node).is_in_group("boss_shielded"):
			continue
		var d: float = (e as Node2D).global_position.distance_to(global_position)
		if d <= attack_range and d < best:
			nearest = e
			best = d
	return nearest


func _current_cooldown() -> float:
	# +3% atk speed por mago morto na wave (compounding via divisão no cd).
	# Nas waves do boss (gorila mago), o bônus é 20% mais fraco = 2.4% por mago,
	# pra evitar snowball absurdo já que o boss invoca dezenas de magos.
	var mages: int = 0
	if _player != null and _player.has_method("get_mages_killed_this_wave"):
		mages = int(_player.get_mages_killed_this_wave())
	var per_mage_bonus: float = 0.03
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and wm.has_method("is_boss_wave_now") and bool(wm.is_boss_wave_now()):
		per_mage_bonus *= 0.8
	return attack_cooldown_base / (1.0 + float(mages) * per_mage_bonus)


func _current_damage() -> float:
	var mult: float = 1.0
	if _player != null and "arrow_damage_multiplier" in _player:
		mult = float(_player.arrow_damage_multiplier)
	return BASE_ARROW_DAMAGE * mult


func _start_fade() -> void:
	# Guard contra dispose antecipado (_cleanup_ting_turrets do wave_manager mata
	# a torreta no fim da wave antes do lifetime estourar — os SceneTreeTimers
	# de _start_fade/_die ainda disparam e tocariam create_tween em nó freed).
	if not is_inside_tree():
		return
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)


func _die() -> void:
	if is_inside_tree():
		queue_free()


func _play_attack_sound() -> void:
	if attack_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = attack_sound
	p.volume_db = attack_sound_volume_db
	var world: Node = get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(ATTACK_SOUND_DURATION).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)
