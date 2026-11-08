class_name MapaGrid
extends GridMap

# Registro central de "quem está em cada célula".
# Chave: Vector3i (célula). Valor: o Ator que está lá.
var _ocupantes := {}


func registrar(ator: Ator, c: Vector3i) -> void:
	_ocupantes[c] = ator


# Só libera se quem está na célula é mesmo esse ator (evita apagar o registro de outro).
func liberar(ator: Ator, c: Vector3i) -> void:
	if _ocupantes.get(c) == ator:
		_ocupantes.erase(c)


func mover(ator: Ator, de: Vector3i, para: Vector3i) -> void:
	liberar(ator, de)
	registrar(ator, para)


# Devolve o Ator na célula, ou null se estiver livre.
func quem_esta(c: Vector3i) -> Ator:
	var a = _ocupantes.get(c)
	if is_instance_valid(a):
		return a
	return null


# =====================================================================
#  VISÃO (consultas do mapa; quem usa: jogador, luzes, e depois a IA)
# =====================================================================

func eh_opaco(c: Vector3i) -> bool:
	return TilesData.eh_opaco(get_cell_item(c))


# Anda em linha reta da origem até (dx, dz) e confere se alguma célula do MEIO bloqueia.
# A origem e o destino não contam: dá pra ver a própria parede, só não o que está atrás dela.
func linha_de_visao_livre(origem: Vector3i, dx: int, dz: int) -> bool:
	var passos := maxi(absi(dx), absi(dz))
	for i in range(1, passos):
		var x := origem.x + roundi(dx * float(i) / passos)
		var z := origem.z + roundi(dz * float(i) / passos)
		if eh_opaco(Vector3i(x, origem.y, z)):
			return false
	return true


# Todas as colunas (x, z) que a origem enxerga dentro do alcance, na camada da origem.
# Devolve Dictionary: Vector2i(x, z) -> distância em células.
func campo_de_visao(origem: Vector3i, alcance: int) -> Dictionary:
	var campo := {}
	for dx in range(-alcance, alcance + 1):
		for dz in range(-alcance, alcance + 1):
			var d2 := dx * dx + dz * dz
			if d2 > alcance * alcance:
				continue
			if linha_de_visao_livre(origem, dx, dz):
				campo[Vector2i(origem.x + dx, origem.z + dz)] = sqrt(d2)
	return campo


# =====================================================================
#  LUZ EM 3D (pode atravessar andares por buracos, escadas, poços...)
# =====================================================================

# Igual à linha de visão, mas em 3 eixos: a luz sobe e desce por aberturas,
# e é bloqueada por qualquer tile opaco no caminho (chão, teto, parede).
func linha_de_luz_livre(origem: Vector3i, dx: int, dy: int, dz: int) -> bool:
	var passos := maxi(maxi(absi(dx), absi(dy)), absi(dz))
	for i in range(1, passos):
		var f := float(i) / passos
		var c := origem + Vector3i(roundi(dx * f), roundi(dy * f), roundi(dz * f))
		if eh_opaco(c):
			return false
	return true


# Todas as células ABERTAS (não opacas) que a luz da origem alcança.
# raio = alcance em células (esfera); raio_z = quantos andares pra cima e pra baixo, no máximo.
# Devolve Dictionary: Vector3i -> distância.
func campo_de_luz(origem: Vector3i, raio: int, raio_z: int) -> Dictionary:
	var campo := {}
	var r2 := raio * raio
	for dy in range(-raio_z, raio_z + 1):
		for dx in range(-raio, raio + 1):
			for dz in range(-raio, raio + 1):
				var d2 := dx * dx + dy * dy + dz * dz
				if d2 > r2:
					continue
				var alvo := origem + Vector3i(dx, dy, dz)
				if eh_opaco(alvo):
					continue   # só iluminamos o ar; as superfícies se iluminam pelo ar vizinho
				if linha_de_luz_livre(origem, dx, dy, dz):
					campo[alvo] = sqrt(d2)
	return campo
