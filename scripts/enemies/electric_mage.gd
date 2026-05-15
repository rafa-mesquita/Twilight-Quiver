extends MageEnemy

# Mago elétrico — variante do MageEnemy. Único ataque: castar DOIS raios
# simultâneos (um na posição atual do alvo, outro na posição prevista pela
# velocidade × bolt_lead_time). Range alto, atk speed lento (6.25s entre
# ataques). Sem tiro normal e sem invocação.

# Cena do raio que pousa numa área e dá dano.
@export var lightning_bolt_scene: PackedScene
# Dano de cada raio (cada ataque solta 2 raios — total max 2× se ambos
# atingirem). Multiplicado pelo damage_mult do scaling de wave.
@export var bolt_damage: float = 12.75
# Tempo entre spawn do raio e impacto = FADE_IN_DURATION + frames-até-impacto.
# Usado como lead time pra previsão de movimento do alvo.
# Cálculo: 0.5s (fade) + 4/14 fps (frames até impacto) ≈ 0.79s.
@export var bolt_lead_time: float = 0.8

# Skin: textura própria do electric mage (mesmas regiões do sheet base do
# mage, layout 32×32 com walk[3] + attack[3]).
const ELECTRIC_MAGE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/eletric mage.png")

# Clamp da distância de lead — se o player tá em dash super-rápido, a
# previsão não dispara um raio absurdamente longe.
const BOLT_MAX_LEAD_DISTANCE: float = 180.0
# Se a previsão fica colada no alvo atual (player parado), aplica um pequeno
# offset aleatório no segundo raio pra dois círculos de dano distintos.
const BOLT_MIN_SEPARATION: float = 12.0
const BOLT_OFFSET_RADIUS: float = 24.0
# Sistema anti-stack: bolts ativos são tracked globalmente. Quando um novo
# bolt vai spawnar no mesmo lugar que outro ainda ativo, é empurrado pra fora.
# Evita o cenário de 2-3 magos elétricos castarem no mesmo ponto e one-shotar
# o player com dano cumulativo.
const BOLT_MIN_DISTANCE: float = 55.0  # > damage_radius (12) com folga
const BOLT_TRACK_DURATION_MSEC: int = 900  # ~tempo até impacto + buffer
const BOLT_DISPLACE_ATTEMPTS: int = 8
# Static: shared entre todos os electric_mages. Cada entry = {pos, expire_msec}.
static var _active_bolts: Array = []


func _ready() -> void:
	super()
	# super() já adiciona ao grupo "mage" (insect_scene null) — adiciona o
	# subgrupo pra wave_manager / boss reconhecerem como electric_mage.
	add_to_group("electric_mage")
	_apply_electric_mage_skin()


func _apply_electric_mage_skin() -> void:
	# Mesmo padrão do fire_mage / ice_mage / summoner skin: duplica
	# SpriteFrames + AtlasTextures e troca atlas pra ELECTRIC_MAGE_TEXTURE.
	if sprite == null or sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = sprite.sprite_frames.duplicate(true)
	for anim_name: StringName in sf.get_animation_names():
		var n: int = sf.get_frame_count(anim_name)
		for i in n:
			var tex: Texture2D = sf.get_frame_texture(anim_name, i)
			if tex is AtlasTexture:
				var new_atlas: AtlasTexture = (tex as AtlasTexture).duplicate()
				new_atlas.atlas = ELECTRIC_MAGE_TEXTURE
				sf.set_frame(anim_name, i, new_atlas)
	sprite.sprite_frames = sf
	if sprite.animation != "":
		sprite.play(sprite.animation)
	else:
		sprite.play("walk")


# Override completo: dispara DOIS raios simultâneos — um na posição atual do
# alvo, outro na posição prevista. Sem tiro normal nem fallback.
func _fire_projectile() -> void:
	if lightning_bolt_scene == null:
		return
	# Curse-ally: mira no current_target (enemy mais próximo). Mago normal:
	# mira no player.
	var target: Node2D = current_target if is_curse_ally else (player as Node2D)
	if target == null or not is_instance_valid(target):
		return
	# Bolt 1: posição atual do alvo.
	_spawn_bolt(target.global_position)
	# Bolt 2: posição prevista (target.velocity × bolt_lead_time, clampado).
	var predicted: Vector2 = target.global_position
	if "velocity" in target:
		var lead: Vector2 = (target.velocity as Vector2) * bolt_lead_time
		if lead.length() > BOLT_MAX_LEAD_DISTANCE:
			lead = lead.normalized() * BOLT_MAX_LEAD_DISTANCE
		predicted += lead
	# Se o alvo tava parado, a previsão é a mesma posição — força um offset
	# aleatório pequeno pra os dois raios não caírem no mesmo pixel.
	if (predicted - target.global_position).length() < BOLT_MIN_SEPARATION:
		var rand_angle: float = randf() * TAU
		predicted += Vector2(cos(rand_angle), sin(rand_angle)) * BOLT_OFFSET_RADIUS
	_spawn_bolt(predicted)


func _spawn_bolt(pos: Vector2) -> void:
	# Empurra a posição se algum bolt ativo já reservou essa área. Só aplica
	# pra bolts de mago original (mago convertido pela maldição não conta —
	# os bolts dele são "player source" e bater em enemies, não no player).
	if not is_curse_ally:
		pos = _displace_if_overlapping(pos)
		_active_bolts.append({
			"pos": pos,
			"expire_msec": Time.get_ticks_msec() + BOLT_TRACK_DURATION_MSEC,
		})
	var bolt: Node2D = lightning_bolt_scene.instantiate()
	if "damage" in bolt:
		bolt.damage = bolt_damage * damage_mult
	# Mago normal: raio é "enemy source" (bate em player+ally+structure).
	# Curse-ally: raio é "player source" — bate em enemies.
	if "is_enemy_source" in bolt:
		bolt.is_enemy_source = not is_curse_ally
	_get_world().add_child(bolt)
	bolt.global_position = pos


func _displace_if_overlapping(pos: Vector2) -> Vector2:
	# Limpa entries expiradas, depois tenta achar uma posição livre empurrando
	# o bolt pra fora dos ativos. Até BOLT_DISPLACE_ATTEMPTS tentativas — se
	# não achar (cenário denso), retorna a última tentativa.
	var now_msec: int = Time.get_ticks_msec()
	_active_bolts = _active_bolts.filter(
		func(entry): return int(entry["expire_msec"]) > now_msec
	)
	if _active_bolts.is_empty():
		return pos
	var min_dist_sq: float = BOLT_MIN_DISTANCE * BOLT_MIN_DISTANCE
	for attempt in BOLT_DISPLACE_ATTEMPTS:
		var conflict: Dictionary = {}
		for entry in _active_bolts:
			var existing_pos: Vector2 = entry["pos"]
			if pos.distance_squared_to(existing_pos) < min_dist_sq:
				conflict = entry
				break
		if conflict.is_empty():
			return pos
		var existing_pos2: Vector2 = conflict["pos"]
		var away: Vector2 = (pos - existing_pos2)
		if away.length_squared() < 0.01:
			# Mesmo ponto — gera direção aleatória pra empurrar.
			away = Vector2(cos(randf() * TAU), sin(randf() * TAU))
		else:
			away = away.normalized()
		pos = existing_pos2 + away * BOLT_MIN_DISTANCE
	return pos
