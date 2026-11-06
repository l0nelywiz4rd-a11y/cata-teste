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
