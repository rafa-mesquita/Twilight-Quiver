extends CharacterBody2D

# Mini Mago (aliado, 4 níveis — design dos upgrades a definir).
# Sem HP, não-targetável. Vagueia pelo mapa parecido com a Capivara/Ting e a
# cada `summon_interval` segundos para, toca anim "cast" e invoca um macaco
# aliado (mesmo modelo do macaco convertido pela Maldição: spawn monkey_enemy
# + CurseAllyHelper.convert_to_ally).
#
# Sprite sheet (96×96): 3 frames × 3 anims arranjadas em rows
#   - row 0 (y=0):  idle (3 frames)
#   - row 1 (y=32): walk (3 frames)
#   - row 2 (y=64): cast (3 frames)
# SpriteFrames é construído em runtime via load() pra não quebrar se o PNG
# ainda não foi exportado do .aseprite.

@export var speed: float = 50.0
@export var summon_interval: float = 8.0
@export var monkey_scene: PackedScene
@export var wander_bounds: Rect2 = Rect2(5, 8, 510, 284)
@export var arrive_dist: float = 6.0
@export var cast_sound: AudioStream
@export var cast_sound_volume_db: float = -14.0
# Quantos macacos invocar por cast (L1-2=1, L3=2, L4=3). Player sobrescreve.
@export var monkey_count: int = 1
# Multiplicador de HP/damage/atk speed/move speed dos macacos invocados.
# L1=1.0 (vanilla), L2+=1.25 (+25%). Player sobrescreve.
@export var monkey_buff_mult: float = 1.0

const SPRITE_SHEET_PATH: String = "res://assets/aliados/mamago/mini-mago.png"
const FRAME_W: int = 32
const FRAME_H: int = 32
const FRAMES_PER_ANIM: int = 3
const IDLE_ROW: int = 0
const WALK_ROW: int = 1
const CAST_ROW: int = 2
const IDLE_FPS: float = 4.0
const WALK_FPS: float = 6.0
const CAST_FPS: float = 6.0
# Raio em que o macaco invocado spawna ao redor do mini mago — mesmo padrão
# do summoner_mage (3 tiles × 16px = 48px, com jitter de ±4px). Ângulo
# aleatório a cada cast. Sem isso o macaco saía em cima do mini mago.
const SUMMON_TILE_SIZE: float = 16.0
const SUMMON_DISTANCE_TILES: int = 3
const SUMMON_RADIUS_JITTER: float = 4.0
const SUMMON_EFFECT_SCENE: PackedScene = preload("res://scenes/effects/summon_effect.tscn")

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _waypoint: Vector2 = Vector2.ZERO
var _summon_cd: float = 0.0
var _is_casting: bool = false
var _anti_stuck: AntiStuckHelper = AntiStuckHelper.new()


func _ready() -> void:
	add_to_group("ally")
	add_to_group("mini_mago")
	_build_sprite_frames()
	sprite.animation_finished.connect(_on_anim_finished)
	_summon_cd = summon_interval
	_pick_new_waypoint()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")


# Drenagem de cooldown acelerada pela Essência Vital do player (1.0 se sem item).
func _cd_drain_mult() -> float:
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("cooldown_drain_mult"):
		return p.cooldown_drain_mult()
	return 1.0


func _physics_process(delta: float) -> void:
	# Entre waves (shop, cinematic): para. Mesmo padrão dos outros pets.
	if not _is_wave_active():
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _summon_cd > 0.0:
		_summon_cd = maxf(_summon_cd - delta * _cd_drain_mult(), 0.0)
	if _is_casting:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if _summon_cd <= 0.0:
		_start_cast()
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
	if absf(dir.x) > 0.001:
		sprite.flip_h = dir.x < 0.0
	if sprite.sprite_frames != null and sprite.animation != "walk" and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")


func _pick_new_waypoint() -> void:
	_waypoint = Vector2(
		randf_range(wander_bounds.position.x, wander_bounds.position.x + wander_bounds.size.x),
		randf_range(wander_bounds.position.y, wander_bounds.position.y + wander_bounds.size.y)
	)


func _start_cast() -> void:
	_is_casting = true
	_play_cast_sound()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("cast"):
		sprite.play("cast")
	else:
		_finish_cast()


func _on_anim_finished() -> void:
	if sprite.animation == "cast":
		_finish_cast()


func _finish_cast() -> void:
	_spawn_monkey_ally()
	_summon_cd = summon_interval
	_is_casting = false
	_pick_new_waypoint()
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation("walk"):
		sprite.play("walk")


func _spawn_monkey_ally() -> void:
	if monkey_scene == null:
		return
	# Segura o spawn fora da wave — a anim "cast" pode ter começado pouco antes
	# do fim da horda e disparado o animation_finished durante a loja.
	if not _is_wave_active():
		return
	# L1=1, L3=2, L4=3 macacos por cast. Ângulos espaçados em volta do mini mago
	# (sem stackar em cima um do outro). Pequeno jitter de raio pra parecer natural.
	var count: int = maxi(1, monkey_count)
	var base_angle: float = randf() * TAU
	for i in count:
		var angle: float = base_angle + (TAU / float(count)) * float(i)
		var radius: float = SUMMON_DISTANCE_TILES * SUMMON_TILE_SIZE + randf_range(-SUMMON_RADIUS_JITTER, SUMMON_RADIUS_JITTER)
		var spawn_pos: Vector2 = global_position + Vector2(cos(angle), sin(angle)) * radius
		_spawn_single_monkey_at(spawn_pos)


func _spawn_single_monkey_at(spawn_pos: Vector2) -> void:
	var monkey: Node2D = monkey_scene.instantiate()
	# Aplica buff de stats ANTES de add_child pra max_hp já entrar com o boost
	# (monkey._ready faz hp = max_hp, então a ordem importa).
	if monkey_buff_mult != 1.0:
		if "max_hp" in monkey:
			monkey.max_hp = float(monkey.max_hp) * monkey_buff_mult
		if "damage" in monkey:
			monkey.damage = float(monkey.damage) * monkey_buff_mult
		if "speed" in monkey:
			monkey.speed = float(monkey.speed) * monkey_buff_mult
		# Atk speed = inverso do cooldown (cooldown menor → ataca mais rápido).
		if "attack_cooldown" in monkey:
			monkey.attack_cooldown = float(monkey.attack_cooldown) / monkey_buff_mult
	_get_world().add_child(monkey)
	monkey.global_position = spawn_pos
	# Converte imediatamente em aliado (mesmo modelo do macaco da Maldição).
	# Tag extra "mini_mago_summon" pra atribuir dano dele à categoria "mini_mago"
	# no painel TAB + bloqueio de gold drop.
	if monkey.has_method("play_spawn_in"):
		monkey.play_spawn_in()
	if not monkey.is_in_group("mini_mago_summon"):
		monkey.add_to_group("mini_mago_summon")
	CurseAllyHelper.convert_to_ally(monkey)
	# Efeito visual lilás no ponto de spawn — coerente com summon do mage.
	if SUMMON_EFFECT_SCENE != null:
		var fx: Node = SUMMON_EFFECT_SCENE.instantiate()
		_get_world().add_child(fx)
		if fx is Node2D:
			(fx as Node2D).global_position = spawn_pos


func _play_cast_sound() -> void:
	if cast_sound == null:
		return
	var p := AudioStreamPlayer2D.new()
	p.bus = &"SFX"
	p.stream = cast_sound
	p.volume_db = cast_sound_volume_db
	p.pitch_scale = randf_range(0.95, 1.05)
	_get_world().add_child(p)
	p.global_position = global_position
	p.play()
	var ref: AudioStreamPlayer2D = p
	get_tree().create_timer(2.0).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.queue_free()
	)


func _build_sprite_frames() -> void:
	# Fallback: só constrói em runtime se a scene não tem sprite_frames pré-
	# configurado (caso o PNG não estivesse exportado quando a scene foi salva).
	# Com sprite_frames embutidos na .tscn (default agora), esta função é no-op.
	if sprite.sprite_frames != null:
		return
	if not ResourceLoader.exists(SPRITE_SHEET_PATH):
		return
	var tex: Texture2D = load(SPRITE_SHEET_PATH) as Texture2D
	if tex == null:
		return
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	_add_anim(sf, &"idle", tex, IDLE_ROW, IDLE_FPS, true)
	_add_anim(sf, &"walk", tex, WALK_ROW, WALK_FPS, true)
	_add_anim(sf, &"cast", tex, CAST_ROW, CAST_FPS, false)
	sprite.sprite_frames = sf


func _add_anim(sf: SpriteFrames, anim_name: StringName, tex: Texture2D, row: int, fps: float, loop: bool) -> void:
	sf.add_animation(anim_name)
	sf.set_animation_loop(anim_name, loop)
	sf.set_animation_speed(anim_name, fps)
	for i in FRAMES_PER_ANIM:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * FRAME_W, row * FRAME_H, FRAME_W, FRAME_H)
		sf.add_frame(anim_name, atlas)


func _is_wave_active() -> bool:
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm == null:
		return true
	return bool(wm.get("wave_active"))


func _get_world() -> Node:
	var w: Node = get_tree().get_first_node_in_group("world")
	if w == null:
		w = get_tree().current_scene
	return w
