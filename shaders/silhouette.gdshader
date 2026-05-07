shader_type canvas_item;

// Silhueta tintada: substitui o RGB do sprite pela cor do modulate (default
// branco, mas pode ser tintada — ex: heal flash usa verde). Preserva o alpha
// original do sprite × modulate.a (pra dar fade preservando o formato).
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(COLOR.rgb, tex.a * COLOR.a);
}
