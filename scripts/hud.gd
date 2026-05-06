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
@onready var tower_alert: Control = $TowerAlertIndicator

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
@onready var intro_overlay: Control = $IntroOverlay
@onready var intro_label: Label = $IntroOverlay/Label
@onready var cleared_overlay: Control = $ClearedOverlay
@onready var cleared_label: Label = $ClearedOverlay/Label
@onready var continue_button: Button = $ClearedOverlay/ContinueButton


var _hud_alpha_target: float = HUD_OPAQUE_ALPHA
var _hud_alpha_tween: Tween


func _ready() -> void:
	add_to_group("hud")
	restart_button.pressed.connect(_on_restart_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	# Aplica scale em runtime — no editor o HudFrame fica em 1× (45×145) pra não
	# atrapalhar a edição do mapa.
	hud_frame.scale = HUD_RUNTIME_SCALE
	# Esconde no runtime — script mostra quando a wave começa. No editor fica visível
	# pra você poder ajustar a posição da arte e da label do número.
	hud_frame.visible = false
	# Conecta no signal de gold do player. Defer pra player garantidamente já estar pronto.
	_connect_player_gold.call_deferred()


func _connect_player_gold() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if player.has_signal("gold_changed") and not player.gold_changed.is_connected(_on_gold_changed):
		player.gold_changed.connect(_on_gold_changed)
	if "gold" in player:
		gold_count_label.text = str(player.gold)


func _on_gold_changed(total: int) -> void:
	gold_count_label.text = str(total)


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
	survival_label.text = "Sobreviveu %d waves" % wave_num
	survival_label.modulate.a = 0.0
	survival_label.visible = true

	restart_button.modulate.a = 0.0
	restart_button.visible = true
	menu_button.modulate.a = 0.0
	menu_button.visible = true

	var t := create_tween().set_parallel(true)
	t.tween_property(survival_label, "modulate:a", 1.0, 0.4)
	t.tween_property(restart_button, "modulate:a", 1.0, 0.4)
	t.tween_property(menu_button, "modulate:a", 1.0, 0.4)


func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


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
