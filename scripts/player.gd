extends CharacterBody2D

signal hp_changed(current: float, maximum: float)
signal gold_changed(total: int)
signal died

@export var speed: float = 55.0
@export var attack_cooldown: float = 1.0
@export var arrow_scene: PackedScene
@export var damage_effect_scene: PackedScene
@export var damage_number_scene: PackedScene
@export var max_hp: float = 100.0
@export var muzzle_offset_x: float = 8.0
@export var death_freeze_duration: float = 1.5  # tempo parado antes da animação de morte
@export var death_fadeout_duration: float = 0.4  # tempo do sprite sumir após kill_effect
@export var death_blackout_duration: float = 0.3  # tempo da tela ficar preta
@export var kill_effect_scene: PackedScene = preload("res://scenes/kill_effect.tscn")
const DEATH_SOUND: AudioStream = preload("res://audios/effects/dead effect.mp3")
@export var poison_number_color: Color = Color(0.55, 1.0, 0.45, 1.0)

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle: Marker2D = $Muzzle
@onready var attack_timer: Timer = $AttackTimer
@onready var hp_bar: Node2D = $HpBar
@onready var damage_audio: AudioStreamPlayer2D = $DamageAudio

const RELEASE_FRAME: int = 4
const POISON_TICK_INTERVAL: float = 0.5

var hp: float
var gold: int = 0
# Upgrade tracking — incrementa ao comprar na shop pós-wave.
var hp_upgrades: int = 0
var damage_upgrades: int = 0
var perfuracao_level: int = 0  # capa em 4 (níveis 1-4)
var arrow_damage_multiplier: float = 1.0  # aplicado ao dano da arrow no spawn
# Conta ataques pra decidir quando proca a flecha perfurante (a cada 3 ataques).
# Reseta ao procar. Em level 4, todo ataque é perfurante (counter ignorado).
var _perf_shot_counter: int = 0
var can_attack: bool = true
var is_attacking: bool = false
var is_drawing: bool = false
var is_dead: bool = false
var locked_aim_dir: Vector2 = Vector2.RIGHT
var locked_facing_left: bool = false
var start_position: Vector2 = Vector2.ZERO

# Status effects (slow + poison DoT). Slow só rastreia o multiplicador mais forte ativo.
var _slow_factor: float = 1.0
var _slow_remaining: float = 0.0
var _poison_dps: float = 0.0
var _poison_remaining: float = 0.0
var _poison_tick_accum: float = 0.0


func _ready() -> void:
	add_to_group("player")
	start_position = global_position
	reset_hp()
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(1.0)

	attack_timer.wait_time = attack_cooldown
	attack_timer.one_shot = true
	attack_timer.timeout.connect(_on_attack_timer_timeout)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.play("idle")


func _physics_process(delta: float) -> void:
	_update_status_effects(delta)
	if is_dead:
		velocity = Vector2.ZERO
		return
	# Durante o cast (atacando), o player fica travado.
	var input_vec := Vector2.ZERO
	if not is_attacking:
		input_vec = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_up", "move_down")
		)
		if input_vec.length() > 1.0:
			input_vec = input_vec.normalized()

	velocity = input_vec * speed * _slow_factor
	move_and_slide()

	_update_facing(input_vec)
	_update_animation(input_vec)


func apply_slow(multiplier: float, duration: float) -> void:
	# Pega o slow mais forte ativo (multiplier mais baixo) e estende a duração se necessário.
	if is_dead:
		return
	if multiplier < _slow_factor or _slow_remaining <= 0.0:
		_slow_factor = multiplier
	_slow_remaining = maxf(_slow_remaining, duration)


func apply_poison(total_damage: float, duration: float) -> void:
	# Sobrescreve poison ativo se o novo for mais forte (DPS maior) ou refresca duração.
	if is_dead or duration <= 0.0:
		return
	var new_dps: float = total_damage / duration
	if new_dps > _poison_dps or _poison_remaining <= 0.0:
		_poison_dps = new_dps
	_poison_remaining = maxf(_poison_remaining, duration)


func _update_status_effects(delta: float) -> void:
	if _slow_remaining > 0.0:
		_slow_remaining -= delta
		if _slow_remaining <= 0.0:
			_slow_remaining = 0.0
			_slow_factor = 1.0

	if _poison_remaining > 0.0:
		_poison_remaining -= delta
		_poison_tick_accum += delta
		while _poison_tick_accum >= POISON_TICK_INTERVAL and _poison_remaining > -POISON_TICK_INTERVAL:
			_poison_tick_accum -= POISON_TICK_INTERVAL
			_apply_poison_tick(_poison_dps * POISON_TICK_INTERVAL)
			if is_dead:
				return
		if _poison_remaining <= 0.0:
			_poison_remaining = 0.0
			_poison_tick_accum = 0.0
			_poison_dps = 0.0


func _apply_poison_tick(amount: float) -> void:
	# Dano silencioso: sem flash/som/damage_effect — só hp-, hp_bar, e damage number verde.
	if is_dead or amount <= 0.0:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(hp / max_hp)
	_spawn_poison_number(amount)
	if hp == 0.0:
		_die()


func _spawn_poison_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	num.modulate = poison_number_color
	num.position = global_position + Vector2(0, -26)
	get_tree().current_scene.add_child(num)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()
		return
	if is_dead:
		return
	if event.is_action_pressed("attack") and can_attack:
		_start_attack()
	elif event.is_action_pressed("skill"):
		_use_skill()


func _update_facing(input_vec: Vector2) -> void:
	# Atacando: usa o lado travado no clique (mesmo critério usado pra prever o muzzle).
	# Andando: direção do movimento.
	if is_attacking:
		sprite.flip_h = locked_facing_left
	elif input_vec.x != 0.0:
		sprite.flip_h = input_vec.x < 0.0
	# Mantém o muzzle no lado pra onde o boneco está olhando.
	muzzle.position.x = -muzzle_offset_x if sprite.flip_h else muzzle_offset_x


func _update_animation(_input_vec: Vector2) -> void:
	if is_attacking:
		return
	if velocity.length() > 0.0:
		if sprite.animation != "walk":
			sprite.play("walk")
	else:
		if sprite.animation != "idle":
			sprite.play("idle")


func _start_attack() -> void:
	# Trava a direção AGORA (no clique). A flecha sai no frame de release com essa direção.
	# Calcula a partir da posição prevista do muzzle (lado pra onde o player vai virar),
	# não do centro do player — senão a flecha sai paralela e erra o alvo por ~muzzle_offset_x.
	var mouse_pos := get_global_mouse_position()
	locked_facing_left = mouse_pos.x < global_position.x
	var predicted_muzzle := global_position + Vector2(
		-muzzle_offset_x if locked_facing_left else muzzle_offset_x,
		muzzle.position.y
	)
	locked_aim_dir = (mouse_pos - predicted_muzzle).normalized()
	can_attack = false
	is_attacking = true
	is_drawing = true
	attack_timer.start()
	sprite.play("attack")


func _release_arrow() -> void:
	is_drawing = false
	if arrow_scene == null:
		return
	var arrow := arrow_scene.instantiate()
	# Configura ANTES de add_child pra _ready() já enxergar os flags.
	arrow.global_position = muzzle.global_position
	if "damage" in arrow:
		arrow.damage = arrow.damage * arrow_damage_multiplier
	# Perfuração: a cada 3 ataques, próxima flecha atravessa tudo + dano bônus.
	# Em level 4, todo ataque é perfurante.
	var is_pierce: bool = _is_piercing_shot()
	if is_pierce:
		if "is_piercing" in arrow:
			arrow.is_piercing = true
		if "damage" in arrow:
			arrow.damage = arrow.damage * (1.0 + _perf_damage_bonus())
		if "hitbox_scale" in arrow and perfuracao_level >= 2:
			arrow.hitbox_scale = 1.8
		_perf_shot_counter = 0
	else:
		_perf_shot_counter += 1
	_get_world().add_child(arrow)
	if arrow.has_method("set_direction"):
		arrow.set_direction(locked_aim_dir)


func _is_piercing_shot() -> bool:
	if perfuracao_level <= 0:
		return false
	if perfuracao_level >= 4:
		return true
	# Levels 1-3: a cada 3 ataques (shots 1,2,3 → 3rd procca).
	return _perf_shot_counter >= 2


func _perf_damage_bonus() -> float:
	match perfuracao_level:
		1: return 0.30
		2: return 0.60
		3: return 0.90
		4: return 0.90
	return 0.0


func _use_skill() -> void:
	# placeholder — definimos a skill depois
	print("skill triggered toward: ", get_global_mouse_position())


func reset_hp() -> void:
	if is_dead:
		return
	hp = max_hp
	hp_changed.emit(hp, max_hp)
	if hp_bar != null:
		hp_bar.set_ratio(1.0)
	_clear_status_effects()


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)


func spend_gold(amount: int) -> bool:
	if amount <= 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


# Aplicação dos upgrades comprados na shop pós-wave.
func apply_upgrade(upgrade_id: String) -> void:
	match upgrade_id:
		"hp":
			hp_upgrades += 1
			# +15% do max_hp original (60) por stack
			max_hp += 15.0
			hp = min(hp + 15.0, max_hp)
			hp_changed.emit(hp, max_hp)
			if hp_bar != null:
				hp_bar.set_ratio(hp / max_hp)
		"damage":
			damage_upgrades += 1
			# +20% no dano da flecha por stack
			arrow_damage_multiplier += 0.20
		"perfuracao":
			perfuracao_level = mini(perfuracao_level + 1, 4)


func get_upgrade_count(upgrade_id: String) -> int:
	match upgrade_id:
		"hp": return hp_upgrades
		"damage": return damage_upgrades
		"perfuracao": return perfuracao_level
	return 0


func _clear_status_effects() -> void:
	_slow_factor = 1.0
	_slow_remaining = 0.0
	_poison_dps = 0.0
	_poison_remaining = 0.0
	_poison_tick_accum = 0.0


func reset_position() -> void:
	if is_dead:
		return
	global_position = start_position
	velocity = Vector2.ZERO


func reset_perf_counter() -> void:
	# Chamado pelo wave_manager no início de cada wave pra evitar que o counter
	# persistente faça a 1ª flecha do round virar perfurante.
	_perf_shot_counter = 0


func take_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(hp - amount, 0.0)
	hp_changed.emit(hp, max_hp)
	hp_bar.set_ratio(hp / max_hp)
	_flash_damage()
	_spawn_damage_effect()
	_spawn_damage_number(amount)
	if damage_audio != null:
		damage_audio.play()
	if hp == 0.0:
		_die()


func _die() -> void:
	is_dead = true
	is_attacking = false
	is_drawing = false
	if sprite != null:
		sprite.stop()
	if hp_bar != null:
		hp_bar.visible = false
	_stop_world_audio()
	# Som de morte tem que vir DEPOIS do _stop_world_audio pra não ser cortado.
	# Anexa no scene root (fora do "world") pra sobreviver à animação de morte.
	_play_death_sound()
	died.emit()
	_play_death_sequence()


func _play_death_sound() -> void:
	if DEATH_SOUND == null:
		return
	# Música pausa pra dar espaço dramático e volta gradual quando o som termina.
	var music := get_tree().current_scene.get_node_or_null("Music") as AudioStreamPlayer
	var music_original_db: float = -30.0
	if music != null:
		music_original_db = music.volume_db
		var fade_down := create_tween()
		fade_down.tween_property(music, "volume_db", -80.0, 0.25)
		fade_down.tween_callback(music.stop)
	var p := AudioStreamPlayer.new()
	p.stream = DEATH_SOUND
	p.volume_db = -14.0
	get_tree().current_scene.add_child(p)
	p.play()
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
		if music != null and is_instance_valid(music):
			music.volume_db = -80.0
			music.play()
			var fade_up := create_tween()
			fade_up.tween_property(music, "volume_db", music_original_db, 1.8)
	)


func _stop_world_audio() -> void:
	# Para todos AudioStreamPlayer2D do mundo (projétil shoot sounds, damage
	# sounds dinâmicos, etc) pra não continuarem soando durante a tela de morte.
	# Música de fundo fica em Main (fora de "world"), então não é afetada.
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		return
	_stop_audio_in_subtree(world)


func _stop_audio_in_subtree(node: Node) -> void:
	if node is AudioStreamPlayer2D:
		(node as AudioStreamPlayer2D).stop()
	elif node is AudioStreamPlayer:
		(node as AudioStreamPlayer).stop()
	for child in node.get_children():
		_stop_audio_in_subtree(child)


func _play_death_sequence() -> void:
	# Toda a sequência roda na HUD (CanvasLayer top), pra ficar por cima do preto.
	# O player "real" no mundo é escondido — o clone na HUD que aparece.
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.has_method("play_death_sequence"):
		return
	if sprite != null:
		sprite.visible = false
	hud.play_death_sequence(
		sprite,
		kill_effect_scene,
		death_freeze_duration,
		death_fadeout_duration,
		death_blackout_duration
	)


func _spawn_damage_effect() -> void:
	if damage_effect_scene == null:
		return
	var fx := damage_effect_scene.instantiate()
	_get_world().add_child(fx)
	# global_position do player = pés (refator do pivô). Sobe 16 pra centro do sprite.
	fx.global_position = global_position + Vector2(0, -16)


var _flash_tween: Tween

func _flash_damage() -> void:
	if sprite == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	sprite.modulate = Color(1.5, 0.3, 0.3, 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(sprite, "modulate", Color.WHITE, 0.2)


func _spawn_damage_number(amount: float) -> void:
	if damage_number_scene == null:
		return
	var num := damage_number_scene.instantiate()
	num.amount = int(round(amount))
	# 10 acima do centro do sprite (que é 16 acima dos pés).
	num.position = global_position + Vector2(0, -26)
	# Damage numbers ficam fora do World pra sempre aparecer por cima (tipo UI).
	get_tree().current_scene.add_child(num)


func _get_world() -> Node:
	var w := get_tree().get_first_node_in_group("world")
	return w if w != null else get_tree().current_scene


func _on_attack_timer_timeout() -> void:
	can_attack = true


func _on_animation_finished() -> void:
	if sprite.animation == "attack":
		is_attacking = false
		# Garantia: se algo cortou a anim antes do release_frame, solta agora.
		if is_drawing:
			_release_arrow()
		sprite.play("idle")


func _on_frame_changed() -> void:
	if is_drawing and sprite.animation == "attack" and sprite.frame == RELEASE_FRAME:
		_release_arrow()
