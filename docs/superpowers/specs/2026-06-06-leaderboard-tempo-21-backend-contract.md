# Contrato de backend — Leaderboard "Tempo até o 21"

> Para o dono do backend (`twilight.hotsed.com`). O jogo já está pronto e
> **já envia** o campo novo no payload de cada run. Falta só o lado do servidor
> guardar/retornar/ordenar por ele. Mudança pequena.

## Contexto

O cliente passou a ter **dois leaderboards**:

1. **Por Waves** — wave mais alta, desempate por score. Funciona 100% no
   cliente hoje (pega o top-100 atual ordenado por score e reordena por wave).
   **Não precisa de nada no backend.**
2. **Tempo até o 21** — menor tempo *efetivo de combate* (exclui pause e loja)
   até vencer o dual boss da **wave 21**. Hoje o cliente só mostra o **recorde
   pessoal local** porque o backend ainda não guarda esse dado. É isso que este
   doc pede pra habilitar de forma global.

## O que o jogo já envia

No `POST /api/runs`, o payload agora inclui um campo a mais:

```json
{
  "nickname": "...",
  "score": 123,
  "wave": 24,
  "time_ms": 540000,          // tempo efetivo TOTAL da run (já era enviado; agora exclui pause/loja)
  "time_to_w21_ms": 312000,   // NOVO: tempo efetivo até limpar a wave 21. -1 se não venceu o 2º boss
  "kills": 1500,
  "dmg_dealt": 200000,
  "version": "pre-alpha-0.10.x",
  ...
}
```

- `time_to_w21_ms`: inteiro em milissegundos. **`-1`** significa que a run **não**
  chegou a vencer o dual boss da wave 21 (não deve entrar nesse ranking).
- Atenção: `time_ms` mudou de semântica — antes era relógio de parede (incluía
  pause/loja); agora é **só tempo de combate**. Mesmo nome, mesmo tipo, só mais
  honesto. Não quebra nada do schema atual.

## O que falta no backend

### 1. Persistir a coluna nova
Guardar `time_to_w21_ms` (int, nullable ou default -1) junto com cada run.

### 2. Endpoint de leitura para esse ranking
O `GET /api/runs` atual: ignora `sort`/`order`, ordena fixo por `score desc`,
corta em **100 linhas**. Para o ranking de tempo, qualquer uma destas serve:

**Opção A (preferida) — query param no endpoint atual:**
```
GET /api/runs?board=time_w21&limit=20
```
Retorna runs com `time_to_w21_ms >= 0`, ordenadas por **`time_to_w21_ms ASC`**
(menor tempo = 1º lugar). Mesmo formato de linha de hoje, só adicionando o campo
`time_to_w21_ms` na resposta.

**Opção B — endpoint dedicado:**
```
GET /api/runs/time-to-21?limit=20
```
Mesma semântica (filtro `>= 0`, ordem `ASC`).

**Opção C (mínima) — só destravar o cliente:**
Retornar o campo `time_to_w21_ms` nas linhas e **subir o cap acima de 100**
(ou aceitar `sort`), que aí o cliente filtra/ordena sozinho. Menos eficiente,
mas evita lógica de ranking no servidor.

> Em qualquer opção, **incluir `time_to_w21_ms` no JSON de resposta** das linhas —
> hoje a resposta só devolve `nickname, score, wave, time_ms, kills, dmg_dealt, version, created_at`.

## O que muda no cliente quando o backend ficar pronto

Trivial — em `scripts/ui/leaderboard.gd`, no `_render_time21()`, trocar a leitura
do recorde local por um `fetch` global (a infra de fetch já existe). O
`leaderboard_client.gd` ganha um método análogo ao `fetch_top` apontando pro
endpoint/param acima. Nada no gameplay muda.

## Resumo do diff já feito no jogo (cliente)

- `player.gd`: cronômetro de tempo **efetivo** (só combate; pause e loja não
  contam) + snapshot `stats_time_to_w21_ms` no clear da wave 21.
- `wave_manager.gd`: liga/desliga o cronômetro junto com `wave_active`; captura
  o tempo no momento em que o dual boss da 21 cai.
- `hud.gd`: inclui `time_to_w21_ms` no payload da run.
- `skin_loadout.gd`: recorde pessoal local (`best_time_to_w21_ms`).
- `leaderboard.gd`: duas abas (Por Waves / Tempo até o 21).
