# Fogo L2 — Escolha de Rastro (Player vs Flecha)

**Data:** 2026-06-04
**Status:** Design aprovado, pronto pra plano de implementação

## Contexto

O elemental Fogo tem dois rastros de DPS além do burn e da skill:

- **Rastro no player** — segmentos que caem no chão enquanto o player anda
  (`_update_player_fire_trail` / `player_fire_trail.tscn`).
- **Rastro na flecha** — segmentos que a flecha deixa no caminho do voo
  (`fire_trail.tscn`, configurado no setup da flecha).

Hoje a ordem é fixa:

| Nível | Conteúdo |
|---|---|
| L1 | Burn (BurnDoT) na flecha |
| L2 | Rastro **no player** |
| L3 | Skill Q (projétil de fogo) |
| L4 | Rastro **na flecha** + bônus globais (+30% burn, +25% área) |

No L4 os **dois rastros ficam ativos** ao mesmo tempo (o do player segue ligado
desde o L2, e o da flecha é adicionado).

Feedback da comunidade: a última troca (player no L2, flecha no L4) dividiu
opiniões — parte amou, parte odiou. A ideia é devolver a escolha ao jogador.

## Objetivo

Ao chegar no **L2**, o jogador escolhe **qual rastro vem primeiro**. A escolha
**só afeta a fase L2-L3** (qual rastro único fica ativo enquanto sobe). No **L4 o
Fogo sempre termina igual ao atual: os dois rastros ativos**, independente da
escolha.

| Escolha (no L2) | L2–L3 | L4 (sempre igual) |
|---|---|---|
| **Player primeiro** (default atual) | só rastro no player | player **+** flecha |
| **Flecha primeiro** | só rastro na flecha | player **+** flecha |

Princípio: a escolha influencia só *o tempo* em que o jogador fica com cada
rastro durante L2 e L3. O endgame do elemental (L4) converge pra versão completa
nos dois caminhos.

## Design

### 1. Estado no player

Novo campo em [player.gd](../../../scripts/player/player.gd), perto de
`fire_arrow_level`:

```gdscript
# Ordem dos rastros do Fogo escolhida no L2. "player_first" (default, = ordem
# atual) ou "arrow_first". Só afeta L2-L3; no L4 os dois rastros ligam de
# qualquer jeito. Reseta junto com o Fogo (nova run / refund / Roleta).
var fire_trail_variant: String = "player_first"
```

### 2. Lógica de ativação

Dois helpers que decidem qual rastro está ligado conforme nível + variant:

```gdscript
func _fire_player_trail_active() -> bool:
	if fire_arrow_level < 2:
		return false
	if fire_arrow_level >= 4:
		return true  # L4 sempre liga os dois
	return fire_trail_variant != "arrow_first"  # L2-L3: só se player_first

func _fire_arrow_trail_active() -> bool:
	if fire_arrow_level < 2:
		return false
	if fire_arrow_level >= 4:
		return true  # L4 sempre liga os dois
	return fire_trail_variant == "arrow_first"  # L2-L3: só se arrow_first
```

Resultado: no L2-L3 exatamente 1 rastro ativo (o escolhido); no L4 os dois.

**Pontos de uso:**

- `_update_player_fire_trail` ([player.gd:2107](../../../scripts/player/player.gd#L2107)):
  troca o gate `if fire_arrow_level < 2 or is_dead:` por
  `if not _fire_player_trail_active() or is_dead:`.
- Setup da flecha ([player.gd:1129](../../../scripts/player/player.gd#L1129)):
  troca `if fire_arrow_level >= 4:` por `if _fire_arrow_trail_active():`.

**Rastro da flecha — sem retune.** O DPS e a área já são keyed por nível:
- `_fire_trail_dps()` (rastro da flecha) já devolve 4/5/7 nos níveis 2/3/4, então
  no `arrow_first` o rastro da flecha aparece no L2 com DPS 4 (escala natural).
- `_fire_area_scale()` já devolve 1.0 fora do L4, então o rastro da flecha no
  L2-L3 não ganha o +25% de área (que é bônus exclusivo do L4).

**Rastro do player — passa a escalar por nível.** Hoje o rastro do player é
*flat* (`PLAYER_FIRE_TRAIL_DPS = 3.0` base), então não cresce de L2 pra L3 —
só ganha o +30% no L4. Como agora ele pode ser o rastro isolado de L2-L3 (no
`player_first`), ele deve escalar igual o da flecha. Troca o constante flat por
um helper keyed por nível:

```gdscript
func _fire_player_trail_dps() -> float:
	var base: float = 0.0
	match fire_arrow_level:
		2: base = 3.0
		3: base = 4.0
		4: base = 5.0
	return base * _fire_burn_multiplier()
```

E `_spawn_player_fire_trail_segment` ([player.gd:2128](../../../scripts/player/player.gd#L2128))
passa a usar `_fire_player_trail_dps() + float(damage_upgrades)` no lugar de
`PLAYER_FIRE_TRAIL_DPS * _fire_burn_multiplier() + float(damage_upgrades)`. O
`+ damage_upgrades` (bônus por status de Dano) e a estrutura da fórmula seguem
iguais — só a base vira por-nível.

> ⚠️ Efeito colateral no L4: o rastro do player no L4 sai de `3.0×1.30 = 3.9`
> pra `5.0×1.30 = 6.5` (+ status). É um buff no L4. Valores 3/4/5 são ponto de
> partida — ajustar no playtest se ficar forte (ex: 3/4/4 mantém o L4 mais
> perto do atual).

### 3. Modal de escolha (loja)

Em `_commit_upgrades_and_close`
([wave_shop.gd:2172](../../../scripts/ui/wave_shop.gd#L2172)):

1. Antes de aplicar os upgrades, capturar o nível do Fogo
   (`fire_lvl_before = player.get_upgrade_level("fire_arrow")` ou ler
   `fire_arrow_level`).
2. Depois de aplicar, se o Fogo **cruzou pra exatamente L2** (`before < 2 and
   after == 2`), adiar um modal de escolha antes do `closed.emit()` — mesmo
   mecanismo de deferral que a Roleta (`_open_roulette_reveal`) e o Joker
   (`_open_joker_modal`) já usam.

Novo `_open_fire_trail_choice()` espelhando o estilo visual de
`_open_roulette_reveal` ([wave_shop.gd:3315](../../../scripts/ui/wave_shop.gd#L3315)):
- Dimma a `root_panel` (modulate alpha 0.35).
- Painel central, fonte Silver.ttf, título + subtítulo curto.
- **Dois botões**: "Rastro no Player" / "Rastro na Flecha", cada um com uma linha
  de descrição. Cada botão seta `player.fire_trail_variant` e fecha o modal →
  `closed.emit()`.
- **Obrigatório escolher** (sem botão de fechar/dismiss), igual o reveal da Roleta
  só sai pelo OK.

**Encadeamento:** se na mesma leva o jogador também comprou Joker/Roleta, esses
modais têm prioridade e a escolha do Fogo aparece depois que eles fecharem.
(Caso raro — Roleta exige elemental no L3, e a escolha do Fogo só dispara no L2 —
mas o Joker pode coincidir.) A escolha do Fogo entra como o último modal da fila.

### 4. Roleta / Fogo direto no L4

A Roleta entrega um elemental direto no **L4**, pulando L2-L3. Nesse caso:
- O modal de escolha **não dispara** (só dispara na transição pra L2).
- Os dois rastros ligam normalmente (porque `level >= 4` nos dois helpers),
  exatamente como o Fogo se comporta hoje.
- `fire_trail_variant` fica irrelevante (ignorado no L4).

### 5. Reset do estado

`fire_trail_variant` volta pra `"player_first"` quando o Fogo é removido:
- `_remove_elemental("fire_arrow")`
  ([player.gd:3979](../../../scripts/player/player.gd#L3979)) — adicionar o reset
  junto de `fire_arrow_level = 0`.
- Reset geral de run (onde os elementais já zeram).

Como upgrades são por-run neste roguelite, na prática a escolha vale pra run
inteira e zera na próxima.

### 6. i18n

Novas keys em [translations.csv](../../../assets/i18n/translations.csv)
(5 colunas: keys, pt_BR, en, es, fr):

| key | pt_BR (exemplo) |
|---|---|
| `SHOP_FIRE_TRAIL_TITLE` | Rastro de Fogo |
| `SHOP_FIRE_TRAIL_SUBTITLE` | Escolha qual rastro vem primeiro |
| `SHOP_FIRE_TRAIL_OPT_PLAYER` | Rastro no Player |
| `SHOP_FIRE_TRAIL_OPT_ARROW` | Rastro na Flecha |
| `SHOP_FIRE_TRAIL_DESC_PLAYER` | Cai no chão por onde você anda |
| `SHOP_FIRE_TRAIL_DESC_ARROW` | A flecha deixa fogo no caminho |

(Textos finais a ajustar; en/es/fr traduzidos seguindo o esquema.)

## Nota de balance (playtest)

DPS dos rastros depois do design (base por nível, antes de status/burn_mult):

| Nível | Rastro do player | Rastro da flecha |
|---|---|---|
| L2 | 3 | 4 |
| L3 | 4 | 5 |
| L4 | 5 (×1.30 = 6.5) | 7 (×1.30 = 9.1) |

Os dois agora escalam por nível. O da flecha continua com DPS bruto um pouco
maior, mas o do player é mais fácil de manter (cai continuamente onde você anda,
sem depender do voo da flecha) — diferença intencional de usabilidade. Único
número que muda de fato é a base do rastro do player (era flat 3.0). Confirmar no
playtest se o buff do L4 (3.9 → 6.5) fica ok.

## Fora de escopo

- **Painel TAB (separação de fonte do rastro)** — assunto separado, não muda aqui.
- **Trocar a escolha depois de feita** — fica travada pela run.
- **Preview de arte de cada rastro nos botões** — pode entrar depois; v1 usa só
  texto.

## Arquivos afetados

- `scripts/player/player.gd` — var de estado, 2 helpers de ativação, novo
  `_fire_player_trail_dps()` (escala por nível), 2 gates, DPS do rastro do player,
  reset.
- `scripts/ui/wave_shop.gd` — detecção da transição L2 + `_open_fire_trail_choice()`.
- `assets/i18n/translations.csv` — 6 keys novas.
