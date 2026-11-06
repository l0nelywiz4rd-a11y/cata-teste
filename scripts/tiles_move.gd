extends Ator
## Jogador: herda todas as regras do Ator e só acrescenta
## o teclado, a câmera (zoom) e o corte de andares.

const ZOOMS := [1.0, 1.6, 2.4, 0.6]   # multiplicadores da distância
var zoom_idx := 0
var offset_camera: Vector3

@onready var camera: Camera3D = $Camera3D


func _ao_iniciar() -> void:
	add_to_group("jogador")
	offset_camera = camera.position


func _a_cada_frame(_delta: float) -> void:
	RenderingServer.global_shader_parameter_set("corte_y", global_position.y + 1.1)


func _unhandled_input(event):
	if event.is_action_pressed("zoom"):
		zoom_idx = (zoom_idx + 1) % ZOOMS.size()
		var tween := create_tween()
		tween.tween_property(camera, "position", offset_camera * ZOOMS[zoom_idx], 0.2)


func _pensar() -> void:
	if Input.is_action_just_pressed("subir"):
		tentar_escada(true)
		return
	if Input.is_action_just_pressed("descer"):
		tentar_escada(false)
		return

	var direcao := _ler_direcao()
	if direcao != Vector3i.ZERO:
		tentar_mover(direcao)


# Soma as teclas apertadas: frente + direita = diagonal.
func _ler_direcao() -> Vector3i:
	var d := Vector3i.ZERO
	if Input.is_action_pressed("frente"):
		d.z -= 1
	if Input.is_action_pressed("tras"):
		d.z += 1
	if Input.is_action_pressed("esquerda"):
		d.x -= 1
	if Input.is_action_pressed("direita"):
		d.x += 1
	return d
