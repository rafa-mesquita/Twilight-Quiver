extends CanvasLayer

# HUD: overlay preto + top layer onde o sprite clonado do player
# (e o kill effect) é renderizado por cima do preto durante a sequência de morte.
# Player.gd encontra esse nó pelo grupo "hud" e chama play_death_sequence().

# Quanto descer o sprite de morte na tela (visualmente o player caído fica um pouco mais embaixo).
# Em pixels do viewport native (1920×1080); 12 = ~3px do mundo após zoom 4× da câmera.
const DEATH_SPRITE_Y_OFFSET: float = 12.0
# Tempo do clone deslizar da posição real do player até o centro (evita teleporte abrupto).
const MOVE_TO_CENTER_DURATION: float = 0.25

@onready var death_overlay: ColorRect = $DeathOverlay
@onready var death_top_layer: CanvasLayer = $DeathTopLayer
@onready var restart_button: Button = $DeathTopLayer/RestartButton
@onready var menu_button: Button = $DeathTopLayer/MenuButton
@onready var survival_label: Label = $DeathTopLayer/SurvivalLabel
@onready var score_label: Label = $DeathTopLayer/ScoreLabel
@onready var unlock_panel: Panel = $DeathTopLayer/UnlockPanel
@onready var unlock_title: Label = $DeathTopLayer/UnlockPanel/Margin/VBox/UnlockTitle
@onready var unlock_preview: Node2D = $DeathTopLayer/UnlockPanel/Margin/VBox/PreviewBox/UnlockPreview
@onready var unlock_name_label: Label = $DeathTopLayer/UnlockPanel/Margin/VBox/UnlockName
@onready var unlock_quest_label: Label = $DeathTopLayer/UnlockPanel/Margin/VBox/UnlockQuestLabel
@onready var tower_alert: Control = $TowerAlertIndicator

# Leaderboard: auto-submit silencioso em build de release. Cliente HTTP é
# instanciado lazy quando player morre (em release). Em debug, nada é enviado.
const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _SCORE_CALC := preload("res://scripts/systems/score_calc.gd")
const _PLAYER_PREVIEW_SCENE: PackedScene = preload("res://scenes/ui/player_preview.tscn")
const _SETTINGS_PATH: String = "user://settings.cfg"
var _leaderboard_client: Node = null

# Tracking pra exibir indicador quando torre sofre ataque off-screen
const TOWER_ALERT_HOLD: float = 1.5
const TOWER_ALERT_EDGE_MARGIN: float = 80.0
var _tower_alert_target: Node2D = null
var _tower_alert_timer: float = 0.0

# Spritesheet do HUD: 9 frames de 45x145, mapeados pra cortes de progresso da wave.
const HUD_FRAME_WIDTH: int = 45
const HUD_FRAME_HEIGHT: int = 145
const PROGRESS_THRESHOLDS: Array[int] = [0, 2, 20, 40, 50, 65, 75, 85, 100]
# Player atrás da HUD: fica translúcido pra dar pra ver atrás.
const HUD_TRANSPARENT_ALPHA: float = 0.4
const HUD_OPAQUE_ALPHA: float = 1.0
const HUD_ALPHA_FADE: float = 0.15
# Scale aplicado em runtime pra HudFrame não ocupar o editor (45×145 nativo).
# Tunable — se ajustar via HUD editor e fizer "Print Values", trocar este valor aqui.
const HUD_RUNTIME_SCALE: Vector2 = Vector2(3, 3)

@onready var hud_frame: TextureRect = $HudFrame
@onready var wave_number_label: Label = $HudFrame/WaveNumberLabel
@onready var gold_count_label: Label = $GoldDisplay/CountLabel
@onready var hp_bar: Control = $HpBar
@onready var hp_bar_fill: ColorRect = $HpBar/Fill
@onready var hp_bar_label: Label = $HpBar/Label
@onready var dash_cd_bar: Control = $DashCdBar
@onready var dash_cd_fill: ColorRect = $DashCdBar/Fill
@onready var dash_cd_label: Label = $DashCdBar/Label
@onready var fire_skill_icon: Control = $FireSkillIcon
@onready var fire_skill_cd_label: Label = $FireSkillIcon/CdLabel
@onready var chain_lightning_skill_icon: Control = $ChainLightningSkillIcon
@onready var chain_lightning_skill_cd_label: Label = $ChainLightningSkillIcon/CdLabel
@onready var curse_skill_icon: Control = $CurseSkillIcon
@onready var curse_skill_cd_label: Label = $CurseSkillIcon/CdLabel
@onready var ice_skill_icon: Control = $IceSkillIcon
@onready var ice_skill_cd_label: Label = $IceSkillIcon/CdLabel
@onready var esquivando_skill_icon: Control = $EsquivandoSkillIcon
@onready var esquivando_stack_label: Label = $EsquivandoSkillIcon/StackLabel
@onready var perfurante_counter_icon: Control = $PerfuranteCounterIcon
@onready var perfurante_count_label: Label = $PerfuranteCounterIcon/CountLabel
@onready var perfurante_frame_ring: ColorRect = $PerfuranteCounterIcon/FrameRing
@onready var perfurante_inner: ColorRect = $PerfuranteCounterIcon/Inner
# Glow ativo (skill do espaço): durante esse período, modulate do ícone é
# sobrescrito pelo "active color" e ignora o estado de stacks.
var _esquivando_ability_glow_active: bool = false
# Posições do ícone do Esquivando: ocupa o slot do elemental (150) quando o
# player ainda não tem nenhum elemental no nível que ativa o icone (Fire/Chain
# lv3+, Curse lv4+). Quando ganha, desloca pro slot 330 (à direita do Chain).
const ESQUIVANDO_ICON_LEFT_X: float = 150.0
const ESQUIVANDO_ICON_RIGHT_X: float = 330.0
const ESQUIVANDO_ICON_WIDTH: float = 76.0
@onready var upgrade_column_vbox: VBoxContainer = $UpgradeColumn/VBox
@onready var boss_hp_bar: Control = $BossHpBar
@onready var boss_hp_fill: ColorRect = $BossHpBar/ArtScale/Fill
@onready var boss_hp_label: Label = $BossHpBar/Label
@onready var boss_name_label: Label = $BossHpBar/NameLabel
# Mapeamento de grupos de boss → nome a exibir. Mais bosses futuros: adicionar
# entrada nesse dict.
const BOSS_NAMES: Dictionary = {
	"mage_monkey": "MAGE MONKEY",
}
var _current_boss: Node2D = null

# Coluna de upgrades adquiridos (right edge da HUD).
const UPGRADE_DISPLAY_ORDER: Array[String] = [
	# Status primeiro (sempre visíveis assim que comprados)
	"hp", "armor", "damage", "attack_speed", "move_speed",
	# Upgrades de gameplay
	"perfuracao", "ricochet_arrow", "multi_arrow", "double_arrows", "chain_lightning",
	"fire_arrow", "curse_arrow", "ice_arrow", "graviton", "boomerang", "critical_chance", "life_steal", "dash", "esquivando",
	"gold_magnet",
	# Aliados
	"woodwarden", "leno", "capivara_joe", "ting",
]
# Caps onde "MAX" substitui "Lx" no badge (status escala infinito → sem cap).
const _UPG_CAPS: Dictionary = {
	"perfuracao": 4, "ricochet_arrow": 4, "multi_arrow": 4, "double_arrows": 4, "chain_lightning": 4,
	"fire_arrow": 4, "curse_arrow": 4, "ice_arrow": 4, "graviton": 4, "boomerang": 4, "critical_chance": 4, "life_steal": 4,
	"dash": 4, "esquivando": 4, "gold_magnet": 4,
	"woodwarden": 4, "leno": 4, "capivara_joe": 4, "ting": 4,
}
const _UPG_STATUS_COMBINED_PATH: String = "res://assets/Hud/shop/status/HP - atck speed - Move speed - Atck Dmg.png"
const _UPG_STATUS_COMBINED_ROWS: Dictionary = {"hp": 0, "attack_speed": 1, "move_speed": 2, "damage": 3}
# Path direto pra cada id que tem arte própria. Faltantes caem em placeholder
# de upgrade ou aliado (categoria detectada pela posição na ordem).
const _UPG_PATHS: Dictionary = {
	"armor": "res://assets/Hud/shop/status/Armadura.png",
	"fire_arrow": "res://assets/Hud/shop/upgrade/fire_arrow2.png",
	"curse_arrow": "res://assets/Hud/shop/upgrade/curse_arrow.png",
	"ice_arrow": "res://assets/Hud/shop/upgrade/ice arrow/sangue frio card design-Sheet.png",
	"multi_arrow": "res://assets/Hud/shop/upgrade/multi_arrow.png",
	"double_arrows": "res://assets/Hud/shop/upgrade/multi_arrow.png",  # compartilha arte do multi_arrow (mesma família marrom)
	"chain_lightning": "res://assets/Hud/shop/upgrade/chain_lightning.png",
	"graviton": "res://assets/Hud/shop/upgrade/graviton/graviton card-Sheet.png",
	"perfuracao": "res://assets/Hud/shop/upgrade/perfuracao.png",
	"ricochet_arrow": "res://assets/Hud/shop/upgrade/ricochete.png",
	"gold_magnet": "res://assets/Hud/shop/upgrade/coin master.png",
	"life_steal": "res://assets/Hud/shop/upgrade/life steal.png",
	"dash": "res://assets/Hud/shop/upgrade/deslizando.png",
	"esquivando": "res://assets/Hud/shop/upgrade/deslizando.png",
	"leno": "res://assets/Hud/shop/aliado/Leno/Leno Card.png",
	"woodwarden": "res://assets/Hud/shop/aliado/woodwarden/woodwarden card.png",
	"ting": "res://assets/Hud/shop/aliado/ting/ting card.png",
	"capivara_joe": "res://assets/Hud/shop/aliado/capivara joe/capivara joe card.png",
	"boomerang": "res://assets/Hud/shop/upgrade/boomerang/boomerang card design.png",
	"critical_chance": "res://assets/Hud/shop/upgrade/flechas criticas/felchas criticas card design.png",
}
const _UPG_FALLBACK_UPGRADE: String = "res://assets/Hud/shop/upgrade/placeholder.png"
const _UPG_FALLBACK_ALIADO: String = "res://assets/Hud/shop/aliado/placeholder.png"
# Tamanho da célula da arte (atlas é 4 cells lado-a-lado por nível).
const _UPG_FRAME_NORMAL: Vector2i = Vector2i(38, 47)  # upgrade/aliado
const _UPG_FRAME_STATUS: Vector2i = Vector2i(65, 17)  # status/armor (faixa horizontal)
# IDs por categoria (pra resolver fallback e tamanho de célula).
const _UPG_STATUS_IDS: Array[String] = ["hp", "armor", "damage", "attack_speed", "move_speed"]
const _UPG_ALIADO_IDS: Array[String] = ["woodwarden", "leno", "capivara_joe", "ting"]
# Largura/altura de cada chip na coluna. Status são wide (65×17), upgrade/aliado
# são quase quadrados (38×47); chip único acomoda os dois com letterbox.
const _UPG_CHIP_SIZE: Vector2 = Vector2(72, 44)
# Quantidade de cells (níveis) por categoria de arte. Status (HP/armor/etc)
# tem 5 frames (1-5); upgrade/aliado tem 4 (1-4). Usado pra mapear o nível
# atual no cell certo do atlas.
const _UPG_MAX_CELLS_NORMAL: int = 4
const _UPG_MAX_CELLS_STATUS: int = 5
const _UPG_BADGE_COLOR: Color = Color(1.0, 0.93, 0.4, 1.0)
# Badge usa fonte do sistema (não ByteBounce) pra renderizar o caractere ★.
# SystemFont escolhe automaticamente uma fonte instalada que suporte unicode.
var _upg_badge_font: SystemFont = null


func _get_upg_badge_font() -> SystemFont:
	if _upg_badge_font != null:
		return _upg_badge_font
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Segoe UI", "Arial", "Helvetica", "DejaVu Sans", "Noto Sans"])
	_upg_badge_font = sf
	return sf

# Largura total do Fill (sem padding agora que tirei o Bg/border).
const BAR_FILL_WIDTH: float = 330.0
@onready var intro_overlay: Control = $IntroOverlay
@onready var intro_label: Label = $IntroOverlay/Label
@onready var cleared_overlay: Control = $ClearedOverlay
@onready var cleared_label: Label = $ClearedOverlay/Label
@onready var continue_button: Button = $ClearedOverlay/ContinueButton


var _hud_alpha_target: float = HUD_OPAQUE_ALPHA
var _hud_alpha_tween: Tween

# Pause menu (ESC) — overlay procedural, process_mode ALWAYS pra continuar
# respondendo enquanto get_tree().paused é true.
var _pause_layer: CanvasLayer = null
var _pause_visible: bool = false

# Settings overlay aberto a partir do botão "Configurações" no menu de pausa.
# Reusa a cena scenes/ui/settings_menu.tscn em modo overlay.
const _SETTINGS_MENU_SCENE: PackedScene = preload("res://scenes/ui/settings_menu.tscn")
var _settings_overlay_layer: CanvasLayer = null


func _ready() -> void:
	add_to_group("hud")
	# HUD precisa receber input mesmo com a árvore pausada — senão ESC pra fechar
	# o pause não chega.
	process_mode = Node.PROCESS_MODE_ALWAYS
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	_create_pause_menu()
	# Aplica scale em runtime — no editor o HudFrame fica em 1× (45×145) pra não
	# atrapalhar a edição do mapa.
	hud_frame.scale = HUD_RUNTIME_SCALE
	# Esconde no runtime — script mostra quando a wave começa. No editor fica visível
	# pra você poder ajustar a posição da arte e da label do número.
	hud_frame.visible = false
	# Marca todos os Controls gameplay como MOUSE_FILTER_IGNORE pra cliques sobre
	# eles (ex: barra de HP) não bloquearem o tiro do player. Buttons da tela de
	# morte/pausa precisam receber input — esses estão em DeathTopLayer/pause_layer
	# (separados, não tocados aqui).
	for control_path in [
		"HudFrame", "HpBar", "DashCdBar", "FireSkillIcon", "ChainLightningSkillIcon", "CurseSkillIcon",
		"IceSkillIcon", "EsquivandoSkillIcon", "PerfuranteCounterIcon", "GoldDisplay", "TowerAlertIndicator",
	]:
		var n := get_node_or_null(control_path)
		if n != null:
			_set_mouse_filter_recursive(n)
	# Marca a coluna de upgrades como mouse-pass-through (consistente com resto da HUD).
	_set_mouse_filter_recursive($UpgradeColumn)
	# Conecta nos signals de gold/hp/dash do player. Defer pra player já estar pronto.
	_connect_player_signals.call_deferred()


func _set_mouse_filter_recursive(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_set_mouse_filter_recursive(child)


func _connect_player_signals() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player.has_signal("gold_changed") and not player.gold_changed.is_connected(_on_gold_changed):
		player.gold_changed.connect(_on_gold_changed)
	if "gold" in player:
		gold_count_label.text = str(player.gold)
	# HP bar.
	if player.has_signal("hp_changed") and not player.hp_changed.is_connected(_on_player_hp_changed):
		player.hp_changed.connect(_on_player_hp_changed)
	if "hp" in player and "max_hp" in player:
		_on_player_hp_changed(player.hp, player.max_hp)
	# Dash bar — só aparece quando o player tem o upgrade.
	if player.has_signal("dash_unlocked") and not player.dash_unlocked.is_connected(_on_dash_unlocked):
		player.dash_unlocked.connect(_on_dash_unlocked)
	if player.has_signal("dash_cooldown_changed") and not player.dash_cooldown_changed.is_connected(_on_dash_cooldown_changed):
		player.dash_cooldown_changed.connect(_on_dash_cooldown_changed)
	if "has_dash" in player and player.has_dash:
		_on_dash_unlocked()
	# Esquivando reusa a mesma barra do dash (mutuamente exclusivos). Só mostra
	# a partir do lv3, quando a skill do espaço destrava — antes disso o
	# Esquivando dá só passive stacks/dodge, sem cooldown a exibir.
	if player.has_signal("esquivando_unlocked") and not player.esquivando_unlocked.is_connected(_on_esquivando_unlocked):
		player.esquivando_unlocked.connect(_on_esquivando_unlocked)
	if player.has_signal("esquivando_cooldown_changed") and not player.esquivando_cooldown_changed.is_connected(_on_dash_cooldown_changed):
		player.esquivando_cooldown_changed.connect(_on_dash_cooldown_changed)
	# Ícone de stacks — visível a partir do lv1 (passive já tá ativa).
	if player.has_signal("esquivando_stacks_changed") and not player.esquivando_stacks_changed.is_connected(_on_esquivando_stacks_changed):
		player.esquivando_stacks_changed.connect(_on_esquivando_stacks_changed)
	# Glow do ícone enquanto a skill do espaço está ativa (lv3+).
	if player.has_signal("esquivando_ability_active_changed") and not player.esquivando_ability_active_changed.is_connected(_on_esquivando_ability_active_changed):
		player.esquivando_ability_active_changed.connect(_on_esquivando_ability_active_changed)
	if "esquivando_level" in player and int(player.esquivando_level) >= 1:
		_on_esquivando_unlocked()
	if "esquivando_level" in player and int(player.esquivando_level) >= 2:
		dash_cd_bar.visible = true
	# Fire skill icon — só aparece quando player chega no Fogo lv3.
	if player.has_signal("fire_skill_unlocked") and not player.fire_skill_unlocked.is_connected(_on_fire_skill_unlocked):
		player.fire_skill_unlocked.connect(_on_fire_skill_unlocked)
	if player.has_signal("fire_skill_cooldown_changed") and not player.fire_skill_cooldown_changed.is_connected(_on_fire_skill_cooldown_changed):
		player.fire_skill_cooldown_changed.connect(_on_fire_skill_cooldown_changed)
	if "fire_arrow_level" in player and int(player.fire_arrow_level) >= 3:
		_on_fire_skill_unlocked()
	# Chain Lightning skill icon — aparece quando player chega no Chain Lightning lv3.
	if player.has_signal("chain_lightning_skill_unlocked") and not player.chain_lightning_skill_unlocked.is_connected(_on_chain_lightning_skill_unlocked):
		player.chain_lightning_skill_unlocked.connect(_on_chain_lightning_skill_unlocked)
	if player.has_signal("chain_lightning_skill_cooldown_changed") and not player.chain_lightning_skill_cooldown_changed.is_connected(_on_chain_lightning_skill_cooldown_changed):
		player.chain_lightning_skill_cooldown_changed.connect(_on_chain_lightning_skill_cooldown_changed)
	if "chain_lightning_level" in player and int(player.chain_lightning_level) >= 3:
		_on_chain_lightning_skill_unlocked()
	# Curse skill icon — só aparece quando player chega na Maldição lv4.
	if player.has_signal("curse_skill_unlocked") and not player.curse_skill_unlocked.is_connected(_on_curse_skill_unlocked):
		player.curse_skill_unlocked.connect(_on_curse_skill_unlocked)
	if player.has_signal("curse_skill_cooldown_changed") and not player.curse_skill_cooldown_changed.is_connected(_on_curse_skill_cooldown_changed):
		player.curse_skill_cooldown_changed.connect(_on_curse_skill_cooldown_changed)
	if "curse_arrow_level" in player and int(player.curse_arrow_level) >= 4:
		_on_curse_skill_unlocked()
	# Ice (Time Freeze) skill icon — aparece quando player chega no Gelo lv4.
	if player.has_signal("time_freeze_skill_unlocked") and not player.time_freeze_skill_unlocked.is_connected(_on_time_freeze_skill_unlocked):
		player.time_freeze_skill_unlocked.connect(_on_time_freeze_skill_unlocked)
	if player.has_signal("time_freeze_skill_cooldown_changed") and not player.time_freeze_skill_cooldown_changed.is_connected(_on_time_freeze_skill_cooldown_changed):
		player.time_freeze_skill_cooldown_changed.connect(_on_time_freeze_skill_cooldown_changed)
	if "ice_arrow_level" in player and int(player.ice_arrow_level) >= 4:
		_on_time_freeze_skill_unlocked()
	# Contador da flecha perfurante — visível a partir do lv1.
	if player.has_signal("perfuracao_counter_changed") and not player.perfuracao_counter_changed.is_connected(_on_perfuracao_counter_changed):
		player.perfuracao_counter_changed.connect(_on_perfuracao_counter_changed)
	if "perfuracao_level" in player and int(player.perfuracao_level) >= 1:
		var ctr: int = int(player.get("_perf_shot_counter")) if "_perf_shot_counter" in player else 0
		_on_perfuracao_counter_changed(ctr, int(player.perfuracao_level))
	# Coluna de upgrades adquiridos: rebuild on signal.
	if player.has_signal("upgrade_applied") and not player.upgrade_applied.is_connected(_on_upgrade_applied):
		player.upgrade_applied.connect(_on_upgrade_applied)
	# Estado inicial — caso já tenha algum upgrade aplicado (free upgrade da wave 1
	# pode ter rolado antes do HUD conectar).
	_refresh_upgrade_column()


func _on_upgrade_applied(_id: String, _level: int) -> void:
	_refresh_upgrade_column()


func _update_boss_hp_bar() -> void:
	# Polling: procura primeiro node em grupo "boss" e mostra a barra com seus
	# dados. Sem boss vivo → esconde. Roda em _process pq spawna mid-wave.
	if _current_boss == null or not is_instance_valid(_current_boss):
		_current_boss = get_tree().get_first_node_in_group("boss") as Node2D
		if _current_boss == null:
			if boss_hp_bar.visible:
				boss_hp_bar.visible = false
			return
		# Boss recém-encontrado: ajusta nome (primeiro grupo conhecido em BOSS_NAMES).
		var name_text: String = "BOSS"
		for grp: String in BOSS_NAMES.keys():
			if (_current_boss as Node).is_in_group(grp):
				name_text = BOSS_NAMES[grp]
				break
		boss_name_label.text = name_text
		boss_hp_bar.visible = true
	if not ("hp" in _current_boss) or not ("max_hp" in _current_boss):
		return
	var hp: float = float(_current_boss.hp)
	var maxhp: float = float(_current_boss.max_hp)
	var ratio: float = 0.0 if maxhp <= 0.0 else clampf(hp / maxhp, 0.0, 1.0)
	# Shader em Fill (boss_bar_fill.gdshader) faz o mascaramento dos caps via
	# row-scan da arte e aplica fill_ratio pra deplecionar pela direita.
	var mat: ShaderMaterial = boss_hp_fill.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill_ratio", ratio)
	boss_hp_label.text = "%d/%d" % [int(round(hp)), int(round(maxhp))]


func _refresh_upgrade_column() -> void:
	if upgrade_column_vbox == null:
		return
	for c in upgrade_column_vbox.get_children():
		c.queue_free()
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	for id in UPGRADE_DISPLAY_ORDER:
		var lvl: int = int(player.get_upgrade_count(id))
		if lvl <= 0:
			continue
		upgrade_column_vbox.add_child(_build_upgrade_chip(id, lvl))


func _build_upgrade_chip(id: String, lvl: int) -> Control:
	var chip := Control.new()
	chip.custom_minimum_size = _UPG_CHIP_SIZE
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Icon ocupa o chip inteiro com KEEP_ASPECT_CENTERED — célula da carta nunca
	# distorce, fica letterboxed nos lados. Usa o cell do nível atual (lvl-1
	# clampeado pelo número de cells daquela arte).
	var icon := TextureRect.new()
	icon.texture = _get_upgrade_icon_atlas(id, lvl)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.anchor_right = 1.0
	icon.anchor_bottom = 1.0
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	# Badge com nível (★ N). Bottom-right do chip, com outline preto. Fonte do
	# sistema porque ByteBounce não tem o caractere de estrela.
	var badge := Label.new()
	var capped: bool = _UPG_CAPS.has(id) and lvl >= int(_UPG_CAPS[id])
	badge.text = "★ MAX" if capped else "★ %d" % lvl
	badge.add_theme_font_override("font", _get_upg_badge_font())
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", _UPG_BADGE_COLOR)
	badge.add_theme_color_override("font_outline_color", Color.BLACK)
	badge.add_theme_constant_override("outline_size", 4)
	badge.anchor_left = 1.0
	badge.anchor_top = 1.0
	badge.anchor_right = 1.0
	badge.anchor_bottom = 1.0
	badge.offset_left = -54.0
	badge.offset_top = -22.0
	badge.offset_right = -2.0
	badge.offset_bottom = -2.0
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(badge)
	return chip


func _get_upgrade_icon_atlas(id: String, level: int) -> AtlasTexture:
	# Mapa: path da arte + tamanho do cell + row (pra status combined). Pega o
	# cell correspondente ao NÍVEL ATUAL (lvl-1 clampeado pelo número de cells).
	var path: String = ""
	var fw: int = 0
	var fh: int = 0
	var max_cells: int = 0
	var y_offset: int = 0
	if _UPG_STATUS_COMBINED_ROWS.has(id):
		path = _UPG_STATUS_COMBINED_PATH
		fw = _UPG_FRAME_STATUS.x
		fh = _UPG_FRAME_STATUS.y
		max_cells = _UPG_MAX_CELLS_STATUS
		y_offset = int(_UPG_STATUS_COMBINED_ROWS[id]) * fh
	elif _UPG_PATHS.has(id):
		path = _UPG_PATHS[id]
		var is_status: bool = _UPG_STATUS_IDS.has(id)
		fw = _UPG_FRAME_STATUS.x if is_status else _UPG_FRAME_NORMAL.x
		fh = _UPG_FRAME_STATUS.y if is_status else _UPG_FRAME_NORMAL.y
		max_cells = _UPG_MAX_CELLS_STATUS if is_status else _UPG_MAX_CELLS_NORMAL
	else:
		# Sem arte mapeada — placeholder por categoria (aliado vs upgrade).
		path = _UPG_FALLBACK_ALIADO if _UPG_ALIADO_IDS.has(id) else _UPG_FALLBACK_UPGRADE
		fw = _UPG_FRAME_NORMAL.x
		fh = _UPG_FRAME_NORMAL.y
		max_cells = _UPG_MAX_CELLS_NORMAL
	var tex: Texture2D = load(path) as Texture2D
	if tex == null:
		return null
	var frame_idx: int = clampi(level - 1, 0, max_cells - 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(frame_idx * fw, y_offset, fw, fh)
	return atlas


func _on_gold_changed(total: int) -> void:
	gold_count_label.text = str(total)


func _on_player_hp_changed(current: float, maximum: float) -> void:
	var ratio: float = 0.0 if maximum <= 0.0 else clampf(current / maximum, 0.0, 1.0)
	hp_bar_fill.size.x = BAR_FILL_WIDTH * ratio
	hp_bar_label.text = "%d/%d" % [int(round(current)), int(round(maximum))]


func _on_dash_unlocked() -> void:
	dash_cd_bar.visible = true


# Esquivando: lv1+ mostra o ícone de stacks. Lv2+ também mostra a barra do
# espaço (reusada do dash, mutuamente exclusivos).
func _on_esquivando_unlocked() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if "esquivando_level" in player and int(player.esquivando_level) >= 1:
		esquivando_skill_icon.visible = true
		_update_esquivando_icon_position(player)
		# Inicializa o label com stacks atuais (em cold load pode ser 0/3).
		var stacks: int = int(player.get("_esquivando_stacks")) if "_esquivando_stacks" in player else 0
		var cap: int = 3
		if player.has_method("_esquivando_max_stacks"):
			cap = int(player._esquivando_max_stacks())
		_on_esquivando_stacks_changed(stacks, cap)
	if "esquivando_level" in player and int(player.esquivando_level) >= 2:
		dash_cd_bar.visible = true


# Esquivando ocupa o slot do elemental (x=150) quando o player ainda não tem
# nenhum elemental no nível que ativa o ícone (Fire/Chain lv3+, Curse lv4+).
# Quando ganha um elemental, o ícone do Esquivando desloca pra x=330.
func _update_esquivando_icon_position(player: Node = null) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var has_any_elemental: bool = false
	if "fire_arrow_level" in player and int(player.fire_arrow_level) >= 3:
		has_any_elemental = true
	elif "chain_lightning_level" in player and int(player.chain_lightning_level) >= 3:
		has_any_elemental = true
	elif "curse_arrow_level" in player and int(player.curse_arrow_level) >= 4:
		has_any_elemental = true
	elif "ice_arrow_level" in player and int(player.ice_arrow_level) >= 4:
		has_any_elemental = true
	var new_x: float = ESQUIVANDO_ICON_RIGHT_X if has_any_elemental else ESQUIVANDO_ICON_LEFT_X
	esquivando_skill_icon.offset_left = new_x
	esquivando_skill_icon.offset_right = new_x + ESQUIVANDO_ICON_WIDTH


# Stack count do Esquivando: 0/3 ou 0/4 dependendo do level. Apaga (modulate
# escurece) quando não tem stacks ativos, fica em destaque quando tem.
# Cuidado: NÃO sobrescreve modulate quando a ability tá ativa (glow vence).
func _on_esquivando_stacks_changed(stacks: int, cap: int) -> void:
	esquivando_stack_label.text = "%d/%d" % [stacks, cap]
	if _esquivando_ability_glow_active:
		return  # mantém glow da ability
	if stacks <= 0:
		esquivando_skill_icon.modulate = Color(0.55, 0.6, 0.55, 1.0)
	else:
		esquivando_skill_icon.modulate = Color.WHITE


# Skill do espaço ativa: ícone brilha em ciano (+50% move ativo). Quando termina,
# volta ao modulate baseado em stacks.
func _on_esquivando_ability_active_changed(active: bool) -> void:
	_esquivando_ability_glow_active = active
	if active:
		esquivando_skill_icon.modulate = Color(0.65, 1.4, 1.1, 1.0)
	else:
		# Re-apply modulate baseado em stacks atuais.
		var player := get_tree().get_first_node_in_group("player")
		var stacks: int = 0
		var cap: int = 3
		if player != null:
			stacks = int(player.get("_esquivando_stacks")) if "_esquivando_stacks" in player else 0
			if player.has_method("_esquivando_max_stacks"):
				cap = int(player._esquivando_max_stacks())
		_on_esquivando_stacks_changed(stacks, cap)


func _on_dash_cooldown_changed(remaining: float, total: float) -> void:
	# Fill cresce do vazio (cooldown rolando) pro cheio (pronto).
	# 0 remaining = pronto = barra cheia.
	var ratio: float = 0.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	dash_cd_fill.size.x = BAR_FILL_WIDTH * ratio
	if remaining <= 0.001:
		dash_cd_label.text = "HUD_DASH_READY"
	else:
		dash_cd_label.text = "%.1fs" % remaining


func _on_fire_skill_unlocked() -> void:
	fire_skill_icon.visible = true
	# Esquivando (se ativo) desloca pra direita pra não sobrepor o ícone do fogo.
	_update_esquivando_icon_position()


func _on_fire_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Quadrado com ícone fixo + label do tempo no centro. Quando pronto, label
	# vazio e ícone full color. Em cooldown, ícone dimmed e label com segundos.
	if remaining <= 0.001:
		fire_skill_cd_label.text = ""
		fire_skill_icon.modulate = Color.WHITE
	else:
		fire_skill_cd_label.text = "%d" % int(ceilf(remaining))
		fire_skill_icon.modulate = Color(0.6, 0.55, 0.55, 1.0)


func _on_chain_lightning_skill_unlocked() -> void:
	chain_lightning_skill_icon.visible = true
	_update_esquivando_icon_position()


func _on_chain_lightning_skill_cooldown_changed(remaining: float, _total: float) -> void:
	if remaining <= 0.001:
		chain_lightning_skill_cd_label.text = ""
		chain_lightning_skill_icon.modulate = Color.WHITE
	else:
		chain_lightning_skill_cd_label.text = "%d" % int(ceilf(remaining))
		chain_lightning_skill_icon.modulate = Color(0.55, 0.6, 0.7, 1.0)


# Contador da Flecha Perfurante: a cada 3 ataques nos lv1-3 (próximo tiro
# perfurante). Lv4: todo tiro é perfurante → ícone sempre em destaque.
# Label mostra "1/2/3" como número do próximo ataque na sequência; quando vai
# pra 3 (counter interno == 2), highlight mostra que o próximo tiro perfura.
func _on_perfuracao_counter_changed(counter: int, level: int) -> void:
	if level <= 0:
		perfurante_counter_icon.visible = false
		return
	perfurante_counter_icon.visible = true
	var is_pierce_imminent: bool = level >= 4 or counter >= 2
	if level >= 4:
		perfurante_count_label.text = "★"
	else:
		perfurante_count_label.text = "%d" % (counter + 1)
	if is_pierce_imminent:
		perfurante_counter_icon.modulate = Color.WHITE
		perfurante_count_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	else:
		perfurante_counter_icon.modulate = Color(0.55, 0.62, 0.7, 1.0)
		perfurante_count_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _on_curse_skill_unlocked() -> void:
	curse_skill_icon.visible = true
	_update_esquivando_icon_position()


func _on_curse_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Mesmo pattern do fire skill: full color quando pronto, dimmed em cd.
	if remaining <= 0.001:
		curse_skill_cd_label.text = ""
		curse_skill_icon.modulate = Color.WHITE
	else:
		curse_skill_cd_label.text = "%d" % int(ceilf(remaining))
		curse_skill_icon.modulate = Color(0.55, 0.50, 0.65, 1.0)


func _on_time_freeze_skill_unlocked() -> void:
	ice_skill_icon.visible = true
	_update_esquivando_icon_position()


func _on_time_freeze_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Mesmo pattern dos outros: full color quando pronto, dimmed em cd.
	if remaining <= 0.001:
		ice_skill_cd_label.text = ""
		ice_skill_icon.modulate = Color.WHITE
	else:
		ice_skill_cd_label.text = "%d" % int(ceilf(remaining))
		ice_skill_icon.modulate = Color(0.55, 0.65, 0.78, 1.0)


func _process(delta: float) -> void:
	_update_tower_alert(delta)
	_update_boss_hp_bar()
	# Se o player passar atrás da HUD (canto do mapa), translúcido pra ver através.
	if not hud_frame.visible:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	# Posição do player na tela (sprite tem offset.y=-16, então corpo vai de origin-32 a origin).
	# Câmera com zoom: rect do player na tela escala pelo zoom (sprite 32×32 em world → 128×128 com zoom 4×).
	var camera := player.get_viewport().get_camera_2d()
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	var player_screen: Vector2 = player.get_global_transform_with_canvas().origin
	var player_size := Vector2(32, 32) * zoom
	var player_rect := Rect2(player_screen + Vector2(-16, -32) * zoom, player_size)
	var hud_rect: Rect2 = hud_frame.get_global_rect()
	var new_target: float = HUD_TRANSPARENT_ALPHA if hud_rect.intersects(player_rect) else HUD_OPAQUE_ALPHA
	if not is_equal_approx(new_target, _hud_alpha_target):
		_hud_alpha_target = new_target
		if _hud_alpha_tween != null and _hud_alpha_tween.is_valid():
			_hud_alpha_tween.kill()
		_hud_alpha_tween = create_tween()
		_hud_alpha_tween.tween_property(hud_frame, "modulate:a", new_target, HUD_ALPHA_FADE)


func flash_screen(color: Color = Color(0, 0, 0, 1), peak_alpha: float = 0.95, strobe_duration: float = 2.0, fade_duration: float = 1.0) -> void:
	# Efeito de trovão dividido em duas fases:
	# - strobe (strobe_duration): escuro bate → clareia → escuro de novo
	# - fade (fade_duration): fade out lento de volta ao normal
	# Total = strobe_duration + fade_duration.
	var rect := ColorRect.new()
	rect.color = Color(color.r, color.g, color.b, 0.0)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.offset_left = 0.0
	rect.offset_top = 0.0
	rect.offset_right = 0.0
	rect.offset_bottom = 0.0
	rect.size = get_viewport().get_visible_rect().size
	rect.z_index = 100
	add_child(rect)
	move_child(rect, get_child_count() - 1)

	# Proporções dentro do strobe (somam 1.0). Holds dominam pra dar peso de raio.
	const FRAC_STRIKE_IN: float = 0.08
	const FRAC_DARK_HOLD: float = 0.25
	const FRAC_CLEAR_OUT: float = 0.10
	const FRAC_CLEAR_HOLD: float = 0.14
	const FRAC_STRIKE2_IN: float = 0.08
	const FRAC_DARK2_HOLD: float = 0.35
	var s: float = maxf(strobe_duration, 0.05)
	var f: float = maxf(fade_duration, 0.05)

	var tw: Tween = create_tween()
	# 1. Bate escuro
	tw.tween_property(rect, "color:a", peak_alpha, s * FRAC_STRIKE_IN)
	tw.tween_interval(s * FRAC_DARK_HOLD)
	# 2. Clareia (deixa cena passar)
	tw.tween_property(rect, "color:a", 0.0, s * FRAC_CLEAR_OUT)
	tw.tween_interval(s * FRAC_CLEAR_HOLD)
	# 3. Bate escuro de novo
	tw.tween_property(rect, "color:a", peak_alpha, s * FRAC_STRIKE2_IN)
	tw.tween_interval(s * FRAC_DARK2_HOLD)
	# 4. Fade out lento (fase separada)
	tw.tween_property(rect, "color:a", 0.0, f)
	tw.tween_callback(Callable(rect, "queue_free"))


func play_raid_intro(wave_number: int) -> void:
	intro_label.text = tr("HUD_RAID_INTRO") % wave_number
	intro_overlay.modulate.a = 1.0
	intro_overlay.visible = true
	# Hold + fade out (revela o mundo).
	await get_tree().create_timer(1.5).timeout
	var t := create_tween()
	t.tween_property(intro_overlay, "modulate:a", 0.0, 0.5)
	await t.finished
	intro_overlay.visible = false


# ---------- Boss intro cinematic (waves 7 e 14) ----------
# Sequência:
#   1. Black overlay full + "Raid X" text fade in.
#   2. Hold com texto.
#   3. Texto fade out.
#   4. Cinematic sprite (16 frames @ 8 fps = 2s) toca no centro da tela.
#   5. Black overlay fade out → revela o mundo (boss já em defense, magos
#      já spawnados pelo wave_manager).
# Total: ~5s. wave_manager controla camera e music separadamente.

const BOSS_CINEMATIC_SHEET: Texture2D = preload(
	"res://assets/enemies/mage-monkey/animação surgimento.png"
)
const BOSS_CINEMATIC_FRAME_COUNT: int = 16
const BOSS_CINEMATIC_FRAME_SIZE: Vector2i = Vector2i(64, 64)
const BOSS_CINEMATIC_FPS: float = 2.0
const BOSS_CINEMATIC_SCALE: float = 5.0  # pixel art 64×64 escalado pra dar peso visual


func play_boss_intro(wave_number: int) -> void:
	intro_label.text = tr("HUD_RAID_INTRO") % wave_number
	intro_overlay.modulate.a = 1.0
	intro_overlay.visible = true
	# Fase 1: hold "Raid X" sobre o preto.
	await get_tree().create_timer(1.2).timeout
	# Fase 2: fade do texto.
	var t1 := create_tween()
	t1.tween_property(intro_label, "modulate:a", 0.0, 0.3)
	await t1.finished
	# Fase 3: cinematic sprite — toca sobre o overlay preto.
	var cinematic: AnimatedSprite2D = _build_boss_cinematic_sprite()
	cinematic.play(&"surgimento")
	var cinematic_duration: float = float(BOSS_CINEMATIC_FRAME_COUNT) / BOSS_CINEMATIC_FPS
	await get_tree().create_timer(cinematic_duration).timeout
	# Fase 4: cinematic some + fade do overlay preto revelando o mundo.
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(cinematic, "modulate:a", 0.0, 0.4)
	t2.tween_property(intro_overlay, "modulate:a", 0.0, 0.6)
	await t2.finished
	# Cleanup: remove sprite cinematic + reseta label/overlay.
	cinematic.queue_free()
	intro_overlay.visible = false
	intro_label.modulate.a = 1.0


func _build_boss_cinematic_sprite() -> AnimatedSprite2D:
	# Constrói o AnimatedSprite2D do surgimento programaticamente. Spritefames
	# tem 1 animação "surgimento" com 16 frames de 64×64 do sheet 1024×64.
	var sprite := AnimatedSprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(BOSS_CINEMATIC_SCALE, BOSS_CINEMATIC_SCALE)
	# Posiciona no centro da tela (IntroOverlay é Control fullscreen).
	sprite.position = intro_overlay.get_size() * 0.5
	var sf := SpriteFrames.new()
	sf.add_animation(&"surgimento")
	sf.set_animation_loop(&"surgimento", false)
	sf.set_animation_speed(&"surgimento", BOSS_CINEMATIC_FPS)
	for i in BOSS_CINEMATIC_FRAME_COUNT:
		var atlas := AtlasTexture.new()
		atlas.atlas = BOSS_CINEMATIC_SHEET
		atlas.region = Rect2(
			i * BOSS_CINEMATIC_FRAME_SIZE.x, 0,
			BOSS_CINEMATIC_FRAME_SIZE.x, BOSS_CINEMATIC_FRAME_SIZE.y
		)
		sf.add_frame(&"surgimento", atlas)
	sprite.sprite_frames = sf
	intro_overlay.add_child(sprite)
	return sprite


func play_wave_cleared(wave_number: int) -> void:
	cleared_label.text = tr("HUD_WAVE_CLEARED") % wave_number
	cleared_overlay.modulate.a = 0.0
	cleared_overlay.visible = true
	hud_frame.visible = false
	var t := create_tween()
	t.tween_property(cleared_overlay, "modulate:a", 1.0, 0.4)
	# Espera o player clicar em Continuar.
	await continue_button.pressed
	# Fade out e some.
	var t2 := create_tween()
	t2.tween_property(cleared_overlay, "modulate:a", 0.0, 0.4)
	await t2.finished
	cleared_overlay.visible = false


func update_wave_progress(killed: int, total: int, wave_number: int) -> void:
	if total <= 0:
		hud_frame.visible = false
		return
	hud_frame.visible = true
	var pct: int = int(round(float(killed) / float(total) * 100.0))
	# Pega o maior frame cujo threshold <= pct.
	var frame_idx: int = 0
	for i in range(PROGRESS_THRESHOLDS.size()):
		if PROGRESS_THRESHOLDS[i] <= pct:
			frame_idx = i
	var atlas := hud_frame.texture as AtlasTexture
	if atlas != null:
		atlas.region = Rect2(frame_idx * HUD_FRAME_WIDTH, 0, HUD_FRAME_WIDTH, HUD_FRAME_HEIGHT)
	wave_number_label.text = str(wave_number)


func play_death_sequence(
	player_sprite: AnimatedSprite2D,
	kill_effect_scene: PackedScene,
	freeze_duration: float,
	fadeout_duration: float,
	blackout_duration: float
) -> void:
	# Esconde HUD frame (número de wave) — não faz sentido mostrar durante a tela de morte.
	hud_frame.visible = false

	var center: Vector2 = get_viewport().get_visible_rect().size / 2.0
	# Câmera tem zoom (atualmente 4×) — preview fica em CanvasLayer NÃO afetado pela câmera,
	# então precisa escalar manualmente pra parecer do mesmo tamanho que o player na tela.
	var camera := player_sprite.get_viewport().get_camera_2d()
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE

	# Posição REAL do player na tela (considera câmera, mesmo se ela bateu na borda do mapa).
	var player_screen: Vector2 = player_sprite.get_global_transform_with_canvas().origin

	# Tela escurece.
	var fade_in := create_tween()
	fade_in.tween_property(death_overlay, "modulate:a", 1.0, blackout_duration)

	# Instancia o player_preview (body + todos os layers + bow) e aplica o loadout
	# atual do jogador. Anima junto durante a sequência. Posicionado pra coincidir
	# com a posição visível do player na tela.
	var preview: Node2D = _PLAYER_PREVIEW_SCENE.instantiate()
	preview.scale = zoom
	preview.position = player_screen
	death_top_layer.add_child(preview)
	SkinLoadout.apply_to(preview)
	var preview_body: AnimatedSprite2D = preview.get_node("Body")
	preview_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_body.flip_h = player_sprite.flip_h
	if preview_body.sprite_frames != null and preview_body.sprite_frames.has_animation(player_sprite.animation):
		preview_body.play(player_sprite.animation)
	preview_body.frame = player_sprite.frame
	preview_body.pause()

	# Desliza pro centro. preview.position é a origem do Node2D — body tem offset
	# (0, -16), então o sprite renderiza acima da posição. Pra terminar com sprite
	# no centro, compensa o offset.
	var center_target: Vector2 = center - Vector2(0.0, preview_body.offset.y * zoom.y)
	var move_tween := create_tween()
	move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(preview, "position", center_target, MOVE_TO_CENTER_DURATION)
	await move_tween.finished

	# Player parado por X segundos (drama).
	await get_tree().create_timer(freeze_duration).timeout

	# Anim de morte (4 frames @ speed 2.5). Desce o sprite alguns px durante a anim
	# (visualmente o personagem cai um pouco). SkinManager._process detecta a troca
	# de anim e propaga pra todos os layers.
	preview.position.y += DEATH_SPRITE_Y_OFFSET
	preview_body.play("death")
	await preview_body.animation_finished

	# Player some (fade out de tudo — preview é Node2D, modulate cascateia pros filhos).
	var fade_preview := create_tween()
	fade_preview.tween_property(preview, "modulate:a", 0.0, fadeout_duration)
	await fade_preview.finished

	# Mostra botão de jogar novamente.
	_show_restart_button()


func _show_restart_button() -> void:
	# Sequência: (1) atualiza stats e detecta unlock. (2) Se tem unlock, mostra
	# notificação primeiro com hold de 2.5s. (3) Depois reveal do score+stats+botões.
	var wave_num: int = 1
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		wave_num = int(wm.wave_number)

	# Pre-arma os elementos invisíveis — todos com modulate.a=0, vão fadear depois.
	var score: int = _SCORE_CALC.calc(_collect_run_stats(wave_num))
	score_label.text = tr("HUD_DEATH_SCORE") % score
	score_label.modulate.a = 0.0
	score_label.visible = true

	var p := get_tree().get_first_node_in_group("player")
	var killed_by_str: String = ""
	if p != null and "stats_killed_by" in p:
		killed_by_str = _format_killed_by(String(p.get("stats_killed_by")))
	survival_label.text = "%s\n%s\n%s" % [tr("HUD_DEATH_SURVIVAL") % wave_num, killed_by_str, _build_death_stats_block()]
	survival_label.modulate.a = 0.0
	survival_label.visible = true

	# Painel do breakdown de dano por fonte fica à ESQUERDA, separado dos botões
	# centrais. Criado programaticamente pra não ter que editar hud.tscn e
	# pra escalar dinâmicamente com qtd de fontes.
	var breakdown_label: Label = _build_or_get_dmg_breakdown_label()
	breakdown_label.text = _build_death_dmg_breakdown()
	breakdown_label.modulate.a = 0.0
	breakdown_label.visible = not breakdown_label.text.is_empty()

	restart_button.modulate.a = 0.0
	restart_button.visible = true
	menu_button.modulate.a = 0.0
	menu_button.visible = true

	unlock_panel.visible = false  # default — só aparece se unlock detectado

	# Atualiza stats persistentes e detecta novos unlocks NESSA run.
	var run_stats: Dictionary = _collect_run_stats(wave_num)
	var newly_unlocked: Array = SkinLoadout.record_run(run_stats)

	# Em release: auto-envia score + telemetria. Em debug: nada é enviado,
	# botões manuais (criados abaixo em _show_dev_send_buttons) fazem o envio.
	if not OS.is_debug_build():
		_auto_submit_score()
		_track_run_end(wave_num)
	else:
		_show_dev_send_buttons(wave_num)

	# Se há unlocks: mostra notificações em SEQUÊNCIA (uma de cada vez).
	# Cada uma: fade in (0.5s) → hold (2.5s) → fade out (0.3s, só se tiver próxima).
	# Múltiplos unlocks numa run só: cada skin ganha seu momento próprio.
	for i in range(newly_unlocked.size()):
		_show_unlock_notification(String(newly_unlocked[i]))
		var unlock_in := create_tween()
		unlock_in.tween_property(unlock_panel, "modulate:a", 1.0, 0.5)
		await unlock_in.finished
		await get_tree().create_timer(2.5).timeout
		# Se tiver próxima skin pra mostrar, fade out antes pra dar transição.
		if i < newly_unlocked.size() - 1:
			var unlock_out := create_tween()
			unlock_out.tween_property(unlock_panel, "modulate:a", 0.0, 0.3)
			await unlock_out.finished

	# Reveal final: score, stats, botões aparecem juntos.
	var reveal := create_tween().set_parallel(true)
	reveal.tween_property(score_label, "modulate:a", 1.0, 0.4)
	reveal.tween_property(survival_label, "modulate:a", 1.0, 0.4)
	reveal.tween_property(restart_button, "modulate:a", 1.0, 0.4)
	reveal.tween_property(menu_button, "modulate:a", 1.0, 0.4)
	if breakdown_label.visible:
		reveal.tween_property(breakdown_label, "modulate:a", 1.0, 0.4)


func _show_unlock_notification(skin_name: String) -> void:
	# Aplica a skin desbloqueada no preview animado e mostra o painel.
	# Usa as sprite_frames do AnimatedSprite2D do player do hud (acessível via grupo).
	var preview_body: AnimatedSprite2D = unlock_preview.get_node_or_null("Body") as AnimatedSprite2D
	var preview_skin: Node = unlock_preview.get_node_or_null("Skin")
	if preview_body == null or preview_skin == null:
		return
	# sprite_frames vem do player ativo na tree (mesmas regions/anims que a skin usa).
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		var player_sprite: AnimatedSprite2D = player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if player_sprite != null and player_sprite.sprite_frames != null:
			preview_body.sprite_frames = player_sprite.sprite_frames
	preview_body.play("walk")
	# Aplica o set inteiro da skin desbloqueada.
	var parts: Dictionary = SkinLoadout.get_parts_by_skin_name(skin_name)
	for slot in SkinLoadout.SLOTS:
		var part: SkinPart = parts.get(slot)
		if preview_skin.has_method("set_part"):
			preview_skin.set_part(slot, part)
	unlock_name_label.text = skin_name
	# Label da quest (ex: "Alcance a raid 10") — extraída do SKIN_QUESTS pra
	# o jogador entender o que fez pra liberar. quest.label é translation key.
	var quest: Dictionary = SkinLoadout.get_quest_for(skin_name)
	unlock_quest_label.text = String(quest.get("label", ""))
	unlock_panel.modulate.a = 0.0
	unlock_panel.visible = true


func _on_menu_pressed() -> void:
	# Garante despausar antes de trocar de cena (senão o menu carrega pausado).
	get_tree().paused = false
	# ESC-out de run em andamento (player vivo): emite run_end pra telemetria
	# e flush sincronizado. Score NÃO vai pro leaderboard — só runs que terminam
	# em morte (death screen) contam pro ranking.
	# Se player já morreu, o death screen já tratou submit/track. Não duplica.
	var player := get_tree().get_first_node_in_group("player")
	var is_dead: bool = player != null and "is_dead" in player and bool(player.is_dead)
	if not is_dead:
		var wave_num: int = 0
		var wm := get_tree().get_first_node_in_group("wave_manager")
		if wm != null and "wave_number" in wm:
			wave_num = int(wm.wave_number)
		_track_run_end(wave_num)
		if has_node("/root/Telemetry"):
			get_node("/root/Telemetry").flush_now()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ---------- Death stats ----------

# Mapeia source_id (passado em player.take_damage pelas criaturas) → translation
# key da frase "Morto pelo X" exibida no death overlay. IDs ausentes caem em
# HUD_DEATH_BY_UNKNOWN. Cada key contém a frase completa pra dar liberdade de
# tradução por idioma (não tem nome de criatura + nome de skill separados).
const _DEATH_SOURCE_LABELS: Dictionary = {
	"melee": "HUD_DEATH_BY_MELEE",
	"monkey": "HUD_DEATH_BY_MONKEY",
	"stone_cube": "HUD_DEATH_BY_STONE_CUBE",
	"insect": "HUD_DEATH_BY_INSECT",
	"insect_poison": "HUD_DEATH_BY_INSECT_POISON",
	"mage": "HUD_DEATH_BY_MAGE",
	"summoner_mage": "HUD_DEATH_BY_SUMMONER_MAGE",
	"fire_mage": "HUD_DEATH_BY_FIRE_MAGE",
	"ice_mage": "HUD_DEATH_BY_ICE_MAGE",
	"electric_mage": "HUD_DEATH_BY_ELECTRIC_MAGE",
	"mage_monkey": "HUD_DEATH_BY_MAGE_MONKEY",
	"mage_monkey_beam": "HUD_DEATH_BY_MAGE_MONKEY_BEAM",
}


func _format_killed_by(source_id: String) -> String:
	if source_id.is_empty():
		return tr("HUD_DEATH_BY_UNKNOWN")
	var key: String = String(_DEATH_SOURCE_LABELS.get(source_id, "HUD_DEATH_BY_UNKNOWN"))
	return tr(key)


func _build_or_get_dmg_breakdown_label() -> Label:
	# Reusa o label entre runs se já foi criado. Posiciona ancorado no centro
	# vertical com offset pra esquerda — fica fora da coluna central (score +
	# survival + botões) pra não empurrar os botões pra baixo quando a lista
	# de fontes é grande.
	var existing: Label = death_top_layer.get_node_or_null("DmgBreakdownLabel") as Label
	if existing != null:
		return existing
	var lbl := Label.new()
	lbl.name = "DmgBreakdownLabel"
	lbl.set_anchors_preset(Control.PRESET_CENTER)
	# Ancora central; offsets puxam pra coluna esquerda do viewport (1920 wide).
	lbl.offset_left = -900.0
	lbl.offset_right = -360.0
	lbl.offset_top = -280.0
	lbl.offset_bottom = 320.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 1, 1))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	lbl.add_theme_constant_override("outline_size", 4)
	var font: Font = load("res://font/ByteBounce.ttf") as Font
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 24)
	death_top_layer.add_child(lbl)
	return lbl


func _build_death_dmg_breakdown() -> String:
	# Breakdown do dano causado por fonte (ordenado desc). Reusa o dict de
	# labels do DamagePanel autoload pra consistência com o painel TAB.
	# Filtra fontes com 0 dano (ex: skills/aliados não usados nessa run).
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not ("stats_damage_dealt_by_source" in p):
		return ""
	var raw: Dictionary = p.get("stats_damage_dealt_by_source")
	var entries: Array = []
	for k in raw.keys():
		var amount: float = float(raw[k])
		if amount <= 0.0:
			continue
		entries.append([String(k), amount])
	if entries.is_empty():
		return ""
	entries.sort_custom(func(a, b): return a[1] > b[1])
	var lines: PackedStringArray = PackedStringArray()
	lines.append(tr("HUD_DEATH_DMG_BREAKDOWN_TITLE"))
	for entry in entries:
		var sid: String = entry[0]
		var amount: float = entry[1]
		var key: String = String(DamagePanel.SOURCE_LABELS.get(sid, ""))
		var name: String = tr(key) if not key.is_empty() else sid
		lines.append("%s: %d" % [name, int(round(amount))])
	return "\n".join(lines)


func _build_death_stats_block() -> String:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return ""
	var time_str: String = "0:00"
	if p.has_method("get_run_time_msec"):
		time_str = _format_run_time(int(p.get_run_time_msec()))
	var kills: int = int(p.get("stats_enemies_killed")) if "stats_enemies_killed" in p else 0
	var allies: int = int(p.get("stats_allies_made")) if "stats_allies_made" in p else 0
	var dmg_dealt: int = int(round(float(p.get("stats_damage_dealt")))) if "stats_damage_dealt" in p else 0
	var dmg_taken: int = int(round(float(p.get("stats_damage_taken")))) if "stats_damage_taken" in p else 0
	return tr("HUD_DEATH_STATS") % [time_str, kills, allies, dmg_dealt, dmg_taken]


func _format_run_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%d:%02d" % [minutes, seconds]


# ---------- Leaderboard auto-submit ----------

func _show_dev_send_buttons(wave_num: int) -> void:
	# Em debug build, em vez de auto-enviar, mostra 2 botões na tela de morte
	# pra disparo manual: telemetria run_end (com flush) e leaderboard submit.
	# Útil pra testar o stack sem poluir o backend com runs de dev.
	if death_top_layer == null:
		return
	var at01: Font = load("res://font/ByteBounce.ttf")

	var tel_btn := Button.new()
	tel_btn.name = "DevSendTelemetryBtn"
	tel_btn.text = "[DEV] Enviar Telemetria"
	tel_btn.set_anchors_preset(Control.PRESET_CENTER)
	tel_btn.position = Vector2(-200, 312)
	tel_btn.size = Vector2(400, 48)
	if at01 != null:
		tel_btn.add_theme_font_override("font", at01)
	tel_btn.add_theme_font_size_override("font_size", 24)
	tel_btn.add_theme_color_override("font_color", Color(0.65, 0.95, 1, 1))
	tel_btn.pressed.connect(func(): _dev_send_telemetry(wave_num, tel_btn))
	death_top_layer.add_child(tel_btn)

	var score_btn := Button.new()
	score_btn.name = "DevSendScoreBtn"
	score_btn.text = "[DEV] Enviar Score"
	score_btn.set_anchors_preset(Control.PRESET_CENTER)
	score_btn.position = Vector2(-200, 370)
	score_btn.size = Vector2(400, 48)
	if at01 != null:
		score_btn.add_theme_font_override("font", at01)
	score_btn.add_theme_font_size_override("font_size", 24)
	score_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.55, 1))
	score_btn.pressed.connect(func(): _dev_send_score(score_btn))
	death_top_layer.add_child(score_btn)


func _dev_send_telemetry(wave_num: int, btn: Button) -> void:
	_track_run_end(wave_num)
	if has_node("/root/Telemetry"):
		get_node("/root/Telemetry").flush_now()
	btn.disabled = true
	btn.text = "[DEV] Telemetria enviada"


func _dev_send_score(btn: Button) -> void:
	_auto_submit_score()
	btn.disabled = true
	btn.text = "[DEV] Score enviado"


func _track_run_end(wave_num: int) -> void:
	# Emite o evento run_end com stats finais. Não dispara flush — caller decide
	# (em release o auto-flush por timer pega; em debug é flush_now() do botão
	# ou do ESC-out).
	if not has_node("/root/Telemetry"):
		return
	var stats: Dictionary = _collect_run_stats(wave_num)
	stats["score"] = _SCORE_CALC.calc(stats)
	var t: Node = get_node("/root/Telemetry")
	t.track("run_end", stats)
	t.end_run()


func _auto_submit_score() -> void:
	var nick: String = _load_nickname()
	if nick.is_empty():
		push_warning("[leaderboard] skip submit: nickname vazio")
		return
	if _leaderboard_client == null:
		_leaderboard_client = _LEADERBOARD_CLIENT.new()
		add_child(_leaderboard_client)
		_leaderboard_client.upload_succeeded.connect(func(): print("[leaderboard] submit OK"))
		_leaderboard_client.upload_failed.connect(func(msg): push_warning("[leaderboard] submit FAIL: " + msg))
	var payload: Dictionary = _build_run_payload(nick)
	print("[leaderboard] submitting: ", payload)
	_leaderboard_client.submit_run(payload)


func _collect_run_stats(wave_num: int) -> Dictionary:
	var p := get_tree().get_first_node_in_group("player")
	var kills: int = 0
	var allies: int = 0
	var monkeys_cursed: int = 0
	var dmg_dealt: int = 0
	var dmg_taken: int = 0
	var bosses: Array = []
	var dmg_by_src: Dictionary = {}
	var dmg_dealt_by_src: Dictionary = {}
	var kills_by_src: Dictionary = {}
	var killed_by: String = ""
	if p != null:
		kills = int(p.get("stats_enemies_killed")) if "stats_enemies_killed" in p else 0
		allies = int(p.get("stats_allies_made")) if "stats_allies_made" in p else 0
		monkeys_cursed = int(p.get("stats_monkeys_cursed")) if "stats_monkeys_cursed" in p else 0
		dmg_dealt = int(round(float(p.get("stats_damage_dealt")))) if "stats_damage_dealt" in p else 0
		dmg_taken = int(round(float(p.get("stats_damage_taken")))) if "stats_damage_taken" in p else 0
		if "stats_bosses_killed" in p:
			bosses = p.get("stats_bosses_killed")
		# Snapshot do breakdown por fonte; valores arredondados pra int pra
		# casar com dmg_taken total (que também é int).
		if "stats_damage_taken_by_source" in p:
			var raw: Dictionary = p.get("stats_damage_taken_by_source")
			for k in raw.keys():
				dmg_by_src[String(k)] = int(round(float(raw[k])))
		if "stats_damage_dealt_by_source" in p:
			var raw_dd: Dictionary = p.get("stats_damage_dealt_by_source")
			for k in raw_dd.keys():
				dmg_dealt_by_src[String(k)] = int(round(float(raw_dd[k])))
		if "stats_kills_by_source" in p:
			var raw_k: Dictionary = p.get("stats_kills_by_source")
			for k in raw_k.keys():
				kills_by_src[String(k)] = int(raw_k[k])
		if "stats_killed_by" in p:
			killed_by = String(p.get("stats_killed_by"))
	return {
		"wave": wave_num,
		"kills": kills,
		"allies": allies,
		"monkeys_cursed": monkeys_cursed,
		"dmg_dealt": dmg_dealt,
		"dmg_taken": dmg_taken,
		"dmg_taken_by_source": dmg_by_src,
		"dmg_dealt_by_source": dmg_dealt_by_src,
		"kills_by_source": kills_by_src,
		"killed_by": killed_by,
		"bosses_killed": bosses,
	}


func _build_run_payload(nick: String) -> Dictionary:
	var wave_num: int = 0
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		wave_num = int(wm.wave_number)
	var time_ms: int = 0
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("get_run_time_msec"):
		time_ms = int(p.get_run_time_msec())
	var stats: Dictionary = _collect_run_stats(wave_num)
	var version: String = str(ProjectSettings.get_setting("application/config/version", ""))
	var payload: Dictionary = stats.duplicate()
	payload["nickname"] = nick
	payload["version"] = version
	payload["time_ms"] = time_ms
	payload["score"] = _SCORE_CALC.calc(stats)
	return payload


func _load_nickname() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return ""
	return str(cfg.get_value("player", "nickname", ""))


# ---------- Pause menu (ESC) ----------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode != KEY_ESCAPE:
		return
	# Bloqueia durante death (o menu de morte já cobre a tela) e quando outro
	# overlay está ativo (cleared / intro / placement de estrutura).
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "is_dead" in player and bool(player.is_dead):
		return
	if cleared_overlay.visible or intro_overlay.visible:
		return
	# Settings overlay aberto: ESC fecha ele, deixa o pause atrás como estava.
	if _settings_overlay_layer != null:
		_close_settings_overlay()
		get_viewport().set_input_as_handled()
		return
	if _pause_visible:
		_close_pause()
	else:
		_open_pause()
	get_viewport().set_input_as_handled()


func _open_pause() -> void:
	if _pause_layer == null:
		return
	_pause_visible = true
	_pause_layer.visible = true
	get_tree().paused = true


# Auto-pause quando a janela perde foco (alt+tab, clique em outro app). Mesma
# guarda do ESC — não interrompe death screen, intros ou cleared overlay.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT:
		return
	if _pause_visible:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "is_dead" in player and bool(player.is_dead):
		return
	if cleared_overlay != null and cleared_overlay.visible:
		return
	if intro_overlay != null and intro_overlay.visible:
		return
	_open_pause()


func _close_pause() -> void:
	if _pause_layer == null:
		return
	_pause_visible = false
	_pause_layer.visible = false
	get_tree().paused = false


# ---------- Settings overlay (a partir do menu de pausa) ----------

func _open_settings_overlay() -> void:
	if _settings_overlay_layer != null:
		return
	# CanvasLayer próprio acima do pause (layer 60) pra renderizar por cima.
	_settings_overlay_layer = CanvasLayer.new()
	_settings_overlay_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_settings_overlay_layer.layer = 70
	var settings: Control = _SETTINGS_MENU_SCENE.instantiate()
	settings.as_overlay = true
	settings.process_mode = Node.PROCESS_MODE_ALWAYS
	settings.closed.connect(_close_settings_overlay)
	_settings_overlay_layer.add_child(settings)
	add_child(_settings_overlay_layer)


func _close_settings_overlay() -> void:
	if _settings_overlay_layer == null:
		return
	_settings_overlay_layer.queue_free()
	_settings_overlay_layer = null


func _create_pause_menu() -> void:
	_pause_layer = CanvasLayer.new()
	_pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_layer.layer = 60
	_pause_layer.visible = false
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.78)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_layer.add_child(bg)
	var at01: Font = load("res://font/ByteBounce.ttf")
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-600, -260)
	title.size = Vector2(1200, 140)
	title.text = "HUD_PAUSE_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if at01 != null:
		title.add_theme_font_override("font", at01)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(title)
	var continue_btn := Button.new()
	continue_btn.set_anchors_preset(Control.PRESET_CENTER)
	continue_btn.position = Vector2(-220, -80)
	continue_btn.size = Vector2(440, 72)
	continue_btn.text = "HUD_PAUSE_CONTINUE"
	if at01 != null:
		continue_btn.add_theme_font_override("font", at01)
	continue_btn.add_theme_font_size_override("font_size", 48)
	continue_btn.pressed.connect(_close_pause)
	bg.add_child(continue_btn)
	var settings_btn := Button.new()
	settings_btn.set_anchors_preset(Control.PRESET_CENTER)
	settings_btn.position = Vector2(-220, 10)
	settings_btn.size = Vector2(440, 64)
	settings_btn.text = "HUD_PAUSE_SETTINGS"
	if at01 != null:
		settings_btn.add_theme_font_override("font", at01)
	settings_btn.add_theme_font_size_override("font_size", 36)
	settings_btn.pressed.connect(_open_settings_overlay)
	bg.add_child(settings_btn)
	var menu_btn := Button.new()
	menu_btn.set_anchors_preset(Control.PRESET_CENTER)
	menu_btn.position = Vector2(-220, 100)
	menu_btn.size = Vector2(440, 64)
	menu_btn.text = "HUD_PAUSE_MENU"
	if at01 != null:
		menu_btn.add_theme_font_override("font", at01)
	menu_btn.add_theme_font_size_override("font_size", 36)
	menu_btn.pressed.connect(_on_menu_pressed)
	bg.add_child(menu_btn)
	add_child(_pause_layer)


# ---------- Tower attack alert ----------

func notify_tower_attacked(tower: Node2D) -> void:
	# Chamado pelas torres quando recebem dano. Mostra indicador se off-screen.
	if not is_instance_valid(tower):
		return
	_tower_alert_target = tower
	_tower_alert_timer = TOWER_ALERT_HOLD


func _update_tower_alert(delta: float) -> void:
	if _tower_alert_timer > 0.0:
		_tower_alert_timer -= delta
	if _tower_alert_target == null or not is_instance_valid(_tower_alert_target) or _tower_alert_timer <= 0.0:
		tower_alert.visible = false
		return
	# Verifica se torre está off-screen.
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		tower_alert.visible = false
		return
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var canvas_xform := get_viewport().get_canvas_transform()
	var tower_screen: Vector2 = canvas_xform * _tower_alert_target.global_position
	var on_screen: bool = tower_screen.x >= 0 and tower_screen.x <= view_size.x \
		and tower_screen.y >= 0 and tower_screen.y <= view_size.y
	if on_screen:
		tower_alert.visible = false
		return
	# Calcula posição na borda apontando pra torre.
	var center: Vector2 = view_size * 0.5
	var dir: Vector2 = (tower_screen - center).normalized()
	# Clamp pra borda da tela respeitando margem.
	var max_x: float = view_size.x * 0.5 - TOWER_ALERT_EDGE_MARGIN
	var max_y: float = view_size.y * 0.5 - TOWER_ALERT_EDGE_MARGIN
	var t_to_x: float = max_x / max(absf(dir.x), 0.0001)
	var t_to_y: float = max_y / max(absf(dir.y), 0.0001)
	var t: float = minf(t_to_x, t_to_y)
	var pos: Vector2 = center + dir * t
	tower_alert.position = pos
	tower_alert.rotation = dir.angle()
	tower_alert.visible = true


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
