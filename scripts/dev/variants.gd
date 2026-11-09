class_name DevVariants
extends RefCounted

## Interruptores de calidad para el banco de pruebas. Un solo export produce toda la
## matriz de medicion: la variante se elige con `--variant N` en la linea de comandos.
## Sin `--variant` se usa la configuracion de juego (shader ligero).

const BASE_SHADER := 0
const LIGHT_SHADER := 1
const LIGHT_SCALE_060 := 2
const LIGHT_SCALE_050 := 3
const VEG_OFF := 4
const LIGHT_SCALE_040 := 5

const LIGHT_SHADER_PATH := "res://assets/terrain_lightweight.gdshader"


static func current() -> int:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--variant")
	if index == -1 or index + 1 >= args.size():
		return LIGHT_SHADER
	return int(args[index + 1])


## True si la variante se eligio explicitamente en la linea de comandos. El banco de
## pruebas la usa siempre, y con eso la escala automatica se queda quieta para que las
## mediciones no cambien de resolucion a mitad de la toma.
static func is_explicit() -> bool:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--variant")
	return index != -1 and index + 1 < args.size()


static func label(variant: int) -> String:
	match variant:
		BASE_SHADER: return "base"
		LIGHT_SHADER: return "light"
		LIGHT_SCALE_060: return "light060"
		LIGHT_SCALE_050: return "light050"
		VEG_OFF: return "vegoff"
		LIGHT_SCALE_040: return "light040"
	return "unknown"


static func vegetation_enabled(variant: int) -> bool:
	return variant != VEG_OFF


static func render_scale(variant: int) -> float:
	match variant:
		LIGHT_SCALE_060: return 0.6
		LIGHT_SCALE_050: return 0.5
		LIGHT_SCALE_040: return 0.4
	return 0.75


static func use_light_shader(variant: int) -> bool:
	return variant != BASE_SHADER
