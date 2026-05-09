class_name CustomSelect
extends Button

# Dropdown custom — visual idêntico aos botões do main menu.
# Substitui OptionButton (que tem estilo nativo do OS) preservando padrão da UI.
#
# Uso:
#   sel.add_item("Janela")
#   sel.add_item("Tela cheia")
#   sel.select(0)
#   sel.item_selected.connect(func(idx): ...)

signal item_selected(index: int)

const _OPTION_HEIGHT: int = 56
const _POPUP_PAD: int = 8
const _OPTIONS_SEP: int = 6

var _items: Array = []
var _selected_index: int = -1
var _popup: PopupPanel
var _options_vbox: VBoxContainer


func _ready() -> void:
	pressed.connect(_open_popup)
	_build_popup()


func _build_popup() -> void:
	_popup = PopupPanel.new()
	add_child(_popup)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.13, 0.1, 0.18, 1)
	panel_style.border_color = Color(0.45, 0.32, 0.6, 1)
	panel_style.border_width_left = 4
	panel_style.border_width_top = 4
	panel_style.border_width_right = 4
	panel_style.border_width_bottom = 4
	panel_style.content_margin_left = _POPUP_PAD
	panel_style.content_margin_right = _POPUP_PAD
	panel_style.content_margin_top = _POPUP_PAD
	panel_style.content_margin_bottom = _POPUP_PAD
	_popup.add_theme_stylebox_override("panel", panel_style)
	_options_vbox = VBoxContainer.new()
	_options_vbox.add_theme_constant_override("separation", _OPTIONS_SEP)
	_popup.add_child(_options_vbox)


func add_item(text_str: String) -> void:
	_items.append(text_str)
	var btn := _make_option_button(text_str, _items.size() - 1)
	_options_vbox.add_child(btn)
	if _items.size() == 1:
		select(0)


func clear_items() -> void:
	_items.clear()
	_selected_index = -1
	for child in _options_vbox.get_children():
		child.queue_free()
	text = ""


func select(idx: int) -> void:
	if _items.is_empty():
		return
	_selected_index = clamp(idx, 0, _items.size() - 1)
	text = str(_items[_selected_index])


func get_selected() -> int:
	return _selected_index


func _make_option_button(text_str: String, idx: int) -> Button:
	var btn := Button.new()
	btn.text = text_str
	btn.custom_minimum_size = Vector2(0, _OPTION_HEIGHT)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Replica visual do CustomSelect (estilos definidos em custom_select.tscn).
	for state in ["normal", "hover", "pressed", "focus"]:
		if has_theme_stylebox_override(state):
			btn.add_theme_stylebox_override(state, get_theme_stylebox(state))
	for color_key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		if has_theme_color_override(color_key):
			btn.add_theme_color_override(color_key, get_theme_color(color_key))
	if has_theme_font_override("font"):
		btn.add_theme_font_override("font", get_theme_font("font"))
	if has_theme_font_size_override("font_size"):
		btn.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	btn.pressed.connect(_on_option_pressed.bind(idx))
	return btn


func _open_popup() -> void:
	if _items.is_empty():
		return
	var screen_pos: Vector2 = get_screen_position()
	var w: int = int(size.x)
	var content_h: int = _OPTION_HEIGHT * _items.size() + _OPTIONS_SEP * max(0, _items.size() - 1)
	var h: int = content_h + _POPUP_PAD * 2 + 8  # extra pra borda do panel
	_popup.popup(Rect2i(int(screen_pos.x), int(screen_pos.y + size.y + 4), w, h))


func _on_option_pressed(idx: int) -> void:
	select(idx)
	_popup.hide()
	item_selected.emit(idx)
