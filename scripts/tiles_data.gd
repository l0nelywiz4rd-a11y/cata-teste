class_name TilesData

# Os valores são os IDs da MeshLibrary (o número que o GridMap guarda), NÃO a posição na lista.
# Se um tile for apagado e a biblioteca re-exportada, os ids podem pular: confira no painel do GridMap.
enum Tile { PISO = 0, PISOLENTO = 1, RAMPA = 3 }

const DADOS = {
	Tile.PISO: {"solido": true, "escalavel": true},
	Tile.PISOLENTO: {"solido": false, "velocidade": 0.5, "escalavel": false, "sobe": true, "desce": true},
	Tile.RAMPA: {"solido": false, "velocidade": 0.5, "escalavel": true},
}


# Função central: lê uma propriedade de um tile, ou devolve o padrão.
# Cobre 3 casos de uma vez: célula vazia (-1), tile que não está em DADOS,
# e tile que não tem aquela propriedade.
static func _prop(tile: int, chave: String, padrao: Variant) -> Variant:
	if tile == -1 or not DADOS.has(tile):
		return padrao
	return DADOS[tile].get(chave, padrao)


static func eh_solido(tile: int) -> bool:
	return bool(_prop(tile, "solido", false))


static func velocidade(tile: int) -> float:
	return float(_prop(tile, "velocidade", 1.0))


# Funciona como TETO? Bloqueia a cabeça de quem está embaixo (não dá pra escalar sob ele).
# Se não for definido, segue o "solido". Grade/vidro: {"solido": true, "teto": true, "opaco": false}.
static func eh_teto(tile: int) -> bool:
	return bool(_prop(tile, "teto", eh_solido(tile)))


# Bloqueia a visão E a luz? Se não for definido, segue o "solido" (parede sólida = opaca).
# Vidro/grade: {"solido": true, "opaco": false}. Fumaça: {"solido": false, "opaco": true}.
static func eh_opaco(tile: int) -> bool:
	return bool(_prop(tile, "opaco", eh_solido(tile)))


static func eh_escalavel(tile: int) -> bool:
	return bool(_prop(tile, "escalavel", false))


static func permite_subir(tile: int) -> bool:
	return bool(_prop(tile, "sobe", false))


static func permite_descer(tile: int) -> bool:
	return bool(_prop(tile, "desce", false))
