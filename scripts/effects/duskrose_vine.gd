extends Area2D

# Vinha espinhosa lançada pela Duskrose. Cresce verticalmente do ponto de
# spawn até a parte de baixo do mapa, tilando o sprite (20×64) o número
# necessário de vezes pra cobrir a distância.
#
# Fases:
#   1. Cast (anim "cast", frames 0-2 ~0.4s): vinha cresce visualmente, SEM
#      collision (player pode atravessar livre — telegraph).
#   2. Active (anim "idle", frame 3 estático): collision ativo. Player ao
#      passar por cima: dano + root (stun de movimento).
#   3. Fade-out (0.6s): alpha pra 0, queue_free.
#
# Tile vertical: parent é um Node2D root, cada filho AnimatedSprite2D é um
# segmento 20×64 stackado em Y.

@export var segment_height: float = 64.0
@export var segment_width: float = 20.0
@export var target_bottom_y: float = 280.0  # quão baixo a vinha vai (world Y)
@export var lifetime: float = 6.0
@export var damage: float = 12.0
@export var damage_mult: float = 1.0
@export var stun_duration: float = 3.0
@export var fade_out_duration: float = 0.6

const VINE_SHEET_PATH: String = "res://assets/enemies/duskrose/vinhas-Sheet.png"
const FRAME_W: int = 20
const FRAME_H: int = 64
# Cast lento (2 fps × 3 frames = 1.5s telegraph) — player tem tempo de reagir
# e ver onde a vinha vai aterrissar antes do collision ligar.
const CAST_FPS: float = 2.0
const CAST_FRAMES: int = 3  # frames 0-2 da sheet
const IDLE_FRAMES: int = 1  # frame 3 (último)
# Som tocado quando vinha bate em player. Mesmo arquivo do cast (Duskrose
# usa pra cast geral; aqui usa só pra hit).
const HIT_SOUND_PATH: String = "res://assets/enemies/duskrose/vinhas espinhocas cast or hit.mp3"
@export var hit_sound_volume_db: float = -10.0

var _segments: Array[AnimatedSprite2D] = []
var _active: bool = false  # true quando collision liga (após anim cast)
var _fading: bool = false
@onready var collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	add_to_group("duskrose_decoration")
	# Quantos segmentos cabem entre spawn point (global_position.y) e target_bottom_y.
	var length: float = maxf(target_bottom_y - global_position.y, segment_height)
	var seg_count: int = int(ceil(length / segment_height))
	seg_count = clampi(seg_count, 1, 10)  # safety cap aumentado pra cobrir mapa maior
	_build_shadow(seg_count)
	_build_segments(seg_count)
	_setup_collision(seg_count)
	# Collision OFF durante a fase de cast.
	collision.disabled = true
	# Toca anim "cast" em todos os segmentos.
	for s in _segments:
		s.play("cast")
	# Idle transition via TIMER (mais confiável que animation_finished signal —
	# que falhava em transicionar pro idle em alguns casos).
	var cast_duration: float = float(CAST_FRAMES) / CAST_FPS
	get_tree().create_timer(cast_duration).timeout.connect(_on_cast_finished)
	body_entered.connect(_on_body_entered)
	# Lifetime timer
	get_tree().create_timer(lifetime).timeout.connect(_start_fade_out)


func _build_shadow(seg_count: int) -> void:
	# Sombra leve por baixo da vinha inteira — Polygon2D capsular (rounded
	# rectangle) que cobre toda a coluna. Adicionada PRIMEIRO ao tree pra
	# renderizar atrás dos sprites dos segments.
	var total_h: float = float(seg_count) * segment_height
	var shadow := Polygon2D.new()
	shadow.color = Color(0, 0, 0, 0.18)
	# Cápsula: semicírculo topo + retângulo middle + semicírculo base.
	# Largura ~10 (mais estreita que o sprite de 20 pra ficar como sombra).
	var pts := PackedVector2Array()
	var radius: float = 6.0
	var sides_per_half: int = 8
	# Top semicircle (vai de PI a 2*PI, vai pra baixo da cápsula)
	for i in range(sides_per_half + 1):
		var ang: float = PI + PI * float(i) / float(sides_per_half)
		pts.append(Vector2(cos(ang) * radius, sin(ang) * radius))
	# Bottom semicircle (vai de 0 a PI)
	for i in range(sides_per_half + 1):
		var ang: float = PI * float(i) / float(sides_per_half)
		pts.append(Vector2(cos(ang) * radius, sin(ang) * radius + total_h))
	shadow.polygon = pts
	shadow.position = Vector2(segment_width * 0.5, 8.0)  # leve offset baixo
	add_child(shadow)


func _build_segments(count: int) -> void:
	var tex: Texture2D = load(VINE_SHEET_PATH) as Texture2D
	if tex == null:
		return
	# Constrói SpriteFrames compartilhado entre os segmentos.
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"cast")
	sf.set_animation_loop(&"cast", false)
	sf.set_animation_speed(&"cast", CAST_FPS)
	for i in CAST_FRAMES:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame(&"cast", atlas)
	sf.add_animation(&"idle")
	sf.set_animation_loop(&"idle", true)
	sf.set_animation_speed(&"idle", 1.0)
	# Frame 3 (último) é o idle.
	var idle_atlas := AtlasTexture.new()
	idle_atlas.atlas = tex
	idle_atlas.region = Rect2(CAST_FRAMES * FRAME_W, 0, FRAME_W, FRAME_H)
	sf.add_frame(&"idle", idle_atlas)
	# Cria N segmentos stackados verticalmente.
	for i in count:
		var seg := AnimatedSprite2D.new()
		seg.sprite_frames = sf
		seg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		# Anchor do node = topo do segmento. Position y aumenta pra baixo.
		seg.position = Vector2(0, i * segment_height)
		seg.centered = false
		add_child(seg)
		_segments.append(seg)


func _setup_collision(seg_count: int) -> void:
	# Collision retangular cobrindo todos os segmentos. Ancora no topo.
	var total_h: float = seg_count * segment_height
	var rect := RectangleShape2D.new()
	rect.size = Vector2(segment_width, total_h)
	collision.shape = rect
	collision.position = Vector2(segment_width * 0.5, total_h * 0.5)


func _on_cast_finished() -> void:
	# Fim do crescimento — transição pra idle, libera collision (vinha ativa).
	_active = true
	collision.disabled = false
	for s in _segments:
		s.play("idle")


func _on_body_entered(body: Node) -> void:
	if not _active or _fading:
		return
	if not body.is_in_group("player"):
		return
	if body.has_method("take_damage"):
		body.take_damage(damage * damage_mult, "duskrose_vine")
	# Stun completo: trava movimento + ataques + força anim idle. Mesmo
	# efeito que o Claudio Druida aplica nos macacos (ícone de stun acima da
	# cabeça). Player continua vulnerável a dano durante o stun.
	if body.has_method("apply_stun"):
		body.apply_stun(stun_duration)
	elif body.has_method("apply_slow"):
		# Fallback caso o alvo não suporte stun (entidades futuras).
		body.apply_slow(0.01, stun_duration)
	# Som do hit — toca no mundo (sobrevive se vinha sumir mid-sound).
	var sound: AudioStream = load(HIT_SOUND_PATH) as AudioStream
	if sound != null:
		var p := AudioStreamPlayer2D.new()
		p.bus = &"SFX"
		p.stream = sound
		p.volume_db = hit_sound_volume_db
		p.pitch_scale = randf_range(0.95, 1.05)
		var world: Node = get_tree().get_first_node_in_group("world")
		if world == null:
			world = get_tree().current_scene
		world.add_child(p)
		p.global_position = global_position
		p.play()
		p.finished.connect(p.queue_free)


func _start_fade_out() -> void:
	if _fading:
		return
	_fading = true
	collision.disabled = true
	# Fade todos os segmentos juntos.
	var t := create_tween().set_parallel(true)
	for s in _segments:
		t.tween_property(s, "modulate:a", 0.0, fade_out_duration)
	t.chain().tween_callback(queue_free)
