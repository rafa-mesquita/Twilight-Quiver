class_name CurseDebuff
extends Node

# Debuff de Maldição aplicado em inimigos pela flecha amaldiçoada.
# Filho do inimigo — quando inimigo é freed, CurseDebuff também é.
# Aplica:
#   - Slow: multiplica `speed` do inimigo por slow_factor (< 1.0).
#   - DoT: tick de dano periódico (similar ao BurnDoT).
# Re-aplicação refresca duração e mantém valores mais fortes (slow menor + dps maior).

@export var dps: float = 4.0
@export var duration: float = 4.0
@export var slow_factor: float = 0.65  # 0.65 = 35% slow
@export var tick_interval: float = 0.5

const SILHOUETTE_SHADER: Shader = preload("res://shaders/silhouette.gdshader")

var _remaining: float = 0.0
var _tick_accum: float = 0.0
var _original_speed: float = -1.0
var _purple_number_color: Color = Color(0.78, 0.45, 1.0, 1.0)
var _purple_flash_color: Color = Color(0.7, 0.3, 1.0, 0.75)


func _ready() -> void:
	_remaining = duration
	_apply_slow()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_restore_speed()
		queue_free()
		return
	_tick_accum += delta
	while _tick_accum >= tick_interval:
		_tick_accum -= tick_interval
		_apply_tick()
		if not is_inside_tree():
			return


func _apply_slow() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	# CC immune: skip slow (mantém DoT, só não mexe no speed).
	if parent.is_in_group("cc_immune"):
		return
	if not ("speed" in parent):
		return
	if _original_speed < 0.0:
		_original_speed = parent.speed
	parent.speed = _original_speed * slow_factor


func _restore_speed() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if "speed" in parent and _original_speed >= 0.0:
		parent.speed = _original_speed


func _apply_tick() -> void:
	var parent: Node = get_parent()
	if parent == null or not is_instance_valid(parent):
		return
	if not parent.has_method("take_damage"):
		return
	# Skip se o parent já está morto/morrendo — evita disparar damage_sound de
	# novo (que vive no world e gera som "continuo" após a morte).
	if parent.is_queued_for_deletion():
		return
	if "hp" in parent and float(parent.hp) <= 0.0:
		return
	var amount: float = dps * tick_interval
	parent.take_damage(amount)
	_spawn_curse_number(amount)
	if parent is Node2D and is_instance_valid(parent):
		_spawn_curse_flash(parent as Node2D)


func _spawn_curse_number(amount: float) -> void:
	# Damage number roxo pra distinguir do dano normal/queimadura.
	var parent: Node = get_parent()
	if parent == null or not (parent is Node2D):
		return
	var dmg_scene: PackedScene = load("res://scenes/damage_number.tscn") as PackedScene
	if dmg_scene == null:
		return
	var num: Node = dmg_scene.instantiate()
	if "amount" in num:
		num.amount = int(round(amount))
	if num is CanvasItem:
		(num as CanvasItem).modulate = _purple_number_color
	if num is Node2D:
		(num as Node2D).position = (parent as Node2D).global_position + Vector2(0, -28)
	get_tree().current_scene.add_child(num)


func _spawn_curse_flash(target: Node2D) -> void:
	# Silhueta roxa no formato exato do enemy via silhouette shader (mesmo
	# pattern do heal flash do woodwarden). Fade rápido pra não acumular
	# entre os ticks de 0.5s.
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
	sil.modulate = _purple_flash_color
	sil.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sil.z_index = 5
	target.add_child(sil)
	var tw := sil.create_tween()
	tw.tween_property(sil, "modulate:a", 0.0, 0.30)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(sil.queue_free)


func _find_sprite_in(node: Node) -> Node2D:
	for child in node.get_children():
		if child is AnimatedSprite2D or child is Sprite2D:
			return child as Node2D
	return null


# Cleanup explícito: restaura speed e remove. Usado por convert_to_ally pra
# garantir que o aliado convertido não fique permanentemente lento (queue_free
# direto não chama _restore_speed; só o _process com _remaining<=0 chama).
func release() -> void:
	_restore_speed()
	queue_free()


# Refresca duração se nova flecha amaldiçoada bate no mesmo alvo.
# Mantém o `dps` mais alto e o `slow_factor` mais forte (menor).
func refresh(new_duration: float, new_dps: float, new_slow_factor: float) -> void:
	_remaining = maxf(_remaining, new_duration)
	if new_dps > dps:
		dps = new_dps
	if new_slow_factor < slow_factor:
		slow_factor = new_slow_factor
		_apply_slow()  # re-aplica com slow mais forte
