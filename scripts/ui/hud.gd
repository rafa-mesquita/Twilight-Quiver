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
@onready var control_hints_container: VBoxContainer = $ControlHintsContainer

# Hints de controle já exibidos nesta run — cada um aparece UMA vez pra não
# encher a tela em ressubmissões. Reset implícito ao reiniciar o jogo.
var _control_hints_shown: Dictionary = {
	"basics": false,   # WASD + Click no início
	"space": false,    # Dash/Esquivando destravados
	"q": false,        # Elemental skill destravada (fogo/chain/curse/ice)
}

# Leaderboard: auto-submit silencioso em build de release. Cliente HTTP é
# instanciado lazy quando player morre (em release). Em debug, nada é enviado.
const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _SCORE_CALC := preload("res://scripts/systems/score_calc.gd")
const _PLAYER_PREVIEW_SCENE: PackedScene = preload("res://scenes/ui/player_preview.tscn")
const _SETTINGS_PATH: String = "user://settings.cfg"
const _CONTROL_HINT_SCENE: PackedScene = preload("res://scenes/ui/control_hint.tscn")
const _CONTROL_TEX_WASD: Texture2D = preload("res://assets/Hud/control_wasd.png")
const _CONTROL_TEX_CLICK: Texture2D = preload("res://assets/Hud/control_click.png")
const _CONTROL_TEX_SPACE: Texture2D = preload("res://assets/Hud/control_space.png")
const _CONTROL_TEX_Q: Texture2D = preload("res://assets/Hud/control_q.png")
var _leaderboard_client: Node = null

# Toast de unlock de skin em TEMPO REAL (canto inferior direito). O death screen
# continua mostrando a celebração completa; este é o aviso imediato. O HUD faz um
# poll leve (a cada _SKIN_UNLOCK_POLL_INTERVAL) combinando stats persistentes +
# live (read-only) via SkinLoadout.evaluate_live_unlocks, deduplica e enfileira.
var _skin_unlock_toast: SkinUnlockToast = null
const _SKIN_UNLOCK_POLL_INTERVAL: float = 0.5
var _skin_unlock_poll_accum: float = 0.0
var _skin_unlock_locked_at_start: Dictionary = {}
var _skin_unlock_snapshot_done: bool = false
var _skin_unlock_toasted: Dictionary = {}

# Tracking pra exibir indicador quando torre sofre ataque off-screen
const TOWER_ALERT_HOLD: float = 1.5
const TOWER_ALERT_EDGE_MARGIN: float = 80.0
var _tower_alert_target: Node2D = null
var _tower_alert_timer: float = 0.0

# Indicadores dos últimos inimigos vivos da wave (lazy-criados).
# Setas amarelas na borda da tela apontando pra cada inimigo off-screen — mesmo
# padrão visual do TowerAlertIndicator. Pool fixo de 2 (threshold do wave_manager).
const LAST_ENEMY_INDICATOR_COUNT: int = 2
const LAST_ENEMY_EDGE_MARGIN: float = 60.0
const LAST_ENEMY_ARROW_COLOR: Color = Color(1.0, 0.25, 0.25, 1.0)
const LAST_ENEMY_OUTLINE_COLOR: Color = Color(0.15, 0.05, 0.05, 0.85)
var _last_enemy_indicators: Array[Control] = []

# Spritesheet do HUD: 9 frames de 45x145, mapeados pra cortes de progresso da wave.
const HUD_FRAME_WIDTH: int = 45
const HUD_FRAME_HEIGHT: int = 145
const PROGRESS_THRESHOLDS: Array[int] = [0, 2, 20, 40, 50, 65, 75, 85, 100]
# Player atrás da HUD: fica translúcido pra dar pra ver atrás.
const HUD_TRANSPARENT_ALPHA: float = 0.4
const HUD_OPAQUE_ALPHA: float = 1.0
const HUD_ALPHA_FADE: float = 0.15
# Boss bar ancorada no rodapé (Duskrose) ocupa área jogável. Frame/texto ficam
# 100% opacos (look HUD normal), só o FILL (preenchimento colorido) é semi-
# transparente — controlado via shader `fill_color.a` no boss_hp_bar.tscn.
# Estas constantes aqui mantêm a interface antiga mas resolvem pra 1.0 (sem
# fade global) — manter pra retrocompatibilidade dos call sites.
const BOSS_BAR_BOTTOM_OPAQUE_ALPHA: float = 1.0
const BOSS_BAR_BOTTOM_TRANSPARENT_ALPHA: float = 1.0
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
@onready var stone_skill_icon: Control = $StoneSkillIcon
@onready var stone_skill_cd_label: Label = $StoneSkillIcon/CdLabel
@onready var tide_shield_icon: Control = $TideShieldIcon
@onready var tide_shield_cd_label: Label = $TideShieldIcon/CdLabel
@onready var esquivando_skill_icon: Control = $EsquivandoSkillIcon
@onready var esquivando_stack_label: Label = $EsquivandoSkillIcon/StackLabel
@onready var perfurante_counter_icon: Control = $PerfuranteCounterIcon
@onready var perfurante_count_label: Label = $PerfuranteCounterIcon/CountLabel
@onready var perfurante_frame_ring: ColorRect = $PerfuranteCounterIcon/FrameRing
@onready var ricochete_counter_icon: Control = $RicocheteCounterIcon
@onready var ricochete_count_label: Label = $RicocheteCounterIcon/CountLabel
@onready var ricochete_frame_ring: ColorRect = $RicocheteCounterIcon/FrameRing
@onready var perfurante_inner: ColorRect = $PerfuranteCounterIcon/Inner
# Glow ativo (skill do espaço): durante esse período, modulate do ícone é
# sobrescrito pelo "active color" e ignora o estado de stacks.
var _esquivando_ability_glow_active: bool = false
# Posições do ícone do Esquivando. SEM elemental ativo: ocupa o slot do elemental
# (x=150, que está livre). COM um elemental (Fire/Chain lv3+, Curse/Ice/Stone
# lv4+): desloca pra ESQUERDA (x=60) pra não sobrepor o cooldown do elemental —
# Esquivando e elemental NÃO são mutex (dá pra ter os dois ao mesmo tempo).
const ESQUIVANDO_ICON_NO_ELEM_X: float = 150.0
const ESQUIVANDO_ICON_ELEM_X: float = 60.0
const ESQUIVANDO_ICON_WIDTH: float = 76.0
@onready var upgrade_column_vbox: VBoxContainer = $UpgradeColumn/VBox
@onready var boss_hp_bar: Control = $BossHpBar
@onready var boss_hp_fill: ColorRect = $BossHpBar/ArtScale/Fill
@onready var boss_hp_label: Label = $BossHpBar/Label
@onready var boss_name_label: Label = $BossHpBar/NameLabel
# Segunda barra de boss (wave 21 boss duplo): duas barras menores na base.
@onready var boss_hp_bar2: Control = $BossHpBar2
@onready var boss_hp_fill2: ColorRect = $BossHpBar2/ArtScale/Fill
@onready var boss_hp_label2: Label = $BossHpBar2/Label
@onready var boss_name_label2: Label = $BossHpBar2/NameLabel
# Layout das barras duplas já aplicado? (aplica 1× ao entrar no modo duplo).
var _dual_bars_laid_out: bool = false
# Mapeamento de grupos de boss → nome a exibir. Mais bosses futuros: adicionar
# entrada nesse dict.
const BOSS_NAMES: Dictionary = {
	"mage_monkey": "MAGE MONKEY",
	"duskrose": "DUSKROSE",
}
var _current_boss: Node2D = null

# Coluna de upgrades adquiridos (right edge da HUD).
const UPGRADE_DISPLAY_ORDER: Array[String] = [
	# Status primeiro (sempre visíveis assim que comprados)
	"hp", "armor", "damage", "attack_speed", "move_speed",
	# Upgrades de gameplay
	"perfuracao", "ricochet_arrow", "multi_arrow", "double_arrows", "chain_lightning",
	"fire_arrow", "curse_arrow", "ice_arrow", "stone_arrow", "tide_arrow", "graviton", "boomerang", "critical_chance", "life_steal", "dash", "esquivando", "fenda",
	"gold_magnet",
	"tiger_claws",
	# Aliados
	"claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto",
]
# Caps onde "MAX" substitui "Lx" no badge (status escala infinito → sem cap).
const _UPG_CAPS: Dictionary = {
	"perfuracao": 4, "ricochet_arrow": 4, "multi_arrow": 4, "double_arrows": 4, "chain_lightning": 4,
	"fire_arrow": 4, "curse_arrow": 4, "ice_arrow": 4, "stone_arrow": 4, "tide_arrow": 4, "graviton": 4, "boomerang": 4, "critical_chance": 4, "life_steal": 4,
	"dash": 4, "esquivando": 4, "fenda": 4, "gold_magnet": 4, "tiger_claws": 4,
	"claudio_druida": 4, "leno": 4, "capivara_joe": 4, "ting": 4, "mini_mago": 4, "arbusto": 4,
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
	"stone_arrow": "res://assets/Hud/shop/upgrade/disparo do pedra/disparo de pedra card-Sheet.png",
	"tide_arrow": "res://assets/Hud/shop/upgrade/furia da maré/furia da maré.png",
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
	"fenda": "res://assets/Hud/shop/upgrade/deslizando.png",
	"leno": "res://assets/Hud/shop/aliado/Leno/Leno Card.png",
	"claudio_druida": "res://assets/Hud/shop/aliado/claudio_druida/claudio_druida card.png",
	"ting": "res://assets/Hud/shop/aliado/ting/ting card.png",
	"capivara_joe": "res://assets/Hud/shop/aliado/capivara joe/capivara joe card.png",
	"mini_mago": "res://assets/Hud/shop/aliado/mini mago/mini mago card.png",
	"arbusto": "res://assets/Hud/shop/aliado/abursto carrara/arbusto.png",
	"boomerang": "res://assets/Hud/shop/upgrade/boomerang/boomerang card design.png",
	"critical_chance": "res://assets/Hud/shop/upgrade/flechas criticas/felchas criticas card design.png",
	"tiger_claws": "res://assets/Hud/shop/upgrade/garras de tigre/garras de tigre hud-Sheet.png",
}
const _UPG_FALLBACK_UPGRADE: String = "res://assets/Hud/shop/upgrade/placeholder.png"
const _UPG_FALLBACK_ALIADO: String = "res://assets/Hud/shop/aliado/placeholder.png"
# Tamanho da célula da arte (atlas é 4 cells lado-a-lado por nível).
const _UPG_FRAME_NORMAL: Vector2i = Vector2i(38, 47)  # upgrade/aliado
const _UPG_FRAME_STATUS: Vector2i = Vector2i(65, 17)  # status/armor (faixa horizontal)
# IDs por categoria (pra resolver fallback e tamanho de célula).
const _UPG_STATUS_IDS: Array[String] = ["hp", "armor", "damage", "attack_speed", "move_speed"]
const _UPG_ALIADO_IDS: Array[String] = ["claudio_druida", "leno", "capivara_joe", "ting", "mini_mago", "arbusto"]
# Largura/altura de cada chip na coluna. Status são wide (65×17), upgrade/aliado
# são quase quadrados (38×47); chip único acomoda os dois com letterbox.
const _UPG_CHIP_SIZE: Vector2 = Vector2(72, 44)
# Quantidade de cells (níveis) por categoria de arte. Status (HP/armor/etc)
# tem 5 frames (1-5); upgrade/aliado tem 4 (1-4). Usado pra mapear o nível
# atual no cell certo do atlas.
const _UPG_MAX_CELLS_NORMAL: int = 4
const _UPG_MAX_CELLS_STATUS: int = 5
const _UPG_BADGE_COLOR: Color = Color(1.0, 0.93, 0.4, 1.0)
# Badge usa Silver.ttf (não ByteBounce) pra renderizar o caractere ★ (U+2605).
# Silver TEM o glifo e é bundled → funciona no WEB. SystemFont NÃO funciona no
# web (navegador não dá acesso a fontes do SO) → o ★ virava tofu "2605".
var _upg_badge_font: Font = null


func _get_upg_badge_font() -> Font:
	if _upg_badge_font != null:
		return _upg_badge_font
	# Silver.ttf tem o glifo ★ (U+2605) e é bundled — renderiza no web.
	_upg_badge_font = load("res://font/Silver.ttf")
	return _upg_badge_font

# Largura total do Fill (sem padding agora que tirei o Bg/border).
const BAR_FILL_WIDTH: float = 330.0
@onready var intro_overlay: Control = $IntroOverlay
@onready var intro_label: Label = $IntroOverlay/Label
@onready var cleared_overlay: Control = $ClearedOverlay
@onready var cleared_label: Label = $ClearedOverlay/Label
@onready var continue_button: Button = $ClearedOverlay/ContinueButton


var _hud_alpha_target: float = HUD_OPAQUE_ALPHA
var _hud_alpha_tween: Tween
var _boss_bar_bottom_anchored: bool = false

# Pause menu (ESC) — overlay procedural, process_mode ALWAYS pra continuar
# respondendo enquanto get_tree().paused é true.
var _pause_layer: CanvasLayer = null
var _pause_visible: bool = false
# Overlay de confirmação ao sair pro menu (perde a run; salva progresso como morte).
var _quit_confirm_layer: CanvasLayer = null

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
		"IceSkillIcon", "StoneSkillIcon", "EsquivandoSkillIcon", "PerfuranteCounterIcon", "GoldDisplay", "TowerAlertIndicator",
	]:
		var n := get_node_or_null(control_path)
		if n != null:
			_set_mouse_filter_recursive(n)
	# Marca a coluna de upgrades como mouse-pass-through (consistente com resto da HUD).
	_set_mouse_filter_recursive($UpgradeColumn)
	# Conecta nos signals de gold/hp/dash do player. Defer pra player já estar pronto.
	_connect_player_signals.call_deferred()
	# Toast de unlock de skin em tempo real (canto inferior direito).
	_skin_unlock_toast = SkinUnlockToast.new()
	add_child(_skin_unlock_toast)


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
	# Stone (Terremoto) skill icon — aparece quando player chega na Pedra lv4.
	if player.has_signal("stone_skill_unlocked") and not player.stone_skill_unlocked.is_connected(_on_stone_skill_unlocked):
		player.stone_skill_unlocked.connect(_on_stone_skill_unlocked)
	if player.has_signal("stone_skill_cooldown_changed") and not player.stone_skill_cooldown_changed.is_connected(_on_stone_skill_cooldown_changed):
		player.stone_skill_cooldown_changed.connect(_on_stone_skill_cooldown_changed)
		if player.has_signal("all_skills_reset") and not player.all_skills_reset.is_connected(_on_all_skills_reset):
			player.all_skills_reset.connect(_on_all_skills_reset)
	if "stone_arrow_level" in player and int(player.stone_arrow_level) >= 4:
		_on_stone_skill_unlocked()
	if player.has_signal("tide_shield_skill_unlocked") and not player.tide_shield_skill_unlocked.is_connected(_on_tide_shield_skill_unlocked):
		player.tide_shield_skill_unlocked.connect(_on_tide_shield_skill_unlocked)
	if player.has_signal("tide_shield_skill_cooldown_changed") and not player.tide_shield_skill_cooldown_changed.is_connected(_on_tide_shield_skill_cooldown_changed):
		player.tide_shield_skill_cooldown_changed.connect(_on_tide_shield_skill_cooldown_changed)
	if "tide_arrow_level" in player and int(player.tide_arrow_level) >= 3:
		_on_tide_shield_skill_unlocked()
	# Troca de elemental (carta "Roleta Elemental"): reavalia quais ícones de skill
	# elemental ficam visíveis (esconde o antigo, mostra o novo).
	if player.has_signal("elementals_changed") and not player.elementals_changed.is_connected(_refresh_elemental_skill_icons):
		player.elementals_changed.connect(_refresh_elemental_skill_icons)
	# Contador da flecha perfurante — visível a partir do lv1.
	if player.has_signal("perfuracao_counter_changed") and not player.perfuracao_counter_changed.is_connected(_on_perfuracao_counter_changed):
		player.perfuracao_counter_changed.connect(_on_perfuracao_counter_changed)
	if "perfuracao_level" in player and int(player.perfuracao_level) >= 1:
		var ctr: int = int(player.get("_perf_shot_counter")) if "_perf_shot_counter" in player else 0
		_on_perfuracao_counter_changed(ctr, int(player.perfuracao_level))
	# Contador da flecha ricochete — mesmo padrão do perfurante.
	if player.has_signal("ricochet_counter_changed") and not player.ricochet_counter_changed.is_connected(_on_ricochet_counter_changed):
		player.ricochet_counter_changed.connect(_on_ricochet_counter_changed)
	if "ricochet_arrow_level" in player and int(player.ricochet_arrow_level) >= 1:
		var rctr: int = int(player.get("_ricochet_shot_counter")) if "_ricochet_shot_counter" in player else 0
		_on_ricochet_counter_changed(rctr, int(player.ricochet_arrow_level))
	# Coluna de upgrades adquiridos: rebuild on signal.
	if player.has_signal("upgrade_applied") and not player.upgrade_applied.is_connected(_on_upgrade_applied):
		player.upgrade_applied.connect(_on_upgrade_applied)
	# Estado inicial — caso já tenha algum upgrade aplicado (free upgrade da wave 1
	# pode ter rolado antes do HUD conectar).
	_refresh_upgrade_column()
	# Tutorial inicial: WASD + Click. Hint aparece com pequeno delay (~1.2s) pra
	# não competir com o intro overlay da wave 1.
	_show_basics_hint_if_needed()


func _on_upgrade_applied(_id: String, _level: int) -> void:
	_refresh_upgrade_column()


func _update_boss_hp_bar() -> void:
	# Conta bosses vivos. 2+ → modo barra dupla (wave 21). Uma vez no modo duplo,
	# permanece nele enquanto houver ≥1 boss (a barra do sobrevivente fica onde
	# está; a do morto some). Só sai quando não há mais boss.
	var bosses: Array = []
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b) and b is Node2D:
			bosses.append(b)
	if bosses.size() >= 2 or (_dual_bars_laid_out and bosses.size() >= 1):
		_update_dual_boss_bars(bosses)
		return
	# Sem bosses (ou nunca entrou no duplo): limpa o estado duplo e cai no single.
	if _dual_bars_laid_out:
		_dual_bars_laid_out = false
		_current_boss = null
		boss_hp_bar.scale = Vector2.ONE
		boss_hp_bar2.scale = Vector2.ONE
	if boss_hp_bar2.visible:
		boss_hp_bar2.visible = false
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
		# Posicionamento: Duskrose fica no TOPO do mapa, então a barra dela
		# vai pro RODAPÉ pra não sobrepor visualmente. Outros bosses (Mage
		# Monkey no centro) usam a posição padrão no topo da tela.
		_position_boss_hp_bar_for(_current_boss as Node)
		# Sync alpha com o estado atual do fade — se o player já está atrás
		# da HUD quando a barra aparece, ela já entra translúcida (em vez de
		# entrar opaca e só atualizar quando o player se mexer).
		var player_overlapping: bool = _hud_alpha_target == HUD_TRANSPARENT_ALPHA
		boss_hp_bar.modulate.a = _boss_bar_alpha_for(player_overlapping)
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


# Anchor presets pra barra de HP do boss. Default = topo da tela (offset
# positivo do topo). Duskrose anchora no rodapé (offset negativo do bottom).
# Largura sempre centralizada (anchor_left/right = 0.5).
const _BOSS_BAR_TOP_OFFSET_TOP: float = 80.0
const _BOSS_BAR_TOP_OFFSET_BOTTOM: float = 152.0
const _BOSS_BAR_BOTTOM_OFFSET_TOP: float = -152.0  # 152px acima da base
const _BOSS_BAR_BOTTOM_OFFSET_BOTTOM: float = -80.0  # 80px acima da base


func _position_boss_hp_bar_for(boss: Node) -> void:
	# Duskrose: anchora no RODAPÉ (boss tá no topo do mapa, não pode sobrepor).
	# Resto: anchora no TOPO (default — boss tá no centro/bottom do mapa).
	if boss == null:
		return
	var bottom_anchor: bool = boss.is_in_group("duskrose")
	_boss_bar_bottom_anchored = bottom_anchor
	if bottom_anchor:
		boss_hp_bar.anchor_top = 1.0
		boss_hp_bar.anchor_bottom = 1.0
		boss_hp_bar.offset_top = _BOSS_BAR_BOTTOM_OFFSET_TOP
		boss_hp_bar.offset_bottom = _BOSS_BAR_BOTTOM_OFFSET_BOTTOM
	else:
		boss_hp_bar.anchor_top = 0.0
		boss_hp_bar.anchor_bottom = 0.0
		boss_hp_bar.offset_top = _BOSS_BAR_TOP_OFFSET_TOP
		boss_hp_bar.offset_bottom = _BOSS_BAR_TOP_OFFSET_BOTTOM


func _boss_bar_alpha_for(player_overlapping: bool) -> float:
	# Duskrose: barra fica no rodapé sobreposta à área jogável — nunca 100% opaca,
	# e quando player passa por baixo cai mais agressivamente que o resto da HUD.
	if _boss_bar_bottom_anchored:
		return BOSS_BAR_BOTTOM_TRANSPARENT_ALPHA if player_overlapping else BOSS_BAR_BOTTOM_OPAQUE_ALPHA
	return HUD_TRANSPARENT_ALPHA if player_overlapping else HUD_OPAQUE_ALPHA


# Wave 21: duas barras menores lado a lado na BASE. Gorilla à esquerda, Duskrose
# à direita (por grupo). Boss morto → barra dele some, a do outro permanece.
func _update_dual_boss_bars(bosses: Array) -> void:
	if not _dual_bars_laid_out:
		_apply_dual_bar_layout()
		_dual_bars_laid_out = true
	var gorilla: Node2D = null
	var dusk: Node2D = null
	for b in bosses:
		if (b as Node).is_in_group("mage_monkey"):
			gorilla = b
		elif (b as Node).is_in_group("duskrose"):
			dusk = b
	_fill_boss_bar(boss_hp_bar, boss_hp_fill, boss_hp_label, boss_name_label, gorilla, "MAGE MONKEY")
	_fill_boss_bar(boss_hp_bar2, boss_hp_fill2, boss_hp_label2, boss_name_label2, dusk, "DUSKROSE")


# Posiciona as duas barras menores lado a lado na base (1× ao entrar no modo
# duplo). Larguras/escala/offsets tunáveis.
func _apply_dual_bar_layout() -> void:
	# Duas barras MAIORES, centralizadas como par (ancoradas no centro horizontal),
	# simétricas em volta do meio da tela, na base. Tunáveis: BAR_SCALE / GAP.
	var BAR_SCALE: float = 0.85   # tamanho das barras (era 0.62)
	var BAR_W: float = 720.0      # largura base do BossHpBar (pré-scale)
	var GAP: float = 50.0         # espaço entre as duas barras
	var scaled_w: float = BAR_W * BAR_SCALE
	for bar in [boss_hp_bar, boss_hp_bar2]:
		bar.scale = Vector2(BAR_SCALE, BAR_SCALE)
		bar.anchor_left = 0.5
		bar.anchor_right = 0.5
		bar.anchor_top = 1.0
		bar.anchor_bottom = 1.0
		bar.offset_top = _BOSS_BAR_BOTTOM_OFFSET_TOP
		bar.offset_bottom = _BOSS_BAR_BOTTOM_OFFSET_BOTTOM
		bar.modulate.a = 1.0
		bar.visible = true
	_boss_bar_bottom_anchored = true
	# Barra esquerda (Gorilla): termina GAP/2 à esquerda do centro.
	boss_hp_bar.offset_left = -GAP * 0.5 - scaled_w
	boss_hp_bar.offset_right = boss_hp_bar.offset_left + BAR_W
	# Barra direita (Duskrose): começa GAP/2 à direita do centro.
	boss_hp_bar2.offset_left = GAP * 0.5
	boss_hp_bar2.offset_right = boss_hp_bar2.offset_left + BAR_W


# Preenche uma barra de boss (fill ratio + nome + label). null → esconde a barra.
func _fill_boss_bar(bar: Control, fill: ColorRect, label: Label, name_label: Label, boss: Node2D, name_text: String) -> void:
	if boss == null or not is_instance_valid(boss):
		bar.visible = false
		return
	bar.visible = true
	name_label.text = name_text
	if not ("hp" in boss) or not ("max_hp" in boss):
		return
	var hp: float = float(boss.hp)
	var maxhp: float = float(boss.max_hp)
	var ratio: float = 0.0 if maxhp <= 0.0 else clampf(hp / maxhp, 0.0, 1.0)
	var mat: ShaderMaterial = fill.material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("fill_ratio", ratio)
	label.text = "%d/%d" % [int(round(hp)), int(round(maxhp))]


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
	badge.add_theme_font_size_override("font_size", 16)
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


func _show_control_hint(icon_texture: Texture2D, label_key: String) -> void:
	# Instancia um ControlHint no VBoxContainer central. Fade in/hold/fade out
	# é auto-gerenciado pelo próprio nó. Cada hint queue_free após o ciclo.
	if control_hints_container == null:
		return
	var hint := _CONTROL_HINT_SCENE.instantiate()
	control_hints_container.add_child(hint)
	if hint.has_method("setup"):
		hint.setup(icon_texture, label_key)


func _show_basics_hint_if_needed() -> void:
	# WASD + Click — tutorial inicial. Mostra UMA vez por run, com pequeno
	# delay pra não sobrepor o intro overlay da wave 1.
	if _control_hints_shown.get("basics", false):
		return
	_control_hints_shown["basics"] = true
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if not is_inside_tree():
			return
		_show_control_hint(_CONTROL_TEX_WASD, "HUD_HINT_MOVE")
		_show_control_hint(_CONTROL_TEX_CLICK, "HUD_HINT_ATTACK")
	)


func _show_space_hint_if_needed() -> void:
	if _control_hints_shown.get("space", false):
		return
	_control_hints_shown["space"] = true
	_show_control_hint(_CONTROL_TEX_SPACE, "HUD_HINT_SKILL_SPACE")


func _show_q_hint_if_needed() -> void:
	if _control_hints_shown.get("q", false):
		return
	_control_hints_shown["q"] = true
	_show_control_hint(_CONTROL_TEX_Q, "HUD_HINT_SKILL_Q")


func _on_dash_unlocked() -> void:
	dash_cd_bar.visible = true
	_show_space_hint_if_needed()


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
		_show_space_hint_if_needed()


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
	elif "stone_arrow_level" in player and int(player.stone_arrow_level) >= 4:
		has_any_elemental = true
	elif "tide_arrow_level" in player and int(player.tide_arrow_level) >= 3:
		has_any_elemental = true
	var new_x: float = ESQUIVANDO_ICON_ELEM_X if has_any_elemental else ESQUIVANDO_ICON_NO_ELEM_X
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
	_show_q_hint_if_needed()


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
	_show_q_hint_if_needed()


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
	# L1-L2: cada 3 ataques (threshold 2). L3: cada 2 ataques (threshold 1).
	var pierce_threshold: int = 1 if level == 3 else 2
	var is_pierce_imminent: bool = level >= 4 or counter >= pierce_threshold
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


# Ricochete: cadência depende do level.
# - L1: cada 3 ataques (counter 0→1→2 → próximo procca). Label mostra 1/2/3.
# - L2-L3: cada 2 ataques (counter 0→1 → próximo procca). Label mostra 1/2.
# - L4: idem L2 (cada 2 ataques) — sem star pq mecânica de hops/splits
#   é o diferencial do nível, não a frequência.
func _on_ricochet_counter_changed(counter: int, level: int) -> void:
	if level <= 0:
		ricochete_counter_icon.visible = false
		return
	ricochete_counter_icon.visible = true
	var threshold: int = 2 if level == 1 else 1
	var is_imminent: bool = counter >= threshold
	ricochete_count_label.text = "%d" % (counter + 1)
	if is_imminent:
		ricochete_counter_icon.modulate = Color.WHITE
		ricochete_count_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45, 1.0))
	else:
		ricochete_counter_icon.modulate = Color(0.55, 0.62, 0.7, 1.0)
		ricochete_count_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _on_curse_skill_unlocked() -> void:
	curse_skill_icon.visible = true
	_update_esquivando_icon_position()
	_show_q_hint_if_needed()


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
	_show_q_hint_if_needed()


func _on_time_freeze_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Mesmo pattern dos outros: full color quando pronto, dimmed em cd.
	if remaining <= 0.001:
		ice_skill_cd_label.text = ""
		ice_skill_icon.modulate = Color.WHITE
	else:
		ice_skill_cd_label.text = "%d" % int(ceilf(remaining))
		ice_skill_icon.modulate = Color(0.55, 0.65, 0.78, 1.0)


func _on_stone_skill_unlocked() -> void:
	stone_skill_icon.visible = true
	_update_esquivando_icon_position()
	_show_q_hint_if_needed()


# Reavalia a visibilidade dos ícones de skill elemental conforme o nível atual.
# Chamado quando o elemental muda (carta "Roleta Elemental"): esconde o ícone do
# elemental antigo e mostra o do novo. Os cooldowns/labels do novo já são emitidos
# pelo apply_upgrade da troca.
func _refresh_elemental_skill_icons() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	fire_skill_icon.visible = ("fire_arrow_level" in p) and int(p.fire_arrow_level) >= 3
	chain_lightning_skill_icon.visible = ("chain_lightning_level" in p) and int(p.chain_lightning_level) >= 3
	curse_skill_icon.visible = ("curse_arrow_level" in p) and int(p.curse_arrow_level) >= 4
	ice_skill_icon.visible = ("ice_arrow_level" in p) and int(p.ice_arrow_level) >= 4
	stone_skill_icon.visible = ("stone_arrow_level" in p) and int(p.stone_arrow_level) >= 4
	tide_shield_icon.visible = ("tide_arrow_level" in p) and int(p.tide_arrow_level) >= 3
	_update_esquivando_icon_position()
	_show_q_hint_if_needed()


func _on_stone_skill_cooldown_changed(remaining: float, _total: float) -> void:
	if remaining <= 0.001:
		stone_skill_cd_label.text = ""
		stone_skill_icon.modulate = Color.WHITE
	else:
		stone_skill_cd_label.text = "%d" % int(ceilf(remaining))
		stone_skill_icon.modulate = Color(0.6, 0.55, 0.45, 1.0)


func _on_tide_shield_skill_unlocked() -> void:
	tide_shield_icon.visible = true
	_update_esquivando_icon_position()
	_show_q_hint_if_needed()


func _on_tide_shield_skill_cooldown_changed(remaining: float, _total: float) -> void:
	if remaining <= 0.001:
		tide_shield_cd_label.text = ""
		tide_shield_icon.modulate = Color.WHITE
	else:
		tide_shield_cd_label.text = "%d" % int(ceilf(remaining))
		tide_shield_icon.modulate = Color(0.5, 0.62, 0.78, 1.0)


func _on_all_skills_reset() -> void:
	# Relógio de Reset coletado: flash de brilho nas barras/ícones de cooldown
	# visíveis, sinalizando que todas as skills voltaram a ficar prontas. As barras
	# em si já são atualizadas pelos *_cooldown_changed; isto é só o realce visual.
	for node in [dash_cd_bar, esquivando_skill_icon, fire_skill_icon,
			chain_lightning_skill_icon, curse_skill_icon, ice_skill_icon, stone_skill_icon, tide_shield_icon]:
		_flash_skill_ui(node)


func _flash_skill_ui(node: Control) -> void:
	if node == null or not node.visible:
		return
	var base: Color = node.modulate
	node.modulate = base * 1.8
	var t := create_tween()
	t.tween_property(node, "modulate", base, 0.4).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	_update_tower_alert(delta)
	_update_boss_hp_bar()
	_poll_skin_unlocks(delta)
	# Se o player passar atrás da HUD (canto do mapa), translúcido pra ver através.
	if not hud_frame.visible:
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null or not is_instance_valid(player):
		return
	# Posição do player na tela calculada manualmente via câmera. Não usar
	# get_global_transform_with_canvas() — em alguns setups (stretch viewport +
	# CanvasLayer da HUD) ela retorna coords inconsistentes com get_global_rect()
	# dos Controls da HUD. Com cálculo manual garantimos que ambos estão no mesmo
	# espaço de pixels do viewport (1920×1080 com stretch viewport).
	var camera := player.get_viewport().get_camera_2d()
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var camera_world_pos: Vector2 = camera.get_screen_center_position() if camera != null else Vector2.ZERO
	var player_screen: Vector2 = (player.global_position - camera_world_pos) * zoom + viewport_size * 0.5
	var player_size := Vector2(32, 32) * zoom
	var player_rect := Rect2(player_screen + Vector2(-16, -32) * zoom, player_size)
	# Considera intersecção com HudFrame, HpBar OU BossHpBar — player atrás de
	# qualquer um ativa o fade translúcido. BossHpBar é especialmente importante
	# na wave 14 (Duskrose) onde a barra desce pro rodapé e cobre área jogável.
	var overlaps: bool = hud_frame.get_global_rect().intersects(player_rect)
	if not overlaps and hp_bar != null:
		overlaps = hp_bar.get_global_rect().intersects(player_rect)
	if not overlaps and boss_hp_bar != null and boss_hp_bar.visible:
		overlaps = boss_hp_bar.get_global_rect().intersects(player_rect)
	var new_target: float = HUD_TRANSPARENT_ALPHA if overlaps else HUD_OPAQUE_ALPHA
	if not is_equal_approx(new_target, _hud_alpha_target):
		_hud_alpha_target = new_target
		if _hud_alpha_tween != null and _hud_alpha_tween.is_valid():
			_hud_alpha_tween.kill()
		_hud_alpha_tween = create_tween().set_parallel(true)
		_hud_alpha_tween.tween_property(hud_frame, "modulate:a", new_target, HUD_ALPHA_FADE)
		# Aplica o mesmo fade nas barras de HP — player vê através delas quando passar
		# por cima (canto do mapa, cinematic, ou rodapé na wave 14).
		if hp_bar != null:
			_hud_alpha_tween.tween_property(hp_bar, "modulate:a", new_target, HUD_ALPHA_FADE)
		if boss_hp_bar != null:
			var boss_target: float = _boss_bar_alpha_for(overlaps)
			_hud_alpha_tween.tween_property(boss_hp_bar, "modulate:a", boss_target, HUD_ALPHA_FADE)


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
	# Wave 14 (Duskrose): skipa o surgimento do gorila mage. Vai direto pro
	# fade do overlay revelando a boss (que já tá no topo do mapa). Animação
	# própria da Duskrose será adicionada quando estiver pronta.
	# Wave 21 (boss duplo) usa o mesmo path: fade do overlay revelando a cena,
	# sem o sprite "surgimento" do Gorilla (a câmera coreografa os 2 bosses).
	if wave_number == 14 or wave_number == 21:
		var t_fade := create_tween()
		t_fade.tween_property(intro_overlay, "modulate:a", 0.0, 0.6)
		await t_fade.finished
		intro_overlay.visible = false
		intro_label.modulate.a = 1.0
		return
	# Fase 3: cinematic sprite — toca sobre o overlay preto (só wave 7).
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


const KILLCAM_HOLD_DURATION: float = 2.0
const KILLCAM_FADE_IN: float = 0.3
const KILLCAM_FADE_OUT: float = 0.25
const KILLCAM_BG_ALPHA: float = 0.85


# Killcam (replay estático): mostra o frame congelado do momento da morte
# (screenshot capturado no player._die) com "MORTO POR X" sobreposto. Player
# pode reassistir clicando no botão "Ver replay da morte" — fica acessível
# enquanto o death screen tá ativo.
func _play_killcam(source_id: String) -> void:
	var killed_by_str: String = _format_killed_by(source_id)
	# Pega o screenshot do player (capturado no _die).
	var p := get_tree().get_first_node_in_group("player")
	var snapshot: Texture2D = null
	if p != null and "death_screenshot" in p:
		snapshot = p.get("death_screenshot")
	# Overlay no death_top_layer (CanvasLayer já em cima do mundo).
	var overlay := Control.new()
	overlay.name = "KillcamOverlay"
	overlay.anchor_right = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	death_top_layer.add_child(overlay)
	# Fundo: o próprio screenshot do momento da morte (full screen). Se não
	# capturou, cai num fundo vermelho-escuro como fallback.
	if snapshot != null:
		var img_rect := TextureRect.new()
		img_rect.texture = snapshot
		img_rect.anchor_right = 1.0
		img_rect.anchor_bottom = 1.0
		img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		# Escurece um pouco pro texto se destacar.
		img_rect.modulate = Color(0.7, 0.7, 0.7, 1.0)
		overlay.add_child(img_rect)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.08, 0.02, 0.02, KILLCAM_BG_ALPHA)
		bg.anchor_right = 1.0
		bg.anchor_bottom = 1.0
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		overlay.add_child(bg)
	# Texto "MORTO POR X" centralizado em vermelho com outline preto.
	if not killed_by_str.is_empty():
		var label := Label.new()
		label.text = killed_by_str
		label.anchor_left = 0.0
		label.anchor_right = 1.0
		label.anchor_top = 0.42
		label.anchor_bottom = 0.58
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 69)
		label.add_theme_color_override("font_color", Color(1, 0.3, 0.3, 1))
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 10)
		if survival_label != null:
			var existing_font := survival_label.get_theme_font("font", "")
			if existing_font != null:
				label.add_theme_font_override("font", existing_font)
		overlay.add_child(label)
	var tw_in := create_tween()
	tw_in.tween_property(overlay, "modulate:a", 1.0, KILLCAM_FADE_IN)
	await tw_in.finished
	await get_tree().create_timer(KILLCAM_HOLD_DURATION).timeout
	var tw_out := create_tween()
	tw_out.tween_property(overlay, "modulate:a", 0.0, KILLCAM_FADE_OUT)
	await tw_out.finished
	overlay.queue_free()


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
	# Botão "Ver replay da morte" no lado DIREITO da tela (simétrico ao breakdown
	# que fica à esquerda). On-click → mostra a killcam estática. Pode ser
	# clicado várias vezes pra reassistir.
	var replay_btn: Button = _build_or_get_replay_button()
	replay_btn.modulate.a = 0.0
	replay_btn.visible = true

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
	reveal.tween_property(replay_btn, "modulate:a", 1.0, 0.4)


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
	"dark_ball": "HUD_DEATH_BY_DARK_BALL",
	"dark_ball_burn": "HUD_DEATH_BY_DARK_BALL_BURN",
	"dark_ball_venom": "HUD_DEATH_BY_DARK_BALL_VENOM",
	"duskrose": "HUD_DEATH_BY_DUSKROSE",
	"duskrose_smoke": "HUD_DEATH_BY_DUSKROSE_SMOKE",
	"duskrose_vine": "HUD_DEATH_BY_DUSKROSE_VINE",
	"duskrose_permanent_thorn": "HUD_DEATH_BY_DUSKROSE_THORN_WALL",
	"duskrose_toxic": "HUD_DEATH_BY_DUSKROSE_TOXIC",
	"duskrose_projectile": "HUD_DEATH_BY_DUSKROSE_PROJECTILE",
	"duskrose_dash": "HUD_DEATH_BY_DUSKROSE_DASH",
	"rose_monster": "HUD_DEATH_BY_ROSE_MONSTER",
}


func _format_killed_by(source_id: String) -> String:
	if source_id.is_empty():
		return tr("HUD_DEATH_BY_UNKNOWN")
	var key: String = String(_DEATH_SOURCE_LABELS.get(source_id, "HUD_DEATH_BY_UNKNOWN"))
	return tr(key)


func _build_or_get_replay_button() -> Button:
	# Botão "Ver replay da morte" logo acima do "Jogar Novamente" (RestartButton
	# fica em offset_top=160, esse vai pra offset_top=96).
	var existing: Button = death_top_layer.get_node_or_null("ReplayDeathButton") as Button
	if existing != null:
		return existing
	var btn := Button.new()
	btn.name = "ReplayDeathButton"
	btn.set_anchors_preset(Control.PRESET_CENTER)
	# Mesma largura do RestartButton (offset -200 a 200), 8px acima dele.
	btn.offset_left = -200.0
	btn.offset_right = 200.0
	btn.offset_top = 96.0
	btn.offset_bottom = 152.0
	btn.text = tr("HUD_REPLAY_DEATH_BUTTON")
	btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 1.0))
	btn.add_theme_color_override("font_outline_color", Color.BLACK)
	btn.add_theme_constant_override("outline_size", 4)
	var font: Font = load("res://font/Silver.ttf") as Font
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", 35)
	btn.pressed.connect(_on_replay_death_pressed)
	death_top_layer.add_child(btn)
	return btn


const _DEATH_REPLAY_SCENE: PackedScene = preload("res://scenes/ui/death_replay.tscn")


func _on_replay_death_pressed() -> void:
	# Reproduz os últimos ~3.5s antes da morte. Pega os snapshots e o
	# stats_killed_by do player (que sobrevivem até a próxima run).
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	var snaps: Array = []
	if "stats_replay_snapshots" in p:
		snaps = p.get("stats_replay_snapshots")
	if snaps.is_empty():
		return
	var src_id: String = ""
	if "stats_killed_by" in p:
		src_id = String(p.get("stats_killed_by"))
	var replay: CanvasLayer = _DEATH_REPLAY_SCENE.instantiate()
	replay.snapshots = snaps
	replay.killed_by_str = _format_killed_by(src_id)
	if "death_screenshot" in p:
		replay.background_texture = p.get("death_screenshot")
	# Adiciona em current_scene pra ficar acima do HUD (CanvasLayer com layer
	# alto). Auto-libera ao terminar via signal.
	get_tree().current_scene.add_child(replay)


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
	var font: Font = load("res://font/Silver.ttf") as Font
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 28)
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
	var at01: Font = load("res://font/Silver.ttf")

	var tel_btn := Button.new()
	tel_btn.name = "DevSendTelemetryBtn"
	tel_btn.text = "[DEV] Enviar Telemetria"
	tel_btn.set_anchors_preset(Control.PRESET_CENTER)
	tel_btn.position = Vector2(-200, 312)
	tel_btn.size = Vector2(400, 48)
	if at01 != null:
		tel_btn.add_theme_font_override("font", at01)
	tel_btn.add_theme_font_size_override("font_size", 28)
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
	score_btn.add_theme_font_size_override("font_size", 28)
	score_btn.add_theme_color_override("font_color", Color(1, 0.85, 0.55, 1))
	score_btn.pressed.connect(func(): _dev_send_score(score_btn))
	death_top_layer.add_child(score_btn)

	var respawn_btn := Button.new()
	respawn_btn.name = "DevRespawnSameUpgradesBtn"
	respawn_btn.text = "[DEV] Renascer (mesmos upgrades)"
	respawn_btn.set_anchors_preset(Control.PRESET_CENTER)
	respawn_btn.position = Vector2(-200, 428)
	respawn_btn.size = Vector2(400, 48)
	if at01 != null:
		respawn_btn.add_theme_font_override("font", at01)
	respawn_btn.add_theme_font_size_override("font_size", 28)
	respawn_btn.add_theme_color_override("font_color", Color(1, 0.7, 0.95, 1))
	respawn_btn.pressed.connect(_dev_respawn_same_upgrades)
	death_top_layer.add_child(respawn_btn)


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


# Lista de TODOS os upgrade ids trackados pelo player. Espelha o que tem em
# dev_panel._ALL_UPGRADE_IDS — duplicado pra evitar dependência da scene em
# ordem de _ready (HUD pode rodar antes do dev_panel existir).
const _DEV_RESPAWN_UPGRADE_IDS: Array[String] = [
	"hp", "armor", "damage", "perfuracao", "attack_speed", "multi_arrow",
	"double_arrows", "chain_lightning", "move_speed", "life_steal",
	"fire_arrow", "curse_arrow", "ice_arrow", "claudio_druida", "leno",
	"capivara_joe", "ting", "arbusto", "mini_mago", "gold_magnet",
	"dash", "esquivando", "ricochet_arrow", "graviton", "boomerang",
	"tiger_claws", "critical_chance",
]


func _dev_respawn_same_upgrades() -> void:
	# Snapshot dos upgrades atuais do player (vivo OU recém-morto) → guarda em
	# GameState.pending_respawn_upgrades → reload da cena. Dev_panel da nova run
	# detecta o snapshot e re-aplica via _apply_pending_respawn_upgrades.
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_upgrade_count"):
		return
	var snapshot: Dictionary = {}
	for upgrade_id in _DEV_RESPAWN_UPGRADE_IDS:
		var lvl: int = player.get_upgrade_count(upgrade_id)
		if lvl > 0:
			snapshot[upgrade_id] = lvl
	var gs := get_node_or_null("/root/GameState")
	if gs != null and "pending_respawn_upgrades" in gs:
		gs.pending_respawn_upgrades = snapshot
	get_tree().reload_current_scene()


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


# Poll leve (a cada _SKIN_UNLOCK_POLL_INTERVAL) que detecta unlocks de skin em
# tempo real e mostra o toast no canto. NÃO grava nada — o commit dos stats segue
# no fim da run (record_run). Só notifica skins que estavam LOCKED no início desta
# run e ainda não foram avisadas.
func _poll_skin_unlocks(delta: float) -> void:
	_skin_unlock_poll_accum += delta
	if _skin_unlock_poll_accum < _SKIN_UNLOCK_POLL_INTERVAL:
		return
	_skin_unlock_poll_accum = 0.0
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not is_instance_valid(p):
		return
	# Durante a sequência de morte o death screen já cuida do unlock — não toasta.
	if "is_dead" in p and bool(p.is_dead):
		return
	# Snapshot 1x: skins locked no início da run = não satisfeitas só com os stats
	# PERSISTENTES (evaluate com dict vazio → contribuição da run = 0).
	if not _skin_unlock_snapshot_done:
		_skin_unlock_snapshot_done = true
		var base_satisfied: Array = SkinLoadout.evaluate_live_unlocks({})
		for skin_name in SkinLoadout.SKIN_QUESTS:
			if not (String(skin_name) in base_satisfied):
				_skin_unlock_locked_at_start[String(skin_name)] = true
	var wave_num: int = 0
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		wave_num = int(wm.wave_number)
	var rs: Dictionary = _collect_run_stats(wave_num)
	for skin_name in SkinLoadout.evaluate_live_unlocks(rs):
		var sn: String = String(skin_name)
		if _skin_unlock_locked_at_start.has(sn) and not _skin_unlock_toasted.has(sn):
			_skin_unlock_toasted[sn] = true
			if _skin_unlock_toast != null:
				_skin_unlock_toast.enqueue(sn)


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
	var elemental_l4: bool = false
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
		# Chegou ao Lv4 de QUALQUER elemental nesta run? (unlock da skin Skeleton)
		for lvl_prop in ["fire_arrow_level", "curse_arrow_level", "ice_arrow_level", "stone_arrow_level"]:
			if lvl_prop in p and int(p.get(lvl_prop)) >= 4:
				elemental_l4 = true
				break
	return {
		"wave": wave_num,
		"kills": kills,
		"allies": allies,
		"monkeys_cursed": monkeys_cursed,
		"stun_seconds": int(round(float(p.get("stats_stun_seconds")))) if p != null and "stats_stun_seconds" in p else 0,
		"active_skills_used": int(p.get("stats_active_skills_used")) if p != null and "stats_active_skills_used" in p else 0,
		"tide_vulnerable_kills": int(p.get("stats_tide_vulnerable_kills")) if p != null and "stats_tide_vulnerable_kills" in p else 0,
		"dmg_dealt": dmg_dealt,
		"dmg_taken": dmg_taken,
		"dmg_taken_by_source": dmg_by_src,
		"dmg_dealt_by_source": dmg_dealt_by_src,
		"kills_by_source": kills_by_src,
		"killed_by": killed_by,
		"bosses_killed": bosses,
		"elemental_l4_reached": elemental_l4,
		"flawless_through_w3": bool(p.get("stats_flawless_through_w3")) if p != null and "stats_flawless_through_w3" in p else false,
		# Armor sobe e nunca cai numa run, então o nível no death == máximo atingido.
		"armor_lv5_reached": (p != null and "armor_level" in p and int(p.get("armor_level")) >= 5),
		# Matou um mago a >= 480px com a flecha nesta run (unlock Patriota).
		"long_mage_kill": bool(p.get("stats_long_mage_kill")) if p != null and "stats_long_mage_kill" in p else false,
		# Passou de um round sem disparo manual de flecha nesta run (unlock Sputnik).
		"no_arrow_round": bool(p.get("stats_no_arrow_round")) if p != null and "stats_no_arrow_round" in p else false,
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
# Cobre APPLICATION_FOCUS_OUT (app inteira) e WM_WINDOW_FOCUS_OUT (janela só).
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT and what != NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		return
	if _pause_visible or get_tree().paused:
		return
	if cleared_overlay != null and cleared_overlay.visible:
		return
	if intro_overlay != null and intro_overlay.visible:
		return
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "is_dead" in player and bool(player.is_dead):
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
	var at01: Font = load("res://font/Silver.ttf")
	var title := Label.new()
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.position = Vector2(-600, -260)
	title.size = Vector2(1200, 140)
	title.text = "HUD_PAUSE_TITLE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if at01 != null:
		title.add_theme_font_override("font", at01)
	title.add_theme_font_size_override("font_size", 101)
	title.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(title)
	var continue_btn := Button.new()
	continue_btn.set_anchors_preset(Control.PRESET_CENTER)
	continue_btn.position = Vector2(-220, -80)
	continue_btn.size = Vector2(440, 72)
	continue_btn.text = "HUD_PAUSE_CONTINUE"
	if at01 != null:
		continue_btn.add_theme_font_override("font", at01)
	continue_btn.add_theme_font_size_override("font_size", 52)
	continue_btn.pressed.connect(_close_pause)
	bg.add_child(continue_btn)
	var settings_btn := Button.new()
	settings_btn.set_anchors_preset(Control.PRESET_CENTER)
	settings_btn.position = Vector2(-220, 10)
	settings_btn.size = Vector2(440, 64)
	settings_btn.text = "HUD_PAUSE_SETTINGS"
	if at01 != null:
		settings_btn.add_theme_font_override("font", at01)
	settings_btn.add_theme_font_size_override("font_size", 39)
	settings_btn.pressed.connect(_open_settings_overlay)
	bg.add_child(settings_btn)
	var menu_btn := Button.new()
	menu_btn.set_anchors_preset(Control.PRESET_CENTER)
	menu_btn.position = Vector2(-220, 100)
	menu_btn.size = Vector2(440, 64)
	menu_btn.text = "HUD_PAUSE_MENU"
	if at01 != null:
		menu_btn.add_theme_font_override("font", at01)
	menu_btn.add_theme_font_size_override("font_size", 39)
	menu_btn.pressed.connect(_request_quit_to_menu)
	bg.add_child(menu_btn)
	add_child(_pause_layer)


# Sair pro menu a partir do pause (player vivo): confirma antes, pois a run é
# abandonada. Ao confirmar, salva o progresso (skins + leaderboard) como se o
# player tivesse morrido agora.
func _request_quit_to_menu() -> void:
	if _quit_confirm_layer == null:
		_build_quit_confirm_layer()
	_quit_confirm_layer.visible = true


func _build_quit_confirm_layer() -> void:
	_quit_confirm_layer = CanvasLayer.new()
	_quit_confirm_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	_quit_confirm_layer.layer = 61  # acima do pause (60)
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_confirm_layer.add_child(bg)
	var at01: Font = load("res://font/Silver.ttf")
	var msg := Label.new()
	msg.set_anchors_preset(Control.PRESET_CENTER)
	msg.position = Vector2(-640, -200)
	msg.size = Vector2(1280, 220)
	msg.text = "HUD_QUIT_CONFIRM_MSG"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if at01 != null:
		msg.add_theme_font_override("font", at01)
	msg.add_theme_font_size_override("font_size", 58)
	msg.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(msg)
	var yes_btn := Button.new()
	yes_btn.set_anchors_preset(Control.PRESET_CENTER)
	yes_btn.position = Vector2(-240, 70)
	yes_btn.size = Vector2(220, 76)
	yes_btn.text = "HUD_QUIT_CONFIRM_YES"
	if at01 != null:
		yes_btn.add_theme_font_override("font", at01)
	yes_btn.add_theme_font_size_override("font_size", 48)
	yes_btn.pressed.connect(_quit_to_menu_with_save)
	bg.add_child(yes_btn)
	var no_btn := Button.new()
	no_btn.set_anchors_preset(Control.PRESET_CENTER)
	no_btn.position = Vector2(20, 70)
	no_btn.size = Vector2(220, 76)
	no_btn.text = "HUD_QUIT_CONFIRM_NO"
	if at01 != null:
		no_btn.add_theme_font_override("font", at01)
	no_btn.add_theme_font_size_override("font_size", 48)
	no_btn.pressed.connect(func() -> void: _quit_confirm_layer.visible = false)
	bg.add_child(no_btn)
	add_child(_quit_confirm_layer)


func _quit_to_menu_with_save() -> void:
	# Confirmado: salva o progresso da run (igual ao death) e volta pro menu.
	get_tree().paused = false
	_save_run_progress_like_death()
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


func _save_run_progress_like_death() -> void:
	# Mesmo save do death screen: persiste stats de skin (unlocks aplicam) e, em
	# release, envia score pro leaderboard + telemetria run_end. Em debug só as
	# skins (igual ao death, que mostra botões manuais em vez de auto-enviar).
	var wave_num: int = 0
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		wave_num = int(wm.wave_number)
	SkinLoadout.record_run(_collect_run_stats(wave_num))
	if not OS.is_debug_build():
		_auto_submit_score()
		_track_run_end(wave_num)
		if has_node("/root/Telemetry"):
			get_node("/root/Telemetry").flush_now()


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


# ---------- Indicadores dos últimos inimigos vivos ----------

func update_last_enemies_indicator(enemies: Array) -> void:
	# Chamado pelo wave_manager a cada frame quando restam <= 2 inimigos e todos
	# já spawnaram. Pra cada inimigo off-screen, posiciona uma seta na borda
	# da tela apontando pra ele. Lista vazia = esconde tudo.
	if _last_enemy_indicators.is_empty() and not enemies.is_empty():
		_build_last_enemy_indicator_pool()
	var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
	var view_size: Vector2 = get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	var canvas_xform: Transform2D = get_viewport().get_canvas_transform() if is_inside_tree() else Transform2D.IDENTITY
	for i in _last_enemy_indicators.size():
		var indicator: Control = _last_enemy_indicators[i]
		if indicator == null:
			continue
		var enemy: Node = enemies[i] if i < enemies.size() else null
		if enemy == null or not is_instance_valid(enemy) or not (enemy is Node2D) or camera == null:
			indicator.visible = false
			continue
		var enemy_screen: Vector2 = canvas_xform * (enemy as Node2D).global_position
		var on_screen: bool = enemy_screen.x >= 0 and enemy_screen.x <= view_size.x \
			and enemy_screen.y >= 0 and enemy_screen.y <= view_size.y
		if on_screen:
			indicator.visible = false
			continue
		var center: Vector2 = view_size * 0.5
		var dir: Vector2 = (enemy_screen - center).normalized()
		var max_x: float = view_size.x * 0.5 - LAST_ENEMY_EDGE_MARGIN
		var max_y: float = view_size.y * 0.5 - LAST_ENEMY_EDGE_MARGIN
		var t_to_x: float = max_x / max(absf(dir.x), 0.0001)
		var t_to_y: float = max_y / max(absf(dir.y), 0.0001)
		var t: float = minf(t_to_x, t_to_y)
		indicator.position = center + dir * t
		indicator.rotation = dir.angle()
		indicator.visible = true


func _build_last_enemy_indicator_pool() -> void:
	# Cria N controles com Arrow + ArrowOutline (mesma geometria do
	# TowerAlertIndicator, cor amarela). Anexa direto ao HUD root.
	for i in LAST_ENEMY_INDICATOR_COUNT:
		var holder := Control.new()
		holder.name = "LastEnemyIndicator%d" % i
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.visible = false
		var outline := Polygon2D.new()
		outline.name = "ArrowOutline"
		outline.show_behind_parent = true
		outline.color = LAST_ENEMY_OUTLINE_COLOR
		outline.polygon = PackedVector2Array([Vector2(34, 0), Vector2(-18, -22), Vector2(-18, 22)])
		holder.add_child(outline)
		var arrow := Polygon2D.new()
		arrow.name = "Arrow"
		arrow.color = LAST_ENEMY_ARROW_COLOR
		arrow.polygon = PackedVector2Array([Vector2(28, 0), Vector2(-14, -18), Vector2(-14, 18)])
		holder.add_child(arrow)
		add_child(holder)
		# Pulse de alpha contínuo pra chamar atenção.
		var tw := holder.create_tween().set_loops()
		tw.tween_property(holder, "modulate:a", 0.45, 0.5)
		tw.tween_property(holder, "modulate:a", 1.0, 0.5)
		_last_enemy_indicators.append(holder)


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()
