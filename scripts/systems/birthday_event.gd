class_name BirthdayEvent
extends RefCounted

# Birthday event (eliyeolio) — time-gated + nickname-gated party hat,
# plus universal fireworks ambient on menus during the window.
#
# Window: 2026-05-13 00:00:00 UTC .. 2026-05-19 23:59:59 UTC (1 week).
# Compare timestamps via Time.get_unix_time_from_system() (UTC by default in Godot).
#
# Unix timestamps pré-computados (UTC):
#   2026-05-13 00:00:00 UTC -> 1778630400
#   2026-05-19 23:59:59 UTC -> 1779235199

const TARGET_NICKNAME: String = "eliyeolio"
const EVENT_START_UNIX: int = 1778630400
const EVENT_END_UNIX: int = 1779235199

# Dev override: botão no dev panel força evento ativo + força match de qualquer
# nick. Permite testar a UI festa sem precisar mudar data/nick. Persiste só na
# sessão atual (não é salvo).
static var dev_force_active: bool = false


static func is_active() -> bool:
	if dev_force_active:
		return true
	var now: int = int(Time.get_unix_time_from_system())
	return now >= EVENT_START_UNIX and now <= EVENT_END_UNIX


static func is_target_player(nickname: String) -> bool:
	if dev_force_active:
		return true
	return nickname == TARGET_NICKNAME


static func should_show_hat_for(nickname: String) -> bool:
	if dev_force_active:
		return true
	return is_active() and is_target_player(nickname)


# Helper de "modo festa": confetti + fireworks só aparecem se o usuário local
# for o nick alvo dentro da janela, OU se o dev toggle estiver ON. Lê o nick
# direto do settings.cfg — não precisa passar parâmetro por todo lugar.
static func is_party_active_for_current_user() -> bool:
	if dev_force_active:
		return true
	if not is_active():
		return false
	return is_target_player(load_current_nickname())


# Lê o nickname do settings.cfg (mesma chave usada por main_menu.gd).
static func load_current_nickname() -> String:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return ""
	return str(cfg.get_value("player", "nickname", ""))


# Spawna um chapéu Sprite2D filho do node passado quando o "modo festa" tá
# ativo (janela + nick alvo, OU dev toggle). Usado em inimigos magos pra
# festa ficar visual nos NPCs. Offset = posição relativa ao node parent
# (geralmente Vector2(0, -16) ou maior, dependendo do tamanho do sprite).
const HAT_TEXTURE_PATH: String = "res://assets/source/chapeu_de_festa1.png"


static func attach_universal_hat(parent: Node2D, head_offset: Vector2) -> Sprite2D:
	if not is_party_active_for_current_user():
		return null
	if parent == null:
		return null
	# BirthdayHat segue flip_h do AnimatedSprite2D do parent — chapéu acompanha
	# quando o player/enemy vira pro outro lado.
	var hat := BirthdayHat.new()
	hat.name = "PartyHat"
	hat.texture = load(HAT_TEXTURE_PATH) as Texture2D
	hat.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hat.position = head_offset
	hat.z_index = 12
	parent.add_child(hat)
	return hat
