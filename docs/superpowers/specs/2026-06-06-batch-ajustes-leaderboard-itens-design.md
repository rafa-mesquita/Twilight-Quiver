# Batch de ajustes — Leaderboard, configs de tempo, itens (2026-06-06)

Conjunto de 6 ajustes pequenos/independentes. Cada um é isolado; podem ser
implementados e revisados separadamente. Sem bump de versão (só em deploy).

---

## 1. Leaderboard — painel de build/itens da run vira lateral direita + botão X

**Estado atual:** [run_build_modal.gd](../../../scripts/ui/run_build_modal.gd) cria um modal
em tela cheia: root `Control` `PRESET_FULL_RECT`, um `ColorRect` de overlay escuro
(`Color(0,0,0,0.65)`, full-rect, `MOUSE_FILTER_STOP`) e um `PanelContainer` `PRESET_CENTER`
(380px). Aberto por [leaderboard.gd:412](../../../scripts/ui/leaderboard.gd#L412)
(`add_child` + `open`). Fecha por ESC (`_unhandled_input`) e clique no overlay
(`_on_bg_input`) — **não há botão visível**, e o overlay **cobre o leaderboard**.

**Mudança:**
- **Remover o overlay escuro full-screen** (o leaderboard continua visível atrás).
- **Ancorar o painel à direita**, ocupando a faixa direita verticalmente com margens
  (largura ~380px). Root `Control` com `mouse_filter = IGNORE`; só o `PanelContainer`
  captura input (`STOP`), pra não bloquear cliques no leaderboard.
- **Adicionar um botão X** no canto superior direito do painel (header com título + X).
  `pressed → queue_free()`. ESC continua fechando. (Remover o fechar-por-clique-fora,
  que não faz sentido sem overlay.)
- i18n: reusar uma key de fechar se existir (`COMMON_*`); senão o X é só o símbolo "✕".

**Escopo:** só `run_build_modal.gd` (posicionamento/anchors + header com X). Nada no
leaderboard.gd além de, se necessário, garantir que o painel é instanciado uma vez só.

---

## 2. Configs — esconder informações de tempo (2 toggles)

**Estado atual:** três pontos mostram tempo, sempre visíveis:
- **Cronômetro live** no HUD: `RunTimerLabel`, atualizado em
  [hud.gd:1104](../../../scripts/ui/hud.gd#L1104) (`_update_run_timer_label`, chamado no `_process`).
- **Tempo do round + tempo da run** na tela "Wave Limpa" do shop:
  `cleared_info_label`, [wave_shop.gd:481](../../../scripts/ui/wave_shop.gd#L481).
- **Tempo da run** na death screen: dentro de `_build_death_stats_block`
  ([hud.gd:1824](../../../scripts/ui/hud.gd#L1824)).

**Mudança:** dois novos booleanos em `user://settings.cfg`, seção `[hud]`:
- `hide_run_timer` → esconde o cronômetro live (`RunTimerLabel.visible = false`).
- `hide_time_info` → esconde **o tempo do round+run** na tela de wave limpa **e** a linha
  de tempo da run na death screen.

**Padrão a seguir** (igual aos toggles existentes de vídeo/áudio):
- `settings_menu.tscn`: 2 linhas `HBox(Label + CheckBox)` novas; refs no
  [settings_menu.gd](../../../scripts/ui/settings_menu.gd) (`_load_current_settings` lê,
  `_on_apply_pressed` salva em `[hud]` e aplica).
- [game_state.gd](../../../scripts/systems/game_state.gd): vars `hide_run_timer`,
  `hide_time_info`; carregar no `_ready` (lendo o cfg) e expor pros consumidores.
- HUD/shop leem `GameState.hide_run_timer` / `GameState.hide_time_info` ao montar os
  respectivos textos/labels.
- i18n: `SETTINGS_HIDE_TIMER`, `SETTINGS_HIDE_TIME_INFO` (pt/en/es/fr).

**Fora de escopo:** o **leaderboard** (que é ranking de tempo) **não** é afetado — esses
toggles valem só pro in-game (HUD/shop/death).

---

## 3. Profano (curse) — inimigo convertido em aliado dropa gold no momento da conversão

**Estado atual:** a conversão é centralizada em
[curse_ally_helper.gd](../../../scripts/skills/curse_ally_helper.gd) (`try_convert_on_death`
→ `convert_to_ally`, seta `is_curse_ally = true`). Cada inimigo (monkey/mage/stone_cube/
dark_ball) chama `try_convert_on_death` **dentro** de `if not is_curse_ally:`, e o
`GoldDrop.try_drop` fica logo depois — então quando converte, retorna **sem** dropar gold
(design antigo "perdeu um aliado, não matou"). O aliado convertido também não dropa ao
decair (gated por `is_curse_ally`).

**Mudança:** rodar o sorteio de gold **no instante da conversão** (1× só), centralizado no
helper — assim o player é recompensado por "derrotar" o inimigo, e o decay continua sem
dropar (evita gold dobrado). Em `try_convert_on_death`/`convert_to_ally`, ao confirmar a
conversão, chamar `GoldDrop.try_drop(...)` na posição do inimigo **com os mesmos parâmetros
de chance de um abate normal** (NÃO é drop garantido 100% — é a % normal; o `try_drop` já
sorteia internamente contra a chance). Exceção: se o inimigo estiver nos grupos já excluídos
por anti-exploit (`insect`, `mini_mago_summon`), não dropa — preserva a regra do summoner/insect.

**A verificar na implementação:** assinatura exata de `GoldDrop.try_drop` e os args usados
nos call-sites dos inimigos (posição, scene/world, chance), pra replicar igual no helper.

---

## 4. Mestre Elemental — unlock de 10 → 5 compras da roleta

[inventory_items.gd:56](../../../scripts/systems/inventory_items.gd#L56): `value` de `10` → `5`
no req `elemental_roulette_buys_total`. O contador já existe e persiste. Atualizar o texto
da key `ITEM_REQ_ELEMENTAL` no CSV se ele citar "10".

---

## 5. Adote Mais Um — unlock vira só 300 kills de Aliado

[inventory_items.gd:64-67](../../../scripts/systems/inventory_items.gd#L64-L67): trocar os
dois reqs (curar 1500 **E** 1000 kills) por **um** req:
`{"stat": &"ally_kills_total", "value": 300, "label": "ITEM_REQ_ADOPT_KILLS"}`.
Atualizar `ITEM_REQ_ADOPT_KILLS` no CSV (1000 → 300). `ITEM_REQ_ADOPT_HEAL` fica órfã no
CSV (inofensivo). Stat `ally_kills_total` já existe e persiste.

---

## 6. Dividendo Arcano — +1 fixo vira sorteio em camadas (máx +2)

**Estado atual:** [inventory_items.gd:73](../../../scripts/systems/inventory_items.gd#L73)
`effect = {"type":"gold_per_round","amount":1}`; aplicado em
[wave_manager.gd:1013](../../../scripts/systems/wave_manager.gd#L1013) via
`InventoryItems.equipped_gold_per_round()` (soma fixa).

**Mudança (camadas, nunca soma):** ao fim do round, se equipado+liberado:
`if randf() < 0.02: +2  elif randf() < 0.50: +1  else: +0`. Média ~0,53/round.
- Adicionar helper `InventoryItems.arcane_dividend_roll() -> int` (0/1/2; 0 se não
  equipado/liberado), centralizando o sorteio.
- `wave_manager._finish_wave` usa o roll em vez do `equipped_gold_per_round()` fixo
  (que pode ser removido se ninguém mais usar).
- i18n: atualizar `ITEM_ARCANE_DIVIDEND_DESC` (pt/en/es/fr) pra descrever a chance
  ("ao fim de cada round, chance de ganhar gold extra").

---

## 7. Inventário — aba Equipamentos antes de Skins + aberta por padrão

[skin_select.gd](../../../scripts/ui/skin_select.gd): a barra de modos (`_build_mode_bar`)
adicionava Skins e depois Equipamentos, e `_ready` abria em `"skins"`. Mudança:
- Adicionar o botão **Equipamentos primeiro** (esquerda), Skins depois.
- `_inv_mode` default `"skins"` → `"equip"`; `_set_inv_mode("skins")` no `_ready` → `"equip"`.

## 8. Loja — tooltip de upgrade (todos os níveis) cortado embaixo

Bug: `_apply_tooltip_pos` ([wave_shop.gd](../../../scripts/ui/wave_shop.gd)) clampava o
tooltip com tela **fixa 1920×1080**; em janelas menores não empurrava o tooltip pra cima o
suficiente e o conteúdo cortava no rodapé. Fix: usar `get_viewport().get_visible_rect().size`
real no clamp (`_apply_tooltip_pos`) e no limiar de lado (`_position_card_tooltip`).

## Nota de implementação (#3)
O drop foi inlined no branch de conversão de cada inimigo (monkey/mage/stone_cube/dark_ball),
não no helper genérico — porque os parâmetros de gold (scene/chance/min/max) são por inimigo.
Insetos seguem sem dropar (não têm o bloco) e macacos do Mini Mago seguem excluídos.

## Ordem sugerida de implementação
Triviais primeiro (4, 5, 6 — edições de dados/constantes + i18n), depois o bug (3),
depois os de UI (2 settings, 1 painel). Cada um é commit/revisão independente.
