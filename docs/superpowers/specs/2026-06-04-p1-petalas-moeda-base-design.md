# P1 — Pétalas (moeda-base) — Design

**Data:** 2026-06-04
**Subprojeto:** P1 da [Economia de Pétalas](2026-06-04-economia-petalas-visao.md)
**Status:** Design aprovado, pronto pro plano de implementação

## Contexto

Primeiro subprojeto (fundação) da economia de pétalas. Introduz a **segunda
moeda** — pétalas — com ganho in-run, HUD, e o modelo **carteira por-run + banco
persistente**. Sem nenhuma loja ainda: o banco só acumula (gastar vem no P2/P4).
É auto-contido e testável sozinho (dá pra ver pétalas acumulando na HUD e no
banco crescendo entre runs).

Espelha o sistema de **gold** existente:
- `player.gold: int` + `add_gold`/`spend_gold` + signal `gold_changed(total)`
  ([player.gd:3090](../../../scripts/player/player.gd#L3090)).
- HUD `$GoldDisplay/CountLabel` conectado a `gold_changed`
  ([hud.gd:660](../../../scripts/ui/hud.gd#L660)).
- Pickup de gold em cena própria (`gold.gd`) com `lifetime` e pisca-alerta.
- Persistência em `settings.cfg [progress]` via `SkinLoadout.get_stat/set_stat`.

## Design

### 1. Modelo da moeda (no player)

[player.gd](../../../scripts/player/player.gd):
- `var petals: int = 0` — **carteira por-run** (zera a cada run, como o gold).
- `signal petals_changed(total: int)`.
- `func add_petals(amount: int)` — soma, emite `petals_changed`, dispara a
  animação de "voar pra carteira" (ver §4). NÃO há `spend_petals` no P1 (sem
  loja).

⚠ A carteira (`petals`) é só da run. O **banco** é persistente e mora no
`settings.cfg` (ver §3) — NÃO é um campo do player.

### 2. HUD — PetalDisplay

[hud.gd](../../../scripts/ui/hud.gd) + cena da HUD:
- Novo nó **`PetalDisplay`** irmão do `GoldDisplay` (mesmo layout: ícone +
  `CountLabel`), posicionado ao lado.
- `@onready var petal_count_label` + conexão em `petals_changed` →
  `petal_count_label.text = str(total)` (mesmo padrão de `_on_gold_changed`,
  [hud.gd:660](../../../scripts/ui/hud.gd#L660)).
- Inicializa lendo `player.petals` (0 no começo da run).
- `PetalDisplay` entra na lista de nós de HUD escondidos/mostrados junto com os
  outros displays ([hud.gd:280](../../../scripts/ui/hud.gd#L280)).

### 3. Ganho

#### a) Level-up (ao concluir a wave)
Hook em `_finish_wave()`
([wave_manager.gd:969](../../../scripts/systems/wave_manager.gd#L969)) — após a
wave ser concluída. Concede pétalas por **tabela fixa por round** (faixa, rola
aleatório dentro dela). Boss waves detectadas por `_is_boss_wave(wave_number)`.

| Round | Pétalas (faixa) |
|---|---|
| 1–5 | 1–2 |
| 6–10 | 2–3 |
| 11+ | 3–4 |
| **Boss** (`_is_boss_wave`) | **4–5** (override) |

- Tabela como `const` (dict/array de faixas) num lugar central (ex.: no próprio
  wave_manager ou um helper `PetalRewards`). Números provisórios — fáceis de
  ajustar depois.
- Boss override: se `_is_boss_wave(wave_number)`, usa a faixa de boss em vez da
  faixa por round.
- Chama `player.add_petals(rolled)` → anima pra carteira.

#### b) Drop de mob
- **0.75%** de chance por kill, **1 pétala** por drop.
- **Mesmas exclusões do gold:** reusa o caminho/elegibilidade de drop do gold
  (inseto invocado NÃO dropa — anti-exploit do summoner; ver
  [[feature_gold_system]]). Onde o gold decide dropar, rola também o 0.75% de
  pétala (independente).
- Spawna um pickup **`petal`** — cena própria espelhando `gold.gd`
  (`scripts/pickups/petal.gd` + `scenes/pickups/petal.tscn`):
  - `lifetime` = **dobro da base do gold** (gold base 9.5s → **19s**), mesmo
    `blink_warn_duration` (pisca-alerta no fim). Valor fixo (não depende de o
    jogador ter Chuva de Coins).
  - Coletar (overlap com o player) → `player.add_petals(1)` + animação pra
    carteira + free do pickup.
  - Pode reusar o hop/bob visual do gold pro placeholder.

### 4. Animação "pétalas → carteira"
Ao `add_petals`, partículas de pétala fazem **tween até o `PetalDisplay`** na HUD
(screen-space); o contador incrementa ao fim do voo. Reusa o espírito do
magnet/chuva-de-coins do gold (tween de posição + fade). Origem das partículas:
- Level-up: a partir da posição do player na tela (ou centro), N pétalas voam.
- Drop coletado: a partir da posição do pickup coletado.

Detalhe de implementação (origem exata, nº de partículas) fica livre — o
importante é o feedback visual de "ganhei pétala, ela foi pra carteira".

### 5. Banco persistente
- Nova chave persistente `STAT_PETAL_BANK` em `settings.cfg [progress]` (via
  `SkinLoadout.get_stat/set_stat` ou um helper análogo — decidir no plano se
  estende `SkinLoadout` ou cria um `PetalBank` próprio; preferência: helper
  próprio `PetalBank` pra não inchar o SkinLoadout, lendo a mesma seção).
- **Depósito na morte:** no fluxo de `record_run`/fim de run
  ([hud.gd:1383](../../../scripts/ui/hud.gd#L1383) /
  [hud.gd:2102](../../../scripts/ui/hud.gd#L2102)), somar `player.petals` ao
  `STAT_PETAL_BANK`. Incluir `petals` no `_collect_run_stats`
  ([hud.gd:1799](../../../scripts/ui/hud.gd#L1799)) pra passar o valor adiante.
- **Death screen:** linha nova "🌸 +Y depositadas (banco: Z)" (Y = pétalas da
  run, Z = banco após depósito). Texto via i18n.
- **Menu principal / tela Player:** label com o total do banco
  (`🌸 Z`) num cantinho. Lê `STAT_PETAL_BANK`. Texto via i18n.

### 6. Placeholder de sprite
Pétala rosa simples pro ícone da HUD + pickup do chão + partícula da animação.
Opções (escolher no plano): desenhar por código (Polygon2D/atlas simples) ou
tintar de rosa um sprite de moeda existente. **Trocável pelo sprite real depois
sem mexer na lógica** (a lógica referencia um path/recurso de textura).

## i18n
Strings novas em [translations.csv](../../../assets/i18n/translations.csv) (5
colunas): rótulo do banco no death screen e no menu, e o que mais aparecer de
texto. Seguir convenção (`HUD_*` / `MENU_*` / `PLAYER_*`). Sem texto hardcoded.

## Fora de escopo (P1)
- **Gastar pétalas** — não há loja no P1; o banco só acumula. Vem no P2 (loja
  in-game) e P4 (loja meta).
- **Sprite final da pétala** — placeholder por ora.
- **Inventário / loja meta** — P3 / P4.

## Arquivos afetados (estimativa)
- `scripts/player/player.gd` — `petals`, `petals_changed`, `add_petals`, reset
  por run.
- `scripts/ui/hud.gd` (+ cena da HUD) — `PetalDisplay`, conexão, depósito no
  record_run, linha no death screen, inclusão no `_collect_run_stats`.
- `scripts/systems/wave_manager.gd` — concessão de pétalas no `_finish_wave`
  (tabela por round + boss).
- `scripts/pickups/petal.gd` + `scenes/pickups/petal.tscn` — pickup novo
  (espelha gold).
- Caminho de drop do gold (onde decide dropar) — rolar o 0.75% de pétala.
- `scripts/systems/petal_bank.gd` (novo, sugerido) — get/add do banco persistente.
- Tela Player / menu principal — label do banco.
- `assets/i18n/translations.csv` — strings novas.
- Placeholder de sprite de pétala (asset).

## Notas de balance (ajustar no playtest)
Números (faixas por round, 0.75% drop, 19s lifetime) são pontos de partida —
fáceis de mexer. A escassez é proposital (sensação de progressão lenta e ganha).
