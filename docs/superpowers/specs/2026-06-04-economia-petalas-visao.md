# Economia de Pétalas — Visão Geral (north star)

**Data:** 2026-06-04
**Tipo:** Documento de visão (não-implementável direto). Amarra 4 subprojetos,
cada um com seu próprio spec → plano → implementação.
**Status:** Visão aprovada. Próximo passo: brainstorm do P1.

## Objetivo

Criar uma **segunda moeda — pétalas** — que o jogador ganha jogando e dá uma
camada de **meta-progressão**: gastável dentro e fora do jogo (skins, upgrades
pré-jogo), pra dar sensação de avanço permanente entre partidas.

## As duas moedas

| | **Gold** (já existe) | **Pétala** (nova) |
|---|---|---|
| Ritmo | Abundante | Escassa |
| Vida | Zera a cada run | Carteira por-run **+ banco persistente** |
| Pra quê | Upgrades normais (3 cards/round) | Estruturas + itens fortes (in-game) **e** skins/itens meta (fora do jogo) |

Gold continua sendo a moeda "pão com manteiga" de cada round (os upgrades
normais). Pétala é a moeda **estratégica/premium**. As duas convivem; gold NÃO
é substituído — só perde o gasto de estruturas (ver P2).

## O loop central

1. **Ganho na run:** ao passar de level, o jogador ganha pétalas — valor
   **aleatório dentro de uma faixa fixa por round** (ex.: round 1 = 1–2 pétalas).
   Mobs têm chance **bem rara** de dropar pétala. A HUD mostra o saldo ao lado do
   gold, **começando do zero a cada run**.
2. **Gasto in-game:** a antiga loja de estruturas **morre e renasce** como a
   **loja de pétalas** — estruturas + itens fortes (ex.: second-life,
   super-upgrade de upgrade), todos por pétala.
3. **Depósito:** o que **sobrar** no fim da run (na morte) vai pro **banco
   persistente**.
4. **Gasto fora do jogo:** o banco só é gasto na **loja meta** (fora da partida):
   skins + itens equipáveis que dão melhorias pré-jogo.

### A tensão central (o que torna interessante)
Cada pétala gasta numa estrutura/second-life **agora** é uma pétala que **não**
vai pro banco da skin/item que você quer **depois**. Poder imediato vs.
progressão permanente — a decisão se repete a cada run.

## Modelo de saldo (decidido)

- **Carteira por-run:** cada run começa em **0 pétalas** na HUD; acumula durante
  a partida.
- **Depósito no fim:** ao morrer, o saldo não-gasto **soma no banco persistente**
  (salvo em `user://settings.cfg`, mesma mecânica dos stats de unlock de skin).
- **Banco só gasta fora do jogo.** In-game, o jogador só gasta o que ganhou
  **naquela** run.

## O Inventário

A aba **"Skins" vira "Inventário"**. Além das skins, guarda os **itens
equipáveis** (buffs pré-jogo). Características:
- Itens liberam por **missão** (mesma engrenagem das skin quests) e/ou compra na
  loja meta.
- Cada categoria de item tem um **número máximo de slots** equipados.
- A skin **World Cup** (já trancada com o label "disponível na loja por pétalas",
  via quest tipo `shop_petals`) é a primeira a usar esse novo fluxo de compra.

## Decomposição — 4 subprojetos (nesta ordem)

| # | Subprojeto | Cobre | Depende de |
|---|---|---|---|
| **P1** | **Pétalas (moeda-base)** — ganho (level-up + drop raro), HUD ao lado do gold, carteira por-run + banco persistente | passos 1 + 3 | — (fundação) |
| **P2** | **Loja de pétalas in-game** — transforma a loja de estruturas; estruturas + itens fortes por pétala | passo 2 | P1 |
| **P3** | **Inventário** — aba Skins → Inventário; slots; itens por missão; equipar buffs pré-jogo | passo 5 | P1 |
| **P4** | **Loja meta (fora do jogo)** — gastar o banco em skins + itens equipáveis | passo 4 | P1 + P3 |

**Sequência:** P1 é a fundação (auto-contido — dá pra ver pétalas acumulando na
HUD e no banco antes de qualquer loja). P2 é a primeira torneira de gasto
(reusa muito o `wave_shop`). P3 + P4 são a camada de meta-progressão — e o P4
**destrava a World Cup**.

## Pontos deixados pros specs de cada subprojeto

- **Escassez/balance:** faixas exatas de pétala por round, taxa de drop de mob,
  preços das lojas (P1 define ganho; P2/P4 definem preços).
- **Tipos de buff pré-jogo** dos itens equipáveis e quantos slots por categoria
  (P3/P4).
- **Skins: missão vs compra** — quais destravam por quest, quais por pétala,
  quais por ambos (mission gate + preço). World Cup é o primeiro caso de compra
  (P4).
- **UI:** como a loja de pétalas in-game e a HUD do saldo se encaixam no layout
  atual (P1/P2).

## Integrações com o que já existe

- **Gold:** `player.gold` + `add_gold`/`spend_gold` + signal `gold_changed` →
  HUD `$GoldDisplay/CountLabel`. Pétala segue o mesmo padrão (var + signal +
  display irmão).
- **Persistência:** `SkinLoadout.get_stat/set_stat` em `settings.cfg [progress]`
  — o banco de pétalas vira mais uma chave persistente.
- **Loja:** `wave_shop.gd` (seção de Estruturas é o que o P2 transforma).
- **Skins/quests:** `skin_select.gd` + `skin_loadout.gd` (`SKIN_QUESTS`,
  loadout, slots) — base do Inventário (P3) e do unlock por missão.
- **Loja meta (fora):** provavelmente nova tela/aba; a World Cup já espera por
  ela (`shop_petals`).
