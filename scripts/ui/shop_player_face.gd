class_name ShopPlayerFace
extends Node2D

# Preview animado do personagem na shop, em camadas: cape (atrás) → head → shirt → hair.
# Cada layer escolhe sua textura a partir do SkinLoadout. Slot vazio ou asset
# faltando cai pro default.png da pasta correspondente.
#
# Sheet esperado: 858x66 (13 frames de 66x66), idle loop. Igual ao
# `assets/Hud/shop/persoangem shop.png` original.

const _HUD_DIR: String = "res://assets/Hud/playerHud"
const _FRAME_W: int = 66
const _FRAME_H: int = 66
const _FRAME_COUNT: int = 13
const _ANIM_FPS: float = 6.0

# Slot interno do SkinLoadout → subpasta em HUD/playerHud + node filho.
# Ordem do array determina z-order de criação (não usado em runtime — o
# .tscn já fixa a ordem de filhos).
const _LAYERS: Array[Dictionary] = [
	{"slot": &"cape",  "dir": "cape",  "node": "Cape"},
	{"slot": &"body",  "dir": "head",  "node": "Head"},
	{"slot": &"shirt", "dir": "shirt", "node": "Shirt"},
	{"slot": &"hair",  "dir": "hair",  "node": "Hair"},
]


func _ready() -> void:
	var loadout: Dictionary = SkinLoadout.load_loadout()
	for layer in _LAYERS:
		var node_name: String = String(layer["node"])
		var sprite: AnimatedSprite2D = get_node_or_null(node_name) as AnimatedSprite2D
		if sprite == null:
			continue
		var part: SkinPart = loadout.get(layer["slot"])
		var tex: Texture2D = _resolve_texture(String(layer["dir"]), part)
		if tex == null:
			sprite.visible = false
			continue
		sprite.sprite_frames = _build_frames_for(tex)
		sprite.animation = &"idle"
		sprite.play("idle")


func _resolve_texture(dir_name: String, part: SkinPart) -> Texture2D:
	# Tenta <skin_name>.png (lowercase) primeiro; senão default.png.
	if part != null and part.display_name != "":
		var custom_path: String = "%s/%s/%s.png" % [_HUD_DIR, dir_name, part.display_name.to_lower()]
		if ResourceLoader.exists(custom_path):
			return load(custom_path) as Texture2D
	var default_path: String = "%s/%s/default.png" % [_HUD_DIR, dir_name]
	if ResourceLoader.exists(default_path):
		return load(default_path) as Texture2D
	return null


func _build_frames_for(texture: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", _ANIM_FPS)
	for i in _FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(i * _FRAME_W, 0, _FRAME_W, _FRAME_H)
		frames.add_frame(&"idle", atlas)
	return frames
