# Leaderboard: modal de build + nova temporada (release 0.11.0)

> Spec de design. Data: 2026-06-06. Status: aprovado, pronto pro plano.

## Contexto

O leaderboard ganhou em 0.10.2 duas abas: **"Por Waves"** e **"Tempo até o 21"**.
A aba de tempo já foi conectada a um ranking global nesta sessão (ver
[2026-06-06-leaderboard-tempo-21-backend-contract.md](2026-06-06-leaderboard-tempo-21-backend-contract.md)) —
backend `time_to_w21_ms` (migration 0004) + cliente `fetch_time21`. Isso já está
implementado e validado, **falta deployar**.

Este spec cobre o pacote maior da **release 0.11.0**:

1. **Modal "Build da Run"** — botão por linha do leaderboard que abre os upgrades
   (texto, agrupados) + itens equipados (ícones) daquela run.
2. **Nova temporada** — devido às mudanças grandes de balance/score, o board
   principal **reinicia a contagem na 0.11.0**. Runs antigas **não são apagadas**;
   ficam num arquivo acessível por um indicador discreto.

## Objetivos

- Guardar a "build" (upgrades + itens) de cada run no backend e exibir num modal.
- Botão de build em **toda linha** (qualquer jogador), nos dois boards.
- Reiniciar o ranking principal a partir da 0.11.0, preservando o histórico.
- Acesso discreto às runs antigas (arquivo "Por Waves").

## Não-objetivos

- Apagar dados antigos (explicitamente preservados).
- Arquivo da aba "Tempo até o 21" (a aba é nova; só arquivamos "Por Waves").
- Editar/comparar builds, filtros avançados no arquivo.
- Backfill de build em runs antigas (impossível — o dado não existia).

## Decisões (do brainstorming)

| Tema | Decisão |
|------|---------|
| Botão de build | Em **toda linha** (qualquer run), nos dois boards. |
| Runs sem build (antigas) | Botão **desabilitado**; modal mostra "Build não registrada". |
| Modelo de dados | **1 coluna `jsonb`** `build` (padrão do `bosses_killed`). |
| Layout do modal | Upgrades = **texto** "Nome — Lv.X"; itens = **ícones**. |
| Categorias (ordem) | Elemental → Upgrades padrão → Status → Aliados → Itens. |
| Corte da temporada | Por **versão** via `version_num` inteiro; marca = **0.11.0** (`11000`). |
| Arquivo ("!") | Abre só o **"Por Waves" antigo** (runs `version_num < 11000`). |
| Versão da release | `pre-alpha-0.11.0`. |

## Arquitetura

### 1. Captura da build (cliente)

Em [hud.gd](../../../scripts/ui/hud.gd) `_collect_run_stats(wave_num)`, adicionar
ao dict retornado:

```gdscript
"build": {
    "upgrades": { "<id>": <level>, ... },   # só level > 0
    "items":    [ "<item_id>", ... ],        # InventoryItems.get_equipped()
}
```

- **upgrades**: itera os ids conhecidos (os mesmos de `dev_panel._ALL_UPGRADE_IDS`
  / pools da loja) chamando `player.get_upgrade_count(id)`; grava só `> 0`.
  `get_upgrade_count` cobre status (HP/Dano inclusive), pool, elementais e aliados.
- **items**: `InventoryItems.get_equipped()` (loadout da run).
- Vai junto no payload do `submit_run` (já existe `_build_run_payload`).

### 2. Backend (`twilight-quiver-site`)

Migration nova (após a 0004 do tempo) adicionando **duas colunas** em `runs`:

- `build jsonb NOT NULL DEFAULT '{}'::jsonb`
- `version_num integer NOT NULL DEFAULT 0` — índice pra filtro de temporada.

**POST** (`app/api/runs/route.ts`):
- zod aceita `build` opcional:
  `{ upgrades: record<string, int>, items: string[] }` com caps
  (ex.: ≤ 64 chaves em upgrades, ≤ 16 itens, ids ≤ 64 chars) contra abuso.
- Calcula `version_num` a partir de `version` (regex `(\d+)\.(\d+)\.(\d+)` →
  `maj*1_000_000 + min*1_000 + patch`; ex.: `0.11.0 → 11000`, `0.10.10 → 10010`).
  Sem match → `0`.
- Grava `build` e `version_num`.

**GET** (`app/api/runs/route.ts`):
- Constante `SEASON_MIN = 11000`.
- Default (board por score) e `board=time_w21` → `WHERE version_num >= SEASON_MIN`
  (+ filtro de `version` exato quando vier, dentro da temporada).
- `?archive=true` → `WHERE version_num < SEASON_MIN`, board por score
  ("Por Waves" antigo). Sem dropdown de versão.
- Toda linha da resposta passa a incluir `build` (objeto; `{}` em runs sem dado).

> Runs existentes herdam `version_num = 0` (< 11000) → caem no **arquivo**
> automaticamente. Nenhum backfill necessário. Temporada nova começa vazia e
> enche a partir dos primeiros submits 0.11.0.

### 3. Modal de build (cliente) — JÁ PROTOTIPADO

[run_build_modal.gd](../../../scripts/ui/run_build_modal.gd) (`class_name RunBuildModal`,
construído em código). API: `open(row: Dictionary)`.

- Cabeçalho: nick · wave · tempo · score.
- Categorias na ordem definida, só renderiza as não-vazias. Upgrade = linha
  "Nome — Lv.X". Itens = `HFlowContainer` de `TextureRect` (ícone de
  `InventoryItems.ITEMS[id].icon`, nome no `tooltip_text`).
- `build` ausente/vazio → "Build não registrada nesta run." (`LEADERBOARD_BUILD_NONE`).
- Fecha ao clicar fora ou ESC.
- Mapa id→name_key embutido reusa keys existentes da loja (`SHOP_UPG_*`,
  `SHOP_STAT_*`, `SHOP_ALLY_*`) e do catálogo de itens (`ITEM_*_NAME`).

Cena de teste DEV: [build_modal_test.tscn](../../../scenes/ui/build_modal_test.tscn)
(F6; ESPAÇO = build aleatória, N = run antiga). Não entra no jogo de release.

### 4. UI do leaderboard (cliente)

[leaderboard.gd](../../../scripts/ui/leaderboard.gd):

- **Coluna extra** no fim de cada linha (waves e tempo) com botão **🔍**
  (`LEADERBOARD_VIEW_BUILD`). `pressed` → instancia `RunBuildModal` e chama
  `open(row)` passando o dict da linha (que carrega `build`).
- **Build vazia = build ausente** (mesmo tratamento): se `build` não veio,
  veio `{}`, ou tem `upgrades` e `items` ambos vazios, o botão fica `disabled`
  com `tooltip_text = LEADERBOARD_BUILD_NONE`. Isso cobre tanto runs antigas
  (coluna default `{}`) quanto runs novas que morreram cedo sem comprar nada —
  nos dois casos não há o que mostrar. O label "Build não registrada" dentro do
  modal continua existindo como fallback (e é usado pela cena de teste DEV).
- **Indicador "!" discreto à direita** (estilo o "(?)" de
  [version_label.gd](../../../scripts/ui/version_label.gd)) → abre o **arquivo**:
  refaz o fetch com `?archive=true` e renderiza o "Por Waves" antigo (reusa
  `_render_waves`). Tooltip "Runs antigas". Botão "voltar" retorna à temporada atual.

### 5. i18n (keys novas — já adicionadas ao CSV)

`LEADERBOARD_VIEW_BUILD`, `LEADERBOARD_BUILD_NONE`, `LEADERBOARD_BUILD_CAT_ELEMENTAL`,
`_STANDARD`, `_STATUS`, `_ALLIES`, `_ITEMS`. Nomes de upgrade/status/aliado/item
reusam keys existentes. (Arquivo pode precisar de 1 key de título tipo
`LEADERBOARD_ARCHIVE_TITLE` — adicionar no plano.)

### 6. Dev (opcional, pós-deploy)

Botão "Enviar run de teste" no [dev_panel.gd](../../../scripts/ui/dev_panel.gd):
monta payload com build aleatória + `time_to_w21_ms` válido e `submit_run`, pra
validar o pipeline ponta-a-ponta no ambiente real. Gated por `OS.is_debug_build()`.

## Contrato de dados

Payload `POST /api/runs` (campos novos em **negrito**):

```json
{
  "nickname": "...", "version": "pre-alpha-0.11.0",
  "wave": 24, "score": 12340, "time_ms": 312000, "time_to_w21_ms": 312000,
  "kills": 1500, "allies": 3, "dmg_dealt": 200000, "dmg_taken": 5000,
  "bosses_killed": ["mage_monkey", "..."],
  "build": { "upgrades": { "attack_speed": 4, "fire_arrow": 4 }, "items": ["sanguinario"] }
}
```

Linha `GET /api/runs` (campos novos em **negrito**): inclui `build`. (`version_num`
é interno, não precisa voltar.)

## Plano de deploy

Pacote único da **0.11.0**:

1. **Backend** (`twilight-quiver-site`): branch de tempo (0004, já feita) + migration
   nova (build + version_num) + POST/GET. Merge `main` → push → Coolify redeploya e
   roda migrations.
2. **Jogo** (`pre-alpha-0.11.0`): aba tempo global (feito) + captura de build +
   botão 🔍 + arquivo "!". Bump versão → push → CI buildа/deploya.

Ordem: backend primeiro (senão o cliente busca de um endpoint sem as colunas).

## Riscos / pontos de atenção

- **Ordem de deploy**: cliente 0.11.0 depende do backend novo no ar.
- **Stragglers em 0.10.x** após o reset: `version_num` deles < 11000 → caem no
  arquivo (comportamento correto — só runs 0.11.0 contam na temporada nova).
- **Caps no zod**: validar tamanho de `build` pra não virar vetor de abuso.
- **`get_upgrade_count`**: confirmar no plano que cobre todos os ids da lista
  (status/pool/aliados) e retorna o nível esperado pra HP/Dano.
- **Reset percebido**: no lançamento o board principal aparece quase vazio — é o
  esperado ("começar a contar de novo"); comunicar nas patch notes.

## Estado já implementado nesta sessão (não deployado)

- Backend: migration 0004 `time_to_w21_ms` + POST/GET `?board=time_w21` (lint/tsc/build OK).
- Cliente: `fetch_time21` + aba "Tempo até o 21" global + keys i18n (Godot scan OK).
- Protótipo do modal: `run_build_modal.gd` + cena de teste (Godot run OK).
