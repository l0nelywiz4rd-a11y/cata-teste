extends Ator
## Jogador: herda todas as regras do Ator e só acrescenta
## o teclado, a câmera (zoom) e o corte de andares.

const ZOOMS := [1.0, 1.6, 2.4, 0.6]   # multiplicadores da distância
var zoom_idx := 0
var offset_camera: Vector3

# Buffer de escada: se apertar < ou > durante o débito, o pedido fica guardado
# por um tempinho e é executado assim que o personagem puder agir.
const BUFFER_MS := 400
var _escada_pedida := 0      # 1 = subir, -1 = descer, 0 = nenhum
var _pedido_expira := 0

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
	elif event.is_action_pressed("subir"):
		_pedir_escada(1)
	elif event.is_action_pressed("descer"):
		_pedir_escada(-1)


func _pedir_escada(sentido: int) -> void:
	_escada_pedida = sentido
	_pedido_expira = Time.get_ticks_msec() + BUFFER_MS


func _pensar() -> void:
	if _escada_pedida != 0:
		var sentido := _escada_pedida
		_escada_pedida = 0   # consome o pedido
		if Time.get_ticks_msec() <= _pedido_expira:
			tentar_escada(sentido > 0)
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
