class_name Ator
extends Node3D
## Classe base de tudo que se move no grid (jogador, zumbis, NPCs).
## Aqui ficam as REGRAS: andar, subir, cair, custo em ticks.
## Quem herda só decide QUANDO agir (input, IA) sobrescrevendo _pensar().

# ---------- Sinais ----------
signal caiu(altura: int)
signal debito_mudou(valor: float)
signal bateu_em(outro: Ator)   # tentou entrar numa célula ocupada (base do ataque)

# ---------- Ajustes (aparecem no Inspector) ----------
@export var celula_inicial := Vector3i(2, 1, 2)
@export var ticks_por_segundo := 550.0   # quanto o débito cai por segundo
@export var bloquear_abismo := true      # true = não deixa andar pra onde não existe chão nenhum

# ---------- Constantes de regras ----------
const CUSTO_MOVER := 100.0
const CUSTO_ESCADA := 150.0
const CUSTO_QUEDA_POR_TILE := 50.0
const ALTURA_ANDAR := 1       # quantas camadas a escada sobe/desce
const ALTURA_ISENTA := 1      # queda de até isso, saindo de um escalável, não conta
const Y_MINIMO := -10         # limite pra busca de chão não rodar pra sempre

# ---------- Estado ----------
var mapa: MapaGrid
var celula: Vector3i
var olhando := Vector3i(0, 0, -1)
var movendo := false
var debito := 0.0
var veio_de_escalavel := false

# Qual node gira pra mostrar a direção (a Camera3D não gira junto).
@onready var visual: Node3D = get_node_or_null("MeshInstance3D")


# =====================================================================
#  CICLO DE VIDA (não sobrescreva estes; use os "ganchos" mais abaixo)
# =====================================================================

func _ready():
	mapa = get_tree().get_first_node_in_group("mapa") as MapaGrid
	celula = celula_inicial
	global_position = _centro_da_celula(celula)
	mapa.registrar(self, celula)
	caiu.connect(_ao_cair)
	_ao_iniciar()


func _exit_tree():
	if mapa:
		mapa.liberar(self, celula)


func _process(delta):
	# 1) recarrega o débito
	if debito > 0.0:
		debito = max(debito - ticks_por_segundo * delta, 0.0)
		debito_mudou.emit(debito)

	# 2) gancho pra coisas que rodam todo frame
	_a_cada_frame(delta)

	# 3) só decide uma ação se estiver livre
	if movendo or not pode_agir():
		return
	_pensar()


# =====================================================================
#  GANCHOS (quem herda sobrescreve)
# =====================================================================

func _ao_iniciar() -> void:
	pass

func _a_cada_frame(_delta: float) -> void:
	pass

func _pensar() -> void:
	pass   # jogador: lê o teclado. Zumbi: decide pra onde ir.

func _ao_cair(_altura: int) -> void:
	pass   # depois: dano de queda


# =====================================================================
#  ACTION POINTS (débito)
# =====================================================================

func pode_agir() -> bool:
	return debito <= 0.0


func gastar(custo: float) -> void:
	debito += custo
	debito_mudou.emit(debito)


# =====================================================================
#  CONSULTAS
# =====================================================================

# Só o terreno: o tile da célula é sólido?
func tile_livre(c: Vector3i) -> bool:
	return not TilesData.eh_solido(mapa.get_cell_item(c))


# Terreno + ocupação: dá pra entrar nessa célula?
func pode_entrar(c: Vector3i) -> bool:
	return tile_livre(c) and mapa.quem_esta(c) == null


func tem_chao(c: Vector3i) -> bool:
	return mapa.get_cell_item(c + Vector3i.DOWN) != -1


func achar_pouso(c: Vector3i) -> Vector3i:
	while not tem_chao(c) and c.y > Y_MINIMO:
		c.y -= 1
	return c


func tem_escada(subindo: bool) -> bool:
	for pos in [celula, celula + Vector3i.DOWN]:
		var tile := mapa.get_cell_item(pos)
		var permite := TilesData.permite_subir(tile) if subindo else TilesData.permite_descer(tile)
		if permite:
			return true
	return false


func _centro_da_celula(c: Vector3i) -> Vector3:
	return mapa.to_global(mapa.map_to_local(c))


# =====================================================================
#  AÇÕES
# =====================================================================

func olhar_para(direcao: Vector3i) -> void:
	if direcao == Vector3i.ZERO:
		return
	olhando = direcao
	if visual:
		visual.rotation.y = atan2(-direcao.x, -direcao.z)


# Aceita as 8 direções. Devolve true se o passo foi dado.
func tentar_mover(direcao: Vector3i) -> bool:
	olhar_para(direcao)

	# Diagonal não "corta quina": se um dos lados é parede, bloqueia.
	if direcao.x != 0 and direcao.z != 0:
		var lado_x := celula + Vector3i(direcao.x, 0, 0)
		var lado_z := celula + Vector3i(0, 0, direcao.z)
		if not tile_livre(lado_x) or not tile_livre(lado_z):
			return false

	var alvo := celula + direcao

	# Se o tile à frente é escalável, o alvo passa a ser o topo dele.
	if TilesData.eh_escalavel(mapa.get_cell_item(alvo)):
		var topo := alvo + Vector3i.UP
		if pode_entrar(topo):
			alvo = topo

	# Tem alguém lá? Isso vira "bater" (ataque no futuro), não movimento.
	var outro := mapa.quem_esta(alvo)
	if outro != null:
		bateu_em.emit(outro)
		return false

	if not pode_entrar(alvo):
		return false

	# Abismo sem fundo: não deixa entrar.
	if bloquear_abismo and not tem_chao(achar_pouso(alvo)):
		return false

	# Guarda se estava em cima de um escalável (pra isentar a queda curta).
	veio_de_escalavel = TilesData.eh_escalavel(mapa.get_cell_item(celula + Vector3i.DOWN))

	# Custo: chão E o que está "dentro" da célula afetam a velocidade.
	var chao := mapa.get_cell_item(alvo + Vector3i.DOWN)
	var dentro := mapa.get_cell_item(alvo)
	var fator := TilesData.velocidade(chao) * TilesData.velocidade(dentro)
	var custo := CUSTO_MOVER * direcao.length() / fator   # diagonal custa ~1.41x

	_deslocar(alvo, custo, _ao_chegar)
	return true


func tentar_escada(subindo: bool) -> bool:
	if not tem_escada(subindo):
		return false

	var passo := ALTURA_ANDAR if subindo else -ALTURA_ANDAR
	var alvo := celula + Vector3i(0, passo, 0)
	if not pode_entrar(alvo) or not tem_chao(alvo):
		return false
	if mapa.quem_esta(alvo) != null:
		return false

	veio_de_escalavel = false
	_deslocar(alvo, CUSTO_ESCADA, _liberar)
	return true


# =====================================================================
#  INTERNOS
# =====================================================================

# Move a posição lógica na hora e anima a posição visual.
func _deslocar(alvo: Vector3i, custo: float, ao_terminar: Callable) -> void:
	mapa.mover(self, celula, alvo)
	celula = alvo
	movendo = true
	gastar(custo)

	var tween := create_tween()
	tween.tween_property(self, "global_position", _centro_da_celula(alvo), custo / ticks_por_segundo)
	tween.finished.connect(ao_terminar)


func _liberar() -> void:
	movendo = false


func _ao_chegar() -> void:
	var pouso := achar_pouso(celula)
	if pouso == celula:
		movendo = false
		return

	var altura := celula.y - pouso.y
	mapa.mover(self, celula, pouso)
	celula = pouso

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # acelera caindo
	tween.tween_property(self, "global_position", _centro_da_celula(pouso), 0.1 * altura)
	tween.finished.connect(_ao_pousar.bind(altura))


func _ao_pousar(altura: int) -> void:
	movendo = false
	var isento := veio_de_escalavel and altura <= ALTURA_ISENTA
	if not isento:
		gastar(altura * CUSTO_QUEDA_POR_TILE)   # atordoado ao cair
		caiu.emit(altura)
