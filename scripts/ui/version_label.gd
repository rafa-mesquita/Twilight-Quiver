extends Label

# Lê application/config/version do project.godot e exibe como "vX.Y.Z" no canto.
# Instanciar como filho de um CanvasLayer (ver version_label.tscn) pra ficar
# fixo no viewport independente do tipo de cena pai (Control ou CanvasLayer).

func _ready() -> void:
	var v: String = str(ProjectSettings.get_setting("application/config/version", ""))
	text = "v%s" % v if v != "" else ""
