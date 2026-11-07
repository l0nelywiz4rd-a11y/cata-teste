shader_type spatial;
render_mode depth_prepass_alpha;

// ---- corte de andares (o que você já tinha) ----
global uniform float corte_y;
uniform vec4 cor : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform float alpha_acima : hint_range(0.0, 1.0) = 0.25;

// ---- visão e luz: preenchidos pelo script Visao em tempo de execução ----
// Cada célula do mapa é um pixel desta textura; o valor (canal R) é a ESCURIDÃO
// da célula: 0 = totalmente clara, 1 = preta.
uniform bool visao_ativa = false;
uniform sampler2D visao_tex : filter_nearest, repeat_disable;
uniform vec3 visao_canto = vec3(0.0);      // canto mínimo da célula de índice 0 (em coordenadas do mundo)
uniform vec3 visao_tamanho = vec3(2.0);    // tamanho de uma célula
uniform ivec3 visao_dim = ivec3(1);        // (largura x, camadas y, profundidade z)

varying float altura_mundo;
varying vec3 pos_mundo;
varying vec3 normal_mundo;

void vertex() {
	vec4 p = MODEL_MATRIX * vec4(VERTEX, 1.0);
	altura_mundo = p.y;
	pos_mundo = p.xyz;
	normal_mundo = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float escuridao = 0.0;
	bool andar_de_cima = altura_mundo > corte_y;   // sem a Visao: corte pela altura, como antes

	if (visao_ativa) {
		// Entra um pouquinho "pra dentro" do tile, pra uma face na borda
		// pertencer sempre à célula DELE e nunca à vizinha.
		vec3 p = pos_mundo - normal_mundo * 0.05 - visao_canto;
		ivec3 c = ivec3(floor(p / visao_tamanho));
		if (c.x >= 0 && c.x < visao_dim.x && c.y >= 0 && c.y < visao_dim.y && c.z >= 0 && c.z < visao_dim.z) {
			escuridao = texelFetch(visao_tex, ivec2(c.x, c.z + c.y * visao_dim.z), 0).r;
		}
		// Corte por CÉLULA: o tile inteiro é do andar de cima ou não é.
		// (Pela altura, a faixa de 0,1 na base do tile de cima ficava opaca: a "linha verde".)
		float base_da_celula = visao_canto.y + float(c.y) * visao_tamanho.y;
		andar_de_cima = base_da_celula > corte_y - visao_tamanho.y * 0.5;
	}

	ALBEDO = cor.rgb * (1.0 - escuridao);
	SPECULAR = 0.5 * (1.0 - escuridao);   // sem brilho residual: preto é preto

	if (andar_de_cima) {
		ALPHA = alpha_acima;
	}
}
