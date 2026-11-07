class_name FonteDeLuz
extends Node3D
## Põe este node em qualquer lugar (ou dentro de um Ator, pra a luz andar junto).
## Ele ilumina as células ao redor, na mesma camada Y em que está.

@export var raio := 6                          # alcance da luz, em células
@export_range(0.0, 1.0) var forca := 1.0       # brilho no centro (cai com a distância)


func _ready() -> void:
	add_to_group("fontes_luz")
