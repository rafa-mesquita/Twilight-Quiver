extends Node2D

# Projétil de gelo invocado pela Frostwisp — cai do céu, pousa numa posição
# alvo, e dá dano + slow em AoE pequena. Crit rolls aplicam normalmente
# (source "frostwisp" no painel de dano — separado de ice_arrow do player).

@export var land_position: Vector2 = Vector2.ZERO
@export var damage: float = 8.0
@export var slow_factor: float = 0.55
@export var slow_duration: float = 1.5
@export var aoe_radius: float = 26.0
@export var fall_speed: float = 480.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _landed: bool = false


func _ready() -> void:
	# freeze_immune: durante o Time Freeze (L4) o projétil continua caindo e
	# explodindo — dá dano nos inimigos congelados. take_damage funciona normal
	# mesmo em nodes com process_mode = DISABLED.
	add_to_group("freeze_immune")
	if sprite != null:
		sprite.play("projectile")


func _physics_process(delta: float) -> void:
	if _landed:
		return
	var to_land: float = land_position.y - global_position.y
	if to_land <= 0.5:
		_land()
		return
	var step: float = minf(fall_speed * delta, to_land)
	global_position.y += step


func _land() -> void:
	_landed = true
	global_position = land_position
	# Crit roll por hit. Se Flechas Críticas comprado, dano pode ser amplificado.
	var p := get_tree().get_first_node_in_group("player")
	# AoE damage + slow nos inimigos no raio
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).is_queued_for_deletion():
			continue
		if "hp" in e and float(e.hp) <= 0.0:
			continue
		var dist: float = (e as Node2D).global_position.distance_to(land_position)
		if dist > aoe_radius:
			continue
		if e.has_method("take_damage"):
			var dmg: float = damage
			# Crit roll por alvo — usa o roll_crit do player se disponível.
			if p != null and p.has_method("roll_crit"):
				var crit: Dictionary = p.roll_crit()
				dmg *= float(crit.get("mult", 1.0))
				if bool(crit.get("crit", false)):
					CritFeedback.mark_next_hit_crit(e)
			var was_alive: bool = (not ("hp" in e)) or float(e.hp) > 0.0
			e.take_damage(dmg)
			if p != null and p.has_method("notify_damage_dealt_by_source"):
				p.notify_damage_dealt_by_source(dmg, "frostwisp")
			if was_alive and p != null and p.has_method("notify_kill_by_source"):
				if "hp" in e and float(e.hp) <= 0.0:
					p.notify_kill_by_source("frostwisp")
		_apply_slow(e)
	_spawn_splash()
	queue_free()


func _apply_slow(target: Node) -> void:
	# Skip se tem FreezeDebuff (frozen tem stack próprio) ou CurseDebuff (slow + DoT já).
	for c in target.get_children():
		if c is FreezeDebuff:
			return
		if c is CurseDebuff:
			return
	if not ("speed" in target):
		return
	for c in target.get_children():
		if c is SlowDebuff:
			(c as SlowDebuff).refresh(slow_duration, slow_factor)
			return
	var deb := SlowDebuff.new()
	deb.duration = slow_duration
	deb.slow_factor = slow_factor
	target.add_child(deb)


func _spawn_splash() -> void:
	var p := CPUParticles2D.new()
	p.amount = 10
	p.lifetime = 0.4
	p.one_shot = true
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.0
	p.spread = 180.0
	p.initial_velocity_min = 20.0
	p.initial_velocity_max = 60.0
	p.gravity = Vector2.ZERO
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.6
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([
		Color(0.7, 0.9, 1.0, 0.9),
		Color(0.7, 0.9, 1.0, 0.0),
	])
	p.color_ramp = ramp
	get_tree().current_scene.add_child(p)
	if p is Node2D:
		(p as Node2D).global_position = land_position
	var tw := p.create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(p.queue_free)
