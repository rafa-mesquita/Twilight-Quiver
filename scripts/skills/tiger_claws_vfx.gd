extends Node2D

# VFX da skill Garras de Tigre. Toca duas animações de 3 frames separadas por
# um gap pra que as arranhadas sejam visualmente distintas (sem o gap as duas
# colavam uma na outra e pareciam uma só). Total da sequência:
#   scratch_1 (0.25s @ 12fps) → gap (0.25s) → scratch_2 (0.25s @ 12fps) = ~0.75s
# Aplica damage_per_scratch ao final de cada arranhada (total = 2×).

@export var damage_per_scratch: float = 25.0
@export var sfx: AudioStream
# Tocar só os primeiros N segundos do mp3 — o stream é mais longo que o efeito.
@export var sfx_duration: float = 1.5
@export var sfx_volume_db: float = -12.0
# Gap entre a primeira e a segunda arranhada (segundos).
@export var gap_between_scratches: float = 0.55
# Raio pra busca de alvo substituto quando o original morre na 1ª arranhada.
@export var search_radius: float = 180.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var target: Node = null
var _scratch_index: int = 0  # 0 = primeira, 1 = segunda


func _ready() -> void:
	if sprite != null:
		sprite.animation_finished.connect(_on_animation_finished)
		sprite.play("scratch_1")
	# Som dispara JUNTO com cada arranhada (não uma só por cast). Spawna no
	# WORLD (não como child do VFX) pra sobreviver ao queue_free do VFX.
	_spawn_audio()


func _process(_delta: float) -> void:
	# Acompanha o inimigo enquanto ele estiver vivo — antes ficava parado no
	# spot inicial e o sprite "ficava pra trás" se o mob se mexia.
	if target != null and is_instance_valid(target) and target is Node2D:
		global_position = (target as Node2D).global_position


func _spawn_audio() -> void:
	if sfx == null:
		return
	var sfx_player := AudioStreamPlayer2D.new()
	sfx_player.bus = &"SFX"
	sfx_player.stream = sfx
	sfx_player.volume_db = sfx_volume_db
	var world := get_tree().get_first_node_in_group("world")
	if world == null:
		world = get_tree().current_scene
	world.add_child(sfx_player)
	sfx_player.global_position = global_position
	sfx_player.play()
	# Para depois de sfx_duration (corta o mp3 que é mais longo) e auto-libera.
	var ref: AudioStreamPlayer2D = sfx_player
	get_tree().create_timer(sfx_duration).timeout.connect(func() -> void:
		if is_instance_valid(ref):
			ref.stop()
			ref.queue_free()
	)


func _on_animation_finished() -> void:
	# Dano aplica no fim de cada anim (último frame visível). Depois decide:
	# 1ª arranhada → se o alvo morreu, sorteia outro; agenda 2ª após o gap.
	# 2ª arranhada → queue_free.
	_apply_damage()
	if _scratch_index == 0:
		_scratch_index = 1
		# Detecta morte por HP (não por is_instance_valid): take_damage chama
		# queue_free no enemy, mas isso é deferred até o fim do frame — então
		# is_instance_valid ainda retorna true aqui. hp <= 0 é o sinal real.
		var dead: bool = (target == null) or (not is_instance_valid(target)) \
			or (("hp" in target) and float(target.hp) <= 0.0)
		if dead:
			target = _find_replacement_target()
		# Esconde durante o gap pra ficar nítido visualmente que são 2 hits.
		if sprite != null:
			sprite.visible = false
		get_tree().create_timer(gap_between_scratches).timeout.connect(_play_second_scratch)
	else:
		queue_free()


func _play_second_scratch() -> void:
	if not is_inside_tree() or sprite == null:
		return
	# Sem alvo válido (1º morreu e não achou substituto) — encerra silenciosamente.
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	# Snap pro alvo novo antes de mostrar (em vez de aparecer fora do mob).
	if target is Node2D:
		global_position = (target as Node2D).global_position
	sprite.visible = true
	sprite.play("scratch_2")
	# Áudio da 2ª arranhada (independente da 1ª).
	_spawn_audio()


func _find_replacement_target() -> Node2D:
	# Sorteia um inimigo vivo no raio em volta do player. Se não acha, retorna null.
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return null
	var center: Vector2 = (p as Node2D).global_position
	var rsq: float = search_radius * search_radius
	var candidates: Array[Node2D] = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e == target:
			continue
		var en: Node2D = e as Node2D
		if en.is_in_group("ally"):
			continue
		# Boss shieldado: pular pra não trocar pra um alvo invulnerável.
		if en.is_in_group("boss_shielded"):
			continue
		if en.global_position.distance_squared_to(center) <= rsq:
			candidates.append(en)
	if candidates.is_empty():
		return null
	candidates.shuffle()
	return candidates[0]


func _apply_damage() -> void:
	if target == null or not is_instance_valid(target):
		return
	if not target.has_method("take_damage"):
		return
	var was_alive: bool = (not ("hp" in target)) or float(target.hp) > 0.0
	target.take_damage(damage_per_scratch)
	# Breakdown por fonte (painel TAB) + kill attribution se a arranhada matou.
	var p := get_tree().get_first_node_in_group("player")
	if p == null:
		return
	if p.has_method("notify_damage_dealt_by_source"):
		p.notify_damage_dealt_by_source(damage_per_scratch, "tiger_claws")
	if was_alive and is_instance_valid(target) and p.has_method("notify_kill_by_source"):
		var killed: bool = ("hp" in target) and float(target.hp) <= 0.0
		if killed:
			p.notify_kill_by_source("tiger_claws")
