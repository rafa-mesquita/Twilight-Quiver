extends CharacterBody2D

# Mini Arbusto — decoy spawnado junto com o Arbusto Carrara.
#
# Vaga aleatoriamente pelo mapa (mais devagar que o big arbusto). Normalmente
# não é alvo dos enemies. Quando o player entra no big arbusto, este chama
# set_decoy_active(true) — o mini entra no group "tank_ally" e todos os mobs
# passam a focar nele.
#
# Tem 150 hp. Quando morre, emite o signal `died` (escutado pelo Arbusto
# Carrara que sai do HIDDEN). O player respawna outro mini 3s depois.

signal died

@export var max_hp: float = 120.0
@export var speed: float = 30.0
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0
@export var kill_effect_scene: PackedScene
@export var death_sound: AudioStream
@export var death_sound_volume_db: float = -14.0

# Decay durante o modo decoy:
# - Sem dano recente: perde DECAY_PER_SEC_IDLE hp/seg (mini "murcha" sozinho).
# - Logo após tomar dano (janela RECENT_HIT_WINDOW): decay cai pra DECAY_PER_SEC_HIT.
# Sem decay o mini ficaria vivo pra sempre se mobs ignorassem ele.
const DECAY_PER_SEC_IDLE: float = 20.0
const DECAY_PER_SEC_HIT: float = 5.0
const RECENT_HIT_WINDOW: float = 1.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var hp_bar: Node2D = $HpBar

var hp: float
var _waypoint: Vector2 = Vector2.ZERO
var _is_dead: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()
# Decoy: só toma dano / mostra hp_bar / bloqueia projétil quando ativo.
# Big arbusto liga via set_decoy_active(true) quando player entra no hide.
var _decoy_active: bool = false
# Tempo desde o último hit recebido. Usado pra decidir o rate de decay
# (ver RECENT_HIT_WINDOW). Começa em INF (sem hit ainda).
var _time_since_last_hit: float = INF


func _ready() -> void:
	add_to_group("ally")
	add_to_group("mini_arbusto")
	hp = max_hp
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
		hp_bar.visible = false  # só aparece quando decoy ativo
	_apply_decoy_collision()
	_apply_wave14_safe_bounds_if_needed()
	_pick_new_waypoint()
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")


func _apply_wave14_safe_bounds_if_needed() -> void:
	# Wave 14 (Duskrose): mini fica restrito à área safe — fora da zona tóxica
	# do TopBarrier e da cerca. Mesma lógica do big arbusto.
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return
	if "wave_number" in wm and "boss_redux_wave" in wm and int(wm.wave_number) == int(wm.boss_redux_wave):
		wander_bounds = Rect2(5, 60, 510, 320)


func _physics_process(delta: float) -> void:
	if _is_dead:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if not _is_wave_active():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# Decay enquanto decoy ativo. Rate diminui se tomou dano recentemente —
	# encoraja o player a "deixar mobs baterem" pra o mini durar mais.
	if _decoy_active:
		_time_since_last_hit += delta
		var decay: float = DECAY_PER_SEC_HIT if _time_since_last_hit < RECENT_HIT_WINDOW else DECAY_PER_SEC_IDLE
		hp -= decay * delta
		if hp_bar != null:
			# Decay roda toda frame — usa set_ratio_silent pra não ficar com o
			# trail branco "preso" no HP inicial (mesmo motivo do curse_ally_decay).
			# Hits diretos via take_damage continuam usando set_ratio (trail ok).
			if hp_bar.has_method("set_ratio_silent"):
				hp_bar.set_ratio_silent(maxf(hp / max_hp, 0.0))
			else:
				hp_bar.set_ratio(maxf(hp / max_hp, 0.0))
		if hp <= 0.0:
			_die()
			return
	var to_wp: Vector2 = _waypoint - global_position
	var dist: float = to_wp.length()
	if dist <= arrive_dist:
		_pick_new_waypoint()
		to_wp = _waypoint - global_position
		dist = to_wp.length()
	var dir: Vector2 = Vector2.ZERO if dist < 0.001 else to_wp / dist
	if dir.length_squared() > 0.001:
		dir = _anti_stuck.resolve(dir, delta)
	velocity = dir * speed
	move_and_slide()
	_anti_stuck.update(self, _waypoint, dir.length_squared() > 0.001, delta)
	if sprite != null and absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0


func take_damage(amount: float) -> void:
	if _is_dead or not _decoy_active:
		return  # invulnerável fora do modo decoy
	hp -= amount
	_time_since_last_hit = 0.0
	if hp_bar != null:
		hp_bar.set_ratio(maxf(hp / max_hp, 0.0))
	if hp <= 0.0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_spawn_kill_effect()
	_play_death_sound()
	emit_signal("died")
	queue_free()


func _spawn_kill_effect() -> void:
	if kill_effect_scene == null:
		return
	var fx := kill_effect_scene.instantiate()
	var world := _world_node()
	world.add_child(fx)
	fx.global_position = global_position


func _play_death_sound() -> void:
	# Som de morte precisa sobreviver ao queue_free do mini, então spawna um
	# AudioStreamPlayer2D no world (não como child) e auto-libera quando o
	# stream termina.
	if death_sound == null:
		return
	var sfx := AudioStreamPlayer2D.new()
	sfx.bus = &"SFX"
	sfx.stream = death_sound
	sfx.volume_db = death_sound_volume_db
	var world := _world_node()
	world.add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	var ref: AudioStreamPlayer2D = sfx
	ref.finished.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _world_node() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


# Chamado pelo Arbusto Carrara quando o player entra no hide.
# Liga o decoy: enemies passam a considerar o mini como tank_ally e focam
# nele em vez do player (que está em group "bush_hidden" e portanto invisível).
# Também reseta o HP, habilita take_damage e mostra a hp_bar.
#
# override_max_hp: se > 0, sobrescreve max_hp (usado pelo arbusto.gd pra
# escalar HP por nível de upgrade — L3+ dá +30 HP). Default mantém max_hp atual.
func set_decoy_active(active: bool, override_max_hp: float = -1.0) -> void:
	_decoy_active = active
	if active:
		# Cada engajamento começa com HP full + decay zerado — mini é um
		# defender fresh por hide.
		if override_max_hp > 0.0:
			max_hp = override_max_hp
		hp = max_hp
		_time_since_last_hit = INF
		if hp_bar != null:
			hp_bar.set_ratio(1.0)
			hp_bar.visible = true
		if not is_in_group("tank_ally"):
			add_to_group("tank_ally")
	else:
		if hp_bar != null:
			hp_bar.visible = false
		if is_in_group("tank_ally"):
			remove_from_group("tank_ally")
	_apply_decoy_collision()


func _apply_decoy_collision() -> void:
	# Layer 4 (ally) só quando decoy ativo — fora disso layer 0 pra projéteis
	# atravessarem em vez de detonar no mini. Mask 2 (paredes) preservado pra
	# movimento continuar normal.
	collision_layer = 4 if _decoy_active else 0


func _pick_new_waypoint() -> void:
	_waypoint = Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _is_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return true
	return bool(wm.get("wave_active"))
