extends Control

# Tela de leaderboard. Acessada via botão no main_menu.
#
# Duas abas:
#   MODE_WAVES   — "Por Waves": ranking por wave mais alta (desempate: maior
#                  score). Puxa o top-100 do backend (que ordena por score) e
#                  reordena no cliente — runs de wave alta têm score alto, então
#                  caem no top-100. Filtro de versão funciona aqui.
#   MODE_TIME21  — "Tempo até o 21": menor tempo efetivo (só combate) até vencer
#                  o dual boss da wave 21. O backend ainda NÃO guarda esse campo
#                  nem ordena por ele, então por ora mostra o RECORDE PESSOAL
#                  local (SkinLoadout.STAT_BEST_TIME_W21). Quando o backend
#                  ganhar a coluna time_to_w21_ms + query, troca-se este modo por
#                  um fetch global (o jogo já envia o campo no payload).

const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _MAIN_MENU_PATH: String = "res://scenes/ui/main_menu.tscn"
const _MAX_ROWS: int = 20
# Puxa mais linhas do que exibe pra reordenar por wave no cliente.
const _FETCH_LIMIT: int = 100
const _ALL_VERSIONS_LABEL: String = "LEADERBOARD_FILTER_ALL"

const MODE_WAVES: int = 0
const MODE_TIME21: int = 1

@onready var grid: GridContainer = $Center/Panel/Margin/VBox/Scroll/Grid
@onready var status_label: Label = $Center/Panel/Margin/VBox/StatusLabel
@onready var back_button: Button = $Center/Panel/Margin/VBox/BackButton
@onready var filter_row: HBoxContainer = $Center/Panel/Margin/VBox/FilterRow
@onready var version_filter: Button = $Center/Panel/Margin/VBox/FilterRow/VersionFilter
@onready var _vbox: VBoxContainer = $Center/Panel/Margin/VBox

var _client: Node = null
# Paralelo ao dropdown: idx 0 = "" (sem filtro/todas), idx N = string da versão.
var _filter_versions: Array[String] = [""]
var _mode: int = MODE_WAVES
# Cache das linhas cruas do último fetch (pra reordenar/trocar de aba sem refetch).
var _rows_cache: Array = []
var _tab_waves: Button = null
var _tab_time21: Button = null


func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	version_filter.item_selected.connect(_on_version_filter_changed)
	# Estado inicial do dropdown — "Todas" enquanto a lista de versões carrega.
	version_filter.add_item(tr(_ALL_VERSIONS_LABEL))
	version_filter.select(0)

	_build_tab_bar()
	_render_header()
	status_label.text = tr("COMMON_LOADING")
	_client = _LEADERBOARD_CLIENT.new()
	add_child(_client)
	_client.fetch_succeeded.connect(_on_fetch_succeeded)
	_client.fetch_failed.connect(_on_fetch_failed)
	_client.versions_fetched.connect(_on_versions_fetched)
	_client.versions_fetch_failed.connect(_on_versions_fetch_failed)
	_client.fetch_top(_FETCH_LIMIT)
	_client.fetch_versions()


func _build_tab_bar() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 24)
	_tab_waves = _make_tab(tr("LEADERBOARD_TAB_WAVES"), MODE_WAVES)
	_tab_time21 = _make_tab(tr("LEADERBOARD_TAB_TIME21"), MODE_TIME21)
	row.add_child(_tab_waves)
	row.add_child(_tab_time21)
	_vbox.add_child(row)
	# Logo abaixo do título (index 0), acima do FilterRow.
	_vbox.move_child(row, 1)
	_update_tab_styles()


func _make_tab(text: String, mode: int) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	var font: Font = load("res://font/Silver.ttf")
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 34)
	b.pressed.connect(_on_tab_pressed.bind(mode))
	return b


func _on_tab_pressed(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	_update_tab_styles()
	_refresh_current_mode()


func _update_tab_styles() -> void:
	var active := Color(1, 0.85, 0.45, 1)
	var idle := Color(0.6, 0.58, 0.7, 1)
	if _tab_waves != null:
		_tab_waves.add_theme_color_override("font_color", active if _mode == MODE_WAVES else idle)
	if _tab_time21 != null:
		_tab_time21.add_theme_color_override("font_color", active if _mode == MODE_TIME21 else idle)


func _refresh_current_mode() -> void:
	if _mode == MODE_WAVES:
		filter_row.visible = true
		_render_waves(_rows_cache)
	else:
		filter_row.visible = false
		_render_time21()


# ───────────────────────── MODE_WAVES ─────────────────────────

func _render_header() -> void:
	grid.columns = 8
	for child in grid.get_children():
		child.queue_free()
	_add_cell(tr("LEADERBOARD_COL_RANK"), true)
	_add_cell(tr("LEADERBOARD_COL_NICK"), true)
	_add_cell(tr("LEADERBOARD_COL_WAVE"), true)
	_add_cell(tr("LEADERBOARD_COL_SCORE"), true)
	_add_cell(tr("LEADERBOARD_COL_TIME"), true)
	_add_cell(tr("LEADERBOARD_COL_KILLS"), true)
	_add_cell(tr("LEADERBOARD_COL_DAMAGE"), true)
	_add_cell(tr("LEADERBOARD_COL_VERSION"), true)


func _render_waves(rows: Array) -> void:
	_render_header()
	if rows.is_empty():
		status_label.text = tr("LEADERBOARD_NO_SCORES")
		return
	status_label.text = ""
	# Reordena por wave desc, desempate por score desc.
	var sorted_rows: Array = rows.duplicate()
	sorted_rows.sort_custom(_compare_waves)
	var shown: int = mini(sorted_rows.size(), _MAX_ROWS)
	for i in range(shown):
		var row: Variant = sorted_rows[i]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_add_cell(str(i + 1))
		_add_cell(str(row.get("nickname", "?")))
		_add_cell(str(row.get("wave", 0)))
		_add_cell(str(row.get("score", 0)))
		_add_cell(_format_time(int(row.get("time_ms", 0))))
		_add_cell(str(row.get("kills", 0)))
		_add_cell(str(row.get("dmg_dealt", 0)))
		_add_cell(str(row.get("version", "")))


func _compare_waves(a: Variant, b: Variant) -> bool:
	var wa: int = int(a.get("wave", 0)) if typeof(a) == TYPE_DICTIONARY else 0
	var wb: int = int(b.get("wave", 0)) if typeof(b) == TYPE_DICTIONARY else 0
	if wa != wb:
		return wa > wb
	var sa: int = int(a.get("score", 0)) if typeof(a) == TYPE_DICTIONARY else 0
	var sb: int = int(b.get("score", 0)) if typeof(b) == TYPE_DICTIONARY else 0
	return sa > sb


# ───────────────────────── MODE_TIME21 ─────────────────────────

func _render_time21() -> void:
	grid.columns = 2
	for child in grid.get_children():
		child.queue_free()
	# Por enquanto: recorde PESSOAL local. Ranking global vem quando o backend
	# ganhar a coluna time_to_w21_ms.
	var best: int = SkinLoadout.get_stat(SkinLoadout.STAT_BEST_TIME_W21)
	_add_cell(tr("LEADERBOARD_BEST_TIME21"), true)
	if best > 0:
		_add_cell(_format_time(best), true)
		status_label.text = tr("LEADERBOARD_TIME21_GLOBAL_SOON")
	else:
		_add_cell("—", true)
		status_label.text = tr("LEADERBOARD_TIME21_NONE")


# ───────────────────────── fetch callbacks ─────────────────────────

func _on_fetch_succeeded(rows: Array) -> void:
	_rows_cache = rows
	if _mode == MODE_WAVES:
		_render_waves(rows)


func _on_fetch_failed(message: String) -> void:
	if _mode == MODE_WAVES:
		status_label.text = tr("LEADERBOARD_ERROR") % message


func _on_versions_fetched(versions: Array) -> void:
	# Reconstrói o dropdown com "Todas" + versões disponíveis.
	# Preserva a versão selecionada se ainda existir; senão volta pra "Todas".
	var current: String = _filter_versions[max(0, version_filter.get_selected())]
	version_filter.clear_items()
	_filter_versions = [""]
	version_filter.add_item(tr(_ALL_VERSIONS_LABEL))
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
	status_label.text = tr("COMMON_LOADING")
	_client.fetch_top(_FETCH_LIMIT, filter)


func _add_cell(text: String, is_header: bool = false) -> void:
	var label := Label.new()
	label.text = text
	var font: Font = load("res://font/Silver.ttf")
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 30 if is_header else 25)
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
