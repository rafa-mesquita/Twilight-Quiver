class_name FreezeDebuff
extends Node

# Congela inimigo: zera speed + pausa AnimatedSprite2D + cubo de gelo derretendo
# em cima + DoT por tick (light blue numbers) + áudio "ice cracker" em loop.
# Filho do inimigo — quando o inimigo é freed, o debuff e todos os efeitos somem.
# Respeita o grupo `cc_immune` (mage_monkey/stone_cube) — não aplica.

@export var duration: float = 2.0
@export var dps: float = 4.0  # Lv1=4, Lv2+=8 (player passa o valor escalado)

const ICE_CUBE_TEXTURE: Texture2D = preload("res://assets/effects/ice cube.png")
const ICE_CRACKER_SOUND: AudioStream = preload("res://audios/effects/ice cracker.mp3")
# Offset Y do cubo pra ficar centrado no corpo do inimigo (mesmo pattern do
# BODY_CENTER_OFFSET do monkey_enemy).
const ICE_CUBE_OFFSET: Vector2 = Vector2(0, -8)
const TICK_INTERVAL: float = 0.5
# Cor do damage number do gelo — azul claro/ciano pra distinguir do dano normal
# (branco) e dos outros DoTs (burn=branco/laranja, curse=roxo).
const ICE_NUMBER_COLOR: Color = Color(0.55, 0.85, 1.0, 1.0)

var _remaining: float = 0.0
var _tick_accum: float = 0.0
var _original_speed: float = -1.0
var _anim_sprite: AnimatedSprite2D = null
var _anim_paused: bool = false
var _ice_cube: Sprite2D = null
var _cube_tween = null
var _cracker_player: AudioStreamPlayer2D = null


func _ready() -> void:
	_remaining = duration
	var parent: Node = get_parent()
	if parent == null or parent.is_in_group("cc_immune"):
		queue_free()
		return
	_apply_freeze()
	_spawn_ice_cube()
	_start_cracker_audio()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_restore_speed()
		_resume_animation()
		_stop_cracker_audio()
		queue_free()
		return
	# DoT: tick a cada TICK_INTERVAL segundos. Não tick se parent já morreu.
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick()
		if not is_inside_tree():
			return


func _apply_freeze() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if "speed" in parent and _original_speed < 0.0:
		_original_speed = parent.speed
		parent.speed = 0.0
	_anim_sprite = _find_anim_sprite(parent)
	if _anim_sprite != null and _anim_sprite.is_playing():
		# pause() pausa no frame atual. Resume com play() (sem reset).
		_anim_sprite.pause()
		_anim_paused = true


func _restore_speed() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if "speed" in parent and _original_speed >= 0.0:
		parent.speed = _original_speed


func _resume_animation() -> void:
	if _anim_paused and _anim_sprite != null and is_instance_valid(_anim_sprite):
		_anim_sprite.play()
	_anim_paused = false


func _spawn_ice_cube() -> void:
	# Cubo de gelo Sprite2D filho do inimigo — segue posição automaticamente.
	# Fade-out gradual durante toda a duração pra parecer "derretendo".
	var parent: Node = get_parent()
	if parent == null or not (parent is Node2D):
		return
	var sp := Sprite2D.new()
	sp.texture = ICE_CUBE_TEXTURE
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.z_index = 5
	sp.position = ICE_CUBE_OFFSET
	sp.modulate = Color(1, 1, 1, 0.95)
	(parent as Node2D).add_child(sp)
	_ice_cube = sp
	_start_cube_melt(duration)


func _start_cube_melt(melt_time: float) -> void:
	if _ice_cube == null or not is_instance_valid(_ice_cube):
		return
	if _cube_tween != null and _cube_tween.is_valid():
		_cube_tween.kill()
	_cube_tween = _ice_cube.create_tween()
	_cube_tween.tween_property(_ice_cube, "modulate:a", 0.0, melt_time)
	_cube_tween.tween_callback(_ice_cube.queue_free)


func _start_cracker_audio() -> void:
	# AudioStreamPlayer2D em loop como filho do inimigo — segue posição e morre
	# junto quando o inimigo é freed. Loop forçado em runtime (mp3 .import vem
	# com loop=false default).
	var parent: Node = get_parent()
	if parent == null or not (parent is Node2D):
		return
	var stream: AudioStream = ICE_CRACKER_SOUND
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_cracker_player = AudioStreamPlayer2D.new()
	_cracker_player.bus = &"SFX"
	_cracker_player.stream = stream
	_cracker_player.volume_db = -10.0
	(parent as Node2D).add_child(_cracker_player)
	_cracker_player.play()


func _stop_cracker_audio() -> void:
	if _cracker_player != null and is_instance_valid(_cracker_player):
		_cracker_player.stop()
		_cracker_player.queue_free()
		_cracker_player = null


func _apply_tick() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if not parent.has_method("take_damage"):
		return
	if parent.is_queued_for_deletion():
		return
	if "hp" in parent and float(parent.hp) <= 0.0:
		return
	var tick_dmg: float = dps * TICK_INTERVAL
	# Crit roll por tick (mesmo padrão do BurnDoT/CurseDebuff). Flechas Críticas
	# afetam o DoT do gelo também.
	var is_crit: bool = false
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("roll_crit_dot"):
		var crit_d: Dictionary = p.roll_crit_dot(tick_dmg)
		tick_dmg = float(crit_d.get("dmg", tick_dmg))
		is_crit = bool(crit_d.get("crit", false))
		if is_crit:
			CritFeedback.mark_next_hit_crit(parent)
	var was_alive: bool = (not ("hp" in parent)) or float(parent.hp) > 0.0
	parent.take_damage(tick_dmg)
	_notify_player_dmg_kill(tick_dmg, "ice_arrow", was_alive, parent)
	_spawn_ice_number(tick_dmg, is_crit)


func _spawn_ice_number(amount: float, is_crit: bool = false) -> void:
	var parent: Node = get_parent()
	if parent == null or not (parent is Node2D):
		return
	var dmg_scene: PackedScene = load("res://scenes/effects/damage_number.tscn") as PackedScene
	if dmg_scene == null:
		return
	var num: Node = dmg_scene.instantiate()
	if "amount" in num:
		num.amount = int(round(amount))
	if num is CanvasItem:
		# Crit: cor amarela do CritFeedback sobrescreve. Senão: azul claro do gelo.
		(num as CanvasItem).modulate = CritFeedback.CRIT_NUMBER_COLOR if is_crit else ICE_NUMBER_COLOR
	if num is Node2D:
		(num as Node2D).position = (parent as Node2D).global_position + Vector2(0, -28)
	get_tree().current_scene.add_child(num)


func _notify_player_dmg_kill(amount: float, source_id: String, was_alive: bool, target: Node) -> void:
	if not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("notify_damage_dealt_by_source"):
		p.notify_damage_dealt_by_source(amount, source_id)
	if was_alive and p.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			p.notify_kill_by_source(source_id)


# Re-aplicação: nova flecha de gelo bate no mesmo alvo congelado. Estende a
# duração e reinicia o derretimento do cubo do zero (alpha 0.95). Mantém o
# DPS mais alto entre o atual e o novo (não down-grade).
func refresh(new_duration: float, new_dps: float = -1.0) -> void:
	_remaining = maxf(_remaining, new_duration)
	if new_dps > dps:
		dps = new_dps
	if _ice_cube != null and is_instance_valid(_ice_cube):
		_ice_cube.modulate.a = 0.95
		_start_cube_melt(_remaining)


func _find_anim_sprite(node: Node) -> AnimatedSprite2D:
	for child in node.get_children():
		if child is AnimatedSprite2D:
			return child as AnimatedSprite2D
	return null
