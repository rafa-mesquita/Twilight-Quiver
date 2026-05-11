extends MageEnemy

# Mago de fogo — variante do MageEnemy. Único poder é a skill Q da flecha de
# fogo (fire_skill_projectile → FireField). Range maior pra ficar mais
# afastado, atk speed mais lento (área é forte). Sem invocação de inseto.
# Aparece no mapa do boss (mage_monkey).

# Cena do projétil em arco (mesmo do player) que pousa e spawna FireField.
@export var fire_skill_projectile_scene: PackedScene
# Cena do FireField que o projétil instancia ao pousar (passa adiante).
@export var fire_field_scene: PackedScene
# Stats do campo deixado no chão.
# Mesmos números do Q da Flecha de Fogo L3 (player_fire_skill): dps 12, 6s.
@export var field_dps: float = 12.0
@export var field_duration: float = 6.0
@export var field_scale: float = 1.0

# Skin: textura própria do fire mage (mesmas regiões do sheet base do mage,
# layout 32×32 com walk[3] + attack[3]).
const FIRE_MAGE_TEXTURE: Texture2D = preload("res://assets/enemies/mage/fire-mage-export.png")


func _ready() -> void:
	super()
	# super() chama o _ready do MageEnemy que adiciona ao grupo "mage" se
	# insect_scene == null. Adiciona o subgrupo "fire_mage" pra wave_manager
	# / boss reconhecer separado.
	add_to_group("fire_mage")
	_apply_fire_mage_skin()


func _apply_fire_mage_skin() -> void:
	# Mesmo padrão do _apply_summoner_skin do MageEnemy: duplica SpriteFrames +
	# AtlasTextures, troca atlas pra textura do fire mage. Sem isso vazaria
	# pros magos normais.
	if sprite == null or sprite.sprite_frames == null:
		return
	var sf: SpriteFrames = sprite.sprite_frames.duplicate(true)
	for anim_name: StringName in sf.get_animation_names():
		var n: int = sf.get_frame_count(anim_name)
		for i in n:
			var tex: Texture2D = sf.get_frame_texture(anim_name, i)
			if tex is AtlasTexture:
				var new_atlas: AtlasTexture = (tex as AtlasTexture).duplicate()
				new_atlas.atlas = FIRE_MAGE_TEXTURE
				sf.set_frame(anim_name, i, new_atlas)
	sprite.sprite_frames = sf
	# super._ready já chamou sprite.play("walk") ANTES desse método. Trocar o
	# sprite_frames trava a animação corrente — re-dispara pra rodar com os
	# frames novos.
	if sprite.animation != "":
		sprite.play(sprite.animation)
	else:
		sprite.play("walk")


# Override: em vez de spawnar mage_projectile (homing roxo), spawna o
# fire_skill_projectile (parábola). Mago normal mira no player + campo
# bate em player/ally/structure. Mago convertido pela maldição (curse_ally)
# inverte: mira no current_target (enemy) + campo bate em enemies.
func _fire_projectile() -> void:
	if fire_skill_projectile_scene == null or fire_field_scene == null:
		return
	# Curse-ally: AI já trocou current_target pra inimigo mais próximo. Mago
	# normal: mira sempre no player.
	var target: Node2D = current_target if is_curse_ally else (player as Node2D)
	if target == null or not is_instance_valid(target):
		return
	var proj: Node2D = fire_skill_projectile_scene.instantiate()
	if "source_id" in proj:
		proj.source_id = "fire_mage"
	if "fire_field_scene" in proj:
		proj.fire_field_scene = fire_field_scene
	if "field_dps" in proj:
		proj.field_dps = field_dps * damage_mult
	if "field_duration" in proj:
		proj.field_duration = field_duration
	if "field_scale" in proj:
		proj.field_scale = field_scale
	# Mago normal: campo é "enemy source" (machuca player+ally+structure, ignora
	# enemies). Curse-ally: campo é "player source" — bate em enemies como
	# qualquer FireField do player.
	if "is_enemy_source" in proj:
		proj.is_enemy_source = not is_curse_ally
	_get_world().add_child(proj)
	# Spawn na posição do mago (cabeça/cima), mira no centro do corpo do alvo.
	var spawn_pos: Vector2 = global_position + Vector2(0, -16)
	var target_pos: Vector2 = target.global_position + Vector2(0, -10)
	if proj.has_method("setup"):
		proj.setup(spawn_pos, target_pos)
