extends Area2D

# Campo de fogo deixado pela skill direita do Fogo lv3. Aplica DPS a inimigos
# dentro da área por `duration` segundos, depois fade e some.

@export var damage_per_second: float = 12.0
@export var duration: float = 6.0
@export var fade_duration: float = 0.6
# Quando true, o campo veio de um inimigo (ex: fire mage do boss). Em vez de
# bater em "enemy", machuca player + tank_ally + structure (e ignora outros
# enemies, evitando friendly fire).
@export var is_enemy_source: bool = false
# Identificador da fonte (ex: "fire_mage") repassado pro player.take_damage
# quando is_enemy_source=true. Sem isso, morrer no fogo aparece como "causa
# desconhecida" no death screen.
@export var source_id: String = ""
const TICK_INTERVAL: float = 0.5
const BURNING_SOUND: AudioStream = preload("res://audios/mago de fogo/fogo queimando.mp3")

var _enemies_inside: Array[Node] = []
var _life_remaining: float = 0.0
var _tick_accum: float = 0.0
var _burning_player: AudioStreamPlayer2D = null


func _ready() -> void:
	_life_remaining = duration
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Stagger das anims dos sprites filhos pra parecer caos de chamas (não sync).
	for child in get_children():
		if child is AnimatedSprite2D and (child as AnimatedSprite2D).sprite_frames != null:
			var sp: AnimatedSprite2D = child
			var fc: int = sp.sprite_frames.get_frame_count("default")
			if fc > 1:
				sp.frame = randi() % fc
				sp.frame_progress = randf()
	# Fogo de inimigo (fire_mage) vira vermelho/carmim pra player diferenciar
	# visualmente do próprio fogo (laranja-amarelo). Modulate é multiplicado
	# pelo modulate do root (self.modulate.a controla o fade), então usamos
	# nos filhos pra não atropelar o tween de fade-out.
	if is_enemy_source:
		_apply_enemy_tint()
	# Captura bodies já sobrepostos no spawn (overlap inicial). Deferred pro
	# physics step ter populado get_overlapping_bodies — sem isso só pega quem
	# entra DEPOIS via body_entered, atrasando o primeiro hit.
	_capture_initial_overlaps.call_deferred()
	# Tick imediato no spawn (tick_accum = TICK_INTERVAL faz o primeiro
	# _apply_tick acontecer no próximo _process em vez de esperar 0.5s).
	_tick_accum = TICK_INTERVAL
	# Fade out nos últimos `fade_duration` segundos.
	var tw := create_tween()
	tw.tween_interval(duration - fade_duration)
	tw.tween_property(self, "modulate:a", 0.0, fade_duration)
	_start_burning_audio()


func _start_burning_audio() -> void:
	# Loop posicional do fogo queimando. Como é filho do FireField, é freed
	# automático quando o campo some — sem fire fields ativos = sem som.
	# Loop forçado em runtime (mp3 .import vem com loop=false default).
	var stream: AudioStream = BURNING_SOUND
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_burning_player = AudioStreamPlayer2D.new()
	_burning_player.bus = &"SFX"
	_burning_player.stream = stream
	_burning_player.volume_db = -14.0
	# Atenuação por proximidade ao listener (a Camera2D segue o player).
	# Viewport 1920x1080 com zoom 3.5x → área visível ~548x308; half-diagonal
	# ~314px. max_distance=350 garante silêncio assim que o campo sai da tela.
	# attenuation=1.5 mantém volume razoável perto e cai rápido na borda.
	_burning_player.max_distance = 350.0
	_burning_player.attenuation = 1.5
	add_child(_burning_player)
	_burning_player.play()
	# Fade do áudio acompanha o fade visual do campo nos últimos segundos.
	var atw := create_tween()
	atw.tween_interval(duration - fade_duration)
	atw.tween_property(_burning_player, "volume_db", -40.0, fade_duration)


func _apply_enemy_tint() -> void:
	# Flames: shift do laranja-amarelo pra vermelho-carmim (mais R, menos G/B).
	# Shadow: vermelho mais escuro pra sombra também ler como "fogo do inimigo".
	# GlowLight: cor do light fica vermelha (modulate não afeta Light2D).
	for child in get_children():
		if child is AnimatedSprite2D:
			(child as AnimatedSprite2D).modulate = Color(1.15, 0.35, 0.45, 1.0)
		elif child is Polygon2D:
			(child as Polygon2D).color = Color(0.55, 0.05, 0.08, 0.45)
	var glow := get_node_or_null("GlowLight") as PointLight2D
	if glow != null:
		glow.color = Color(1.0, 0.25, 0.3, 1.0)


func _capture_initial_overlaps() -> void:
	for body in get_overlapping_bodies():
		_on_body_entered(body)


func _process(delta: float) -> void:
	_life_remaining -= delta
	if _life_remaining <= 0.0:
		queue_free()
		return
	_tick_accum += delta
	while _tick_accum >= TICK_INTERVAL:
		_tick_accum -= TICK_INTERVAL
		_apply_tick()


func _apply_tick() -> void:
	var amount: float = damage_per_second * TICK_INTERVAL
	var p_for_crit := get_tree().get_first_node_in_group("player") if not is_enemy_source else null
	for enemy in _enemies_inside.duplicate():
		if not is_instance_valid(enemy):
			_enemies_inside.erase(enemy)
			continue
		if enemy.has_method("take_damage"):
			var was_alive_ff: bool = (not ("hp" in enemy)) or float(enemy.hp) > 0.0
			var dmg_ff: float = amount
			# Crit roll por tick (só pra fonte player — boss/enemy não crita).
			if p_for_crit != null and p_for_crit.has_method("roll_crit_dot"):
				var crit_ff: Dictionary = p_for_crit.roll_crit_dot(dmg_ff)
				dmg_ff = float(crit_ff.get("dmg", dmg_ff))
				if bool(crit_ff.get("crit", false)):
					CritFeedback.mark_next_hit_crit(enemy)
			# Enemy-source + target player: passa source_id pro death screen
			# creditar a fonte (ex: "fire_mage"). Outros casos (enemy hits
			# ally/structure ou player-source hits enemy) usam signature 1-arg.
			if is_enemy_source and enemy.is_in_group("player"):
				enemy.take_damage(dmg_ff, source_id)
			else:
				enemy.take_damage(dmg_ff)
				if not is_enemy_source:
					_notify_player_dmg_kill(dmg_ff, "fire_skill", was_alive_ff, enemy)


func _on_body_entered(body: Node) -> void:
	# Filter por origem: skill do player → bate em "enemy"; skill do boss/inimigo
	# → bate em player/ally/structure.
	var hits: bool
	if is_enemy_source:
		hits = body.is_in_group("player") or body.is_in_group("tank_ally") or body.is_in_group("structure")
	else:
		hits = body.is_in_group("enemy")
	if hits and not body in _enemies_inside:
		_enemies_inside.append(body)


func _on_body_exited(body: Node) -> void:
	_enemies_inside.erase(body)


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
