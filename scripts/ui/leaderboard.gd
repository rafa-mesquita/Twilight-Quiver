extends Control

# Tela de leaderboard. Acessada via botão no main_menu.
# Filtro de versão no topo (popula com as versões distintas que existem na base).
# Default = "Todas" (sem filtro).

const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const _MAX_ROWS: int = 20
const _COLUMN_COUNT: int = 8
const _ALL_VERSIONS_LABEL: String = "Todas"

@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Scroll/Grid
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var back_button: Button = $Center/Panel/Margin/VBox/BackButton
@onready var version_filter: Button = $Center/Panel/Margin/VBox/FilterRow/VersionFilter

var _client: Node = null
# Paralelo ao dropdown: idx 0 = "" (sem filtro/todas), idx N = string da versão.
var _filter_versions: Array[String] = [""]


func _ready() -> void:
	grid.columns = _COLUMN_COUNT
	back_button.pressed.connect(_on_back_pressed)
	version_filter.item_selected.connect(_on_version_filter_changed)
	# Estado inicial do dropdown — "Todas" enquanto a lista de versões carrega.
	version_filter.add_item(_ALL_VERSIONS_LABEL)
	version_filter.select(0)

	_render_header()
	status_label.text = "Carregando..."
	_client = _LEADERBOARD_CLIENT.new()
	add_child(_client)
	_client.fetch_succeeded.connect(_on_fetch_succeeded)
	_client.fetch_failed.connect(_on_fetch_failed)
	_client.versions_fetched.connect(_on_versions_fetched)
	_client.versions_fetch_failed.connect(_on_versions_fetch_failed)
	_client.fetch_top(_MAX_ROWS)
	_client.fetch_versions()


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
	_add_cell("Versao", true)


func _on_fetch_succeeded(rows: Array) -> void:
	_render_header()
	if rows.is_empty():
		status_label.text = "Nenhum score nessa versao."
		return
	status_label.text = ""
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
		_add_cell(str(row.get("version", "")))


func _on_fetch_failed(message: String) -> void:
	status_label.text = "Erro: %s" % message


func _on_versions_fetched(versions: Array) -> void:
	# Reconstrói o dropdown com "Todas" + versões disponíveis.
	# Preserva a versão selecionada se ainda existir; senão volta pra "Todas".
	var current: String = _filter_versions[max(0, version_filter.get_selected())]
	version_filter.clear_items()
	_filter_versions = [""]
	version_filter.add_item(_ALL_VERSIONS_LABEL)
	for v in versions:
		var s: String = str(v)
		if s.is_empty():
			continue
		_filter_versions.append(s)
		version_filter.add_item(s)
	var keep_idx: int = _filter_versions.find(current)
	version_filter.select(keep_idx if keep_idx >= 0 else 0)


func _on_versions_fetch_failed(_message: String) -> void:
	# Falhou listar versões — mantém só "Todas". Não mostra erro proeminente
	# porque a lista do leaderboard ainda funciona.
	pass


func _on_version_filter_changed(idx: int) -> void:
	var filter: String = _filter_versions[idx] if idx < _filter_versions.size() else ""
	status_label.text = "Carregando..."
	_client.fetch_top(_MAX_ROWS, filter)


func _add_cell(text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	var font: Font = load("res://font/ByteBounce.ttf")
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 28 if is_header else 22)
	if is_header:
		label.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
	else:
		label.add_theme_color_override("font_color", Color(0.9, 0.85, 1, 1))
	label.custom_minimum_size = Vector2(110, 0)
	grid.add_child(label)


func _format_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%d:%02d" % [minutes, seconds]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
