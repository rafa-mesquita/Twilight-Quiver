extends Node2D

# Pulso gravitacional do Graviton (upgrade do ramo Arco/Ataque):
# - Aplica SlowDebuff em todos os inimigos na área
# - Puxa levemente os inimigos pro centro (gravidade leve)
# - Após `lifetime`, se `explosion_damage > 0` (lv3+), causa dano AoE no fim
# - Visual: campo cinza tênue + ondas de propagação concêntricas + flash branco
#   pulsante nos inimigos sendo puxados

@export var radius: float = 60.0
@export var lifetime: float = 3.0
@export var slow_factor: float = 0.7  # 0.7 = 30% slow
@export var pull_strength: float = 30.0  # px/s puxados pro centro
@export var explosion_damage: float = 0.0  # 0 = sem explosão (lv1/lv2)
@export var source: Node = null  # quem criou o pulso (player) — pra notify_damage_dealt

const PULSE_COLOR_CORE: Color = Color(0.55, 0.55, 0.60, 0.18)  # cinza tênue
const WAVE_COLOR: Color = Color(0.78, 0.78, 0.82, 0.55)        # cinza claro pra ondas
const EXPLOSION_COLOR: Color = Color(0.92, 0.92, 0.95, 0.85)
const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")
# Ondas: novo ring expandido a cada WAVE_SPAWN_INTERVAL, dura WAVE_EXPAND_DURATION.
const WAVE_SPAWN_INTERVAL: float = 0.55
const WAVE_EXPAND_DURATION: float = 1.10
# Flash branco nos inimigos: silhueta nova spawnada periodicamente, faz pulse.
const WHITE_FLASH_INTERVAL: float = 0.35
const WHITE_FLASH_FADE: float = 0.45
const WHITE_FLASH_COLOR: Color = Color(1.0, 1.0, 1.0, 0.35)

var _elapsed: float = 0.0
var _affected: Dictionary = {}  # enemy → SlowDebuff (pra refresh)
var _flash_timers: Dictionary = {}  # enemy → segundos restantes até próximo flash
var _wave_accum: float = 0.0
var _core: Polygon2D = null


func _ready() -> void:
	_create_visuals()
	# Spawna primeira onda imediatamente pra não esperar 0.55s pra primeira ripple.
	_spawn_wave()


func _create_visuals() -> void:
	# Core: disco cinza tênue (sem ring outline duro — borda suave via baixo alpha).
	_core = Polygon2D.new()
	_core.color = PULSE_COLOR_CORE
	var pts := PackedVector2Array()
	var segs: int = 32
	for i in segs:
		var ang: float = TAU * float(i) / float(segs)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	_core.polygon = pts
	_core.z_as_relative = false
	_core.z_index = 1
	add_child(_core)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		_finish()
		return
	# Pulso visual leve no core (oscilação sutil).
	if _core != null:
		var pulse: float = 1.0 + sin(_elapsed * 4.0) * 0.04
		_core.scale = Vector2(pulse, pulse)
	# Spawna ondas concêntricas em intervalos pra simular propagação.
	_wave_accum += delta
	if _wave_accum >= WAVE_SPAWN_INTERVAL:
		_wave_accum -= WAVE_SPAWN_INTERVAL
		_spawn_wave()
	_apply_field(delta)


func _spawn_wave() -> void:
	# Ring que parte do centro e expande até o raio do campo. Várias ondas
	# acumulam pra dar a sensação de propagação contínua.
	var ring := Line2D.new()
	ring.width = 1.8
	ring.default_color = WAVE_COLOR
	ring.closed = true
	var segs: int = 28
	for i in segs:
		var ang: float = TAU * float(i) / float(segs)
		ring.add_point(Vector2(cos(ang), sin(ang)) * 8.0)
	ring.z_as_relative = false
	ring.z_index = 0
	add_child(ring)
	var target_scale := Vector2(radius / 8.0, radius / 8.0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", target_scale, WAVE_EXPAND_DURATION)\
		.set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(ring, "modulate:a", 0.0, WAVE_EXPAND_DURATION)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(ring.queue_free)


func _apply_field(delta: float) -> void:
	# Itera inimigos no raio. Aplica/refresca slow + puxa pro centro + flash branco.
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		var e2d: Node2D = e
		var to_center: Vector2 = global_position - e2d.global_position
		var dist: float = to_center.length()
		if dist > radius:
			# Saiu da área: limpa tracking (flashes existentes auto-fadem).
			if _affected.has(e):
				_affected.erase(e)
			if _flash_timers.has(e):
				_flash_timers.erase(e)
			continue
		# CC immune: skip slow + pull (mas continua sofrendo dano da explosão final).
		if e.is_in_group("cc_immune"):
			continue
		# Garante slow ativo no inimigo dentro do campo.
		if not _affected.has(e):
			_apply_slow_to(e)
		# Pull leve pro centro (skip se já no centro pra evitar jitter).
		if dist > 4.0:
			var dir: Vector2 = to_center / dist
			e2d.global_position += dir * pull_strength * delta
		# Flash branco pulsante: spawna silhueta nova a cada WHITE_FLASH_INTERVAL,
		# e cada uma fade rapidinho — dá efeito "respirando" branco.
		var t: float = _flash_timers.get(e, 0.0)
		t -= delta
		if t <= 0.0:
			_spawn_white_flash(e2d)
			t = WHITE_FLASH_INTERVAL
		_flash_timers[e] = t


func _apply_slow_to(target: Node) -> void:
	for child in target.get_children():
		if child is CurseDebuff:
			_affected[target] = child
			return
		if child is SlowDebuff:
			(child as SlowDebuff).refresh(lifetime, slow_factor)
			_affected[target] = child
			return
	var deb := SlowDebuff.new()
	deb.duration = lifetime
	deb.slow_factor = slow_factor
	target.add_child(deb)
	_affected[target] = deb


func _spawn_white_flash(target: Node2D) -> void:
	# Silhueta branca leve via shader silhouette (mesmo padrão do curse_flash mas
	# branco e mais tênue). Cada flash fade individualmente pra criar pulse.
	var src_sprite: Node2D = _find_sprite_in(target)
	if src_sprite == null:
		return
	var sil := Sprite2D.new()
	if src_sprite is AnimatedSprite2D:
		var anim_sp: AnimatedSprite2D = src_sprite
		if anim_sp.sprite_frames == null:
			return
		var tex := anim_sp.sprite_frames.get_frame_texture(anim_sp.animation, anim_sp.frame)
		if tex == null:
			return
		sil.texture = tex
		sil.flip_h = anim_sp.flip_h
		sil.offset = anim_sp.offset
		sil.scale = anim_sp.scale
	elif src_sprite is Sprite2D:
		var st: Sprite2D = src_sprite
		sil.texture = st.texture
		sil.flip_h = st.flip_h
		sil.offset = st.offset
		sil.scale = st.scale
	else:
		return
	sil.position = src_sprite.position
	var mat := ShaderMaterial.new()
	mat.shader = SILHOUETTE_SHADER
	sil.material = mat
	sil.modulate = WHITE_FLASH_COLOR
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sil.z_index = 4
	target.add_child(sil)
	var tw := sil.create_tween()
	tw.tween_property(sil, "modulate:a", 0.0, WHITE_FLASH_FADE)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sil.queue_free)


func _find_sprite_in(node: Node) -> Node2D:
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child as Node2D
	return null


func _finish() -> void:
	if explosion_damage > 0.0:
		_explode()
	# Fade out do core (waves acabam por conta própria).
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)
	set_process(false)


func _explode() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		if not e.has_method("take_damage"):
			continue
		if (e as Node2D).global_position.distance_to(global_position) > radius:
			continue
		e.take_damage(explosion_damage)
		if source != null and source.has_method("notify_damage_dealt"):
			source.notify_damage_dealt(explosion_damage)
	# Burst da explosão.
	var burst := Polygon2D.new()
	var pts := PackedVector2Array()
	var segs: int = 32
	for i in segs:
		var ang: float = TAU * float(i) / float(segs)
		pts.append(Vector2(cos(ang), sin(ang)) * radius)
	burst.polygon = pts
	burst.color = EXPLOSION_COLOR
	burst.z_as_relative = false
	burst.z_index = 5
	burst.global_position = global_position
	get_parent().add_child(burst)
	var tw := burst.create_tween().set_parallel(true)
	tw.tween_property(burst, "scale", Vector2(1.5, 1.5), 0.30)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(burst, "modulate:a", 0.0, 0.30)
	tw.chain().tween_callback(burst.queue_free)
