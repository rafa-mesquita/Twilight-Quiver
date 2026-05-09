extends Control

@onready var start_button: Button = $Center/VBox/StartButton
@onready var dev_button: Button = $Center/VBox/DevButton
@onready var quit_button: Button = $Center/VBox/QuitButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	dev_button.pressed.connect(_on_dev_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()


func _on_start_pressed() -> void:
	GameState.dev_mode = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_dev_pressed() -> void:
	GameState.dev_mode = true
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit_pressed() -> void:
	get_tree().quit()
