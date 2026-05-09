class_name SkinPart
extends Resource

# Uma peça de skin (variante de um slot). Construído em runtime pelo SkinLoadout
# escaneando assets/player/<slot>/*.png — não precisa criar .tres manualmente.
#
# REGRA IMPORTANTE: o spritesheet (texture) deve ter EXATAMENTE o mesmo layout
# de frames que o body do player — mesmas dimensões, mesmas regions, mesma
# ordem de animações. SkinManager copia as regions do body e só troca a textura.
#
# Slot `bow` usa duas texturas: `texture` (front, segurada na mão) e
# `texture_back` (back, atrás do corpo). Convenção de arquivo:
#   assets/player/bow/<Variant>_front.png   (ou só <Variant>.png se não houver back)
#   assets/player/bow/<Variant>_back.png    (opcional)

@export var slot: StringName        # &"body", &"hair", &"cape", &"shirt", &"alfaja", &"legs", &"bow", &"quiver"
@export var display_name: String    # ex: "Default", "Loiro" — vem do nome do arquivo
@export var texture: Texture2D      # spritesheet principal
@export var texture_back: Texture2D # apenas pra slot `bow` — back de bow renderizado atrás do body
@export var thumbnail: Texture2D    # opcional; default = texture
