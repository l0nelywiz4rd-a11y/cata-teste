class_name Visao
extends Node
## Visão estilo Cataclysm, em três ideias que se combinam:
##   1. CAMPO DE VISÃO: o que não está atrás de uma parede (opaca).
##   2. LUZ: dia/noite (luz_ambiente) + fontes de luz (FonteDeLuz). Sem luz, não enxerga.
##   3. MEMÓRIA: o que você já viu fica escurecido, mas continua no mapa.
## Visualmente, o shader dos tiles (corte.gdshader) lê uma textura onde cada pixel é uma
## célula do mapa e diz o quão escura ela deve ser. Nada é desenhado por cima: o próprio
## tile escurece, então não existem emendas nem linhas.
## Criaturas fora de vista ficam escondidas.

@export var alcance := 12   # distância máxima de visão, em células
@export_range(0.0, 1.0) var luz_ambiente := 1.0:   # 1 = dia claro, 0 = noite fechada
	set(valor):
		luz_ambiente = valor
		_sujo = true

@export_range(0.0, 1.0) var luz_interior := 0.2:   # quanto da luz do dia chega sob um teto (0 = escuridão total)
	set(valor):
		luz_interior = valor
		_sujo = true

const ALCANCE_Z := 2            # quantos andares acima/abaixo uma fonte de luz alcança
const CACHE_LUZ_MS := 2000      # fontes paradas reaproveitam o cálculo por esse tempo
const VIZINHOS := [Vector3i.UP, Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
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

# Textura de escuridão: largura = nº de colunas x do mapa; altura = profundidade z * camadas,
# com as camadas empilhadas (a célula (x, y, z) fica no pixel (x, z + y * profundidade)).
var _imagem: Image
var _textura: ImageTexture
var _min := Vector3i.ZERO     # menor célula usada pelo mapa (vira o pixel 0)
var _dim := Vector3i.ONE      # tamanho do mapa em células: (x, camadas, z)
var _camada_textura := -999   # camada do jogador na última atualização
var _y_max := 0               # camada mais alta do mapa (pra procurar teto)
var _topo_opaco := {}         # coluna -> y do tile opaco mais alto (cache de UM recálculo)
var _cache_luz := {}          # Vector4i(célula, raio) -> [quando, campo de luz]


func _ready() -> void:
	add_to_group("visao")
	# Espera todo mundo terminar o _ready (o jogador só entra no grupo lá).
	_iniciar.call_deferred()


func _iniciar() -> void:
	mapa = get_tree().get_first_node_in_group("mapa") as MapaGrid
	jogador = get_tree().get_first_node_in_group("jogador") as Ator
	if mapa == null or jogador == null:
		push_warning("Visao: não achei o mapa (grupo 'mapa') ou o jogador (grupo 'jogador').")
		return
	jogador.celula_mudou.connect(func(_c): _sujo = true)
	preparar_textura()
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
	var antes := visiveis.duplicate()   # o que estava à vista antes (pra saber o que mudou)
	_topo_opaco.clear()

	var origem := jogador.celula
	var camada := origem.y

	var luz := _calcular_luz(origem)                       # luz das fontes, em 3D
	var campo: Dictionary = mapa.campo_de_visao(origem, alcance)   # o que não está atrás de parede

	visiveis.clear()
	for coluna in campo:
		var perto: bool = campo[coluna] <= 1.5
		var nivel_topo := _nivel_em(Vector3i(coluna.x, camada, coluna.y), luz)
		if nivel_topo < LUZ_MINIMA and not perto:
			continue    # escuro demais e longe: não enxerga
		_revelar_coluna(coluna, camada, luz, perto)

	_atualizar_textura(camada, antes)


# Marca como visível a célula da camada do jogador e tudo que está embaixo dela
# até o primeiro tile (o chão). Assim buracos mostram o fundo.
# Cada célula tem a SUA luz (um fundo de poço pode estar mais escuro que a borda).
func _revelar_coluna(coluna: Vector2i, camada: int, luz: Dictionary, perto: bool) -> void:
	var y := camada
	while y >= Ator.Y_MINIMO:
		var c := Vector3i(coluna.x, y, coluna.y)
		var nivel := _nivel_em(c, luz)
		if perto:
			nivel = maxf(nivel, LUZ_VIZINHA)
		visiveis[c] = nivel
		explorados[c] = true
		if y < camada and mapa.get_cell_item(c) != -1:
			break   # achou o chão
		y -= 1


# =====================================================================
#  LUZ: dia sob o céu, dia sob um teto, e fontes em 3D
# =====================================================================

# Tem algum tile opaco ACIMA dessa célula, na mesma coluna? Então a luz do dia não chega.
func esta_exposto_ao_ceu(c: Vector3i) -> bool:
	var coluna := Vector2i(c.x, c.z)
	var topo: int
	if _topo_opaco.has(coluna):
		topo = _topo_opaco[coluna]
	else:
		topo = -100000   # nenhum tile opaco na coluna
		for y in range(_y_max, _min.y - 1, -1):
			if mapa.eh_opaco(Vector3i(c.x, y, c.z)):
				topo = y
				break
		_topo_opaco[coluna] = topo
	return topo <= c.y   # o próprio tile (ou nada) no topo: céu aberto


# Luz de uma célula ABERTA (ar): dia (se tiver céu, ou uma fração sob teto) ou fontes.
func _nivel_aberto(c: Vector3i, luz: Dictionary) -> float:
	var dia := luz_ambiente if esta_exposto_ao_ceu(c) else luz_ambiente * luz_interior
	return maxf(dia, luz.get(c, 0.0))


# Luz de qualquer célula. Um tile opaco (chão, parede) não tem luz própria:
# recebe a do ar vizinho (em cima e nos lados).
func _nivel_em(c: Vector3i, luz: Dictionary) -> float:
	if not mapa.eh_opaco(c):
		return _nivel_aberto(c, luz)
	var melhor := 0.0
	for d in VIZINHOS:
		var v: Vector3i = c + d
		if not mapa.eh_opaco(v):
			melhor = maxf(melhor, _nivel_aberto(v, luz))
	return melhor


# Brilho das FonteDeLuz em cada célula aberta, em 3D (alcançam andares próximos,
# por buracos e escadas, e não atravessam chão, teto ou parede).
# Devolve Dictionary: Vector3i -> brilho.
func _calcular_luz(origem: Vector3i) -> Dictionary:
	var luz := {}
	for no in get_tree().get_nodes_in_group("fontes_luz"):
		var fonte := no as FonteDeLuz
		if fonte == null or fonte.raio <= 0:
			continue
		var c := mapa.local_to_map(mapa.to_local(fonte.global_position))
		# longe demais pra interessar (horizontal) ou só ilumina andares acima de nós
		if maxi(absi(c.x - origem.x), absi(c.z - origem.z)) > alcance + fonte.raio:
			continue
		if c.y - ALCANCE_Z > origem.y:
			continue
		var campo: Dictionary = _campo_de_luz_cacheado(c, fonte.raio)
		for alvo in campo:
			var brilho: float = fonte.forca * (1.0 - campo[alvo] / (fonte.raio + 1.0))
			if brilho > luz.get(alvo, 0.0):
				luz[alvo] = brilho
	return luz


# O campo de uma fonte PARADA só precisa ser refeito de vez em quando.
func _campo_de_luz_cacheado(c: Vector3i, raio: int) -> Dictionary:
	var agora := Time.get_ticks_msec()
	var chave := Vector4i(c.x, c.y, c.z, raio)
	if _cache_luz.size() > 64:
		_cache_luz.clear()   # fontes que andam deixam lixo; limpa de vez em quando
	var entrada = _cache_luz.get(chave)
	if entrada == null or agora - entrada[0] > CACHE_LUZ_MS:
		entrada = [agora, mapa.campo_de_luz(c, raio, ALCANCE_Z)]
		_cache_luz[chave] = entrada
	return entrada[1]


# Esqueça o cache de luz (chame se mudar tiles em tempo de execução).
func invalidar_luz() -> void:
	_cache_luz.clear()
	_sujo = true


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
#  A TEXTURA DE ESCURIDÃO (visual)
# =====================================================================

# Cria a textura do tamanho do mapa e entrega pros materiais dos tiles.
# Chame de novo se o mapa crescer (tiles fora da área original).
func preparar_textura() -> void:
	var usadas := mapa.get_used_cells()
	if usadas.is_empty():
		push_warning("Visao: o mapa está vazio.")
		return

	var minimo: Vector3i = usadas[0]
	var maximo: Vector3i = usadas[0]
	for c in usadas:
		minimo = Vector3i(mini(minimo.x, c.x), mini(minimo.y, c.y), mini(minimo.z, c.z))
		maximo = Vector3i(maxi(maximo.x, c.x), maxi(maximo.y, c.y), maxi(maximo.z, c.z))
	_min = minimo
	_dim = maximo - minimo + Vector3i.ONE
	_y_max = maximo.y

	var altura_textura := _dim.z * _dim.y
	if _dim.x > 16384 or altura_textura > 16384:
		push_error("Visao: mapa grande demais pra textura (%d x %d)." % [_dim.x, altura_textura])
		return

	_imagem = Image.create_empty(_dim.x, altura_textura, false, Image.FORMAT_R8)
	_imagem.fill(Color(1, 0, 0, 1))   # começa tudo como "nunca visto"
	_textura = ImageTexture.create_from_image(_imagem)
	_camada_textura = -999

	# canto mínimo da célula _min, em coordenadas do mundo
	var canto := mapa.to_global(mapa.map_to_local(_min) - mapa.cell_size * 0.5)
	var materiais := _materiais_dos_tiles()
	for m in materiais:
		m.set_shader_parameter("visao_tex", _textura)
		m.set_shader_parameter("visao_canto", canto)
		m.set_shader_parameter("visao_tamanho", mapa.cell_size)
		m.set_shader_parameter("visao_dim", _dim)
		m.set_shader_parameter("visao_ativa", true)
	if materiais.is_empty():
		push_warning("Visao: nenhum tile usa o corte.gdshader novo, então nada vai escurecer.")


# Acha os ShaderMaterial dos tiles da MeshLibrary que sabem receber a textura.
func _materiais_dos_tiles() -> Array[ShaderMaterial]:
	var lista: Array[ShaderMaterial] = []
	var biblioteca := mapa.mesh_library
	if biblioteca == null:
		return lista
	for id in biblioteca.get_item_list():
		var malha := biblioteca.get_item_mesh(id)
		if malha == null:
			continue
		for superficie in malha.get_surface_count():
			var material := malha.surface_get_material(superficie) as ShaderMaterial
			if material == null or material.shader == null:
				push_warning("Visao: o tile %d (%s) não usa o corte.gdshader, então não vai escurecer. Re-exportou a MeshLibrary?"
					% [id, biblioteca.get_item_name(id)])
				continue
			if lista.has(material):
				continue
			var aceita := false
			for u in material.shader.get_shader_uniform_list():
				if u["name"] == "visao_tex":
					aceita = true
			if aceita:
				lista.append(material)
			else:
				push_warning("Visao: o tile %d usa um shader sem 'visao_tex' (corte.gdshader desatualizado?)." % id)
	return lista


# Escreve a escuridão de UMA célula na imagem.
func _pintar(c: Vector3i) -> void:
	if c.y > _camada_textura:
		return   # andares acima do jogador: o shader de corte cuida deles
	var rel := c - _min
	if rel.x < 0 or rel.y < 0 or rel.z < 0 or rel.x >= _dim.x or rel.y >= _dim.y or rel.z >= _dim.z:
		return   # fora da área do mapa (ar além das bordas)
	_imagem.set_pixel(rel.x, rel.z + rel.y * _dim.z, Color(escuridao_em(c), 0, 0, 1))


# Refaz a imagem inteira. Só acontece ao mudar de andar.
func _reconstruir_textura() -> void:
	_imagem.fill(Color(1, 0, 0, 1))
	for camada_y in _dim.y:
		if _min.y + camada_y > _camada_textura:
			# andares acima: sem escuridão, pra não pintar de preto o "fantasma" do corte
			_imagem.fill_rect(Rect2i(0, camada_y * _dim.z, _dim.x, _dim.z), Color(0, 0, 0, 1))
	for c in explorados:
		_pintar(c)


func _atualizar_textura(camada: int, antes: Dictionary) -> void:
	if _imagem == null:
		return
	var mudou_de_andar := camada != _camada_textura
	_camada_textura = camada
	if mudou_de_andar:
		_reconstruir_textura()
	else:
		for c in antes:
			if not visiveis.has(c):
				_pintar(c)   # saiu de vista: vira memória
		for c in visiveis:
			_pintar(c)
	_textura.update(_imagem)
