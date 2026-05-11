extends Node2D

# Raio elétrico do Electric Mage. Padrão de execução:
#   1. Fade-in da nuvem (FADE_IN_DURATION) — sombra também fade-in.
#   2. Strike 1: anima frames 0-6 do "strike", dano aplica no frame DAMAGE_FRAME.
#   3. Idle: troca pro sprite "idle_cloud" (single frame da nuvem solta) por
#      IDLE_BETWEEN_STRIKES segundos.
#   4. Strike 2: anima "strike" de novo, dano aplica de novo no frame de
#      impacto. Sombra some nesse momento.
#   5. Final: espera o sfx do último strike terminar antes de queue_free
#      pra não cortar o som.

const FADE_IN_DURATION: float = 0.5
const IDLE_BETWEEN_STRIKES: float = 3.0
const DAMAGE_FRAME: int = 4

# Nome da animação de fade no SpriteFrames (definida em lightning_bolt.tscn).
# Quando o último strike acaba, toca esta animação e fadeia a sombra junto
# pra somar a nuvem gradualmente. Sem a animação, cai no fallback hide.
const FADE_ANIM_NAME: StringName = &"fade"

@export var damage: float = 15.0
@export var damage_radius: float = 12.0
# True: spawnado por enemy (atinge player + aliados + estruturas).
# False: spawnado por curse-ally (atinge enemies).
@export var is_enemy_source: bool = true

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var strike_sound: AudioStreamPlayer2D = get_node_or_null("StrikeSound")

# Sombra de telegrafia em 3 camadas — mesmo estilo isométrico das sombras
# dos inimigos do projeto (ex: fire_mage.tscn). Ratio de achatamento 8:3
# (largura:altura) preservado. Cada camada com alpha diferente.
const SHADOW_SEGMENTS: int = 16
const SHADOW_RATIO_Y: float = 0.375  # height = width × 0.375 → mesma proporção 8:3
const SHADOW_MIDDLE_SCALE: float = 0.625  # 5/8 do raio externo
const SHADOW_INNER_SCALE: float = 0.375  # 3/8 do raio externo
const SHADOW_OUTER_ALPHA: float = 0.15
const SHADOW_MIDDLE_ALPHA: float = 0.22
const SHADOW_INNER_ALPHA: float = 0.32

# Root Node2D da sombra (contém as 3 polygons como filhos). Tween de
# modulate no root afeta todas as 3 camadas juntas.
var _shadow: Node2D = null
# Strike counter: 0 antes do strike 1, 1 entre strikes, 2 depois do strike 2.
var _strike_index: int = 0
# Flag por strike pra não aplicar dano múltiplas vezes no mesmo strike.
var _damage_applied_this_strike: bool = false


func _ready() -> void:
	if sprite == null or sprite.sprite_frames == null:
		queue_free()
		return
	_build_shadow()
	# Fase 1: nuvem (frame 0 do "strike") + sombra fade-in em paralelo.
	sprite.frame = 0
	sprite.stop()
	sprite.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(sprite, "modulate:a", 1.0, FADE_IN_DURATION)
	if _shadow != null:
		tw.tween_property(_shadow, "modulate:a", 1.0, FADE_IN_DURATION).from(0.0)
	# Connect signals (one-shot pra reusar entre strike 1 e strike 2).
	sprite.frame_changed.connect(_on_frame_changed)
	# Dispara strike 1 após o fade.
	get_tree().create_timer(FADE_IN_DURATION).timeout.connect(_start_strike)


func _build_shadow() -> void:
	# Sombra isométrica 3-camadas no origin (= ponto de impacto). Mesmo
	# estilo das sombras de inimigos do projeto (fire_mage etc): elipse
	# achatada na vertical, alpha cresce do exterior pro interior.
	# z_index = -1 absoluto (mesmo bucket do Ground TileMap) → em cima do
	# chão e atrás de player/aliados/inimigos/estruturas/props.
	var root := Node2D.new()
	root.z_index = -1
	root.z_as_relative = false
	root.modulate.a = 0.0
	add_child(root)
	_shadow = root
	# 2 camadas concentricas (outer + middle) — removida a inner mais escura
	# central por pedido (visual mais limpo, sem "bolinha" no meio).
	_add_shadow_layer(root, damage_radius, SHADOW_OUTER_ALPHA)
	_add_shadow_layer(root, damage_radius * SHADOW_MIDDLE_SCALE, SHADOW_MIDDLE_ALPHA)


func _add_shadow_layer(parent: Node, rx: float, alpha: float) -> void:
	var ry: float = rx * SHADOW_RATIO_Y
	var p := Polygon2D.new()
	p.color = Color(0, 0, 0, alpha)
	var pts := PackedVector2Array()
	for i in SHADOW_SEGMENTS:
		var a: float = (float(i) / float(SHADOW_SEGMENTS)) * TAU
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	p.polygon = pts
	parent.add_child(p)


func _start_strike() -> void:
	# Reset flag de dano pra esse strike e toca o sfx.
	_damage_applied_this_strike = false
	if strike_sound != null:
		strike_sound.play()
	# animation_finished é one-shot — reconecta a cada strike pra rodar o callback.
	sprite.animation_finished.connect(_on_strike_finished, CONNECT_ONE_SHOT)
	sprite.play("strike")


func _on_frame_changed() -> void:
	# Só interessa quando o sprite tá rodando o "strike" e atingiu o frame
	# de impacto. Bloqueia múltiplas aplicações no mesmo strike via flag.
	if sprite.animation != &"strike":
		return
	if not _damage_applied_this_strike and sprite.frame >= DAMAGE_FRAME:
		_damage_applied_this_strike = true
		_apply_damage()


func _on_strike_finished() -> void:
	_strike_index += 1
	if _strike_index == 1:
		# Entre strikes: cloud idle por IDLE_BETWEEN_STRIKES segundos, depois
		# strike 2. Sombra continua visível pra telegrafar o próximo impacto.
		sprite.play("idle_cloud")
		get_tree().create_timer(IDLE_BETWEEN_STRIKES).timeout.connect(_start_strike)
	else:
		# Strike 2 acabou — toca fade-out (nuvem some gradualmente) e fadeia
		# a sombra junto no mesmo ritmo, depois queue_free.
		_finalize()


func _finalize() -> void:
	# Tenta tocar a animação de fade. Se a textura existir, retorna a duração.
	# Senão, retorna 0 e cai no fallback (hide imediato).
	var fade_duration: float = _try_play_fade()
	if fade_duration > 0.0:
		# Fade da sombra no mesmo ritmo da nuvem — somem juntas.
		if _shadow != null:
			var tw := create_tween()
			tw.tween_property(_shadow, "modulate:a", 0.0, fade_duration)
		# Quando a animação de fade acabar, esconde o sprite e fecha o node
		# (esperando o sfx do último strike terminar antes de queue_free).
		sprite.animation_finished.connect(_finalize_cleanup, CONNECT_ONE_SHOT)
	else:
		# Sem textura de fade — hide imediato (comportamento antigo).
		if _shadow != null:
			_shadow.visible = false
		_finalize_cleanup()


func _try_play_fade() -> float:
	var sf := sprite.sprite_frames as SpriteFrames
	if sf == null or not sf.has_animation(FADE_ANIM_NAME):
		return 0.0
	var fc: int = sf.get_frame_count(FADE_ANIM_NAME)
	var fps: float = sf.get_animation_speed(FADE_ANIM_NAME)
	if fc <= 0 or fps <= 0.0:
		return 0.0
	sprite.play(FADE_ANIM_NAME)
	return float(fc) / fps


func _finalize_cleanup() -> void:
	if sprite != null:
		sprite.visible = false
	if _shadow != null:
		_shadow.visible = false
	if strike_sound != null and strike_sound.playing:
		strike_sound.finished.connect(queue_free)
	else:
		queue_free()


func _apply_damage() -> void:
	# Itera grupos relevantes e dá dano em tudo dentro do damage_radius.
	# Filtra cc_immune e checa take_damage.
	var groups: Array[String] = []
	if is_enemy_source:
		groups = ["player", "ally", "structure"]
	else:
		groups = ["enemy"]
	var seen: Dictionary = {}
	for g in groups:
		for body in get_tree().get_nodes_in_group(g):
			if seen.has(body):
				continue
			seen[body] = true
			if not is_instance_valid(body) or not (body is Node2D):
				continue
			if body.is_in_group("cc_immune"):
				continue
			var b2d: Node2D = body
			var dist: float = (b2d.global_position - global_position).length()
			if dist <= damage_radius and body.has_method("take_damage"):
				var was_alive_lb: bool = (not ("hp" in body)) or float(body.hp) > 0.0
				body.take_damage(damage)
				if not is_enemy_source:
					_notify_player_dmg_kill(damage, "chain_lightning_skill", was_alive_lb, body)


func _notify_player_dmg_kill(amount: float, source_id: String, was_alive: bool, target: Node) -> void:
	if not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("notify_damage_dealt_by_source"):
		p.notify_damage_dealt_by_source(amount, source_id)
	if was_alive and p.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			p.notify_kill_by_source(source_id)
