extends MageEnemy

# Mago de gelo — variante do MageEnemy. Padrão de ataque: 2 tiros normais
# (mage_projectile pintado de branco/azul, atk speed um pouco mais rápido)
# + 1 bola de gelo lançada em arco que pousa numa área de slow (60% por 3s,
# atinge player e aliados). A área é 2× maior que a do Leno. Sem invocação
# de inseto (insect_scene null).

# Cena do projétil em arco (AoE slow ao pousar). Idêntico em estrutura ao
# fire_skill_projectile, mas spawna IceSlowArea em vez de FireField.
@export var ice_skill_projectile_scene: PackedScene
# Cena da área de slow que o projétil instancia ao pousar.
@export var ice_slow_area_scene: PackedScene
# Stats da área no chão.
@export var slow_multiplier: float = 0.63  # 0.63 = 37% slow (player.speed × 0.63)
@export var area_lifetime: float = 6.0
@export var area_scale: float = 1.0

# Skin: textura própria do ice mage. Reusa as MESMAS regiões do sheet base
# (32×32 com walk[3] + attack[3]) — só troca o atlas.
const ICE_MAGE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/ice mage.png")

# Tinta dos tiros normais — branco/azul claro.
const ICE_PROJ_TINT: Color = Color(0.7, 0.92, 1.0, 1.0)
const ICE_PROJ_TRAIL_TIP: Color = Color(0.55, 0.85, 1.0, 0.7)
const ICE_PROJ_TRAIL_HEAD: Color = Color(0.55, 0.85, 1.0, 0.0)

# A cada N ataques (incluindo o N-ésimo), dispara a AoE de slow em vez do
# tiro normal. 4 = "3 normais, 1 AoE".
const AOE_EVERY: int = 4

# Previsão de movimento do alvo: quando dispara a bola de gelo, o mago lê a
# velocity do player e mira em onde ele VAI estar quando a bola pousar (em vez
# da posição atual). Mantém o ARC_DURATION sincronizado com ice_skill_projectile.
const ICE_AOE_LEAD_TIME: float = 0.65
# Lead clamp pra previsão não disparar absurdamente longe se o player tiver
# velocity altíssimo (dash, etc) — só leva uma fração de segundo de movimento.
const ICE_AOE_MAX_LEAD_DISTANCE: float = 120.0


func _ready() -> void:
	super()
	# super() já adiciona ao grupo "mage" (insect_scene null) — adiciona o
	# subgrupo pra wave_manager / boss reconhecerem como ice_mage.
	add_to_group("ice_mage")
	_apply_ice_mage_skin()


func _apply_ice_mage_skin() -> void:
	# Mesmo padrão do fire_mage / summoner skin: duplica SpriteFrames +
	# AtlasTextures e troca atlas pra ICE_MAGE_TEXTURE. Sem isso vazaria nos
	# magos comuns que usam a mesma SpriteFrames.
	if sprite == null or sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = sprite.sprite_frames.duplicate(true)
	for anim_name: StringName in sf.get_animation_names():
		var n: int = sf.get_frame_count(anim_name)
		for i in n:
			var tex: Texture2D = sf.get_frame_texture(anim_name, i)
			if tex is AtlasTexture:
				var new_atlas: AtlasTexture = (tex as AtlasTexture).duplicate()
				new_atlas.atlas = ICE_MAGE_TEXTURE
				sf.set_frame(anim_name, i, new_atlas)
	sprite.sprite_frames = sf
	# super._ready já fez sprite.play("walk"). Re-dispara pra rodar com os
	# frames novos (trocar sprite_frames trava a animação corrente).
	if sprite.animation != "":
		sprite.play(sprite.animation)
	else:
		sprite.play("walk")


# Override: alterna entre tiro normal (branco/azul) e bola de gelo (AoE
# slow) seguindo o padrão "2 normais, 1 AoE". attack_count vem do parent
# (incrementado em _try_shoot ANTES desta função rodar).
func _fire_projectile() -> void:
	if attack_count > 0 and attack_count % AOE_EVERY == 0:
		_fire_ice_aoe()
	else:
		_fire_normal_shot()


func _fire_normal_shot() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	if "source_id" in proj:
		proj.source_id = "ice_mage"
	if "damage" in proj and damage_mult != 1.0:
		proj.damage = proj.damage * damage_mult
	# Curse-ally: marca projétil como ally_source (mira em enemy).
	if is_curse_ally and "is_ally_source" in proj:
		proj.is_ally_source = true
	if "apply_curse" in proj and is_curse_ally:
		proj.apply_curse = true
	_get_world().add_child(proj)
	proj.global_position = Vector2(muzzle.global_position.x, global_position.y + 2)
	if proj.has_method("set_direction"):
		proj.set_direction(locked_attack_dir)
	_apply_ice_projectile_skin(proj)


func _apply_ice_projectile_skin(proj: Node) -> void:
	# Mesmo padrão do _apply_summoner_projectile_skin no parent: tinge
	# sprite + glow + trail (com gradient duplicado pra não vazar).
	var s: Node = proj.get_node_or_null("AnimatedSprite2D")
	if s is CanvasItem:
		(s as CanvasItem).modulate = ICE_PROJ_TINT
	var glow: Node = proj.get_node_or_null("GlowLight")
	if glow is PointLight2D:
		(glow as PointLight2D).color = ICE_PROJ_TINT
	var trail: Node = proj.get_node_or_null("Trail")
	if trail is Line2D:
		var l: Line2D = trail as Line2D
		l.default_color = ICE_PROJ_TINT
		if l.gradient != null:
			var g: Gradient = l.gradient.duplicate() as Gradient
			g.colors = PackedColorArray([ICE_PROJ_TRAIL_HEAD, ICE_PROJ_TRAIL_TIP])
			l.gradient = g


func _fire_ice_aoe() -> void:
	if ice_skill_projectile_scene == null or ice_slow_area_scene == null:
		# Fallback: dispara um tiro normal pra não quebrar o ritmo se as
		# scenes não estiverem setadas no editor.
		_fire_normal_shot()
		return
	# Curse-ally: AI já trocou current_target pra inimigo. Mago normal mira
	# no player (mesmo padrão do fire_mage curse-flip).
	var target: Node2D = current_target if is_curse_ally else (player as Node2D)
	if target == null or not is_instance_valid(target):
		return
	var proj: Node2D = ice_skill_projectile_scene.instantiate()
	if "ice_slow_area_scene" in proj:
		proj.ice_slow_area_scene = ice_slow_area_scene
	if "slow_multiplier" in proj:
		proj.slow_multiplier = slow_multiplier
	if "area_lifetime" in proj:
		proj.area_lifetime = area_lifetime
	if "area_scale" in proj:
		proj.area_scale = area_scale
	# Mago normal: área é "enemy source" (slow em player+ally). Curse-ally:
	# área é "player source" (slow em enemies). Mesmo flip do fire_mage.
	if "is_enemy_source" in proj:
		proj.is_enemy_source = not is_curse_ally
	_get_world().add_child(proj)
	var spawn_pos: Vector2 = global_position + Vector2(0, -16)
	# Previsão de movimento: lê target.velocity (CharacterBody2D) e mira em
	# onde o alvo VAI estar quando a bola pousar. Clamp na distância máxima
	# pra evitar lead absurdo durante dash do player.
	var predicted: Vector2 = target.global_position
	if "velocity" in target:
		var lead: Vector2 = target.velocity * ICE_AOE_LEAD_TIME
		if lead.length() > ICE_AOE_MAX_LEAD_DISTANCE:
			lead = lead.normalized() * ICE_AOE_MAX_LEAD_DISTANCE
		predicted += lead
	var target_pos: Vector2 = predicted + Vector2(0, -10)
	if proj.has_method("setup"):
		proj.setup(spawn_pos, target_pos)
