# Itens desbloqueáveis (lock UI + tracking + efeitos) — Design

> Data: 2026-06-05
> Branch: `feature/economia-petalas`
> Escopo escolhido pelo user: **tudo de uma vez** (UI + tracking persistente + efeitos).
> Relacionado: [[feature_skin_lock_ui]], Inventário v1, economia de pétalas.

## Objetivo

Transformar os itens do inventário num sistema de **desbloqueio** análogo às skins:
itens travados aparecem no inventário com visual de bloqueio e o requisito no hover;
itens liberados se comportam normal (arrastáveis/equipáveis). 2 itens novos +
re-categorização dos 2 existentes + 1 item liberado de exemplo (Mestre Elemental).

Também: **corrigir tooltips do StatsCard do shop que vazam abaixo da tela** (upgrades,
itens, aliados) — bug de clamp de posição.

## Catálogo final (`InventoryItems.ITEMS`)

| id | nome | efeito | desbloqueio |
|----|------|--------|-------------|
| `midnight_dagger` | Adaga da Meia-Noite | +1 status de Dano (start) | **loja** ("Disponível na loja") |
| `golden_bow` | Arco Dourado | +1 Vel. Ataque (start) | **loja** |
| `elemental_master` | Mestre Elemental | escolha de elemental no welcome | **sempre liberado** (exemplo) |
| `adopt_one_more` | Adote Mais Um | **+1 slot de Aliado** | **quest**: curar 1500 via Aliado **E** 1000 kills de Aliado |
| `arcane_dividend` | Dividendo Arcano | **+1 gold no fim de todo round** | **quest**: gastar 2500 gold no total |

### Modelo de `unlock` (campo novo em cada item)
- `{"type": "default"}` → sempre liberado.
- `{"type": "shop"}` → travado por enquanto (loja meta P4 não existe); tooltip = `ITEM_UNLOCK_SHOP`.
- `{"type": "quest", "reqs": [{stat, value, label}, ...]}` → liberado se **TODAS** as reqs
  satisfeitas (`SkinLoadout.get_stat(stat) >= value`). Tooltip lista cada req (vermelho se
  falta, branco se cumprida — igual skin).

## Stats persistentes novos (em `SkinLoadout`, reusa `get_stat`/`set_stat` no `[progress]`)

- `STAT_ALLY_HEAL = &"ally_heal_total"`
- `STAT_ALLY_KILLS = &"ally_kills_total"`
- `STAT_GOLD_SPENT = &"gold_spent_total"`

Acumulados em `SkinLoadout.record_run(run_stats)` a partir das chaves de run
`ally_heal`, `ally_kills`, `gold_spent` (somadas ao total persistente, padrão dos demais).

## Tracking no gameplay (run-stats no player → `_collect_run_stats`)

- **ally_kills**: SOMA de `player.stats_kills_by_source[src]` para `src` em
  `ALLY_KILL_SOURCES = {"frostwisp","ting_turret","capivara_joe","leno","claudio_druida"}`
  (já são creditados hoje via `notify_kill_by_source`). Calculado em `_collect_run_stats`.
- **ally_heal**: novo contador `player.stats_ally_heal: float`, incrementado nos sites de cura
  POR ALIADO:
  - `capivara_mushroom.gd` no `player.heal(...)` da cura.
  - `arbusto` heal-per-hit (no ponto do player que aplica o `heal_per_hit` do bush).
  Exposto em `_collect_run_stats` como `ally_heal`.
- **gold_spent**: novo contador `player.stats_gold_spent: int`, incrementado em
  `player.spend_gold(amount)` (hook central). Exposto como `gold_spent`.

`_collect_run_stats` (hud.gd) ganha as 3 chaves; `record_run` acumula nos STAT_* novos.

## Efeitos

- **+1 slot de Aliado** (`adopt_one_more`): `wave_shop` passa a usar
  `_effective_pet_cap() = MAX_DISTINCT_PETS + (1 se adopt_one_more equipado E liberado)`.
  Usado no gate de compra (`pet_capped`, ~linha 705) e no roll de aliados. O display já
  mostra 3 slots (`PETS_DISPLAY_SLOTS`); sem o item o 3º fica reservado (não comprável),
  com o item vira comprável.
- **+1 gold/round** (`arcane_dividend`): em `wave_manager._finish_wave`, se equipado+liberado,
  `player.add_gold(1)`.
- `start_status` (dagger/bow) e `welcome_elemental_choice` (elemental) inalterados.
  `apply_to_player` continua só `start_status`.

## Desbloqueio / posse

`InventoryItems`:
- `is_unlocked(id) -> bool` (substitui o `is_owned` placeholder):
  - `default` → true; `shop` → false (por ora); `quest` → todas reqs satisfeitas.
  - DEV: `DEV_UNLOCK_ALL_ITEMS: bool = false` (em debug, true libera tudo p/ testar). Mantido
    **false** por padrão pra o user VER o estado travado agora.
- `get_equipped()` passa a filtrar por `is_unlocked` (item travado nunca fica ativo).
- `toggle_equipped`/UI: só item liberado equipa.

## UI do Inventário ([skin_select.gd](scripts/ui/skin_select.gd))

Espelha a UX de skin travada:
- Lista de itens mostra **todos** (não só liberados). Liberado = chip normal arrastável.
  Travado = ícone dessaturado/escurecido + **"!"** no canto + (nome vermelho se houver label) +
  **não arrastável**.
- Drag forwarding recusa itens travados.
- Slots equipados: item travado não aparece equipado (`get_equipped` filtra).
- `_show_item_tooltip(id)`: 
  - liberado → nome + descrição do efeito.
  - travado → nome + "Como liberar:" + linhas de requisito (vermelho=falta, branco=cumprido)
    ou `ITEM_UNLOCK_SHOP` pros itens de loja.
- Reaproveita `_make_lock_badge` (já existe pra skins).

## Fix das tooltips do StatsCard (overflow)

Os 4 sites (`_on_augment_hovered`, item, pet, "ver todos") usam o mesmo clamp falho:
`clampf(pos.y, 16.0, 1080.0 - tip_size.y - 16.0)`. Quando a tooltip é mais alta que a área,
`max < min` e o clamp se comporta mal → vaza embaixo. Fix:
- Helper único `_place_augment_tooltip_left_of(chip_global)`:
  - espera o layout assentar (2 frames; tooltip com RichText + autowrap),
  - `var max_y = maxf(16.0, 1080.0 - tip_h - 16.0)`,
  - `pos.y = clampf(pos.y, 16.0, max_y)` (se mais alta que a tela, ancora no topo).
- Os 4 sites passam a chamar o helper (dedup).

## Arte

Decodar (decoder Python validado, 32×32, todas as layers compostas):
- `assets/Hud/itens/Adote Mais Um.aseprite` → `adopt_one_more.png`
- `assets/Hud/itens/Dividendo arcano.aseprite` → `arcane_dividend.png`
Depois `--import` (gera `.import`/`.ctex`). dagger/bow/elemental já têm PNG.

## i18n (`translations.csv`, 5 colunas pt/en/es/fr)

- `ITEM_ADOPT_ONE_MORE_NAME/DESC`, `ITEM_ARCANE_DIVIDEND_NAME/DESC`
- `ITEM_UNLOCK_SHOP` ("Disponível na loja")
- `ITEM_REQ_ADOPT_HEAL`, `ITEM_REQ_ADOPT_KILLS`, `ITEM_REQ_ARCANE_GOLD`
- `ITEM_UNLOCK_HOW` ("Como liberar:")

## Arquivos afetados

- `scripts/systems/inventory_items.gd` — catálogo (2 itens + unlock), `is_unlocked`, DEV flag,
  `get_equipped` filtra, `get_icon_path` (já existe), efeito helpers (`gives_pet_slot`,
  `gives_gold_per_round`).
- `scripts/systems/skin_loadout.gd` — 3 STAT_* novos + acumular em `record_run`.
- `scripts/player/player.gd` — `stats_ally_heal`, `stats_gold_spent`; incrementos em
  `heal` (via aliado) e `spend_gold`.
- `scripts/allies/capivara_mushroom.gd`, `scripts/allies/arbusto.gd` (ou player no ponto do
  bush heal) — marcar cura como ally heal.
- `scripts/ui/hud.gd` — `_collect_run_stats` expõe `ally_heal`/`ally_kills`/`gold_spent`.
- `scripts/systems/wave_manager.gd` — `_finish_wave` +1 gold se `arcane_dividend`.
- `scripts/ui/wave_shop.gd` — `_effective_pet_cap()`; fix tooltip clamp (helper único).
- `scripts/ui/skin_select.gd` — UI de item travado (lista, drag, tooltip).
- `assets/Hud/itens/` — 2 PNGs novos (+ .import).
- `assets/i18n/translations.csv` — keys novas.

## Edge cases

- Item travado equipado em save antigo → `get_equipped` filtra (não aplica efeito).
- Stats começam em 0 → quest items travados (estado que o user quer ver agora).
- `adopt_one_more` desequipado no meio: cap volta a 2 no próximo cálculo (recompute por chamada).
- Arte faltando → chip renderiza vazio (não quebra).

## Fora de escopo

- Loja meta (P4) que de fato libera os itens de `shop` — vem depois.
- Balance dos valores (1500/1000/2500) — placeholders do user, fáceis de ajustar.
