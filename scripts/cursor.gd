extends CanvasLayer

@export var frame_size: Vector2i = Vector2i(33, 33)
@export var frame_count: int = 6
@export var fps: float = 8.0

@onready var sprite: Sprite2D = $Sprite2D

var _t: float = 0.0
var _frame: int = 0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	process_mode = Node.PROCESS_MODE_ALWAYS
	sprite.region_enabled = true
	_apply_frame()
	print("[cursor] ready, frames=", frame_count, " size=", frame_size)


func _process(delta: float) -> void:
	sprite.global_position = sprite.get_global_mouse_position()
	_t += delta
	var step := 1.0 / fps
	while _t >= step:
		_t -= step
		_frame = (_frame + 1) % frame_count
		_apply_frame()


func _apply_frame() -> void:
	sprite.region_rect = Rect2(_frame * frame_size.x, 0, frame_size.x, frame_size.y)
