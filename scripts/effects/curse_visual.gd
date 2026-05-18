extends Node2D

# Visual de maldição: 4 frames de curse animations-Sheet.png em loop, centrados
# no parent enquanto o CurseDebuff estiver ativo. CurseDebuff cria e libera
# esse node explicitamente (sem self-polling — evita custo de _process).

const CURSE_TEXTURE: Texture2D = preload("res://assets/effects/curse animations-Sheet.png")
const FRAME_COUNT: int = 4
const FRAME_W: int = 32
const FRAME_H: int = 32
const FPS: float = 8.0
const BODY_OFFSET_Y: float = -8.0


func _ready() -> void:
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = _build_frames()
	anim.animation = &"curse"
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	anim.z_index = 6
	anim.position = Vector2(0, BODY_OFFSET_Y)
	# Frame inicial randômico pra não sincronizar entre inimigos próximos.
	add_child(anim)
	anim.play(&"curse")
	anim.frame = randi() % FRAME_COUNT


static func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	if sf.has_animation(&"default"):
		sf.remove_animation(&"default")
	sf.add_animation(&"curse")
	sf.set_animation_loop(&"curse", true)
	sf.set_animation_speed(&"curse", FPS)
	for i in FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = CURSE_TEXTURE
		atlas.region = Rect2(i * FRAME_W, 0, FRAME_W, FRAME_H)
		sf.add_frame(&"curse", atlas)
	return sf
