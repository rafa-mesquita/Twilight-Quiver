extends Node2D

# AoE de impacto do Disparo de Pedra (elemental Pedra).
# One-shot: ao spawnar, aplica dano + knockback radial + stun em todos os
# inimigos no raio (exceto `exclude`, o alvo que já levou o hit direto da
# flecha), toca o visual de estouro de detritos e se auto-destrói.
#
# Spawnado pela arrow.gd em 3 gatilhos: acertar inimigo, cravar em estrutura,
# ou cair no fim do range (lifetime). Crítico aumenta a duração do stun.

@export var radius: float = 55.0
@export var damage: float = 25.0  # referência = dano direto da flecha
# % de `damage` aplicada em cada inimigo: 0.5 splash (hit direto) / 0.8 (queda).
@export var damage_pct: float = 0.8
@export var knockback_strength: float = 70.0
@export var stun_duration: float = 0.4
@export var source: Node = null  # quem disparou (player) — pra crit + notify
# Alvo que já tomou o hit direto da flecha: leva stun/knockback do AoE mas NÃO
# o dano splash (evita dupla contagem com o dano direto). null = pega todo mundo.
var exclude: Node = null
# Posição do estouro. Setada pelo spawner ANTES do add_child — o _ready aplica
# o AoE a partir daqui (setar global_position só funciona já dentro da árvore).
var origin: Vector2 = Vector2.ZERO

const STUN_VISUAL_SCRIPT: GDScript = preload("res://scripts/effects/stun_visual.gd")
const ROCK_IMPACT_TEXTURE: Texture2D = preload("res://assets/effects/Rock Arrow/Rock Arrow Impact.png")
const IMPACT_FRAME_W: int = 32
const IMPACT_FRAME_H: int = 32
const IMPACT_FRAMES: int = 3
const IMPACT_FPS: float = 18.0
# Onda sísmica que marca visualmente a ÁREA do stun (3 frames 31x31). Escalada
# pra cobrir o diâmetro do AoE (frame = raio → scale = raio*2/31).
const SEISMIC_TEXTURE: Texture2D = preload("res://assets/effects/Rock Arrow/SISMIC STUN-Sheet.png")
const SEISMIC_FRAME_W: int = 31
const SEISMIC_FRAME_H: int = 31
const SEISMIC_FRAMES: int = 3
const SEISMIC_FPS: float = 18.0
# Repete cada frame Nx pra deixar a anim mais lenta/cadenciada (3 frames × 6 =
# 18 frames). A opacidade decai ao longo da anim (fade no _spawn_visual).
const SEISMIC_REPEAT: int = 6


func _ready() -> void:
	global_position = origin
	_apply_aoe()
	_spawn_visual()


func _apply_aoe() -> void:
	var r_sq: float = radius * radius
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if e.is_queued_for_deletion():
			continue
		var e2d: Node2D = e
		var offset: Vector2 = e2d.global_position - global_position
		if offset.length_squared() > r_sq:
			continue
		# Stun + knockback radial pra TODO inimigo no raio (inclui o exclude).
		var stun: float = stun_duration
		var dealt_dmg: float = damage * damage_pct
		# Crit por inimigo (mesmo padrão do graviton). Crit amplia dano E stun.
		if source != null and source.has_method("roll_crit"):
			var crit: Dictionary = source.roll_crit()
			if bool(crit.get("crit", false)):
				var mult: float = float(crit.get("mult", 1.0))
				dealt_dmg *= mult
				stun *= mult
				CritFeedback.mark_next_hit_crit(e)
		# stun_duration 0 = estouro sem stun (não é a 1ª flecha do ataque; o gate
		# de stun fica no player, igual ao raio). Esse estouro só dá dano + kb.
		if stun > 0.0 and e.has_method("apply_stun"):
			e.apply_stun(stun)
			_ensure_stun_visual(e)
		if e.has_method("apply_knockback") and offset.length() > 1.0:
			e.apply_knockback(offset.normalized(), knockback_strength)
		# Dano splash: pula o alvo do hit direto (já levou dano cheio da flecha).
		if e == exclude:
			continue
		if not e.has_method("take_damage"):
			continue
		var was_alive: bool = (not ("hp" in e)) or float(e.hp) > 0.0
		e.take_damage(dealt_dmg)
		if source != null and source.has_method("notify_damage_dealt"):
			source.notify_damage_dealt(dealt_dmg)
		if source != null and source.has_method("notify_damage_dealt_by_source"):
			source.notify_damage_dealt_by_source(dealt_dmg, "stone_arrow")
		if was_alive and source != null and source.has_method("notify_kill_by_source"):
			if ("hp" in e) and float(e.hp) <= 0.0:
				source.notify_kill_by_source("stone_arrow")


func _ensure_stun_visual(target: Node) -> void:
	# Mesmo ícone de stun (stun.png) usado pelo Claudio Druida. Auto-destrói
	# quando _stun_remaining zera. Skip se o alvo já tem um ativo.
	if not is_instance_valid(target):
		return
	if not ("_stun_remaining" in target) or float(target._stun_remaining) <= 0.0:
		return
	for c in target.get_children():
		if c is Node and (c as Node).is_in_group("stun_visual"):
			return
	target.add_child(STUN_VISUAL_SCRIPT.new())


func _spawn_visual() -> void:
	# z_index = 0 nos dois (sem forçar): assim y-sortam com o mundo (Entities tem
	# y_sort_enabled) — ficam ATRÁS de árvores/objetos quando o impacto está
	# "acima" deles, e na frente quando abaixo. Forçar z jogava sempre pra frente.
	var seismic_dur: float = float(SEISMIC_FRAMES * SEISMIC_REPEAT) / SEISMIC_FPS
	# Onda sísmica no chão = indicador da ÁREA do STUN. Só aparece quando ESTE
	# estouro realmente stuna (1ª flecha do ataque). Estouros sem stun (extras do
	# Multi / ricochete) mostram só os detritos — sem a onda, pra não enganar.
	var has_stun: bool = stun_duration > 0.0
	if has_stun:
		# Escalada pro diâmetro do AoE (frame de 31px = raio → scale = raio*2/31),
		# centrada na origem. Cada frame repetido SEISMIC_REPEAT× pra ficar mais
		# lenta/cadenciada + fade de opacidade.
		var seismic := AnimatedSprite2D.new()
		seismic.sprite_frames = _build_frames(SEISMIC_TEXTURE, SEISMIC_FRAME_W, SEISMIC_FRAME_H, SEISMIC_FRAMES, SEISMIC_FPS, SEISMIC_REPEAT)
		seismic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var seismic_scale: float = (radius * 2.0) / float(SEISMIC_FRAME_W)
		seismic.scale = Vector2(seismic_scale, seismic_scale)
		add_child(seismic)
		seismic.play(&"default")
		# Fade: opacidade decai ao longo de toda a animação.
		var tw := seismic.create_tween()
		tw.tween_property(seismic, "modulate:a", 0.0, seismic_dur)

	# Detritos da pedra (Rock Arrow Impact.png — 3 frames 32x32) em tamanho
	# natural. Adicionado DEPOIS da sísmica → desenha por cima dela (mesmo z).
	var anim := AnimatedSprite2D.new()
	anim.sprite_frames = _build_frames(ROCK_IMPACT_TEXTURE, IMPACT_FRAME_W, IMPACT_FRAME_H, IMPACT_FRAMES, IMPACT_FPS)
	anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(anim)
	anim.play(&"default")
	anim.animation_finished.connect(anim.queue_free)
	# Libera o AoE quando o visual mais longo termina: com onda, ela segura o node;
	# sem onda (sem stun), os detritos curtos. Timer cobre os dois casos.
	var impact_dur: float = float(IMPACT_FRAMES) / IMPACT_FPS
	var life: float = (seismic_dur if has_stun else impact_dur) + 0.3
	get_tree().create_timer(life).timeout.connect(_die)


func _build_frames(tex: Texture2D, fw: int, fh: int, count: int, fps: float, repeat: int = 1) -> SpriteFrames:
	# Fatia uma sheet horizontal em `count` frames numa anim "default" (não loopa).
	# `repeat` duplica cada frame N vezes (deixa a anim mais lenta/cadenciada).
	var sf := SpriteFrames.new()
	sf.set_animation_loop(&"default", false)
	sf.set_animation_speed(&"default", fps)
	for i in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		for _r in repeat:
			sf.add_frame(&"default", atlas)
	return sf


func _die() -> void:
	if is_inside_tree():
		queue_free()
