class_name PetalBank
extends RefCounted

# Banco persistente de pétalas (meta-moeda da economia de pétalas).
# A carteira POR-RUN vive em `player.petals`; no fim da run o saldo não-gasto é
# depositado aqui via deposit(). Acumula entre runs no settings.cfg [progress]
# (mesma seção dos stats de unlock de skin). Gastar só FORA do jogo (loja meta,
# P4) — no P1 o banco só enche.

const _SETTINGS_PATH: String = "user://settings.cfg"
const _SECTION: String = "progress"
const _KEY: String = "petal_bank_total"


static func get_total() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(_SETTINGS_PATH) != OK:
		return 0
	return int(cfg.get_value(_SECTION, _KEY, 0))


static func deposit(amount: int) -> int:
	# Soma `amount` ao banco e retorna o novo total. amount <= 0 é no-op.
	if amount <= 0:
		return get_total()
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	var new_total: int = int(cfg.get_value(_SECTION, _KEY, 0)) + amount
	cfg.set_value(_SECTION, _KEY, new_total)
	cfg.save(_SETTINGS_PATH)
	return new_total


static func spend(amount: int) -> bool:
	# Debita `amount` do banco se houver saldo. Retorna true se gastou.
	if amount <= 0:
		return false
	var cfg := ConfigFile.new()
	cfg.load(_SETTINGS_PATH)
	var total: int = int(cfg.get_value(_SECTION, _KEY, 0))
	if total < amount:
		return false
	cfg.set_value(_SECTION, _KEY, total - amount)
	cfg.save(_SETTINGS_PATH)
	return true
