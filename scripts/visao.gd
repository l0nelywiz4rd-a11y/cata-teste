class_name Visao
extends Node
## Visão estilo Cataclysm, em três ideias que se combinam:
##   1. CAMPO DE VISÃO: o que não está atrás de uma parede (opaca).
##   2. LUZ: dia/noite (luz_ambiente) + fontes de luz (FonteDeLuz). Sem luz, não enxerga.
##   3. MEMÓRIA: o que você já viu fica escurecido, mas continua no mapa.
## Visualmente, cada tile fora de vista ganha uma caixa preta por cima (a "neblina"),
## mais ou menos transparente conforme a luz. Criaturas fora de vista ficam escondidas.

@export var alcance := 12   # distância máxima de visão, em células
@export_range(0.0, 1.0) var luz_ambiente := 1.0:   # 1 = dia claro, 0 = noite fechada
	set(valor):
		luz_ambiente = valor
		_sujo = true

const LUZ_MINIMA := 0.15        # abaixo disso a célula é escura demais pra enxergar
const LUZ_VIZINHA := 0.35       # células coladas em você sempre aparecem, com pelo menos isso
# A escuridão segue sempre esta ordem:  iluminado < pouca luz < memória < nunca visto
const ESCURIDAO_MAX := 0.7      # escuridão de uma célula VISÍVEL sem nenhuma luz (escala 0 a isso)
const ESCURIDAO_MEMORIA := 0.8  # escuridão do que você já viu, mas não vê agora
const INTERVALO := 0.3          # a cada quanto tempo recalcula (pra luzes que se movem)

var mapa: MapaGrid
var jogador: Ator

# Vector3i (célula) -> brilho de 0 a 1. É o que você enxerga AGORA.
var visiveis := {}
# Vector3i -> true. Tudo que você já enxergou alguma vez.
var explorados := {}

var _sujo := true
var _tempo := 0.0
var _neblina: MultiMeshInstance3D


func _ready() -> void:
	# Espera todo mundo terminar o _ready (o jogador só entra no grupo lá).
	_iniciar.call_deferred()


func _iniciar() -> void:
	mapa = get_tree().get_first_node_in_group("mapa") as MapaGrid
	jogador = get_tree().get_first_node_in_group("jogador") as Ator
	if mapa == null or jogador == null:
		push_warning("Visao: não achei o mapa (grupo 'mapa') ou o jogador (grupo 'jogador').")
		return
	jogador.celula_mudou.connect(func(_c): _sujo = true)
	_criar_neblina()
	recalcular()


func _process(delta: float) -> void:
	if jogador == null:
		return
	_tempo += delta
	if _sujo or _tempo >= INTERVALO:
		recalcular()
	_atualizar_atores()


# =====================================================================
#  CONSULTAS PÚBLICAS
# =====================================================================

func esta_visivel(c: Vector3i) -> bool:
	return visiveis.has(c)


func brilho_em(c: Vector3i) -> float:
	return visiveis.get(c, 0.0)


# O quão escura a célula deve ser desenhada: 0 = totalmente clara, 1 = preta.
func escuridao_em(c: Vector3i) -> float:
	if visiveis.has(c):
		return (1.0 - visiveis[c]) * ESCURIDAO_MAX      # à vista: depende da luz
	if explorados.has(c):
		return ESCURIDAO_MEMORIA                         # já vista, fora de vista agora
	return 1.0                                           # nunca vista


# =====================================================================
#  O CÁLCULO
# =====================================================================

func recalcular() -> void:
	_sujo = false
	_tempo = 0.0

	var origem := jogador.celula
	var camada := origem.y

	var luz := _calcular_luz(camada)                       # luz das fontes
	var campo := mapa.campo_de_visao(origem, alcance)      # o que não está atrás de parede

	visiveis.clear()
	for coluna in campo:
		var nivel: float = maxf(luz_ambiente, luz.get(coluna, 0.0))
		var perto: bool = campo[coluna] <= 1.5
		if nivel < LUZ_MINIMA and not perto:
			continue    # escuro demais e longe: não enxerga
		if perto:
			nivel = maxf(nivel, LUZ_VIZINHA)
		_revelar_coluna(coluna, camada, nivel)

	_atualizar_neblina(camada)


# Marca como visível a célula da camada do jogador e tudo que está embaixo dela
# até o primeiro tile (o chão). Assim buracos mostram o fundo.
func _revelar_coluna(coluna: Vector2i, camada: int, nivel: float) -> void:
	var y := camada
	while y >= Ator.Y_MINIMO:
		var c := Vector3i(coluna.x, y, coluna.y)
		visiveis[c] = maxf(visiveis.get(c, 0.0), nivel)
		explorados[c] = true
		if y < camada and mapa.get_cell_item(c) != -1:
			break   # achou o chão
		y -= 1


# Luz de cada FonteDeLuz, que também não atravessa paredes opacas.
# Devolve Dictionary: Vector2i (coluna) -> brilho.
func _calcular_luz(camada: int) -> Dictionary:
	var luz := {}
	for no in get_tree().get_nodes_in_group("fontes_luz"):
		var fonte := no as FonteDeLuz
		if fonte == null or fonte.raio <= 0:
			continue
		var c := mapa.local_to_map(mapa.to_local(fonte.global_position))
		if c.y != camada:
			continue    # só ilumina a própria camada
		var campo := mapa.campo_de_visao(c, fonte.raio)
		for coluna in campo:
			var brilho: float = fonte.forca * (1.0 - campo[coluna] / (fonte.raio + 1.0))
			if brilho > luz.get(coluna, 0.0):
				luz[coluna] = brilho
	return luz


# Criaturas fora do seu campo de visão ficam escondidas.
func _atualizar_atores() -> void:
	for no in get_tree().get_nodes_in_group("atores"):
		var ator := no as Ator
		if ator == null or ator == jogador:
			continue
		var c := ator.celula
		# também vale quem está em cima de algo que você vê (um degrau, outro ator...)
		ator.visible = visiveis.has(c) or visiveis.has(c + Vector3i.DOWN)


# =====================================================================
#  A NEBLINA (visual)
# =====================================================================
# Uma caixa preta, um pouco maior que a célula, sobre cada tile que você não vê direito.
# Tudo numa MultiMesh: milhares de caixas num único desenho.

func _criar_neblina() -> void:
	var caixa := BoxMesh.new()
	caixa.size = mapa.cell_size * 1.01

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	# Os tiles (shader de corte) também são transparentes, e a Godot desenha transparentes
	# por distância. Prioridade alta = a neblina é SEMPRE desenhada por último, por cima.
	material.render_priority = 100
	caixa.material = material

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D   # estas duas linhas vêm ANTES
	mm.use_colors = true                            # do instance_count
	mm.mesh = caixa
	mm.instance_count = maxi(mapa.get_used_cells().size(), 1)
	mm.visible_instance_count = 0

	_neblina = MultiMeshInstance3D.new()
	_neblina.multimesh = mm
	_neblina.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mapa.add_child(_neblina)


func _atualizar_neblina(camada: int) -> void:
	var mm := _neblina.multimesh
	var usadas := mapa.get_used_cells()
	if usadas.size() > mm.instance_count:
		mm.instance_count = usadas.size()   # o mapa cresceu

	var i := 0
	for c in usadas:
		if c.y > camada:
			continue   # andares de cima já são tratados pelo shader de corte
		var escuridao := escuridao_em(c)
		if escuridao <= 0.01:
			continue   # totalmente iluminado: sem caixa
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, mapa.map_to_local(c)))
		mm.set_instance_color(i, Color(0, 0, 0, escuridao))
		i += 1
	mm.visible_instance_count = i
