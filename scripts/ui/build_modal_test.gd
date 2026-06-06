extends Control

# Cena de teste do RunBuildModal (DEV). Abra no editor e dê F6.
#   ESPAÇO → gera uma build aleatória e reabre o modal
#   N      → simula run antiga (sem build → "build não registrada")
#   ESC    → fecha o modal
#
# Não entra em build de release (é só uma cena de teste solta).

const _MODAL := preload("res://scripts/ui/run_build_modal.gd")

# Mesmos ids/níveis-máximos que o jogo usa, pra randomizar de forma realista.
const _UPGRADE_IDS: Array = [
	"fire_arrow", "curse_arrow", "ice_arrow", "stone_arrow", "tide_arrow",
	"perfuracao", "multi_arrow", "double_arrows", "chain_lightning", "life_steal",
	"gold_magnet", "dash", "esquivando", "fenda", "ricochet_arrow", "graviton",
	"boomerang", "critical_chance", "tiger_claws",
	"claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto",
]
const _STATUS_IDS: Array = ["hp", "damage", "attack_speed", "move_speed", "armor"]

var _hint: Label = null


func _ready() -> void:
	# Fundo (pra cena de teste não ficar transparente).
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.09, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_hint = Label.new()
	_hint.text = "ESPAÇO = build aleatória   ·   N = run antiga (sem build)   ·   ESC = fechar"
	_hint.position = Vector2(16, 12)
	var font: Font = load("res://font/Silver.ttf")
	if font != null:
		_hint.add_theme_font_override("font", font)
	_hint.add_theme_font_size_override("font_size", 22)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.66, 0.85, 1))
	add_child(_hint)

	_show_modal(_random_row())


func _show_modal(row: Dictionary) -> void:
	for c in get_children():
		if c is RunBuildModal:
			c.queue_free()
	var m: RunBuildModal = _MODAL.new()
	add_child(m)
	# open() depende dos nós internos criados no _ready do modal.
	m.call_deferred("open", row)


func _random_row() -> Dictionary:
	var upgrades: Dictionary = {}
	# ~45% de chance por upgrade, nível 1-4.
	for id in _UPGRADE_IDS:
		if randf() < 0.45:
			upgrades[id] = randi_range(1, 4)
	# Status escala mais alto (1-8).
	for id in _STATUS_IDS:
		if randf() < 0.6:
			upgrades[id] = randi_range(1, 8)

	# Itens: subset aleatório do catálogo (0-4).
	var all_items: Array = InventoryItems.ITEMS.keys()
	all_items.shuffle()
	var n_items: int = randi_range(0, mini(4, all_items.size()))
	var items: Array = all_items.slice(0, n_items)

	var wave: int = randi_range(21, 32)
	return {
		"nickname": "DEV-%04d" % randi_range(0, 9999),
		"wave": wave,
		"score": randi_range(5000, 25000),
		"time_ms": randi_range(240000, 600000),
		"time_to_w21_ms": randi_range(180000, 420000),
		"build": {"upgrades": upgrades, "items": items},
	}


func _old_run_row() -> Dictionary:
	# Sem a chave "build" → caminho "build não registrada".
	return {
		"nickname": "OLD-RUN",
		"wave": randi_range(15, 28),
		"score": randi_range(3000, 18000),
		"time_ms": randi_range(240000, 600000),
		"time_to_w21_ms": -1,
	}


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_show_modal(_random_row())
		KEY_N:
			_show_modal(_old_run_row())
