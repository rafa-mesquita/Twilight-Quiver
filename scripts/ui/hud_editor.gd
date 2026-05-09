extends CanvasLayer

# Painel HUD editor no canto inferior-esquerdo. Dropup: só o título visível
# por default; clica e o Content abre acima. Sliders aplicam ao vivo no HUD;
# Print Values loga no console pra commitar nos .tscn depois.

const HUD_FRAME_BASE := "Content/Scroll/VBox/HudFrameSection/HudFrameContent"
const WAVE_BASE := "Content/Scroll/VBox/WaveLabelSection/WaveLabelContent"

@onready var hud_frame_scale: HSlider = get_node(HUD_FRAME_BASE + "/HudFrameScaleRow/Slider")
@onready var hud_frame_scale_val: Label = get_node(HUD_FRAME_BASE + "/HudFrameScaleRow/Value")
@onready var hud_frame_x: HSlider = get_node(HUD_FRAME_BASE + "/HudFrameXRow/Slider")
@onready var hud_frame_x_val: Label = get_node(HUD_FRAME_BASE + "/HudFrameXRow/Value")
@onready var hud_frame_y: HSlider = get_node(HUD_FRAME_BASE + "/HudFrameYRow/Slider")
@onready var hud_frame_y_val: Label = get_node(HUD_FRAME_BASE + "/HudFrameYRow/Value")

@onready var wave_font_size: HSlider = get_node(WAVE_BASE + "/WaveFontRow/Slider")
@onready var wave_font_size_val: Label = get_node(WAVE_BASE + "/WaveFontRow/Value")
@onready var wave_label_x: HSlider = get_node(WAVE_BASE + "/WaveLabelXRow/Slider")
@onready var wave_label_x_val: Label = get_node(WAVE_BASE + "/WaveLabelXRow/Value")
@onready var wave_label_y: HSlider = get_node(WAVE_BASE + "/WaveLabelYRow/Slider")
@onready var wave_label_y_val: Label = get_node(WAVE_BASE + "/WaveLabelYRow/Value")
@onready var wave_label_w: HSlider = get_node(WAVE_BASE + "/WaveLabelWRow/Slider")
@onready var wave_label_w_val: Label = get_node(WAVE_BASE + "/WaveLabelWRow/Value")
@onready var wave_label_h: HSlider = get_node(WAVE_BASE + "/WaveLabelHRow/Slider")
@onready var wave_label_h_val: Label = get_node(WAVE_BASE + "/WaveLabelHRow/Value")

@onready var print_btn: Button = $Content/Scroll/VBox/PrintBtn
@onready var toggle_btn: Button = $Content/Scroll/VBox/ToggleHudBtn
@onready var main_toggle: Button = $MainToggle


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Setup das seções colapsáveis internas (cada uma alterna seu content).
	_setup_section($Content/Scroll/VBox/HudFrameSection/HudFrameHeader,
		$Content/Scroll/VBox/HudFrameSection/HudFrameContent, "HudFrame")
	_setup_section($Content/Scroll/VBox/WaveLabelSection/WaveLabelHeader,
		$Content/Scroll/VBox/WaveLabelSection/WaveLabelContent, "Wave Number Label")
	# Toggle principal: dropup do Content inteiro.
	main_toggle.pressed.connect(_on_main_toggle)
	# Lê valores atuais do HUD (defer pra HUD já estar pronta).
	_load_from_hud.call_deferred()
	hud_frame_scale.value_changed.connect(_on_hud_frame_scale_changed)
	hud_frame_x.value_changed.connect(_on_hud_frame_x_changed)
	hud_frame_y.value_changed.connect(_on_hud_frame_y_changed)
	wave_font_size.value_changed.connect(_on_wave_font_changed)
	wave_label_x.value_changed.connect(_on_wave_x_changed)
	wave_label_y.value_changed.connect(_on_wave_y_changed)
	wave_label_w.value_changed.connect(_on_wave_w_changed)
	wave_label_h.value_changed.connect(_on_wave_h_changed)
	print_btn.pressed.connect(_print_values)
	toggle_btn.pressed.connect(_toggle_hud_visible)


func _on_main_toggle() -> void:
	var content: Control = $Content
	content.visible = not content.visible
	main_toggle.text = "HUD EDITOR ▼" if content.visible else "HUD EDITOR ▲"


func _setup_section(header: Button, content: Control, label: String) -> void:
	header.text = ("[-] " if content.visible else "[+] ") + label
	header.pressed.connect(func() -> void:
		content.visible = not content.visible
		header.text = ("[-] " if content.visible else "[+] ") + label
	)


func _get_hud_frame() -> TextureRect:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return null
	return hud.get_node_or_null("HudFrame") as TextureRect


func _get_wave_label() -> Label:
	var hf := _get_hud_frame()
	if hf == null:
		return null
	return hf.get_node_or_null("WaveNumberLabel") as Label


func _load_from_hud() -> void:
	var hf := _get_hud_frame()
	if hf != null:
		hf.visible = true
		_set_slider_silently(hud_frame_scale, hf.scale.x)
		_set_slider_silently(hud_frame_x, hf.position.x)
		_set_slider_silently(hud_frame_y, hf.position.y)
		hud_frame_scale_val.text = "%.2f" % hf.scale.x
		hud_frame_x_val.text = "%d" % int(hf.position.x)
		hud_frame_y_val.text = "%d" % int(hf.position.y)
	var wl := _get_wave_label()
	if wl != null:
		var fs: int = wl.get_theme_font_size("font_size")
		if fs <= 0:
			fs = 11
		_set_slider_silently(wave_font_size, fs)
		_set_slider_silently(wave_label_x, wl.offset_left)
		_set_slider_silently(wave_label_y, wl.offset_top)
		_set_slider_silently(wave_label_w, wl.offset_right - wl.offset_left)
		_set_slider_silently(wave_label_h, wl.offset_bottom - wl.offset_top)
		wave_font_size_val.text = "%d" % fs
		wave_label_x_val.text = "%.2f" % wl.offset_left
		wave_label_y_val.text = "%.2f" % wl.offset_top
		wave_label_w_val.text = "%.2f" % (wl.offset_right - wl.offset_left)
		wave_label_h_val.text = "%.2f" % (wl.offset_bottom - wl.offset_top)


func _set_slider_silently(s: HSlider, v: float) -> void:
	s.set_block_signals(true)
	s.value = v
	s.set_block_signals(false)


func _on_hud_frame_scale_changed(v: float) -> void:
	var hf := _get_hud_frame()
	if hf != null:
		hf.scale = Vector2(v, v)
	hud_frame_scale_val.text = "%.2f" % v


func _on_hud_frame_x_changed(v: float) -> void:
	var hf := _get_hud_frame()
	if hf != null:
		hf.position.x = v
	hud_frame_x_val.text = "%d" % int(v)


func _on_hud_frame_y_changed(v: float) -> void:
	var hf := _get_hud_frame()
	if hf != null:
		hf.position.y = v
	hud_frame_y_val.text = "%d" % int(v)


func _on_wave_font_changed(v: float) -> void:
	var wl := _get_wave_label()
	if wl != null:
		wl.add_theme_font_size_override("font_size", int(v))
	wave_font_size_val.text = "%d" % int(v)


func _on_wave_x_changed(v: float) -> void:
	var wl := _get_wave_label()
	if wl != null:
		var w: float = wl.offset_right - wl.offset_left
		wl.offset_left = v
		wl.offset_right = v + w
	wave_label_x_val.text = "%.2f" % v


func _on_wave_y_changed(v: float) -> void:
	var wl := _get_wave_label()
	if wl != null:
		var h: float = wl.offset_bottom - wl.offset_top
		wl.offset_top = v
		wl.offset_bottom = v + h
	wave_label_y_val.text = "%.2f" % v


func _on_wave_w_changed(v: float) -> void:
	var wl := _get_wave_label()
	if wl != null:
		wl.offset_right = wl.offset_left + v
	wave_label_w_val.text = "%.2f" % v


func _on_wave_h_changed(v: float) -> void:
	var wl := _get_wave_label()
	if wl != null:
		wl.offset_bottom = wl.offset_top + v
	wave_label_h_val.text = "%.2f" % v


func _print_values() -> void:
	var hf := _get_hud_frame()
	var wl := _get_wave_label()
	print("===== HUD VALUES =====")
	if hf != null:
		print("HudFrame.scale = Vector2(%.2f, %.2f)" % [hf.scale.x, hf.scale.y])
		print("HudFrame.position = Vector2(%d, %d)" % [int(hf.position.x), int(hf.position.y)])
	if wl != null:
		var fs: int = wl.get_theme_font_size("font_size")
		print("WaveNumberLabel.font_size = %d" % fs)
		print("WaveNumberLabel.offset_left  = %.2f" % wl.offset_left)
		print("WaveNumberLabel.offset_top   = %.2f" % wl.offset_top)
		print("WaveNumberLabel.offset_right = %.2f" % wl.offset_right)
		print("WaveNumberLabel.offset_bottom= %.2f" % wl.offset_bottom)
	print("======================")


func _toggle_hud_visible() -> void:
	var hf := _get_hud_frame()
	if hf == null:
		return
	hf.visible = not hf.visible
