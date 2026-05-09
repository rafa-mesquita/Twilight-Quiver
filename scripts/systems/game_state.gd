extends Node

# Singleton de estado global. Autoloaded no project.godot como "GameState".
# Carrega defaults toda vez que o jogo é aberto — não persiste entre runs.

# Dev mode: quando true, main.tscn não roda waves automáticas e exibe o DevPanel
# pra o desenvolvedor testar inimigos/upgrades isoladamente.
var dev_mode: bool = false


func reset() -> void:
	dev_mode = false
