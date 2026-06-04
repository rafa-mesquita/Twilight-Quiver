extends Node

# Logger de performance pra CAÇAR o leak de FPS (nós/recursos/memória que acumulam
# e derrubam o frame depois da wave 7). Mostra um overlay no canto da tela E grava
# em user://perf_log.txt. A cada INTERVAL registra:
#   - fps, total de nós, nós ÓRFÃOS (removidos da árvore mas não liberados = leak),
#     total de objetos, total de recursos (pega leak de ShaderMaterial/Texture/etc),
#     memória estática (MB), draw calls;
#   - contagem por GRUPO (enemy/gold/arrow/...);
#   - top 6 CLASSES de nó na cena (acha o que acumula fora dos grupos).
#
# COMO USAR (build de diagnóstico): jogue até a wave cair de FPS. O overlay no canto
# superior esquerdo mostra os números ao vivo — tire um print quando travar. Tudo
# também fica em user://perf_log.txt:
#   Windows: %APPDATA%\Godot\app_userdata\Twilight Quiver\perf_log.txt
# Tecla F3 liga/desliga o overlay.
#
# É só DIAGNÓSTICO — `ENABLED = false` desliga tudo. NÃO deve ir pra release ligado.
# Autoload registrado em project.godot ([autoload] PerfLog).

const ENABLED: bool = true
const INTERVAL: float = 2.0        # gravação no arquivo + cálculo das top classes
const UI_INTERVAL: float = 0.5     # atualização do overlay (mais responsivo)
const GROUPS: Array[String] = [
	"enemy", "ally", "tank_ally", "gold", "arrow", "mage_projectile",
	"boomerang", "structure", "fire_mage", "ice_mage", "electric_mage",
	"dark_ball", "mini_arbusto", "arbusto", "heart", "world",
]
const LOG_PATH: String = "user://perf_log.txt"

var _accum: float = 0.0
var _ui_accum: float = 0.0
var _top_cache: String = ""
var _overlay: CanvasLayer = null
var _label: Label = null


func _ready() -> void:
	if not ENABLED:
		set_process(false)
		set_process_input(false)
		return
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line("=== perf log start (jogue até o FPS cair) ===")
		f.close()
	_build_overlay()
	print("[PERF] logger ativo — overlay no canto (F3 liga/desliga). Loga em ", LOG_PATH)


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	add_child(_overlay)
	_label = Label.new()
	_label.position = Vector2(8, 6)
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.4, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.text = "[PERF] aguardando partida... (F3 esconde)"
	_overlay.add_child(_label)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_F3 and _overlay != null:
			_overlay.visible = not _overlay.visible


func _process(delta: float) -> void:
	var tree := get_tree()
	if tree == null or tree.get_first_node_in_group("player") == null:
		return
	_ui_accum += delta
	_accum += delta
	if _accum >= INTERVAL:
		_accum = 0.0
		_top_cache = _top_classes(tree)
		_write_file(_compose(tree, true))
	if _ui_accum >= UI_INTERVAL:
		_ui_accum = 0.0
		if _label != null:
			_label.text = _compose(tree, false)


func _compose(tree: SceneTree, full: bool) -> String:
	var fps: float = Performance.get_monitor(Performance.TIME_FPS)
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphans: int = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	var objs: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var res: int = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	var mem_mb: float = Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var parts: Array[String] = []
	for g in GROUPS:
		var c: int = tree.get_nodes_in_group(g).size()
		if c > 0:
			parts.append("%s=%d" % [g, c])
	if full:
		return "[PERF] fps=%.0f nodes=%d orphans=%d objs=%d res=%d mem=%.1fMB draws=%d | %s | top:%s" % [
			fps, nodes, orphans, objs, res, mem_mb, draws, " ".join(parts), _top_cache,
		]
	# Overlay (multilinha, legível).
	return "[PERF]  fps %.0f   (F3 esconde)\nnodes %d   orphans %d\nres %d   mem %.0fMB   draws %d\n%s\ntop: %s" % [
		fps, nodes, orphans, res, mem_mb, draws, " ".join(parts), _top_cache,
	]


func _write_file(line: String) -> void:
	print(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line(line)
		f.close()


# Conta nós por classe na cena atual e devolve as 6 classes mais comuns.
func _top_classes(tree: SceneTree) -> String:
	var counts: Dictionary = {}
	var root: Node = tree.current_scene
	if root == null:
		return ""
	_walk(root, counts)
	var arr: Array = []
	for k in counts:
		arr.append([k, counts[k]])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	var out: Array[String] = []
	for i in mini(6, arr.size()):
		out.append("%s:%d" % [arr[i][0], arr[i][1]])
	return ",".join(out)


func _walk(n: Node, counts: Dictionary) -> void:
	var cls: String = n.get_class()
	counts[cls] = int(counts.get(cls, 0)) + 1
	for c in n.get_children():
		_walk(c, counts)
