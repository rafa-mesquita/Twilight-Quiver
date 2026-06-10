# Diamante de Eulária — Design

Item equipável (1 dos 3 slots de inventário) que sorteia **um** upgrade pra ficar mais
forte a run inteira, em troca de você perder os rerolls da loja. Alto risco, alta recompensa.

---

## 0. Atualizações na implementação (divergências do design original)

- **Nome:** "Diamante de Eulária" (era "de Primeira Classe"). Id interno segue `diamante_primeira_classe`.
- **Unlock:** compra na **loja de pétalas por 350** (`loja_petalas.CATALOG`), não mais a quest "wave 14 sem reroll". O código do unlock-por-quest foi removido.
- **Carta:** sem broche/ícone — o emoji 💎 no texto basta. A linha fica **"💎 Upgrade do diamante: \<efeito\>"** no topo da desc, no tooltip da carta e no hover do item.
- **Boas-vindas:** não ocupa a **categoria exclusiva** do upgrade do diamante (ex: elementais), pra ele nunca ficar bloqueado na loja. (`get_diamond_exclusive_group` no player + filtro no `_grant_free_random_upgrade`.)
- **Hover no item da loja:** mostra qual upgrade foi sorteado nesta run.
- **Correções de base (resumo antigo estava errado):** Garras de Tigre real é 1/2/3/4 → diamante **1/3/4/5**. Gráviton explode **só no L4** → diamante explode no **L3** + **L4 +25%**.
- **VFX:** burst azul na explosão do gelo, burst roxo-escuro no AoE da fenda. As duas instâncias de dano entram no stats/TAB (fontes `ice_arrow` / `fenda`).

---

## 1. Mecânica do item

| # | Regra | Detalhe |
|---|-------|---------|
| 1 | **Sorteio no início da run** | Sorteia 1 dos 21 upgrades de build (`UPGRADE_POOL`), **excluindo** os que já vêm de graça de um item equipado (ver nota abaixo). Guardado em `_diamond_upgrade_id`, fixo até o fim da run. |
| 2 | **Versão diamante** | Enquanto a run dura, o upgrade sorteado usa a versão turbinada em **todos os níveis (L1–L4)**. Tabela na seção 2. |
| 3 | **Diamante na carta** | Quando o upgrade sorteado aparece na loja, a carta ganha um ícone de 💎 no canto **e a descrição mostra o que o diamante melhora** (linha 💎 destacada no fim da desc), pra o jogador saber o buff antes de comprar. É assim que ele descobre qual foi (sem aviso prévio). |
| 4 | **Sem rerolls** | Com o item equipado, o reroll global da loja fica desabilitado a run inteira. |
| 5 | **Não vem de graça** | O upgrade sorteado sai da `FREE_UPGRADE_POOL` (boas-vindas / grants grátis): tem que ser comprado na loja. |

**Aparição:** odds normais — pode aparecer tarde ou nunca, e sem rerolls pra cavar. É o risco.

**Unlock:** quest — passar da **wave 14** numa run **sem usar nenhum reroll**.

**Itens que dão upgrade de graça (disclaimer):** o sorteio do diamante **exclui** qualquer
upgrade que um item equipado já concede de graça no início (efeito `start_status` — ex: o
item que dá Ímã de Ouro +2). Se o sorteio cairia nesse upgrade, sorteia **outro** dos
restantes. Motivo: o diamante tem que ser comprado/conquistado, não pode coincidir com algo
que já veio grátis. Os itens continuam funcionando normal — só saem do pool do diamante.
Reusa `InventoryItems.start_granted_amount(id)` (`> 0` = exclui). Hoje só o Ímã de Ouro se
encaixa entre os 21; a regra é geral pra itens futuros.

**Casos de borda:**
- Equipado junto com **"Estou com Sorte"** (reroll grátis): o no-reroll do Diamante vence; o outro fica sem efeito.
- Upgrade sorteado nunca aparece → item não faz nada naquela run (risco aceito).
- O modal de **build da run** (leaderboard) mostra qual upgrade teve o diamante.
- Se TODOS os 21 estiverem excluídos por itens (improvável), o diamante não sorteia nada (item inerte na run).

**Arte/i18n:** ícone `assets/Hud/itens/diamante_primeira_classe.png` (a criar), keys `ITEM_DIAMANTE_*`, e um 💎 pequeno pro overlay da carta.

> 🔧 = a versão diamante adiciona **mecânica nova** (mais que troca de número), então pesa mais na implementação.

---

## 2. As 21 versões diamante

### Flechas / dano direto

**Perfuração (`perfuracao`)**
- Atual: perfura a cada 3/3/2/1 ataques; bônus de dano +30%/+60%/+90%/+90%; hitbox 1.8× (do L2).
- 💎 Diamante: bônus de dano ×1.3 (+39% / +78% / +117% / +117%), perfura 1 ataque mais cedo no L1/L2 (a cada 2), **e a hitbox maior já vale a partir do L1**.

**Múltiplas Flechas (`multi_arrow`)** 🔧
- Atual: 3 / 3 / 3 / 5 flechas (laterais 30%→65%→75%→85%).
- 💎 Diamante: **L3 vira 5 flechas** (o leque do L4 atual) e **L4 vira 10 flechas distribuídas em 360°** ao redor do player. (L1/L2 seguem 3.)

**Flechas Duplas (`double_arrows`)**
- Atual: chance de 2/3/5 flechas — 50% / 60% / 75%+45% / 90%+60%+5%.
- 💎 Diamante: chances +30% (65% / 78% / 90%+60% / 95%+75%+12%).

**Flecha Espectral (`spectral_arrow`)**
- Atual: 1×50% / 1×75% / 2×75% / 3×85%.
- 💎 Diamante: +1 espectral do L2 em diante (1 / 2 / 3 / 4) e dano +10%.

**Flecha Ricochete (`ricochet_arrow`)**
- Atual: 1 pulo / 1+split / 2 pulos / 2 pulos+2 splits (−80% dano por salto).
- 💎 Diamante: **+1 pulo por nível** (2 / 2 / 3 / 3).

**Flechas Críticas (`critical_chance`)**
- Atual: 30%/+50% · 50%/+50% · 70%/+60% · 100%/+65%.
- 💎 Diamante: **+10% no multiplicador de dano crítico** em todos os níveis (+60/+60/+70/+75%) **e +20% de chance de crit** em todos os níveis (50/70/90/100%, teto 100%).

### Elementais

**Flecha de Fogo (`fire_arrow`)**
- Atual: queima 6 / 7 / 9 / 12 dps; rastro de fogo do L2+.
- 💎 Diamante: dps de queima ×1.3 (8 / 9 / 12 / 16) **e +40% de dano nos dois rastros** (rastro de fogo + rastro da flecha).

**Fica Frio (`ice_arrow`)** 🔧
- Atual: congela 2.0s; dps 4 / 8 / 8 / 10; L3 invoca Frostwisp.
- 💎 Diamante: **inimigos que morrem congelados explodem** (dano em área + slow em área) **e a Frostwisp dá +10% de dano**.

**Disparo Profano / Maldição (`curse_arrow`)** 🔧
- Atual: DoT 3/4/6/8 dps; propagação pula em 75px; aliados convertidos decaem em 12s.
- 💎 Diamante: **propagação com range infinito** (a maldição pula sem limite de distância) **e o decay dos aliados convertidos dura 25s** (hoje 12s).

**Disparo de Pedra (`stone_arrow`)**
- Atual: alcance curto (downgrade de range); dano direto ×1.40/1.55/1.70/1.90; stun 2.0/2.3/2.6/3.0s.
- 💎 Diamante: **remove o downgrade de alcance** (alcance normal) **e +1s de stun** em todos os níveis.

**Fúria da Maré (`tide_arrow`)**
- Atual: −15% de dano de flecha; atk speed 0/20/25/30%.
- 💎 Diamante: **remove o −15% de dano de flecha** (sem penalidade) **e o L2 dá +10% de atk speed** a mais.

### Pulsos / raios

**Cadeia de Raios (`chain_lightning`)**
- Atual: salto da cadeia 1/2/4/∞ alvos; raio automático ganho a partir do L2.
- 💎 Diamante: **+1 alvo por nível** tanto no salto da cadeia quanto no raio automático (L2+).

**Gráviton (`graviton`)**
- Atual: pulso 45–50px; **explosão de dano SÓ no L4** (20 de dano, escala com o stat Dano). L1–L3 são puro slow/CC.
- 💎 Diamante: **explosão passa a acontecer já no L3** (hoje só L4) **e +25% no dano da explosão do L4** (20 → 25).

### Skills extras

**Boomerang Veloz (`boomerang`)**
- Atual: dano 15/20/32/42, cd 5→3s; 2 boomerangs no L3, 4 no L4.
- 💎 Diamante: dano ×1.5, cooldown −30%, **e o L4 lança 6 boomerangs** (em vez de 4).

**Garras de Tigre (`tiger_claws`)**
- Atual: alvos 1/2/2/4, dano 25/27/40/48 por arranhão.
- 💎 Diamante: **+1 alvo por nível a partir do L2** (1 / 3 / 3 / 5) **e +15% de dano** em todos os níveis.

### Mobilidade

**Deslizando / Dash (`dash`)** 🔧
- Atual: cd 6.3/5.3/4.8/4.3s; rastro de fogo a partir do L2.
- 💎 Diamante: cooldown −30% (4.4 / 3.7 / 3.4 / 3.0s), **rastro já a partir do L1**, **e no L2 o rastro dá +50% de dano**.

**Esquivando (`esquivando`)**
- Atual: +5/6/9/11% por stack (cap 3/3/4/5); dodge 2/2/5/5%.
- 💎 Diamante: % por stack ×1.3 (6.5 / 8 / 12 / 14%) e dodge +50% (3 / 3 / 8 / 8%).

**Fenda Crepuscular (`fenda`)** 🔧
- Atual: cd 20/18/16/14s; corte 25→50 de dano (corte a partir do L2).
- 💎 Diamante: cooldown −20% (16 / 14.4 / 12.8 / 11.2s), dano do corte +20%, **adiciona um dano em área no ponto de destino** (mesmo dano do corte) **e desde o L1 já tem o dano primário do corte** (que hoje só vem do L2).

**Adrenalina (`adrenalina`)**
- Atual: +0.5%/0.7% move por HP perdido; skill +15%/+30% atk speed.
- 💎 Diamante: move por HP perdido +50% (0.75% / 1.0% por HP) e atk speed da skill +30% (20% / 39%).

### Utilidade

**Mestre da Cura / Life Steal (`life_steal`)** 🔧
- Atual: cura 15/20/25/25% do dano no hit; puxa corações no L4.
- 💎 Diamante: cura por hit ×1.3 (20 / 26 / 33 / 33%), **puxa corações já a partir do L3**, **e cada coração pego dá +7% de move speed por 1s**.

**Chuva de Coins / Ímã (`gold_magnet`)**
- Atual: +5→9% chance de drop de ouro; ímã (puxa moedas) a partir do L3.
- 💎 Diamante: **puxa as moedas já a partir do L3** (mantém) **e +1% de chance de drop por nível a partir do L2** (acumulando).

---

## 3. Notas de implementação

- **Estado:** um único `_diamond_upgrade_id: String` no player (vazio = sem diamante). Setado por `InventoryItems.apply_to_player` no início da run, sorteando da lista dos 21 menos os excluídos por itens.
- **Aplicação:** cada versão diamante é lida no ponto onde aquele upgrade calcula o efeito (a maioria já tem função/const própria — ex: `_fire_burn_dps`, `CRIT_CHANCE_BY_LEVEL`, `DASH_COOLDOWNS_BY_LEVEL`). Quando o id bate com `_diamond_upgrade_id`, usa o valor/comportamento turbinado. Sem o item, comportamento idêntico ao atual.
- **Mecânicas novas (🔧):** `multi_arrow` (leque 360° no L4), `ice_arrow` (explosão ao morrer congelado), `curse_arrow` (range infinito de propagação), `dash` (rastro no L1 + dano no L2), `fenda` (dano em área no destino), `life_steal` (move speed por coração) — essas exigem código novo, não só troca de constante. Vão num lote separado das que são só número.
- **Loja:** no `_build_card`, se o id da carta == `_diamond_upgrade_id`, adiciona o overlay de 💎 **e injeta uma linha de descrição do buff** (key `SHOP_DIAMANTE_DESC_<UPGRADE>` por upgrade — 21 textos curtos player-facing, ex: "💎 L4 dispara 10 flechas em 360°"). Reroll global desabilitado se o item está equipado.
- **Boas-vindas:** `FREE_UPGRADE_POOL` exclui `_diamond_upgrade_id` na hora de sortear grant grátis.
- **Unlock (stat novo):** flag `reroll_used_this_run` — zera no início de cada run, vira `true` em qualquer reroll global. A quest libera quando o player passa da wave 14 com a flag ainda `false`. (Stat persistente só registra o "feito"; a flag em si é por-run.)
- **Faseável:** mecânica do item (sorteio + overlay 💎 + sem reroll + exclusões + unlock) primeiro; depois as 21 versões diamante em lotes (números → mecânicas novas).

---

## 4. Pendências

- [ ] Arte do ícone do item + ícone de 💎 da carta (única pendência de asset).
- [x] ~~Gráviton: explosão é só no L4 (confirmado no código). Diamante = explosão no L3 + L4 com +25%.~~
- [x] ~~Fenda: cd −20% (16 / 14.4 / 12.8 / 11.2s) — confirmado.~~
- [x] ~~Maré: L2 dá +10 pontos percentuais de atk speed — confirmado.~~
