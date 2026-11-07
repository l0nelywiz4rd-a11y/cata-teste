class_name CicloDia
extends Node
## Relógio do jogo e ciclo de dia e noite.
## A cada momento calcula a altura do sol, converte em luz ambiente e entrega pra Visao.
## Também escurece o céu (WorldEnvironment) pra combinar.

signal hora_mudou(hora: float)   # a cada frame em que o relógio anda (use pra uma UI)
signal dia_mudou(dia: int)       # à meia-noite

@export_range(0.0, 24.0) var hora := 8.0:   # a hora do jogo; dá pra mexer no Inspector
	set(valor):
		hora = fposmod(valor, 24.0)
		_aplicar()
@export var minutos_reais_por_dia := 10.0   # quanto dura um dia inteiro de jogo. 0 = relógio parado
@export var nascer_do_sol := 6.0
@export var por_do_sol := 18.0
@export_range(0.0, 1.0) var luz_noite := 0.06   # luz ambiente da noite mais escura
@export var visao: Visao                        # se vazio, procura sozinho
@export var ambiente: WorldEnvironment          # se vazio, usa o primeiro que achar
@export var escurecer_ceu := true               # escurece o fundo de noite (ver o aviso abaixo)

var dia := 1
var _avisou_ceu := false


func _ready() -> void:
	_iniciar.call_deferred()


func _iniciar() -> void:
	if ambiente == null:
		var achados := get_tree().root.find_children("*", "WorldEnvironment", true, false)
		if not achados.is_empty():
			ambiente = achados[0] as WorldEnvironment
	_aplicar()


func _process(delta: float) -> void:
	if minutos_reais_por_dia <= 0.0:
		return
	var nova := hora + 24.0 * delta / (minutos_reais_por_dia * 60.0)
	if nova >= 24.0:
		dia += 1
		dia_mudou.emit(dia)
	hora = nova          # o setter dá a volta (fposmod) e chama _aplicar()
	hora_mudou.emit(hora)


# =====================================================================
#  CONSULTAS
# =====================================================================

# Altura do sol: 1 = meio-dia, 0 = nascer/pôr do sol, -1 = meia-noite.
func altura_do_sol(h: float) -> float:
	var duracao_dia := por_do_sol - nascer_do_sol
	if h >= nascer_do_sol and h <= por_do_sol:
		return sin(PI * (h - nascer_do_sol) / duracao_dia)
	var duracao_noite := 24.0 - duracao_dia
	var desde_o_por := fposmod(h - por_do_sol, 24.0)
	return -sin(PI * desde_o_por / duracao_noite)


# A luz ambiente numa hora qualquer. O smoothstep cria o crepúsculo:
# o escuro chega aos poucos, em vez de um corte seco no pôr do sol.
func luz_na_hora(h: float) -> float:
	var claridade := smoothstep(-0.30, 0.40, altura_do_sol(h))
	return lerpf(luz_noite, 1.0, claridade)


func eh_dia() -> bool:
	return altura_do_sol(hora) > 0.0


func hora_texto() -> String:
	var h := int(hora)
	var m := int((hora - h) * 60.0)
	return "%02d:%02d" % [h, m]


# Avança o relógio na marra (dormir, esperar, depurar).
func avancar(horas: float) -> void:
	var nova := hora + horas
	while nova >= 24.0:
		nova -= 24.0
		dia += 1
		dia_mudou.emit(dia)
	hora = nova


# =====================================================================
#  APLICAÇÃO
# =====================================================================

func _aplicar() -> void:
	var luz := luz_na_hora(hora)

	if visao == null and is_inside_tree():
		visao = get_tree().get_first_node_in_group("visao") as Visao
	# só repassa quando mudou de verdade: cada mudança faz a Visao recalcular
	if visao != null and absf(visao.luz_ambiente - luz) > 0.004:
		visao.luz_ambiente = luz

	_escurecer_ceu(luz)


func _escurecer_ceu(luz: float) -> void:
	if not escurecer_ceu or ambiente == null or ambiente.environment == null:
		return
	var amb := ambiente.environment
	# Se a luz ambiente vem do Sky, escurecer o céu escurece TAMBÉM todos os tiles
	# (e a lanterna perde a graça). Então só dá pra escurecer o céu com o ambiente em "Color".
	if amb.ambient_light_source == Environment.AMBIENT_SOURCE_SKY:
		if not _avisou_ceu:
			_avisou_ceu = true
			push_warning("CicloDia: o céu NÃO foi escurecido porque a luz ambiente vem dele. "
				+ "Pra escurecer, ponha Environment > Ambient Light > Source em 'Color'.")
		return
	amb.background_energy_multiplier = lerpf(0.03, 1.0, luz)
