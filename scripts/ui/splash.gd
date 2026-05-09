extends Control

# Splash de abertura: mostra a logo do studio com fade in/hold/fade out e
# transiciona pro main menu. Click/tecla pula a sequência.

const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const _FADE_IN: float = 0.6
const _HOLD: float = 1.5
const _FADE_OUT: float = 0.5

@onready var logo: TextureRect = $Logo

var _done: bool = false


func _ready() -> void:
	logo.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(logo, "modulate:a", 1.0, _FADE_IN)
	t.tween_interval(_HOLD)
	t.tween_property(logo, "modulate:a", 0.0, _FADE_OUT)
	t.tween_callback(_finish)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_finish()
	elif event is InputEventKey and event.pressed:
		_finish()


func _finish() -> void:
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
