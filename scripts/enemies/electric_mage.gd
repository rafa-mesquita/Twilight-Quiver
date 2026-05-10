extends MageEnemy

# Mago elétrico — variante do MageEnemy. Esqueleto básico: dispara o tiro
# normal (mage_projectile) tintado de amarelo elétrico. Poderes especiais
# serão adicionados depois.

# Skin: textura própria do electric mage (mesmas regiões do sheet base do
# mage, layout 32×32 com walk[3] + attack[3]).
const ELECTRIC_MAGE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/eletric mage.png")

# Tinta dos tiros — amarelo brilhante "elétrico".
const ELECTRIC_PROJ_TINT: Color = Color(1.0, 0.95, 0.4, 1.0)
const ELECTRIC_PROJ_TRAIL_TIP: Color = Color(1.0, 0.85, 0.3, 0.7)
const ELECTRIC_PROJ_TRAIL_HEAD: Color = Color(1.0, 0.85, 0.3, 0.0)


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


# Override: dispara o tiro normal pintado de amarelo elétrico. Mesma estrutura
# do fire_mage._fire_projectile pra curse-ally support.
func _fire_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
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
	_apply_electric_projectile_skin(proj)


func _apply_electric_projectile_skin(proj: Node) -> void:
	# Mesmo padrão do _apply_summoner_projectile_skin / _apply_ice_projectile_skin:
	# tinge sprite + glow + trail (com gradient duplicado pra não vazar).
	var s: Node = proj.get_node_or_null("AnimatedSprite2D")
	if s is CanvasItem:
		(s as CanvasItem).modulate = ELECTRIC_PROJ_TINT
	var glow: Node = proj.get_node_or_null("GlowLight")
	if glow is PointLight2D:
		(glow as PointLight2D).color = ELECTRIC_PROJ_TINT
	var trail: Node = proj.get_node_or_null("Trail")
	if trail is Line2D:
		var l: Line2D = trail as Line2D
		l.default_color = ELECTRIC_PROJ_TINT
		if l.gradient != null:
			var g: Gradient = l.gradient.duplicate() as Gradient
			g.colors = PackedColorArray([ELECTRIC_PROJ_TRAIL_HEAD, ELECTRIC_PROJ_TRAIL_TIP])
			l.gradient = g
