extends Area2D

# Barreira permanente de espinhos da Duskrose. Root = THORN área (visível +
# dano forte). Filho `ToxicArea` é zona invisível ACIMA da thorn que dá DoT
# tóxico — pro player não conseguir burlar e ir pra cima da boss.
#
# Posicionada manualmente no wave14_map.tscn. Cleanup junto com wave14_map
# (group "duskrose_decoration").
#
# 2 zonas de dano:
#   1. ThornArea (root, visível): tilingdo sprite da vinha rotacionado 90°
#      + collision retangular @ y = 0..thorn_collision_height. Player em
#      cima = 100% HP em 3s (~34 dps).
#   2. ToxicArea (filho Area2D, invisível com overlay verde): @ y =
#      -toxic_extend_up..0. ~20 dps — DoT que força retreat se player
#      conseguir passar.

# Dimensões da área visível dos espinhos.
@export var area_width: float = 480.0
@export var thorn_collision_height: float = 24.0
# Zona tóxica ACIMA da thorn — cobre desde o wall até o TOPO do mapa.
# 200px é suficiente: com wall em y=25, cobre y=-175 a y=25, bem acima de
# qualquer dash possível do player. Sem isso, player conseguia dashar pra
# uma área "safe" acima da zona tóxica.
@export var toxic_extend_up: float = 200.0
# Damage rates.
@export var thorn_damage_per_tick: float = 17.0  # 100% HP em ~3s @ 0.5s tick
@export var toxic_damage_per_tick: float = 10.0  # ~5s pra matar
@export var tick_interval: float = 0.5
# Stun ao tocar os espinhos (mesma mecânica das vinhas verticais da boss).
@export var thorn_stun_duration: float = 3.0
# Cores.
@export var purple_tint: Color = Color(1.5, 0.5, 1.3, 1.0)

# Bubbles animadas que cobrem a zona tóxica (substituem o filtro verde antigo).
# Cada bubble é AnimatedSprite2D 32×32 loop de 5 frames com fps + initial frame
# randomizados pra não sincronizar (efeito orgânico).
@export var bubble_density: int = 40  # quantas bubbles spawnar na zona tóxica
const BUBBLES_SHEET_PATH: String = "res://assets/enemies/duskrose/bubbles-Sheet.png"
const BUBBLE_FRAME_COUNT: int = 5
const BUBBLE_FRAME_W: int = 32
const BUBBLE_FRAME_H: int = 32
const BUBBLE_FPS_BASE: float = 5.0
const BUBBLE_SPEED_MIN: float = 0.7  # speed_scale mínimo
const BUBBLE_SPEED_MAX: float = 1.4  # speed_scale máximo

const VINE_SHEET: Texture2D = preload("res://assets/enemies/duskrose/vinhas-Sheet.png")
const FRAME_W: int = 20
const FRAME_H: int = 64
const IDLE_FRAME_INDEX: int = 3

var _toxic_area: Area2D
var _player_in_thorn: bool = false
var _player_in_toxic: bool = false
var _player_ref: Node2D = null
var _thorn_tick_accum: float = 0.0
var _toxic_tick_accum: float = 0.0


func _ready() -> void:
	add_to_group("duskrose_decoration")
	z_index = 2
	collision_layer = 0
	collision_mask = 1  # detecta player na ThornArea (root)
	_build_visual()
	_build_thorn_collision()
	_build_toxic_area()
	body_entered.connect(_on_thorn_entered)
	body_exited.connect(_on_thorn_exited)


func _build_visual() -> void:
	# Tile do sprite da vinha (frame idle) rotacionado 90° = horizontal.
	var atlas := AtlasTexture.new()
	atlas.atlas = VINE_SHEET
	atlas.region = Rect2(IDLE_FRAME_INDEX * FRAME_W, 0, FRAME_W, FRAME_H)
	# 20×64 rotacionado vira 64×20 visualmente.
	var tile_visual_width: float = float(FRAME_H)  # 64
	var tile_visual_height: float = float(FRAME_W)  # 20
	var tile_count: int = int(ceil(area_width / tile_visual_width))
	for i in tile_count:
		var s := Sprite2D.new()
		s.texture = atlas
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.rotation = PI * 0.5
		s.modulate = purple_tint
		s.position = Vector2(
			float(i) * tile_visual_width + tile_visual_width * 0.5,
			tile_visual_height * 0.5
		)
		add_child(s)
	# Bubbles animadas espalhadas na zona tóxica (substituem o overlay verde).
	# Cada bubble com initial_frame e speed_scale random pra não sincronizar.
	_build_toxic_bubbles()


func _build_toxic_bubbles() -> void:
	# Distribuição em GRID com JITTER: divide a zona tóxica em N células e
	# coloca 1 bubble por célula com pequeno offset random. Garante cobertura
	# uniforme sem clusters/gaps (que random puro causava).
	var tex: Texture2D = load(BUBBLES_SHEET_PATH) as Texture2D
	if tex == null:
		return
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"bubble")
	sf.set_animation_loop(&"bubble", true)
	sf.set_animation_speed(&"bubble", BUBBLE_FPS_BASE)
	for i in BUBBLE_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(
			float(i) * float(BUBBLE_FRAME_W), 0,
			float(BUBBLE_FRAME_W), float(BUBBLE_FRAME_H)
		)
		sf.add_frame(&"bubble", atlas)
	# Calcula rows/cols pra grid proporcional ao aspect ratio da zona.
	# rows ≈ sqrt(density * height / width); cols = ceil(density / rows).
	var aspect_factor: float = toxic_extend_up / area_width
	var rows: int = maxi(1, int(round(sqrt(float(bubble_density) * aspect_factor))))
	var cols: int = maxi(1, int(ceil(float(bubble_density) / float(rows))))
	var cell_w: float = area_width / float(cols)
	var cell_h: float = toxic_extend_up / float(rows)
	# Jitter: até 35% do tamanho da célula em cada direção (pra parecer natural
	# sem grid óbvio, mas sem permitir overlap pesado entre células vizinhas).
	var jitter_x: float = cell_w * 0.35
	var jitter_y: float = cell_h * 0.35
	for row in rows:
		for col in cols:
			var cx: float = float(col) * cell_w + cell_w * 0.5 + randf_range(-jitter_x, jitter_x)
			var cy: float = float(row) * cell_h + cell_h * 0.5 + randf_range(-jitter_y, jitter_y)
			# Posição em local coords: x já tá no range certo, y precisa
			# ofsetar pra ficar acima da thorn wall (y=-toxic_extend_up a y=0).
			var bubble := AnimatedSprite2D.new()
			bubble.sprite_frames = sf
			bubble.animation = &"bubble"
			bubble.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			bubble.position = Vector2(cx, cy - toxic_extend_up)
			bubble.speed_scale = randf_range(BUBBLE_SPEED_MIN, BUBBLE_SPEED_MAX)
			bubble.frame = randi() % BUBBLE_FRAME_COUNT
			bubble.z_index = -1
			add_child(bubble)
			bubble.play(&"bubble")


func _build_thorn_collision() -> void:
	# Collision retangular DO ROOT (Area2D). Cobre os espinhos visuais.
	var shape := RectangleShape2D.new()
	shape.size = Vector2(area_width, thorn_collision_height)
	var coll := CollisionShape2D.new()
	coll.shape = shape
	coll.position = Vector2(area_width * 0.5, thorn_collision_height * 0.5)
	add_child(coll)


func _build_toxic_area() -> void:
	# Filho Area2D separado pra detectar player acima da thorn wall.
	_toxic_area = Area2D.new()
	_toxic_area.collision_layer = 0
	_toxic_area.collision_mask = 1
	add_child(_toxic_area)
	var shape := RectangleShape2D.new()
	shape.size = Vector2(area_width, toxic_extend_up)
	var coll := CollisionShape2D.new()
	coll.shape = shape
	coll.position = Vector2(area_width * 0.5, -toxic_extend_up * 0.5)
	_toxic_area.add_child(coll)
	_toxic_area.body_entered.connect(_on_toxic_entered)
	_toxic_area.body_exited.connect(_on_toxic_exited)


func _physics_process(delta: float) -> void:
	if _player_ref == null or not is_instance_valid(_player_ref):
		return
	if _player_in_thorn:
		_thorn_tick_accum += delta
		while _thorn_tick_accum >= tick_interval:
			_thorn_tick_accum -= tick_interval
			if _player_ref.has_method("take_damage"):
				_player_ref.take_damage(thorn_damage_per_tick, "duskrose_permanent_thorn")
	if _player_in_toxic:
		_toxic_tick_accum += delta
		while _toxic_tick_accum >= tick_interval:
			_toxic_tick_accum -= tick_interval
			if _player_ref.has_method("take_damage"):
				_player_ref.take_damage(toxic_damage_per_tick, "duskrose_toxic")


func _on_thorn_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_thorn = true
		_player_ref = body as Node2D
		_thorn_tick_accum = tick_interval
		# Stun ao tocar (mesma mecânica das vinhas espinhosas verticais).
		if body.has_method("apply_stun"):
			body.apply_stun(thorn_stun_duration)


func _on_thorn_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_thorn = false
		_thorn_tick_accum = 0.0
		_maybe_clear_player_ref()


func _on_toxic_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_toxic = true
		_player_ref = body as Node2D
		_toxic_tick_accum = tick_interval


func _on_toxic_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_toxic = false
		_toxic_tick_accum = 0.0
		_maybe_clear_player_ref()


func _maybe_clear_player_ref() -> void:
	if not _player_in_thorn and not _player_in_toxic:
		_player_ref = null
