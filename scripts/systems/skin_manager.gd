class_name SkinManager
extends Node2D

# Coordena os sprites layered do player.
# - body é o "mestre": player.gd controla animação direto nele.
# - Layers (filhos deste node) sincronizam com o body (frame, anim, flip_h, etc).
# - bow tem 2 sprites: BowSprite (front, filho) + BowBackSprite (sibling do body,
#   posicionado ANTES do body no tree pra renderizar atrás).
# - DashEffectSprite (sibling do body): efeito visual que toca durante dash anim.
# - set_part(slot, part) troca textura(s) do(s) layer(s); null esconde.
#
# Layout dos spritesheets (TODOS os PNGs de skin têm 8 linhas, 32x32 por frame):
#   Row 0: Idle (3 frames)
#   Row 1: Walk (4 frames)
#   Row 2: Attack (5 frames)
#   Row 3-5: damage/arrow_hit/indicator (não usadas pelo player aqui)
#   Row 6: Death (4 frames)
#   Row 7: Dash (4 frames)
#
# Exceção: bow front (PNG 160×64) tem 2 rows: row 0 = attack, row 1 = death.

# NodePath pro AnimatedSprite2D do body (mestre). Default = irmão deste node.
@export var body_path: NodePath = NodePath("../AnimatedSprite2D")
# NodePath pro BowBackSprite (sibling do body).
@export var bow_back_path: NodePath = NodePath("../BowBackSprite")
# NodePath pro DashEffectSprite (sibling do body) — efeito durante dash.
@export var dash_effect_path: NodePath = NodePath("../DashEffectSprite")

# Mapeia slot -> nome do AnimatedSprite2D filho de Skin.
const SLOT_TO_NODE: Dictionary = {
	&"hair":   "HairSprite",
	&"shirt":  "ShirtSprite",
	&"alfaja": "AlfajaSprite",
	&"legs":   "LegsSprite",
	&"cape":   "CapeSprite",
	&"quiver": "QuiverSprite",
	&"bow":    "BowSprite",
}

const FRAME_SIZE: Vector2i = Vector2i(32, 32)

# Layout padrão dos spritesheets (body, hair, cape, etc).
const ANIM_LAYOUT: Dictionary = {
	&"idle":   {"row": 0, "frames": 3, "fps": 4.0,  "loop": true},
	&"walk":   {"row": 1, "frames": 4, "fps": 7.0,  "loop": true},
	&"attack": {"row": 2, "frames": 5, "fps": 8.0,  "loop": false},
	&"death":  {"row": 6, "frames": 4, "fps": 2.5,  "loop": false},
	&"dash":   {"row": 7, "frames": 4, "fps": 18.0, "loop": false},
}

# Bow front: PNG menor com só 2 rows (attack na 0, death na 1).
const BOW_FRONT_LAYOUT: Dictionary = {
	&"attack": {"row": 0, "frames": 5, "fps": 8.0, "loop": false},
	&"death":  {"row": 1, "frames": 4, "fps": 2.5, "loop": false},
}

# Bow tem visibilidade especial baseada na animação:
#  - attack/death: bow FRONT visível (na mão, em cima de tudo)
#  - resto (idle/walk/dash/etc): bow BACK visível (nas costas, atrás do body)
const BOW_FRONT_ANIMATIONS: Array = [&"attack", &"death"]
# Anim que ativa o efeito visual de dash.
const DASH_EFFECT_ANIMATION: StringName = &"dash"

var _body_sprite: AnimatedSprite2D
var _bow_back_sprite: AnimatedSprite2D
var _dash_effect_sprite: AnimatedSprite2D
var _layers: Dictionary = {}
var _frames_cache: Dictionary = {}     # texture -> SpriteFrames
var _bow_has_front: bool = false
var _bow_has_back: bool = false
var _last_anim: StringName = &""


func _ready() -> void:
	_body_sprite = get_node_or_null(body_path) as AnimatedSprite2D
	if _body_sprite == null:
		push_warning("SkinManager: body sprite nao encontrado em '%s'" % body_path)
		return
	_bow_back_sprite = get_node_or_null(bow_back_path) as AnimatedSprite2D
	if _bow_back_sprite != null:
		_bow_back_sprite.visible = false
	_dash_effect_sprite = get_node_or_null(dash_effect_path) as AnimatedSprite2D
	if _dash_effect_sprite != null:
		_dash_effect_sprite.visible = false
	for slot in SLOT_TO_NODE.keys():
		var node_name: String = SLOT_TO_NODE[slot]
		var sprite_node: AnimatedSprite2D = get_node_or_null(node_name) as AnimatedSprite2D
		if sprite_node != null:
			_layers[slot] = sprite_node
			sprite_node.visible = false


func _process(_delta: float) -> void:
	if _body_sprite == null:
		return
	var flip: bool = _body_sprite.flip_h
	var anim: StringName = _body_sprite.animation
	var frame_idx: int = _body_sprite.frame
	var speed: float = _body_sprite.speed_scale
	var mod: Color = _body_sprite.modulate
	if anim != _last_anim:
		_last_anim = anim
		_update_bow_visibility(anim)
		_update_dash_effect_visibility(anim)
	for sprite_node in _layers.values():
		_sync_sprite(sprite_node, flip, anim, frame_idx, speed, mod)
	if _bow_back_sprite != null:
		_sync_sprite(_bow_back_sprite, flip, anim, frame_idx, speed, mod)
	if _dash_effect_sprite != null:
		_sync_sprite(_dash_effect_sprite, flip, anim, frame_idx, speed, mod)


func _sync_sprite(sprite_node: AnimatedSprite2D, flip: bool, anim: StringName, frame_idx: int, speed: float, mod: Color) -> void:
	if not sprite_node.visible:
		return
	if sprite_node.animation != anim and sprite_node.sprite_frames != null and sprite_node.sprite_frames.has_animation(anim):
		sprite_node.play(anim)
	sprite_node.flip_h = flip
	sprite_node.frame = frame_idx
	sprite_node.speed_scale = speed
	sprite_node.modulate = mod


func set_part(slot: StringName, part: SkinPart) -> void:
	if slot == &"body":
		# Body: troca o sprite_frames do mestre direto.
		if part != null and part.texture != null and _body_sprite != null:
			_body_sprite.sprite_frames = _build_frames_for(part.texture, ANIM_LAYOUT)
		return
	if slot == &"bow":
		_apply_bow_part(part)
		return
	# Layer normal (filho de Skin).
	var sprite_node: AnimatedSprite2D = _layers.get(slot)
	if sprite_node == null:
		return
	if part == null or part.texture == null:
		sprite_node.visible = false
	else:
		sprite_node.sprite_frames = _build_frames_for(part.texture, ANIM_LAYOUT)
		sprite_node.visible = true
		_init_sprite_state(sprite_node)


func _apply_bow_part(part: SkinPart) -> void:
	# Front usa BOW_FRONT_LAYOUT (PNG só com attack/death). Back usa layout padrão.
	var bow_front: AnimatedSprite2D = _layers.get(&"bow")
	_bow_has_front = part != null and part.texture != null
	_bow_has_back  = part != null and part.texture_back != null
	if bow_front != null and _bow_has_front:
		bow_front.sprite_frames = _build_frames_for(part.texture, BOW_FRONT_LAYOUT)
		_init_sprite_state(bow_front)
	if _bow_back_sprite != null and _bow_has_back:
		_bow_back_sprite.sprite_frames = _build_frames_for(part.texture_back, ANIM_LAYOUT)
		_init_sprite_state(_bow_back_sprite)
	var anim_now: StringName = _body_sprite.animation if _body_sprite != null else &"idle"
	_last_anim = anim_now
	_update_bow_visibility(anim_now)


func _update_bow_visibility(anim: StringName) -> void:
	var anim_uses_front: bool = BOW_FRONT_ANIMATIONS.has(anim)
	var bow_front: AnimatedSprite2D = _layers.get(&"bow")
	if bow_front != null:
		bow_front.visible = _bow_has_front and anim_uses_front
	if _bow_back_sprite != null:
		_bow_back_sprite.visible = _bow_has_back and not anim_uses_front


func _update_dash_effect_visibility(anim: StringName) -> void:
	if _dash_effect_sprite == null:
		return
	var should_show: bool = anim == DASH_EFFECT_ANIMATION and _dash_effect_sprite.sprite_frames != null
	_dash_effect_sprite.visible = should_show
	if should_show and _dash_effect_sprite.sprite_frames.has_animation(anim):
		_dash_effect_sprite.play(anim)


func _init_sprite_state(sprite_node: AnimatedSprite2D) -> void:
	if _body_sprite == null:
		return
	sprite_node.flip_h = _body_sprite.flip_h
	if sprite_node.sprite_frames != null and sprite_node.sprite_frames.has_animation(_body_sprite.animation):
		sprite_node.play(_body_sprite.animation)
	sprite_node.frame = _body_sprite.frame
	sprite_node.speed_scale = _body_sprite.speed_scale
	sprite_node.modulate = _body_sprite.modulate


# Constrói SpriteFrames pro texture dada usando o layout especificado.
# Cacheado por texture pra evitar rebuild a cada troca.
func _build_frames_for(texture: Texture2D, layout: Dictionary) -> SpriteFrames:
	if _frames_cache.has(texture):
		return _frames_cache[texture]
	var fresh := SpriteFrames.new()
	for anim_name in layout.keys():
		var info: Dictionary = layout[anim_name]
		fresh.add_animation(anim_name)
		fresh.set_animation_loop(anim_name, bool(info.loop))
		fresh.set_animation_speed(anim_name, float(info.fps))
		var y: int = int(info.row) * FRAME_SIZE.y
		var n: int = int(info.frames)
		for i in range(n):
			var x: int = i * FRAME_SIZE.x
			var atlas := AtlasTexture.new()
			atlas.atlas = texture
			atlas.region = Rect2(x, y, FRAME_SIZE.x, FRAME_SIZE.y)
			fresh.add_frame(anim_name, atlas, 1.0)
	_frames_cache[texture] = fresh
	return fresh
