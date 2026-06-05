# P2 — Loja de Pétalas in-game ("ESPECIAL") — Design

**Data:** 2026-06-05
**Subprojeto:** P2 da [Economia de Pétalas](2026-06-04-economia-petalas-visao.md)
**Status:** Design aprovado, pronto pro plano de implementação
**Depende de:** P1 (pétalas moeda-base) — já implementado.

> **Prioridade do roadmap (pedido do user):** implementar **P2 (loja) + P3
> (inventário)** primeiro; a loja meta fora do jogo (P4) vem depois.

## Contexto

A seção **"ESTRUTURAS"** do wave shop **morre e vira a loja de pétalas**
("ESPECIAL"). Hoje essa seção
([wave_shop.gd](../../../scripts/ui/wave_shop.gd)):
- Tem **2 cards** (`estrut_cards`, `estrutura_slots`), rolados em
  `_roll_estrutura_slots` ([:620](../../../scripts/ui/wave_shop.gd#L620)).
- Pool atual = só `arrow_tower` (`_STRUCTURES_ROW`,
  [:356](../../../scripts/ui/wave_shop.gd#L356)); 2º slot é "Em breve".
- Compra por **gold** (`_buy_estrutura` [:1863](../../../scripts/ui/wave_shop.gd#L1863),
  checa `player.gold`); estrutura entra na **fila de placement**.
- Gated: wave 8+, a cada `ESTRUT_UNLOCK_INTERVAL=4` waves, bloqueada na wave 13.

## Design

### 1. A seção "ESPECIAL"

- **Header renomeado** "ESTRUTURAS" → **"ESPECIAL"** (i18n).
- **Aparição aleatória:** a loja só aparece com **10% de chance por shop a partir
  da wave 6**. Quando NÃO aparece, os 2 cards ficam no estado **locked/vazio**
  (reusa o visual "locked" atual).
- **Pity:** garante que a loja apareça **pelo menos 1× antes da wave 14**. Flag
  por-run `_petal_shop_seen`. Se chegou no último shop antes da 14 (wave 13) sem
  ter aparecido, **força** a aparição nesse shop. (Hoje a wave 13 bloqueia
  estruturas pré-Duskrose — a loja de pétalas SUBSTITUI esse bloqueio quando o
  pity dispara.)
- Substitui o gate antigo (wave 8 / a cada 4 / bloqueio wave 13) pela lógica
  acima em `_roll_estrutura_slots`.

### 2. Pool de itens (v1) — rola 2 de 3

Quando a loja aparece, sorteia **2 itens distintos** de um pool de 3:

| Item | id | Efeito | Preço (pétalas, provisório) |
|---|---|---|---|
| 🏹 Torre de Flechas | `arrow_tower` | A torre atual (auto-ataca). Placement igual hoje. | 3 |
| ❤️ Segunda Vida | `second_life` | +1 carga de revive. Ao morrer, consome 1 carga e revive com 50% do max HP. **Empilhável** (comprar mais = mais cargas). | 8 |
| ⬆️ Super-Upgrade | `super_upgrade` | +1 nível instantâneo em cada status (HP, Dano, Vel. Mov., Vel. Atq., Armadura), respeitando os caps de cada um. | 6 |

A Torre **rola junto** (pode não cair num shop em que a loja apareça).

### 3. Mecânica de cada item

**Torre de Flechas** — sem mudança de comportamento; só o **preço vira pétala** e
o gasto debita `player.petals`. Mantém placement + (decidir no plano se mantém o
`STRUCTURE_SURCHARGE_PER_OWNED`; sugiro **remover** o surcharge — pétala já é
escassa).

**Segunda Vida** — novo estado no player: `petal_second_life_charges: int`.
- Comprar: `+1` carga.
- No death (hook em `take_damage`/`_apply_poison_tick` quando `hp <= 0`): se
  `charges > 0`, consome 1, restaura HP pra `0.5 * max_hp`, cancela a morte
  (mesma ideia do god mode, mas one-shot por carga). Feedback visual (flash/ToY).
- Reseta com a run (carteira por-run; o player é recriado).

**Super-Upgrade** — ao comprar, chama `player.apply_upgrade(id)` para cada status
em `["hp", "damage", "move_speed", "attack_speed", "armor"]`. `apply_upgrade` já
respeita os caps; status no cap simplesmente não sobe. Aplicado no **commit** da
compra.

### 4. Gasto de pétalas

- Novo `player.spend_petals(amount) -> bool` (espelha `spend_gold`
  [:3105](../../../scripts/player/player.gd#L3105)): debita `petals`, emite
  `petals_changed`, retorna false se saldo insuficiente.
- Os cards da seção ESPECIAL checam **`player.petals`** (não `player.gold`) pra
  affordability (`_buy_estrutura` e os checks de custo em
  `_selected_total_cost`/commit).
- ⚠ **Custo misto:** o shop hoje soma um `_selected_total_cost()` em gold (status
  + estrutura + aliado + upgrade). Os itens de pétala têm uma carteira SEPARADA
  (pétala), então o cálculo de affordability da seção ESPECIAL é **independente**
  do total em gold. Decidir no plano: rastrear `_selected_petal_cost` à parte e
  checar contra `player.petals`; o resto do shop segue em gold.
- No `_commit_upgrades_and_close`
  ([:2172](../../../scripts/ui/wave_shop.gd#L2172)): debitar pétalas dos itens de
  pétala selecionados; Torre vai pro placement; Segunda Vida/Super-Upgrade
  aplicam o efeito no player.

### 5. UI / reorganização
- Header "ESPECIAL" + o contador de pétalas (já posto à direita do header no P1).
- Cards reusam o template atual (arte placeholder por item; arte final depois).
- Estado locked quando a loja não aparece (reusa o card "locked").

## i18n
Novas keys em [translations.csv](../../../assets/i18n/translations.csv) (5 col):
nome/descrição de cada item (`SHOP_SPECIAL_*`, `SHOP_SECOND_LIFE_*`,
`SHOP_SUPER_UPGRADE_*`), header `SHOP_SPECIAL_HEADER`, e textos de locked.

## Fora de escopo (P2)
- **Mais itens no pool** — amplia depois.
- **Gastar o BANCO de pétalas** — isso é a loja meta (P4), fora do jogo.
- **Arte final dos itens** — placeholder por ora.
- **Inventário** — P3 (próximo subprojeto).

## Arquivos afetados (estimativa)
- `scripts/ui/wave_shop.gd` — `_roll_estrutura_slots` (aparição 10% + pity + pool
  de 3), pool de itens, `_buy_estrutura`/custo em pétala, commit (debita pétala +
  aplica efeitos), header "ESPECIAL".
- `scripts/player/player.gd` — `spend_petals`; `petal_second_life_charges` +
  revive no death; (super-upgrade reusa `apply_upgrade`).
- `assets/i18n/translations.csv` — strings novas.
- Arte placeholder dos cards (Segunda Vida / Super-Upgrade).

## Notas de balance (playtest)
Chance 10%/wave (da 6), pity antes da 14; preços 3/8/6 — todos provisórios.
Segunda Vida revive a 50% HP; Super-Upgrade +1 em cada status. Ajustar no jogo.
