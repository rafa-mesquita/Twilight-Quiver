extends CanvasLayer

# Death Replay: reproduz os últimos ~3.5s antes da morte. Usa os snapshots
# capturados pelo player.gd e cria sprites "ghost" (pool por id) que vão
# se reposicionando frame a frame em câmera-locked no player.
#
# Spawnado pelo HUD quando o botão "Ver replay da morte" é clicado.

signal finished

const WORLD_ZOOM: float = 3.5  # Mesmo zoom da Camera2D do main.tscn.
const PLAYBACK_FPS: float = 20.0  # Mesma taxa de captura.
const SLOW_MO_FACTOR: float = 0.6  # Replay em 60% da velocidade real.
const FADE_DURATION: float = 0.4
const _PLAYER_PREVIEW_SCENE: PackedScene = preload("res://scenes/ui/player_preview.tscn")

@onready var root_ctrl: Control = $Root
@onready var bg: ColorRect = $Root/Bg
@onready var world_root: Node2D = $Root/WorldRoot
@onready var title_label: Label = $Root/TitleLabel
@onready var killed_by_label: Label = $Root/KilledByLabel

var snapshots: Array = []
var killed_by_str: String = ""
var background_texture: Texture2D = null

var _elapsed: float = 0.0
var _total_duration: float = 0.0
var _ghosts: Dictionary = {}  # id -> Node2D
# Posição-âncora no mundo: a posição do player no MOMENTO DA MORTE (último
# snapshot). Todos os ghosts são plotados como rel_pos = entity.pos - anchor,
# o que combina com a screenshot de fundo (que mostra a câmera no momento da morte).
var _anchor_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	# Sem snapshots → encerra imediato (defensive).
	if snapshots.is_empty():
		emit_signal("finished")
		queue_free()
		return
	# Total = N snapshots / fps × slow_mo (sec ajustado pela velocidade do playback).
	_total_duration = float(snapshots.size()) / PLAYBACK_FPS / SLOW_MO_FACTOR
	# Âncora = player_pos no último snapshot (momento da morte). Combina com a
	# screenshot do fundo (câmera estava no player nesse momento).
	var last_snap: Dictionary = snapshots[snapshots.size() - 1]
	_anchor_pos = last_snap.get("player_pos", Vector2.ZERO)
	# Posiciona world_root no centro do viewport com o zoom aplicado.
	world_root.position = get_viewport().get_visible_rect().size / 2.0
	world_root.scale = Vector2(WORLD_ZOOM, WORLD_ZOOM)
	# Background: screenshot capturada no momento da morte (cobre o viewport).
	# Se não tem screenshot, fica só com o fundo escuro do ColorRect.
	if background_texture != null:
		bg.color = Color(1, 1, 1, 1)  # neutralizando — TextureRect vai por cima
		var img_rect := TextureRect.new()
		img_rect.texture = background_texture
		img_rect.anchor_right = 1.0
		img_rect.anchor_bottom = 1.0
		img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		img_rect.modulate = Color(0.6, 0.6, 0.6, 1.0)
		# Insere ATRÁS dos labels mas na frente do Bg.
		root_ctrl.add_child(img_rect)
		root_ctrl.move_child(img_rect, 1)
	# Label de cabeçalho.
	title_label.text = tr("HUD_REPLAY_TITLE")
	killed_by_label.text = killed_by_str
	# Fade in (CanvasLayer não tem modulate — usa o Control Root como wrapper).
	root_ctrl.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(root_ctrl, "modulate:a", 1.0, FADE_DURATION)
	# Renderiza primeiro snapshot.
	_render_snapshot_at(0.0)


func _process(delta: float) -> void:
	if snapshots.is_empty():
		return
	_elapsed += delta
	if _elapsed >= _total_duration:
		# Fim — espera um beat mostrando o último frame, depois fade out.
		_render_snapshot_at(_total_duration)
		_finish_replay()
		set_process(false)
		return
	_render_snapshot_at(_elapsed)


func _render_snapshot_at(t: float) -> void:
	# Mapeia tempo decorrido pro índice do snapshot (linear, sem interpolação).
	var progress: float = clampf(t / maxf(_total_duration, 0.001), 0.0, 1.0)
	var idx: int = mini(int(progress * float(snapshots.size() - 1) + 0.5), snapshots.size() - 1)
	var snap: Dictionary = snapshots[idx]
	var entities: Array = snap.get("entities", [])
	# Marca todos os ghosts como "não vistos" — os que aparecerem ficam, o resto some.
	var seen_ids: Dictionary = {}
	for entry in entities:
		var id: int = int(entry.get("id", 0))
		seen_ids[id] = true
		_apply_entity(entry)
	# Esconde ghosts que não estão no snapshot atual.
	for id in _ghosts.keys():
		if not seen_ids.has(id):
			var g: Node = _ghosts[id]
			if is_instance_valid(g):
				(g as Node2D).visible = false


func _apply_entity(entry: Dictionary) -> void:
	var id: int = int(entry.get("id", 0))
	var ghost: Node2D = _get_or_create_ghost(id, entry)
	if ghost == null:
		return
	ghost.visible = true
	var pos: Vector2 = entry.get("pos", Vector2.ZERO)
	# Relativo ao MOMENTO DA MORTE — combina com o background (screenshot
	# tirada nesse instante, com a câmera no player).
	ghost.position = pos - _anchor_pos
	var is_player: bool = bool(entry.get("is_player", false))
	var anim: String = String(entry.get("anim", ""))
	var frame_idx: int = int(entry.get("frame", 0))
	var flip_h: bool = bool(entry.get("flip_h", false))
	if is_player:
		_apply_player_ghost(ghost, anim, frame_idx, flip_h, entry.get("modulate", Color.WHITE))
	else:
		var sprite_node: AnimatedSprite2D = ghost.get_node_or_null("Sprite") as AnimatedSprite2D
		if sprite_node == null:
			return
		if not anim.is_empty() and sprite_node.sprite_frames != null \
				and sprite_node.sprite_frames.has_animation(anim):
			if sprite_node.animation != StringName(anim):
				sprite_node.animation = StringName(anim)
		sprite_node.frame = frame_idx
		sprite_node.flip_h = flip_h
		sprite_node.modulate = entry.get("modulate", Color.WHITE)


func _apply_player_ghost(ghost: Node2D, anim: String, frame_idx: int, flip_h: bool, mod: Color) -> void:
	# Player ghost = player_preview com SkinLoadout. Body é a anim master, Skin/*
	# segue automaticamente via skin_manager.gd.
	var body: AnimatedSprite2D = ghost.get_node_or_null("Body") as AnimatedSprite2D
	if body == null:
		return
	if not anim.is_empty() and body.sprite_frames != null \
			and body.sprite_frames.has_animation(anim):
		if body.animation != StringName(anim):
			body.animation = StringName(anim)
	body.frame = frame_idx
	body.flip_h = flip_h
	# Flipa todos os layers de skin pra acompanhar o Body.
	var skin: Node = ghost.get_node_or_null("Skin")
	if skin != null:
		for child in skin.get_children():
			if child is AnimatedSprite2D:
				(child as AnimatedSprite2D).flip_h = flip_h
				if not anim.is_empty() and (child as AnimatedSprite2D).sprite_frames != null \
						and (child as AnimatedSprite2D).sprite_frames.has_animation(anim):
					(child as AnimatedSprite2D).animation = StringName(anim)
				(child as AnimatedSprite2D).frame = frame_idx
	ghost.modulate = mod


func _get_or_create_ghost(id: int, entry: Dictionary) -> Node2D:
	if _ghosts.has(id):
		return _ghosts[id]
	# Player ghost: usa o player_preview scene + SkinLoadout pra capturar a roupa.
	if bool(entry.get("is_player", false)):
		var preview: Node2D = _PLAYER_PREVIEW_SCENE.instantiate()
		preview.z_index = int(entry.get("z_index", 0))
		world_root.add_child(preview)
		# SkinLoadout.apply_to é static — chama direto pela classe.
		SkinLoadout.apply_to(preview)
		_ghosts[id] = preview
		return preview
	# Ghost normal: AnimatedSprite2D com o sprite_frames original.
	var sprite_frames: SpriteFrames = entry.get("sprite_frames")
	if sprite_frames == null:
		return null
	var ghost := Node2D.new()
	ghost.name = "Ghost_%d" % id
	ghost.z_index = int(entry.get("z_index", 0))
	world_root.add_child(ghost)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = sprite_frames
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Reproduz o offset do sprite original (ex: offset=(0,-16) coloca o sprite
	# acima dos pés). Sem isso, todos os ghosts ficam centralizados nos pés.
	sprite.position = entry.get("sprite_offset", Vector2.ZERO)
	ghost.add_child(sprite)
	_ghosts[id] = ghost
	return ghost


func _finish_replay() -> void:
	var tw := create_tween()
	tw.tween_property(root_ctrl, "modulate:a", 0.0, FADE_DURATION)
	await tw.finished
	emit_signal("finished")
	queue_free()
