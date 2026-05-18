class_name BirthdayHat
extends Sprite2D

# Chapéu de festa que SEGUE o sprite principal do parent (player ou enemy).
# Polla o primeiro AnimatedSprite2D filho do parent a cada frame e espelha
# flip_h + inverte a posição X relativa quando o sprite vira pro outro lado.
# Sem isso, o chapéu fica no mesmo lugar no plano cartesiano enquanto o
# player/enemy vira, e parece "destacado" da cabeça.

var _base_position: Vector2 = Vector2.ZERO
var _tracked_sprite: AnimatedSprite2D = null


func _ready() -> void:
	_base_position = position
	_find_tracked_sprite()


func _find_tracked_sprite() -> void:
	# Acha o primeiro AnimatedSprite2D no parent (player tem $Body, enemies têm
	# $AnimatedSprite2D — convenção do projeto).
	var p := get_parent()
	if p == null:
		return
	for c in p.get_children():
		if c is AnimatedSprite2D:
			_tracked_sprite = c
			return


func _process(_delta: float) -> void:
	if _tracked_sprite == null or not is_instance_valid(_tracked_sprite):
		return
	var flipped: bool = _tracked_sprite.flip_h
	flip_h = flipped
	position = Vector2(-_base_position.x if flipped else _base_position.x, _base_position.y)
