class_name TilesData

# A ordem aqui TEM que bater com a ordem dos tiles na MeshLibrary.
enum Tile { PISO, PISOLENTO, RAMPA }

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


static func eh_escalavel(tile: int) -> bool:
	return bool(_prop(tile, "escalavel", false))


static func permite_subir(tile: int) -> bool:
	return bool(_prop(tile, "sobe", false))


static func permite_descer(tile: int) -> bool:
	return bool(_prop(tile, "desce", false))
