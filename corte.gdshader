shader_type spatial;
render_mode depth_prepass_alpha;

global uniform float corte_y;
uniform vec4 cor : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float alpha_acima : hint_range(0.0, 1.0) = 0.25;

varying float altura_mundo;

void vertex() {
	altura_mundo = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	ALBEDO = cor.rgb;
	if (altura_mundo > corte_y) {
		ALPHA = alpha_acima;
	}
}
