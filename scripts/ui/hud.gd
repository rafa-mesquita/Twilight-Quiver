extends CanvasLayer

# HUD: overlay preto + top layer onde o sprite clonado do player
# (e o kill effect) é renderizado por cima do preto durante a sequência de morte.
# Player.gd encontra esse nó pelo grupo "hud" e chama play_death_sequence().

# Quanto descer o sprite de morte na tela (visualmente o player caído fica um pouco mais embaixo).
# Em pixels do viewport native (1920×1080); 12 = ~3px do mundo após zoom 4× da câmera.
const DEATH_SPRITE_Y_OFFSET: float = 12.0
# Tempo do clone deslizar da posição real do player até o centro (evita teleporte abrupto).
const MOVE_TO_CENTER_DURATION: float = 0.4

@onready var death_overlay: ColorRect = $DeathOverlay
@onready var death_top_layer: CanvasLayer = $DeathTopLayer
@onready var restart_button: Button = $DeathTopLayer/RestartButton
@onready var menu_button: Button = $DeathTopLayer/MenuButton
@onready var survival_label: Label = $DeathTopLayer/SurvivalLabel
@onready var score_label: Label = $DeathTopLayer/ScoreLabel
@onready var tower_alert: Control = $TowerAlertIndicator

# Leaderboard: auto-submit silencioso em build de release. Cliente HTTP é
# instanciado lazy quando player morre (em release). Em debug, nada é enviado.
const _LEADERBOARD_CLIENT := preload("res://scripts/systems/leaderboard_client.gd")
const _SCORE_CALC := preload("res://scripts/systems/score_calc.gd")
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
@onready var curse_skill_icon: Control = $CurseSkillIcon
@onready var curse_skill_cd_label: Label = $CurseSkillIcon/CdLabel
@onready var upgrade_column_vbox: VBoxContainer = $UpgradeColumn/VBox

# Coluna de upgrades adquiridos (right edge da HUD).
const UPGRADE_DISPLAY_ORDER: Array[String] = [
	# Status primeiro (sempre visíveis assim que comprados)
	"hp", "armor", "damage", "attack_speed", "move_speed",
	# Upgrades de gameplay
	"perfuracao", "ricochet_arrow", "multi_arrow", "chain_lightning",
	"fire_arrow", "curse_arrow", "graviton", "life_steal", "dash",
	"gold_magnet",
	# Aliados
	"woodwarden", "leno", "capivara_joe",
]
# Caps onde "MAX" substitui "Lx" no badge (status escala infinito → sem cap).
const _UPG_CAPS: Dictionary = {
	"perfuracao": 4, "ricochet_arrow": 4, "multi_arrow": 4, "chain_lightning": 4,
	"fire_arrow": 4, "curse_arrow": 4, "graviton": 4, "life_steal": 4,
	"dash": 4, "gold_magnet": 4,
	"woodwarden": 4, "leno": 4, "capivara_joe": 4,
}
const _UPG_STATUS_COMBINED_PATH: String = "res://assets/Hud/shop/status/HP - atck speed - Move speed - Atck Dmg.png"
const _UPG_STATUS_COMBINED_ROWS: Dictionary = {"hp": 0, "attack_speed": 1, "move_speed": 2, "damage": 3}
# Path direto pra cada id que tem arte própria. Faltantes caem em placeholder
# de upgrade ou aliado (categoria detectada pela posição na ordem).
const _UPG_PATHS: Dictionary = {
	"armor": "res://assets/Hud/shop/status/Armadura.png",
	"fire_arrow": "res://assets/Hud/shop/upgrade/fire_arrow.png",
	"curse_arrow": "res://assets/Hud/shop/upgrade/curse_arrow.png",
	"multi_arrow": "res://assets/Hud/shop/upgrade/multi_arrow.png",
	"chain_lightning": "res://assets/Hud/shop/upgrade/chain_lightning.png",
	"graviton": "res://assets/Hud/shop/upgrade/graviton/graviton card-Sheet.png",
	"leno": "res://assets/Hud/shop/aliado/Leno/Leno Card.png",
	"woodwarden": "res://assets/Hud/shop/aliado/woodwarden/woodwarden card.png",
}
const _UPG_FALLBACK_UPGRADE: String = "res://assets/Hud/shop/upgrade/placeholder.png"
const _UPG_FALLBACK_ALIADO: String = "res://assets/Hud/shop/aliado/placeholder.png"
# Tamanho da célula da arte (atlas é 4 cells lado-a-lado por nível).
const _UPG_FRAME_NORMAL: Vector2i = Vector2i(38, 47)  # upgrade/aliado
const _UPG_FRAME_STATUS: Vector2i = Vector2i(65, 17)  # status/armor (faixa horizontal)
# IDs por categoria (pra resolver fallback e tamanho de célula).
const _UPG_STATUS_IDS: Array[String] = ["hp", "armor", "damage", "attack_speed", "move_speed"]
const _UPG_ALIADO_IDS: Array[String] = ["woodwarden", "leno", "capivara_joe"]
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
		"HudFrame", "HpBar", "DashCdBar", "FireSkillIcon", "CurseSkillIcon",
		"GoldDisplay", "TowerAlertIndicator",
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
	# Fire skill icon — só aparece quando player chega no Fogo lv3.
	if player.has_signal("fire_skill_unlocked") and not player.fire_skill_unlocked.is_connected(_on_fire_skill_unlocked):
		player.fire_skill_unlocked.connect(_on_fire_skill_unlocked)
	if player.has_signal("fire_skill_cooldown_changed") and not player.fire_skill_cooldown_changed.is_connected(_on_fire_skill_cooldown_changed):
		player.fire_skill_cooldown_changed.connect(_on_fire_skill_cooldown_changed)
	if "fire_arrow_level" in player and int(player.fire_arrow_level) >= 3:
		_on_fire_skill_unlocked()
	# Curse skill icon — só aparece quando player chega na Maldição lv4.
	if player.has_signal("curse_skill_unlocked") and not player.curse_skill_unlocked.is_connected(_on_curse_skill_unlocked):
		player.curse_skill_unlocked.connect(_on_curse_skill_unlocked)
	if player.has_signal("curse_skill_cooldown_changed") and not player.curse_skill_cooldown_changed.is_connected(_on_curse_skill_cooldown_changed):
		player.curse_skill_cooldown_changed.connect(_on_curse_skill_cooldown_changed)
	if "curse_arrow_level" in player and int(player.curse_arrow_level) >= 4:
		_on_curse_skill_unlocked()
	# Coluna de upgrades adquiridos: rebuild on signal.
	if player.has_signal("upgrade_applied") and not player.upgrade_applied.is_connected(_on_upgrade_applied):
		player.upgrade_applied.connect(_on_upgrade_applied)
	# Estado inicial — caso já tenha algum upgrade aplicado (free upgrade da wave 1
	# pode ter rolado antes do HUD conectar).
	_refresh_upgrade_column()


func _on_upgrade_applied(_id: String, _level: int) -> void:
	_refresh_upgrade_column()


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


func _on_dash_cooldown_changed(remaining: float, total: float) -> void:
	# Fill cresce do vazio (cooldown rolando) pro cheio (pronto).
	# 0 remaining = pronto = barra cheia.
	var ratio: float = 0.0 if total <= 0.0 else clampf(1.0 - remaining / total, 0.0, 1.0)
	dash_cd_fill.size.x = BAR_FILL_WIDTH * ratio
	if remaining <= 0.001:
		dash_cd_label.text = "Pronto"
	else:
		dash_cd_label.text = "%.1fs" % remaining


func _on_fire_skill_unlocked() -> void:
	fire_skill_icon.visible = true


func _on_fire_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Quadrado com ícone fixo + label do tempo no centro. Quando pronto, label
	# vazio e ícone full color. Em cooldown, ícone dimmed e label com segundos.
	if remaining <= 0.001:
		fire_skill_cd_label.text = ""
		fire_skill_icon.modulate = Color.WHITE
	else:
		fire_skill_cd_label.text = "%d" % int(ceilf(remaining))
		fire_skill_icon.modulate = Color(0.6, 0.55, 0.55, 1.0)


func _on_curse_skill_unlocked() -> void:
	curse_skill_icon.visible = true


func _on_curse_skill_cooldown_changed(remaining: float, _total: float) -> void:
	# Mesmo pattern do fire skill: full color quando pronto, dimmed em cd.
	if remaining <= 0.001:
		curse_skill_cd_label.text = ""
		curse_skill_icon.modulate = Color.WHITE
	else:
		curse_skill_cd_label.text = "%d" % int(ceilf(remaining))
		curse_skill_icon.modulate = Color(0.55, 0.50, 0.65, 1.0)


func _process(delta: float) -> void:
	_update_tower_alert(delta)
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


func play_raid_intro(wave_number: int) -> void:
	intro_label.text = "Raid %d" % wave_number
	intro_overlay.modulate.a = 1.0
	intro_overlay.visible = true
	# Hold + fade out (revela o mundo).
	await get_tree().create_timer(1.5).timeout
	var t := create_tween()
	t.tween_property(intro_overlay, "modulate:a", 0.0, 0.5)
	await t.finished
	intro_overlay.visible = false


func play_wave_cleared(wave_number: int) -> void:
	cleared_label.text = "Wave %d Limpa" % wave_number
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
	# Câmera tem zoom (atualmente 4×) — clone fica em CanvasLayer NÃO afetado pela câmera,
	# então precisa escalar manualmente pra parecer do mesmo tamanho que o player na tela.
	var camera := player_sprite.get_viewport().get_camera_2d()
	var zoom: Vector2 = camera.zoom if camera != null else Vector2.ONE

	# Posição REAL do player na tela (considera câmera, mesmo se ela bateu na borda do mapa).
	# Sprite tem offset.y=-16 em world space; multiplica pelo zoom pra virar offset de tela.
	var player_screen: Vector2 = player_sprite.get_global_transform_with_canvas().origin
	var initial_clone_pos: Vector2 = player_screen + Vector2(0.0, player_sprite.offset.y * zoom.y)

	# Tela escurece.
	var fade_in := create_tween()
	fade_in.tween_property(death_overlay, "modulate:a", 1.0, blackout_duration)

	# Clone do sprite do player no top layer — começa onde o player ESTÁ na tela
	# e desliza até o centro (em paralelo ao fade preto). Evita teleporte abrupto
	# quando o player morre perto da borda do mapa.
	var clone := AnimatedSprite2D.new()
	clone.sprite_frames = player_sprite.sprite_frames
	clone.animation = player_sprite.animation
	clone.frame = player_sprite.frame
	clone.pause()
	clone.flip_h = player_sprite.flip_h
	clone.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clone.scale = zoom
	clone.position = initial_clone_pos
	death_top_layer.add_child(clone)

	# Desliza pro centro da tela.
	var move_tween := create_tween()
	move_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	move_tween.tween_property(clone, "position", center, MOVE_TO_CENTER_DURATION)
	await move_tween.finished

	# Player parado por X segundos (drama).
	await get_tree().create_timer(freeze_duration).timeout

	# Anim de morte (4 frames @ speed 2.5 = mesmo ritmo da árvore).
	# Desce o sprite 3px só durante a anim (visualmente o personagem cai um pouco).
	clone.position.y += DEATH_SPRITE_Y_OFFSET
	clone.play("death")
	await clone.animation_finished

	# Player some.
	var fade_clone := create_tween()
	fade_clone.tween_property(clone, "modulate:a", 0.0, fadeout_duration)
	await fade_clone.finished

	# Mostra botão de jogar novamente.
	_show_restart_button()


func _show_restart_button() -> void:
	# Mensagem de wave alcançada antes do botão. Sem acentos — fonte at01 não tem.
	var wave_num: int = 1
	var wm := get_tree().get_first_node_in_group("wave_manager")
	if wm != null and "wave_number" in wm:
		wave_num = int(wm.wave_number)
	# Score em destaque (calculado a partir das mesmas stats que vão pro leaderboard).
	var score: int = _SCORE_CALC.calc(_collect_run_stats(wave_num))
	score_label.text = "SCORE %d" % score
	score_label.modulate.a = 0.0
	score_label.visible = true

	survival_label.text = "Sobreviveu %d waves\n%s" % [wave_num, _build_death_stats_block()]
	survival_label.modulate.a = 0.0
	survival_label.visible = true

	restart_button.modulate.a = 0.0
	restart_button.visible = true
	menu_button.modulate.a = 0.0
	menu_button.visible = true

	var t := create_tween().set_parallel(true)
	t.tween_property(score_label, "modulate:a", 1.0, 0.4)
	t.tween_property(survival_label, "modulate:a", 1.0, 0.4)
	t.tween_property(restart_button, "modulate:a", 1.0, 0.4)
	t.tween_property(menu_button, "modulate:a", 1.0, 0.4)

	# Envio silencioso pro leaderboard — fire-and-forget. Em debug nem instancia
	# o cliente (evita poluir leaderboard com runs de dev).
	if not OS.is_debug_build():
		_auto_submit_score()


func _on_menu_pressed() -> void:
	# Garante despausar antes de trocar de cena (senão o menu carrega pausado).
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn")


# ---------- Death stats ----------

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
	return "Tempo: %s\nInimigos mortos: %d\nAliados feitos: %d\nDano causado: %d\nDano sofrido: %d" % [time_str, kills, allies, dmg_dealt, dmg_taken]


func _format_run_time(msec: int) -> String:
	var total_sec: int = msec / 1000
	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%d:%02d" % [minutes, seconds]


# ---------- Leaderboard auto-submit ----------

func _auto_submit_score() -> void:
	var nick: String = _load_nickname()
	if nick.is_empty():
		# Sem nick salvo (cara abriu jogo, não preencheu prompt e foi direto pra death?
		# Não deveria acontecer em fluxo normal). Skip silencioso.
		return
	if _leaderboard_client == null:
		_leaderboard_client = _LEADERBOARD_CLIENT.new()
		add_child(_leaderboard_client)
		# Sem listeners de upload_succeeded/failed — fire-and-forget.
	_leaderboard_client.submit_run(_build_run_payload(nick))


func _collect_run_stats(wave_num: int) -> Dictionary:
	var p := get_tree().get_first_node_in_group("player")
	var kills: int = 0
	var allies: int = 0
	var dmg_dealt: int = 0
	var dmg_taken: int = 0
	if p != null:
		kills = int(p.get("stats_enemies_killed")) if "stats_enemies_killed" in p else 0
		allies = int(p.get("stats_allies_made")) if "stats_allies_made" in p else 0
		dmg_dealt = int(round(float(p.get("stats_damage_dealt")))) if "stats_damage_dealt" in p else 0
		dmg_taken = int(round(float(p.get("stats_damage_taken")))) if "stats_damage_taken" in p else 0
	return {
		"wave": wave_num,
		"kills": kills,
		"allies": allies,
		"dmg_dealt": dmg_dealt,
		"dmg_taken": dmg_taken,
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


func _close_pause() -> void:
	if _pause_layer == null:
		return
	_pause_visible = false
	_pause_layer.visible = false
	get_tree().paused = false


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
	title.text = "PAUSADO"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if at01 != null:
		title.add_theme_font_override("font", at01)
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color.WHITE)
	bg.add_child(title)
	var continue_btn := Button.new()
	continue_btn.set_anchors_preset(Control.PRESET_CENTER)
	continue_btn.position = Vector2(-220, -60)
	continue_btn.size = Vector2(440, 72)
	continue_btn.text = "Continuar"
	if at01 != null:
		continue_btn.add_theme_font_override("font", at01)
	continue_btn.add_theme_font_size_override("font_size", 48)
	continue_btn.pressed.connect(_close_pause)
	bg.add_child(continue_btn)
	var menu_btn := Button.new()
	menu_btn.set_anchors_preset(Control.PRESET_CENTER)
	menu_btn.position = Vector2(-220, 40)
	menu_btn.size = Vector2(440, 64)
	menu_btn.text = "Voltar ao Menu"
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
