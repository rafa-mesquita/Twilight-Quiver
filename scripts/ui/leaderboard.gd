extends Control

# Tela de leaderboard. Acessada via botão no main_menu. Faz GET no Supabase
# (top 20 ordenado por score desc) e renderiza linhas em um GridContainer.

const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const _MAX_ROWS: int = 20
const _COLUMN_COUNT: int = 7

@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Scroll/Grid
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var back_button: Button = $Center/Panel/Margin/VBox/BackButton

var _client: Node = null


func _ready() -> void:
	grid.columns = _COLUMN_COUNT
	back_button.pressed.connect(_on_back_pressed)
	_render_header()
	status_label.text = "Carregando..."
	_client = _LEADERBOARD_CLIENT.new()
	add_child(_client)
	_client.fetch_succeeded.connect(_on_fetch_succeeded)
	_client.fetch_failed.connect(_on_fetch_failed)
	_client.fetch_top(_MAX_ROWS)


func _render_header() -> void:
	for child in grid.get_children():
		child.queue_free()
	_add_cell("#", true)
	_add_cell("Nick", true)
	_add_cell("Score", true)
	_add_cell("Wave", true)
	_add_cell("Tempo", true)
	_add_cell("Kills", true)
	_add_cell("Dano", true)


func _on_fetch_succeeded(rows: Array) -> void:
	status_label.text = ""
	if rows.is_empty():
		status_label.text = "Nenhum score ainda."
		return
	for i in range(rows.size()):
		var row: Variant = rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_add_cell(str(i + 1))
		_add_cell(str(row.get("nickname", "?")))
		_add_cell(str(row.get("score", 0)))
		_add_cell(str(row.get("wave", 0)))
		_add_cell(_format_time(int(row.get("time_ms", 0))))
		_add_cell(str(row.get("kills", 0)))
		_add_cell(str(row.get("dmg_dealt", 0)))


func _on_fetch_failed(message: String) -> void:
	status_label.text = "Erro: %s" % message


func _add_cell(text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	var font: Font = load("res://font/ByteBounce.ttf")
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 28 if is_header else 24)
	if is_header:
		label.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.85, 1, 1))
	label.custom_minimum_size = Vector2(130, 0)
	grid.add_child(label)


func _format_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%d:%02d" % [minutes, seconds]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
