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
	var tw := create_tween()
	tw.tween_property(root_ctrl, "modulate:a", 0.0, FADE_DURATION)
	await tw.finished
	emit_signal("finished")
	queue_free()
