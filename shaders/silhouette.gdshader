shader_type canvas_item;

// Silhueta branca: substitui o RGB do sprite por branco puro,
// preservando o alpha original × o modulate.a (pra dar fade).
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(1.0, 1.0, 1.0, tex.a * COLOR.a);
}
