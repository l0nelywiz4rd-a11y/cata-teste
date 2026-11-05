class_name TilesData

enum Tile { PISO, PISOLENTO, RAMPA}

const DADOS = {
	Tile.PISO: {"solido": true, "escalavel": true},
	Tile.PISOLENTO: {"solido": false, "velocidade": 0.5, "escalavel": false, "sobe": true, "desce": true},
	Tile.RAMPA: {"solido": false, "velocidade": 0.5, "escalavel": true}
}

static func eh_solido(tile: int) -> bool:
	if tile == -1:
		return false
	return DADOS[tile]["solido"]

static func velocidade(tile: int) -> float:
	if tile == -1: 
		return 1.0
	return DADOS[tile].get("velocidade", 1.0)

static func eh_escalavel(tile: int) -> bool:
	if tile == -1:
		return false
	return DADOS[tile].get("escalavel", false)

static func permite_subir(tile: int) -> bool:
	if tile == -1:
		return false
	return DADOS[tile].get("sobe", false)


static func permite_descer(tile: int) -> bool:
	if tile == -1:
		return false
	return DADOS[tile].get("desce", false)
