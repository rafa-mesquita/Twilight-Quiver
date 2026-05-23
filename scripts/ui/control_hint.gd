extends HBoxContainer

# Hint visual de controle (WASD/Space/Q/Click). Mostra um ícone + label e
# faz fade in/hold/fade out automático. Auto-destrói no fim. Usado pra
# tutorial inicial do jogo + notificação quando skill nova destrava.

@export var fade_in_duration: float = 0.4
@export var hold_duration: float = 4.0
@export var fade_out_duration: float = 0.7

@onready var icon: TextureRect = $Icon
@onready var label: Label = $Label


func setup(icon_texture: Texture2D, label_key: String) -> void:
	# Setar antes de adicionar ao tree pra não piscar opaco antes do tween.
	if icon != null:
		icon.texture = icon_texture
	if label != null:
		# tr() explícito — o hint vive 5s, não precisa re-traduzir em runtime.
		label.text = tr(label_key)
	modulate.a = 0.0


func _ready() -> void:
	var t := create_tween()
	t.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	t.tween_interval(hold_duration)
	t.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	t.tween_callback(queue_free)
