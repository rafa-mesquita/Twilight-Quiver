extends Control

# Tela de leaderboard. Acessada via botão no main_menu.
#
# Duas abas:
#   MODE_WAVES   — "Por Waves": ranking por wave mais alta (desempate: maior
#                  score). Puxa o top-100 do backend (que ordena por score) e
#                  reordena no cliente — runs de wave alta têm score alto, então
#                  caem no top-100. Filtro de versão funciona aqui.
#   MODE_TIME21  — "Tempo até o 21": menor tempo efetivo (só combate) até vencer
#                  o dual boss da wave 21. Ranking GLOBAL: o backend filtra runs
#                  com time_to_w21_ms >= 0 e ordena por menor tempo
#                  (GET /api/runs?board=time_w21). O recorde pessoal local
#                  (SkinLoadout.STAT_BEST_TIME_W21) aparece no rodapé. Fetch é
#                  lazy — só na 1ª vez que a aba abre.

const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _BUILD_MODAL := preload("res://scripts/ui/run_build_modal.gd")
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
# Cache do ranking de tempo (fetch lazy na 1ª abertura da aba).
var _time21_rows: Array = []
var _time21_loaded: bool = false
var _tab_waves: Button = null
var _tab_time21: Button = null
var _tab_row: HBoxContainer = null
# Arquivo (temporada anterior): board "Por Waves" das runs version_num < SEASON_MIN.
var _archive_btn: Button = null
var _archive_view: bool = false
var _archive_rows: Array = []
var _archive_loaded: bool = false


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
	_client.time21_fetched.connect(_on_time21_fetched)
	_client.time21_fetch_failed.connect(_on_time21_fetch_failed)
	_client.archive_fetched.connect(_on_archive_fetched)
	_client.archive_fetch_failed.connect(_on_archive_fetch_failed)
	_client.versions_fetched.connect(_on_versions_fetched)
	_client.versions_fetch_failed.connect(_on_versions_fetch_failed)
	_build_archive_button()
	_client.fetch_top(_FETCH_LIMIT)
	_client.fetch_versions()


# "!" discreto no canto superior direito do painel → abre o arquivo de runs
# antigas (temporada anterior). Vira "↩" pra voltar.
func _build_archive_button() -> void:
	_archive_btn = Button.new()
	_archive_btn.text = "!"
	_archive_btn.flat = true
	_archive_btn.focus_mode = Control.FOCUS_NONE
	var font: Font = load("res://font/Silver.ttf")
	if font != null:
		_archive_btn.add_theme_font_override("font", font)
	_archive_btn.add_theme_font_size_override("font_size", 30)
	_archive_btn.add_theme_color_override("font_color", Color(0.55, 0.52, 0.66, 1))
	_archive_btn.tooltip_text = tr("LEADERBOARD_ARCHIVE_TOOLTIP")
	_archive_btn.pressed.connect(_on_archive_pressed)
	# Canto superior direito da TELA, discreto. Offsets explícitos (setar só
	# offset_right dava largura negativa e jogava o botão pro centro).
	add_child(_archive_btn)
	_archive_btn.anchor_left = 1.0
	_archive_btn.anchor_right = 1.0
	_archive_btn.anchor_top = 0.0
	_archive_btn.anchor_bottom = 0.0
	_archive_btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_archive_btn.offset_left = -64
	_archive_btn.offset_right = -18
	_archive_btn.offset_top = 14
	_archive_btn.offset_bottom = 54


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
	_tab_row = row
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
	# Ambas as abas têm filtro de versão (refaz o fetch com o filtro atual ao
	# trocar de aba, pra manter consistência da versão selecionada).
	filter_row.visible = true
	status_label.text = tr("COMMON_LOADING")
	var f: String = _current_version_filter()
	if _mode == MODE_WAVES:
		_render_header()
		_client.fetch_top(_FETCH_LIMIT, f)
	else:
		_render_time21_header()
		_client.fetch_time21(_MAX_ROWS, f)


func _current_version_filter() -> String:
	var idx: int = version_filter.get_selected()
	return _filter_versions[idx] if idx >= 0 and idx < _filter_versions.size() else ""


# ───────────────────────── MODE_WAVES ─────────────────────────

func _render_header() -> void:
	grid.columns = 9
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
	_add_cell("", true)  # coluna do botão "Ver build"


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
		_add_build_button(row)


func _compare_waves(a: Variant, b: Variant) -> bool:
	var wa: int = int(a.get("wave", 0)) if typeof(a) == TYPE_DICTIONARY else 0
	var wb: int = int(b.get("wave", 0)) if typeof(b) == TYPE_DICTIONARY else 0
	if wa != wb:
		return wa > wb
	var sa: int = int(a.get("score", 0)) if typeof(a) == TYPE_DICTIONARY else 0
	var sb: int = int(b.get("score", 0)) if typeof(b) == TYPE_DICTIONARY else 0
	return sa > sb


# ───────────────────────── MODE_TIME21 ─────────────────────────

func _render_time21_header() -> void:
	grid.columns = 5
	for child in grid.get_children():
		child.queue_free()
	_add_cell(tr("LEADERBOARD_COL_RANK"), true)
	_add_cell(tr("LEADERBOARD_COL_NICK"), true)
	_add_cell(tr("LEADERBOARD_COL_TIME"), true)
	_add_cell(tr("LEADERBOARD_COL_VERSION"), true)
	_add_cell("", true)  # coluna do botão "Ver build"


func _render_time21(rows: Array) -> void:
	_render_time21_header()
	# Só runs que venceram a 21 (time_to_w21_ms > 0). O backend já filtra/ordena,
	# mas garantimos aqui — se um backend antigo ignorar o board, as linhas sem o
	# campo caem fora em vez de aparecer como 0:00.
	var valid: Array = []
	for r in rows:
		if typeof(r) == TYPE_DICTIONARY and int(r.get("time_to_w21_ms", -1)) > 0:
			valid.append(r)
	valid.sort_custom(func(a, b): return int(a.get("time_to_w21_ms", 0)) < int(b.get("time_to_w21_ms", 0)))

	if valid.is_empty():
		status_label.text = tr("LEADERBOARD_TIME21_EMPTY")
	else:
		var shown: int = mini(valid.size(), _MAX_ROWS)
		for i in range(shown):
			var row: Dictionary = valid[i]
			_add_cell(str(i + 1))
			_add_cell(str(row.get("nickname", "?")))
			_add_cell(_format_time(int(row.get("time_to_w21_ms", 0))))
			_add_cell(str(row.get("version", "")))
			_add_build_button(row)
		# Recorde pessoal local no rodapé.
		var best: int = SkinLoadout.get_stat(SkinLoadout.STAT_BEST_TIME_W21)
		if best > 0:
			status_label.text = "%s: %s" % [tr("LEADERBOARD_BEST_TIME21"), _format_time(best)]
		else:
			status_label.text = tr("LEADERBOARD_TIME21_NONE")


# ───────────────────────── fetch callbacks ─────────────────────────

func _on_fetch_succeeded(rows: Array) -> void:
	_rows_cache = rows
	if _mode == MODE_WAVES:
		_render_waves(rows)


func _on_fetch_failed(message: String) -> void:
	if _mode == MODE_WAVES:
		status_label.text = tr("LEADERBOARD_ERROR") % message


func _on_time21_fetched(rows: Array) -> void:
	_time21_rows = rows
	_time21_loaded = true
	if _mode == MODE_TIME21:
		_render_time21(rows)


func _on_time21_fetch_failed(message: String) -> void:
	if _mode == MODE_TIME21:
		status_label.text = tr("LEADERBOARD_ERROR") % message


# ───────────────────────── arquivo (runs antigas) ─────────────────────────

func _on_archive_pressed() -> void:
	_archive_view = not _archive_view
	if _archive_view:
		_enter_archive()
	else:
		_exit_archive()


func _enter_archive() -> void:
	if _tab_row != null:
		_tab_row.visible = false
	filter_row.visible = false
	_archive_btn.text = "<"
	_archive_btn.tooltip_text = tr("LEADERBOARD_ARCHIVE_BACK")
	if _archive_loaded:
		_render_waves(_archive_rows)
	else:
		_render_header()
		status_label.text = tr("COMMON_LOADING")
		_client.fetch_archive(_FETCH_LIMIT)


func _exit_archive() -> void:
	if _tab_row != null:
		_tab_row.visible = true
	_archive_btn.text = "!"
	_archive_btn.tooltip_text = tr("LEADERBOARD_ARCHIVE_TOOLTIP")
	_refresh_current_mode()


func _on_archive_fetched(rows: Array) -> void:
	_archive_rows = rows
	_archive_loaded = true
	if _archive_view:
		_render_waves(rows)


func _on_archive_fetch_failed(message: String) -> void:
	if _archive_view:
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
	if _mode == MODE_WAVES:
		_client.fetch_top(_FETCH_LIMIT, filter)
	else:
		_client.fetch_time21(_MAX_ROWS, filter)


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


func _add_build_button(row: Dictionary) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.text = tr("LEADERBOARD_VIEW_BUILD")
	var font: Font = load("res://font/Silver.ttf")
	if font != null:
		b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(110, 0)
	if _row_has_build(row):
		b.add_theme_color_override("font_color", Color(1, 0.85, 0.45, 1))
		b.pressed.connect(_open_build_modal.bind(row))
	else:
		b.disabled = true
		b.tooltip_text = tr("LEADERBOARD_BUILD_NONE")
	grid.add_child(b)


func _row_has_build(row: Dictionary) -> bool:
	var b: Variant = row.get("build")
	if typeof(b) != TYPE_DICTIONARY:
		return false
	var up: Variant = b.get("upgrades")
	var it: Variant = b.get("items")
	var has_up: bool = typeof(up) == TYPE_DICTIONARY and not (up as Dictionary).is_empty()
	var has_it: bool = typeof(it) == TYPE_ARRAY and not (it as Array).is_empty()
	return has_up or has_it


func _open_build_modal(row: Dictionary) -> void:
	var m: RunBuildModal = _BUILD_MODAL.new()
	add_child(m)
	m.call_deferred("open", row)


func _format_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%d:%02d" % [minutes, seconds]


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(_MAIN_MENU_PATH)
