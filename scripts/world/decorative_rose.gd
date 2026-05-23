extends Node2D

# Rosa decorativa do mapa do Duskrose (wave 14) — Node2D com filho Sprite2D
# (uma das 3 variantes dos frames 5-7 da duskrose-Sheet) + sombra leve abaixo.
# Drop-and-place no editor pra distribuir pelo mapa.
#
# A scene vem com uma variante default (frame 5) atribuída ao Sprite2D pra
# aparecer no editor. No runtime, `_ready` substitui pela variante escolhida
# (random por default; `variant` exportado permite forçar uma específica).

const ROSE_TEXTURE_PATH: String = "res://assets/enemies/duskrose/duskrose-Sheet.png"
const FRAME_SIZE: int = 40
# Frames 5, 6, 7 são as variantes de rosa decorativa no sheet.
const ROSE_FRAME_INDICES: Array[int] = [5, 6, 7]

# Override opcional pra forçar uma variante específica.
@export_enum("Random", "Variant 0", "Variant 1", "Variant 2") var variant: int = 0

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	# No editor (tool=false), só roda em runtime. Random pick OU variante forçada.
	if sprite == null:
		return
	var tex: Texture2D = load(ROSE_TEXTURE_PATH) as Texture2D
	if tex == null:
		return
	var frame_idx: int = ROSE_FRAME_INDICES.pick_random() if variant == 0 else ROSE_FRAME_INDICES[variant - 1]
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(frame_idx * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	sprite.texture = atlas
