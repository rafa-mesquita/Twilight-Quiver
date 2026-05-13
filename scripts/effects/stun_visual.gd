extends Node2D

# Visual de stun: 5 primeiros frames de assets/effects/stun.png em loop,
# renderizados acima da cabeça do parent. Self-destruct quando o parent
# perde o _stun_remaining (volta a 0) ou some da árvore.

const STUN_TEXTURE: Texture2D = preload("res://assets/effects/stun.png")
const FRAME_COUNT: int = 5
const FRAME_W: int = 64
const FRAME_H: int = 64
const FPS: float = 12.0
# 64×0.5 = 32px — proporcional a inimigos de ~32px.
const SCALE_FACTOR: float = 0.5
# Acima da cabeça (sprite do inimigo geralmente tem offset -8 e altura 32 →
# topo ~-24; coloca o ícone um pouco acima disso).
const HEAD_OFFSET_Y: float = -32.0


func _ready() -> void:
	add_to_group("stun_visual")
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = _build_frames()
	anim.animation = &"stun"
	anim.scale = Vector2(SCALE_FACTOR, SCALE_FACTOR)
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.z_index = 20
	anim.position = Vector2(0, HEAD_OFFSET_Y)
	add_child(anim)
	anim.play(&"stun")


func _process(_delta: float) -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		queue_free()
		return
	if not ("_stun_remaining" in parent) or float(parent._stun_remaining) <= 0.0:
		queue_free()
		return


static func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"stun")
	sf.set_animation_loop(&"stun", true)
	sf.set_animation_speed(&"stun", FPS)
	for i in FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = STUN_TEXTURE
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame(&"stun", atlas)
	return sf
