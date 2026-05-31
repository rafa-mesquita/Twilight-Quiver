extends Node

## Áudio dos menus pré-jogo (autoload — persiste entre trocas de cena):
##  - Música de fundo CONTÍNUA nos menus (main, skins, leaderboard, settings).
##    Não reinicia ao navegar entre menus; PARA ao entrar no jogo.
##  - SFX de clique em QUALQUER BaseButton pressionado num menu pré-jogo
##    (inclui botões criados em runtime, ex: cards/abas da tela de skins).
##
## Assets vêm de res://audios/Menu/ e são auto-detectados: arquivo com "click"
## no nome = SFX de clique; o outro = música. Buses: música→"Music", clique→"SFX"
## (respeitam os sliders de volume das Settings). Botões in-game (HUD/shop) ficam
## mudos porque a current_scene não está em _MENU_SCENES.

const _MENU_DIR: String = "res://audios/Menu"
# Ajuste fino dos volumes (dB). Mais negativo = mais baixo.
const _MUSIC_VOLUME_DB: float = -28.0
const _CLICK_VOLUME_DB: float = -14.0

# Cenas (current_scene) consideradas "menu pré-jogo". O resto (jogo) fica mudo.
const _MENU_SCENES: Array[String] = [
	"res://scenes/ui/main_menu.tscn",
	"res://scenes/ui/skin_select.tscn",
	"res://scenes/ui/leaderboard.tscn",
	"res://scenes/ui/settings_menu.tscn",
]

var _music: AudioStreamPlayer
var _click: AudioStreamPlayer


func _ready() -> void:
	var music_stream: AudioStream = null
	var click_stream: AudioStream = null
	for path in _list_audio_files():
		# SFX de clique = arquivo cujo nome tem "click"/"sound"/"sfx"; música = o resto.
		var fname: String = path.get_file().to_lower()
		if fname.find("click") != -1 or fname.find("sound") != -1 or fname.find("sfx") != -1:
			click_stream = load(path) as AudioStream
		else:
			music_stream = load(path) as AudioStream

	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	_music.volume_db = _MUSIC_VOLUME_DB
	if music_stream != null:
		_set_loop(music_stream, true)
		_music.stream = music_stream
	add_child(_music)

	_click = AudioStreamPlayer.new()
	_click.bus = &"SFX"
	_click.volume_db = _CLICK_VOLUME_DB
	if click_stream != null:
		_set_loop(click_stream, false)
		_click.stream = click_stream
	add_child(_click)

	# Conecta depois de adicionar os players próprios (pra não auto-disparar).
	get_tree().node_added.connect(_on_node_added)
	_connect_existing(get_tree().root)
	var cur: Node = get_tree().current_scene
	if cur != null:
		_update_music(cur.scene_file_path)


func _set_loop(stream: AudioStream, value: bool) -> void:
	# mp3/ogg expõem `loop`; wav usa loop_mode (não tratado — assets são mp3).
	if stream is AudioStreamMP3 or stream is AudioStreamOggVorbis:
		stream.loop = value


# ---------- Detecção de troca de cena + botões novos ----------

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)
	# Raiz de cena nova = filho direto do root com scene_file_path setado.
	if node.get_parent() == get_tree().root and node.scene_file_path != "":
		_update_music(node.scene_file_path)


func _connect_existing(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)
	for child in node.get_children():
		_connect_existing(child)


func _connect_button(btn: BaseButton) -> void:
	if not btn.pressed.is_connected(_on_button_pressed):
		btn.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	if _click.stream == null:
		return
	var cur: Node = get_tree().current_scene
	if cur != null and _MENU_SCENES.has(cur.scene_file_path):
		_click.play()


func _update_music(scene_path: String) -> void:
	if _music.stream == null:
		return
	if _MENU_SCENES.has(scene_path):
		if not _music.playing:
			_music.play()
	elif _music.playing:
		_music.stop()


# ---------- Scan da pasta (aceita .import pra build exportado) ----------

func _list_audio_files() -> Array:
	var out: Array = []
	var dir := DirAccess.open(_MENU_DIR)
	if dir == null:
		return out
	var seen: Dictionary = {}
	dir.list_dir_begin()
	var f: String = dir.get_next()
	while f != "":
		if not dir.current_is_dir():
			var fname: String = f
			var low: String = f.to_lower()
			if low.ends_with(".import"):
				fname = f.substr(0, f.length() - 7)
				low = fname.to_lower()
			var is_audio: bool = low.ends_with(".mp3") or low.ends_with(".ogg") or low.ends_with(".wav")
			if is_audio and not seen.has(fname):
				seen[fname] = true
				out.append("%s/%s" % [_MENU_DIR, fname])
		f = dir.get_next()
	dir.list_dir_end()
	return out
