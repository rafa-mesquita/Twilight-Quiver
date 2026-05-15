class_name AntiStuckHelper
extends RefCounted

# Helper anti-stuck pra walkers (inimigos/aliados que usam move_and_slide).
# Detecta "andando no mesmo lugar" (preso em árvore/parede/borda) e injeta
# uma direção lateral por alguns frames pra contornar o obstáculo.
#
# Uso típico no _physics_process do CharacterBody2D:
#   var dir := _anti_stuck.resolve(desired_dir, delta)
#   velocity = dir * speed + ...outros forces (separação, knockback)
#   move_and_slide()
#   _anti_stuck.update(self, anchor_pos, desired_dir.length() > 0.01, delta)
#
# `desired_dir` é a direção que a AI queria ir; `anchor_pos` é o ponto de
# referência (player, waypoint) — direção lateral rotaciona em torno dele.

# Cada quantos segundos verificar se houve progresso.
var check_interval: float = 0.25
# Quanto tempo dura o "sidestep" depois que detecta stuck.
var step_duration: float = 0.4
# Mínimo de distância percorrida no intervalo pra NÃO considerar stuck.
var min_progress: float = 3.0

var _check_timer: float = 0.0
var _step_timer: float = 0.0
var _step_dir: Vector2 = Vector2.ZERO
var _last_position: Vector2 = Vector2.ZERO
var _initialized: bool = false


# ANTES do move_and_slide: retorna a direção a usar. Em stuck-step retorna
# lateral; senão devolve a desejada (passthrough).
func resolve(desired_dir: Vector2, delta: float) -> Vector2:
	if _step_timer > 0.0:
		_step_timer = maxf(_step_timer - delta, 0.0)
		return _step_dir
	return desired_dir


# DEPOIS do move_and_slide: detecta stuck via delta de posição e arma o
# stuck_step se necessário. `was_trying_to_move` evita disparar stuck quando
# a AI deliberadamente parou (atacando, idle).
func update(node: Node2D, anchor_pos: Vector2, was_trying_to_move: bool, delta: float) -> void:
	if not _initialized:
		_initialized = true
		_last_position = node.global_position
		return
	if not was_trying_to_move or _step_timer > 0.0:
		_check_timer = 0.0
		_last_position = node.global_position
		return
	_check_timer += delta
	if _check_timer < check_interval:
		return
	_check_timer = 0.0
	var progress: float = node.global_position.distance_to(_last_position)
	_last_position = node.global_position
	if progress >= min_progress:
		return
	# Stuck: rotaciona 90° pra um lado random em torno do anchor.
	var to_anchor: Vector2 = anchor_pos - node.global_position
	if to_anchor.length_squared() < 0.01:
		return
	var to_dir: Vector2 = to_anchor.normalized()
	var s: float = -1.0 if randf() < 0.5 else 1.0
	_step_dir = to_dir.rotated(deg_to_rad(90.0) * s)
	_step_timer = step_duration
