extends Node3D
#------------------------------------------------------------------------------------
@export var tempo_por_tile := 0.18   # menor = mais rápido
@export var celula_inicial := Vector3i(2, 1, 2)
@export var ticks_por_segundo := 550.0   # quanto o débito cai por segundo
#------------------------------------------------------------------------------------
var mapa: GridMap
var celula: Vector3i
var movendo := false

const CUSTO_MOVER := 100.0
const CUSTO_ESCADA := 150.0

var debito := 0.0

signal debito_mudou(valor: float)   # pra uma barra na tela depois
#------------------------------------------------------------------------------------
var veio_de_escalavel := false
const ALTURA_ANDAR := 1   # quantas camadas tem um andar
#------------------------------------------------------------------------------------
signal caiu(altura: int)

const Y_MINIMO := -10   # limite pra não cair pra sempre
#------------------------------------------------------------------------------------
const ZOOMS := [1.0, 1.6, 2.4, 0.6]   # multiplicadores da distância
var zoom_idx := 0
var offset_camera: Vector3

@onready var camera: Camera3D = $Camera3D
#------------------------------------------------------------------------------------

func _unhandled_input(event):
	if event.is_action_pressed("zoom"):
		zoom_idx = (zoom_idx + 1) % ZOOMS.size()
		var tween = create_tween()
		tween.tween_property(camera, "position", offset_camera * ZOOMS[zoom_idx], 0.2)


func _ready():
	add_to_group("jogador")
	mapa = get_tree().get_first_node_in_group("mapa")
	celula = celula_inicial
	global_position = _centro_da_celula(celula)
	offset_camera = camera.position
	caiu.connect(_ao_cair)


func _process(_delta):
	RenderingServer.global_shader_parameter_set("corte_y", global_position.y + 1.1)
	
	debito = max(debito - ticks_por_segundo * _delta, 0.0)
	
	if movendo or not pode_agir():
		return

	var direcao := Vector3i.ZERO
	if Input.is_action_pressed("frente"):
		direcao = Vector3i(0, 0, -1)
	elif Input.is_action_pressed("tras"):
		direcao = Vector3i(0, 0, 1)
	elif Input.is_action_pressed("esquerda"):
		direcao = Vector3i(-1, 0, 0)
	elif Input.is_action_pressed("direita"):
		direcao = Vector3i(1, 0, 0)

	if Input.is_action_just_pressed("subir"):
		tentar_escada(true)
		return
	if Input.is_action_just_pressed("descer"):
		tentar_escada(false)
		return

	if direcao != Vector3i.ZERO:
		tentar_mover(direcao)


func tentar_mover(direcao: Vector3i):
	var alvo = celula + direcao

	# se o tile à frente é escalável, o alvo passa a ser o topo dele
	if TilesData.eh_escalavel(mapa.get_cell_item(alvo)):
		var topo = alvo + Vector3i.UP
		if pode_entrar(topo):
			alvo = topo

	if not pode_entrar(alvo):
		return

	# guarda se o jogador estava em cima de um tile escalável
	veio_de_escalavel = TilesData.eh_escalavel(mapa.get_cell_item(celula + Vector3i.DOWN))

	celula = alvo
	movendo = true

	var chao = mapa.get_cell_item(alvo + Vector3i(0, -1, 0))
	var custo = CUSTO_MOVER / TilesData.velocidade(chao)
	gastar(custo)
	var tempo = custo / ticks_por_segundo

	var tween = create_tween()
	tween.tween_property(self, "global_position", _centro_da_celula(alvo), tempo)
	tween.finished.connect(_ao_chegar)


func pode_entrar(alvo: Vector3i) -> bool:
	return not TilesData.eh_solido(mapa.get_cell_item(alvo))


func _centro_da_celula(c: Vector3i) -> Vector3:
	return mapa.to_global(mapa.map_to_local(c))

func tem_chao(c: Vector3i) -> bool:
	return mapa.get_cell_item(c + Vector3i.DOWN) != -1


func _ao_chegar():
	var pouso = achar_pouso(celula)
	if pouso == celula:
		movendo = false
		return

	var altura = celula.y - pouso.y
	celula = pouso

	var tween = create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)   # acelera caindo
	tween.tween_property(self, "global_position", _centro_da_celula(pouso), 0.1 * altura)
	tween.finished.connect(func():
		movendo = false
		var isento = veio_de_escalavel and altura <= 1
		if not isento:
			caiu.emit(altura)
	)


func _ao_cair(altura: int):
	print("Caiu ", altura, " tiles")   # depois: dano aqui

func achar_pouso(c: Vector3i) -> Vector3i:
	while not tem_chao(c) and c.y > Y_MINIMO:
		c.y -= 1
	return c


func tem_escada(subindo: bool) -> bool:
	for pos in [celula, celula + Vector3i.DOWN]:
		var tile = mapa.get_cell_item(pos)
		var permite = TilesData.permite_subir(tile) if subindo else TilesData.permite_descer(tile)
		if permite:
			return true
	return false


func tentar_escada(subindo: bool):
	if not tem_escada(subindo):
		return

	var passo = ALTURA_ANDAR if subindo else -ALTURA_ANDAR
	var alvo = celula + Vector3i(0, passo, 0)
	if not pode_entrar(alvo) or not tem_chao(alvo):
		return

	veio_de_escalavel = false
	celula = alvo
	movendo = true
	
	gastar(CUSTO_ESCADA)

	var tween = create_tween()
	tween.tween_property(self, "global_position", _centro_da_celula(alvo), CUSTO_ESCADA / ticks_por_segundo)
	tween.finished.connect(func(): movendo = false)


func pode_agir() -> bool:
	return debito <= 0.0


func gastar(custo: float):
	debito += custo
	debito_mudou.emit(debito)
