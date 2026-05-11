shader_type canvas_item;

// Preenchimento (fill) da boss HP bar com máscara nas pontas via row-scan
// da arte da borda. Não desenha contorno — só decide onde fill_color aparece.
//
// O cap_tex é a textura ORIGINAL completa (40x24 no nosso caso). cap_uv_scale
// diz qual fração da textura corresponde ao cap (ex: 10/40 = 0.25 em x).

uniform sampler2D cap_tex : repeat_disable, filter_nearest;
uniform vec2 cap_uv_scale = vec2(0.25, 1.0);
uniform vec4 fill_color : source_color = vec4(0.78, 0.22, 0.85, 1.0);
uniform vec4 bg_color : source_color = vec4(0.18, 0.18, 0.2, 1.0);
uniform float bar_width = 240.0;
uniform float bar_height = 24.0;
uniform float cap_width = 10.0;
uniform float fill_ratio : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 px = UV * vec2(bar_width, bar_height);
	float u_y = UV.y;
	bool show_fill = false;

	if (px.x < cap_width) {
		float local_u = px.x / cap_width;
		for (int i = 0; i < 10; i++) {
			float scan_u = (float(i) + 0.5) / cap_width;
			if (scan_u <= local_u) {
				vec2 sample_uv = vec2(scan_u * cap_uv_scale.x, u_y * cap_uv_scale.y);
				if (texture(cap_tex, sample_uv).a > 0.5) {
					show_fill = true;
				}
			}
		}
	} else if (px.x > bar_width - cap_width) {
		float local_u = (bar_width - px.x) / cap_width;
		for (int i = 0; i < 10; i++) {
			float scan_u = (float(i) + 0.5) / cap_width;
			if (scan_u <= local_u) {
				vec2 sample_uv = vec2(scan_u * cap_uv_scale.x, u_y * cap_uv_scale.y);
				if (texture(cap_tex, sample_uv).a > 0.5) {
					show_fill = true;
				}
			}
		}
	} else {
		show_fill = true;
	}

	bool depleted = (px.x / bar_width) > fill_ratio;

	if (show_fill) {
		COLOR = depleted ? bg_color : fill_color;
	} else {
		COLOR = vec4(0.0);
	}
}
