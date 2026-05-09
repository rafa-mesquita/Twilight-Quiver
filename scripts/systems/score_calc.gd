class_name ScoreCalc
extends RefCounted

# Calcula um score único pra ordenar runs no leaderboard.
# Stats vem do player: wave alcançada, kills, allies, dano causado/sofrido, tempo.
#
# Filosofia da fórmula:
#  - Wave é o que mais importa (+1000 por wave).
#  - Allies criados (Maldição/etc) valem mais por slot que kills (+150 cada).
#  - Dano causado entra direto (1 ponto por hp, mas weighted pra não dominar).
#  - Dano sofrido penaliza (skill expression: aguentar mais dano = run mais sofrida).
#  - Tempo NÃO entra (jogo é survival; alcançar wave alta importa, não velocidade).
#
# Ajuste os pesos abaixo se quiser balancear o leaderboard de outro jeito.
const WAVE_WEIGHT: int = 1000
const KILL_WEIGHT: int = 5
const ALLY_WEIGHT: int = 150
const DMG_DEALT_WEIGHT: float = 0.5
const DMG_TAKEN_PENALTY: float = 0.25


static func calc(stats: Dictionary) -> int:
	var wave: int = int(stats.get("wave", 0))
	var kills: int = int(stats.get("kills", 0))
	var allies: int = int(stats.get("allies", 0))
	var dmg_dealt: int = int(stats.get("dmg_dealt", 0))
	var dmg_taken: int = int(stats.get("dmg_taken", 0))
	var score: float = 0.0
	score += float(wave) * WAVE_WEIGHT
	score += float(kills) * KILL_WEIGHT
	score += float(allies) * ALLY_WEIGHT
	score += float(dmg_dealt) * DMG_DEALT_WEIGHT
	score -= float(dmg_taken) * DMG_TAKEN_PENALTY
	return max(0, int(round(score)))
