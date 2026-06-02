# Perfuração com alcance total + correção da quest do Patriota

**Data:** 2026-06-02
**Status:** Aprovado, pronto pra plano de implementação

## Problema

A skin **Patriota** desbloqueia com a quest `long_mage_kill`: "matar um mago a longa
distância com a flecha". A condição implementada exige que a flecha tenha viajado
`LONG_MAGE_KILL_DIST = 480px` do disparo até o impacto
([arrow.gd:1254](../../../scripts/skills/arrow.gd)).

Mas a flecha **normal (mesmo com perfuração)** tem alcance fixo de **330px**
(`speed = 220` × `lifetime = 1.5s`). A perfuração **não estende o alcance** hoje —
só faz a flecha atravessar inimigos/objetos. O único projétil que passa de 480px é
Pedra + Perfuração (`_stone_pierce_lifetime() = 5.0s`).

Resultado: **480px > 330px** → a condição é impossível de satisfazer com flecha
comum/perfurante. O jogador matou magos com perfuração comum e a quest nunca liberou,
porque a flecha despawnava aos 330px antes de chegar no mago.

A cadeia de tracking em si está correta ponta a ponta e **não muda**:
`arrow.notify_long_mage_kill` → `player.stats_long_mage_kill` → `hud._collect_run_stats`
→ `SkinLoadout.record_run` → `STAT_LONG_MAGE_KILL` → unlock.

## Intenção de design

A perfuração deve **aumentar o alcance da flecha** — vira uma feature dela. A quest
então exige um kill **além do alcance da flecha normal**, o que só é possível graças a
esse alcance extra. Matar um mago a ≥350px com flecha perfurante **prova** que o bônus
de alcance da perfuração foi usado. Tema "lançamento longo" (futebol americano) mantido.

## Solução

### Parte 1 — Perfuração ganha alcance "infinito" (Lv1+)

A flecha perfurante passa a viver muito mais tempo, atravessando o mapa inteiro.

- A arena jogável é ~510×284px (`wander_bounds`), diagonal máx ~584px.
- Flecha perfurante: `lifetime` 1.5s → **4.0s** → ~880px de alcance (×220 speed) ≈
  1.5× a diagonal do mapa. De qualquer posição, a flecha cruza a arena inteira e
  despawna invisível fora dos bounds (sem vazamento — o timer de lifetime já existe).
- Aplicado no bloco `if is_pierce:` de `player._spawn_arrow`. Vale pra flecha primária
  E extras perfurantes (Multi Arrow / Flechas Duplas), desde o Lv1.
- **Stone + Perfuração não muda:** o bloco da pedra roda DEPOIS do bloco `is_pierce`
  em `_spawn_arrow` e sobrescreve com `_stone_pierce_lifetime() = 5.0s` próprio.

### Parte 2 — Quest do Patriota

- `LONG_MAGE_KILL_DIST`: `480.0` → **`350.0`** (= alcance normal 330 + 20). Flecha sem
  perfuração morre aos 330px, então um kill a ≥350px só acontece com o alcance bônus.
- Condição do unlock (em `arrow._notify_player_dmg_kill`, no path de hit direto):
  - hit direto de flecha (não chain/AoE), E
  - `is_piercing == true` (flecha perfurante), E
  - alvo é mago (`_target_is_mage`, já cobre comum/invocador/fogo/gelo/elétrico; boss
    `mage_monkey` não conta), E
  - `_spawn_pos.distance_to(global_position) >= LONG_MAGE_KILL_DIST`.
- **Robustez:** a checagem hoje mora dentro de `_notify_player_dmg_kill`, que também é
  chamada pela Cadeia de Raios ([arrow.gd:1158](../../../scripts/skills/arrow.gd))
  usando a posição da *flecha* (não do inimigo encadeado) — fonte de falso
  positivo/negativo. Adicionar parâmetro `count_long_mage: bool = false`; só o hit
  direto ([arrow.gd:546](../../../scripts/skills/arrow.gd)) passa `true`. Chain/AoE
  ficam no default `false`.

### Parte 3 — Texto e comentários

- `PLAYER_QUEST_PATRIOTA` em `assets/i18n/translations.csv` (pt_BR/en/es/fr) →
  "Elimine um mago a longa distância com uma flecha perfurante" (e traduções).
- Atualizar comentários defasados que citam "480px / 1.45x range":
  - `arrow.gd` (perto do `const LONG_MAGE_KILL_DIST`).
  - `skin_loadout.gd` (comentário da entrada `Patriota` em `SKIN_QUESTS`, e a linha de
    doc do tipo `long_mage_kill`).

## Arquivos afetados

| Arquivo | Mudança |
|---|---|
| `scripts/player/player.gd` | `_spawn_arrow`: setar `arrow.lifetime = 4.0` no bloco `is_pierce`. |
| `scripts/skills/arrow.gd` | `LONG_MAGE_KILL_DIST` 480→350; gate `is_piercing` + `count_long_mage` na condição; novo param em `_notify_player_dmg_kill`; comentários. |
| `assets/i18n/translations.csv` | Reescrever `PLAYER_QUEST_PATRIOTA` (4 línguas). |
| `scripts/systems/skin_loadout.gd` | Comentários defasados (480px/1.45x). |

## Fora de escopo

- Não mexer na cadeia de tracking/unlock (já funciona).
- Não escalar o alcance da perfuração por nível (decisão: infinito desde Lv1).
- Não tocar no comportamento de kiting dos magos (`preferred_distance = 130`).
- Sem bump de versão (não é deploy; ver CLAUDE.md).

## Critérios de aceite

1. Com Perfuração ativa, a flecha perfurante atravessa o mapa inteiro de qualquer
   posição (não despawna mais aos 330px visíveis).
2. Matar um mago a ≥350px com flecha perfurante (hit direto) seta `stats_long_mage_kill`
   e, no death, desbloqueia a Patriota.
3. Matar um mago de perto (<350px), ou com flecha não-perfurante, ou via chain/AoE,
   NÃO conta.
4. Stone + Perfuração continua com alcance ~750px (inalterado).
5. Texto da quest atualizado nas 4 línguas, sem citar 480px.
