extends CanvasLayer

# Death Replay (Path B — vídeo): reproduz os últimos ~3.5s antes da morte usando os
# FRAMES do viewport gravados pelo player (player.stats_replay_frames). Fidelidade
# total — é o frame real renderizado, então rotação/trail/partícula/alinhamento vêm
# de graça (sem reconstruir "ghosts").
#
# Spawnado pelo HUD quando o botão "Ver replay da morte" é clicado.

signal finished

const PLAYBACK_FPS: float = 20.0   # Mesma taxa de captura.
const SLOW_MO_FACTOR: float = 0.6  # Replay em 60% da velocidade real.
const FADE_DURATION: float = 0.4

const _MENU_FONT_PATH: String = "res://font/Silver.ttf"

@onready var root_ctrl: Control = $Root
@onready var bg: ColorRect = $Root/Bg
@onready var title_label: Label = $Root/TitleLabel
@onready var killed_by_label: Label = $Root/KilledByLabel

# Setado pelo HUD antes de add_child: Array[Image] dos últimos ~3.5s.
var frames: Array = []
var killed_by_str: String = ""

var _textures: Array = []   # Array[ImageTexture] convertidas dos Images.
var _frame_view: TextureRect = null
var _elapsed: float = 0.0
var _total_duration: float = 0.0
# Barra de ações que aparece quando o replay termina (Ver novamente / Gravar / Voltar).
var _actions_row: HBoxContainer = null
var _saved_label: Label = null
var _replay_saved: bool = false  # evita salvar o mesmo replay várias vezes


func _ready() -> void:
	if frames.is_empty():
		emit_signal("finished")
		queue_free()
		return
	# Converte os Images gravados em texturas (uma vez só, na abertura).
	for img in frames:
		if img is Image and not (img as Image).is_empty():
			_textures.append(ImageTexture.create_from_image(img))
	if _textures.is_empty():
		emit_signal("finished")
		queue_free()
		return
	_total_duration = float(_textures.size()) / PLAYBACK_FPS / SLOW_MO_FACTOR
	# TextureRect cobrindo a tela (atrás dos labels, na frente do Bg).
	_frame_view = TextureRect.new()
	_frame_view.anchor_right = 1.0
	_frame_view.anchor_bottom = 1.0
	_frame_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_frame_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_frame_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # pixel-art nítido
	root_ctrl.add_child(_frame_view)
	root_ctrl.move_child(_frame_view, 1)
	# Labels.
	title_label.text = tr("HUD_REPLAY_TITLE")
	killed_by_label.text = killed_by_str
	# Fade in.
	root_ctrl.modulate.a = 0.0
	create_tween().tween_property(root_ctrl, "modulate:a", 1.0, FADE_DURATION)
	_show_frame(0)


func _process(delta: float) -> void:
	if _textures.is_empty():
		return
	_elapsed += delta
	if _elapsed >= _total_duration:
		_show_frame(_textures.size() - 1)
		_finish_replay()
		set_process(false)
		return
	var progress: float = clampf(_elapsed / maxf(_total_duration, 0.001), 0.0, 1.0)
	var idx: int = mini(int(progress * float(_textures.size() - 1) + 0.5), _textures.size() - 1)
	_show_frame(idx)


func _show_frame(idx: int) -> void:
	if _frame_view == null or idx < 0 or idx >= _textures.size():
		return
	_frame_view.texture = _textures[idx]


func _finish_replay() -> void:
	# Em vez de fechar direto, oferece ações: rever, gravar em disco ou voltar.
	# Mostra o cursor do SO pra os botões serem clicáveis (gameplay usa mira escondida).
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ensure_actions_row()
	_actions_row.visible = true


func _ensure_actions_row() -> void:
	if _actions_row != null:
		return
	_actions_row = HBoxContainer.new()
	_actions_row.add_theme_constant_override("separation", 24)
	_actions_row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_actions_row.position = Vector2(0, -60)
	_actions_row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_actions_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root_ctrl.add_child(_actions_row)
	_actions_row.add_child(_make_button("HUD_REPLAY_AGAIN", _on_again_pressed))
	_actions_row.add_child(_make_button("HUD_REPLAY_SAVE", _on_save_pressed))
	_actions_row.add_child(_make_button("COMMON_BACK", _on_back_pressed))
	# Label de feedback ("Replay salvo em ...") acima dos botões.
	_saved_label = Label.new()
	_saved_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_saved_label.position = Vector2(0, -130)
	_saved_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_saved_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_saved_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_saved_label.add_theme_color_override("font_color", Color(0.7, 1, 0.7, 1))
	_saved_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_saved_label.add_theme_constant_override("outline_size", 4)
	var fnt := load(_MENU_FONT_PATH)
	if fnt != null:
		_saved_label.add_theme_font_override("font", fnt)
	_saved_label.add_theme_font_size_override("font_size", 26)
	_saved_label.visible = false
	root_ctrl.add_child(_saved_label)


func _make_button(text_key: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = tr(text_key)
	b.custom_minimum_size = Vector2(220, 56)
	b.focus_mode = Control.FOCUS_NONE
	var fnt := load(_MENU_FONT_PATH)
	if fnt != null:
		b.add_theme_font_override("font", fnt)
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", Color(0.95, 0.85, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.pressed.connect(handler)
	return b


func _on_again_pressed() -> void:
	if _actions_row != null:
		_actions_row.visible = false
	if _saved_label != null:
		_saved_label.visible = false
	_elapsed = 0.0
	_show_frame(0)
	set_process(true)


func _on_back_pressed() -> void:
	var tw := create_tween()
	tw.tween_property(root_ctrl, "modulate:a", 0.0, FADE_DURATION)
	await tw.finished
	emit_signal("finished")
	queue_free()


func _on_save_pressed() -> void:
	if _replay_saved:
		return
	var path: String = _save_replay_to_disk()
	if _saved_label != null:
		if path.is_empty():
			_saved_label.text = tr("HUD_REPLAY_SAVE_FAIL")
			_saved_label.add_theme_color_override("font_color", Color(1, 0.6, 0.6, 1))
		else:
			_replay_saved = true
			_saved_label.text = tr("HUD_REPLAY_SAVED") % path
		_saved_label.visible = true


# Salva os frames do replay como PNGs numa subpasta de replays/, ao lado do
# executável (a pasta que o launcher cria). Cai em user:// se não der escrita.
# Retorna o caminho da pasta salva, ou "" em falha.
func _save_replay_to_disk() -> String:
	if frames.is_empty():
		return ""
	var ts: Dictionary = Time.get_datetime_dict_from_system()
	var folder_name: String = "replay_%04d%02d%02d_%02d%02d%02d" % [
		ts.year, ts.month, ts.day, ts.hour, ts.minute, ts.second]
	var bases: Array[String] = [
		OS.get_executable_path().get_base_dir().path_join("replays"),
		"user://replays",
	]
	for base in bases:
		var dir_path: String = base.path_join(folder_name)
		if DirAccess.make_dir_recursive_absolute(dir_path) != OK:
			continue
		var saved_any: bool = false
		var i: int = 0
		for img in frames:
			if img is Image and not (img as Image).is_empty():
				var fpath: String = dir_path.path_join("frame_%03d.png" % i)
				if (img as Image).save_png(fpath) == OK:
					saved_any = true
			i += 1
		if saved_any:
			return ProjectSettings.globalize_path(dir_path) if dir_path.begins_with("user://") else dir_path
	return ""
