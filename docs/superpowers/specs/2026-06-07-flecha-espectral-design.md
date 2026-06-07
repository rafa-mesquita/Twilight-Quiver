# Flecha Espectral — Upgrade tipo-de-flecha (design)

**Data:** 2026-06-07
**Tipo:** Novo upgrade de loja (categoria "tipo de flecha", mutex com Perfuração/Ricochete).
**Release alvo:** 0.12.0 (junto da Essência Vital; bump só no deploy).

## Resumo

Ao **matar** um inimigo com uma flecha, nasce do cadáver uma **flecha espectral** que
voa (homing, não erra) até um inimigo aleatório próximo, causando uma % do dano e
aplicando o **pacote completo** de efeitos de contato da flecha atual. Se a espectral
matar, **repete o processo** (mais espectrais, com dano decaindo 60% por geração).

| Nível | Flechas no burst | Dano (% do dano da flecha que matou) |
|---|---|---|
| L1 | 1 | 50% |
| L2 | 1 | 75% |
| L3 | 2 | 75% |
| L4 | 3 | 85% |

- **Área de alvo:** raio de **180px** (= `TIGER_CLAWS_RADIUS`) em volta da morte.
- **Encadeamento (exponencial):** cada espectral que mata spawna a **contagem do nível**
  (L3=2, L4=3), cada uma a **60% do dano da espectral anterior**. Sem crit próprio.
- **Efeitos:** pacote completo (queimar/maldição/gelo/maré/AoE da pedra/graviton/cadeia),
  aplicados como flecha **primária** (cheios), espelhando a flecha atual do player.
- **Visual:** idêntico à flecha atual (mesmos flags elementais), com **opacidade ~0.5**
  (aspecto fantasmagórico).
- **Mutex:** categoria tipo-de-flecha — escolhe Perfuração **ou** Ricochete **ou** Espectral.

## Travas de segurança (aprovadas)

Exponencial sem freio trava o jogo (L4: 3→9→27… cada uma com AoE de pedra/graviton).
Dois limites invisíveis, raramente atingidos em jogo normal:

1. **Piso de dano:** não spawna a próxima geração se o dano dela cairia **< 1.0**. Com o
   decaimento de 60%, isso já corta a recursão em poucas gerações.
2. **Teto global:** no máximo **120 flechas espectrais vivas simultâneas** (contador
   estático em `arrow.gd`). Estourou → não spawna mais naquele instante. Decrementa no
   `_die`/`queue_free` da espectral.

## Arquitetura — reúso máximo

**Decisão central:** a flecha espectral **é uma instância de `arrow.gd`** num modo novo
`is_spectral` (homing). Assim herda todo o pacote de efeitos de contato (já implementado
no `_on_hit`) sem duplicar nada e sem desincronizar da flecha real.

### Refactors habilitadores (em `player.gd` e `arrow.gd`)

1. **`player._stamp_current_effects(arrow, is_primary)`** — extrai o bloco de carimbo de
   efeitos do `_spawn_arrow` (linhas ~1214-1367: chain/fire/curse/ice/stone/tide/graviton
   + source/volley_id). `_spawn_arrow` passa a chamá-lo; o spawn da espectral também.
   O dano da espectral é setado pelo chamador (absoluto, já calculado), então o stamp
   **não** recalcula `arrow.damage`.
2. **`arrow._apply_to_enemy(target, dmg) -> bool`** — extrai do `_on_hit` o trecho que
   aplica curse-antes/crit/`take_damage`/knockback/burn/freeze/tide/stone/graviton/chain
   num inimigo (linhas ~681-767). Retorna `true` se o alvo **morreu** nesse hit. O caminho
   de colisão normal e a chegada da espectral chamam o mesmo método.
   - Nuance: na espectral, `dmg` é o dano espectral (sem recálculo de perfuração/crit).
     O método aceita o `dmg` pronto. Crit: a espectral **não** rola crit (passa o dano
     direto); a flecha normal continua rolando crit no seu próprio fluxo.

### Detecção de kill → spawn do burst (caminho único)

No fim de `_apply_to_enemy` (ou logo após, no caller), se o alvo **morreu** E o player tem
`spectral_arrow_level > 0`, dispara `_spawn_spectral_burst(origin, base_dmg, count, gen)`:

- **Flecha normal mata:** `base_dmg = dano aplicado × pct_do_nível` (50/75/75/85%),
  `count = count_do_nível`, `gen = 1`.
- **Espectral mata:** `base_dmg = dano_desta_espectral × 0.60`, `count = count_do_nível`,
  `gen = gen_desta + 1`.

`_spawn_spectral_burst` aplica as travas (piso de dano, teto global) e instancia `count`
flechas espectrais.

### Modo `is_spectral` em `arrow.gd`

Novos campos:
```
var is_spectral: bool = false
var spectral_target: Node = null
var spectral_count: int = 1      # quantas spawnar se ESTA matar (contagem do nível)
var spectral_gen: int = 0        # geração (cap de profundidade via piso de dano)
static var _spectral_alive: int = 0   # contador global pro teto
const SPECTRAL_ARRIVE_DIST: float = 10.0
const SPECTRAL_RETARGET_RADIUS: float = 180.0
const SPECTRAL_HOMING_SPEED: float = 320.0
const SPECTRAL_MAX_ALIVE: int = 120
const SPECTRAL_MIN_DAMAGE: float = 1.0
```

- **`_ready` (spectral):** `modulate.a = 0.5` (fantasma); **não** conecta `body_entered`
  (não bloqueia em nada); `_spectral_alive += 1`. Visuais elementais (`_apply_*_visuals`)
  rodam normalmente via os flags carimbados.
- **`_physics_process` (spectral):** se alvo inválido/morto → `_spectral_retarget()`
  (aleatório vivo em `SPECTRAL_RETARGET_RADIUS` da posição atual); sem alvo → `_die()`.
  Com alvo: vira a direção pro alvo (corrige a cada frame = não erra), anda
  `SPECTRAL_HOMING_SPEED`; ao chegar (`distance_to(alvo) <= SPECTRAL_ARRIVE_DIST`) chama
  `_spectral_strike()`. Atravessa objetos/inimigos (sem colisão de bloqueio).
- **`_spectral_strike()`:** `var killed = _apply_to_enemy(spectral_target, damage)`; se
  `killed` e player tem espectral → `_spawn_spectral_burst(pos_do_alvo, damage*0.60,
  spectral_count, spectral_gen+1)`; depois `_die()`.
- **`_die` (spectral):** `_spectral_alive -= 1` antes do `queue_free`.

### Seleção de alvo

`_pick_random_enemy_in(center, radius, exclude)` — varre `get_tree().get_nodes_in_group(
"enemy")`, filtra válidos/vivos/dentro do raio, exclui `tank_ally`/estruturas e o alvo já
morto, e sorteia um (`randi()` indexando). Retorna `null` se vazio.

## Player — novo upgrade

- `var spectral_arrow_level: int = 0`.
- `apply_upgrade("spectral_arrow")`: `spectral_arrow_level = mini(spectral_arrow_level+1, 4)`.
- Helpers: `_spectral_count()` → `[1,1,2,3][level-1]`; `_spectral_pct()` →
  `[0.50,0.75,0.75,0.85][level-1]`.
- `_spawn_spectral_burst(origin, base_dmg, count, gen)`: aplica travas; pra cada uma,
  instancia `arrow.gd`, `arrow.is_spectral=true`, `arrow.damage=base_dmg`,
  `arrow.spectral_count=count`, `arrow.spectral_gen=gen`, alvo via
  `_pick_random_enemy_in(origin, 180, morto)`, `_stamp_current_effects(arrow, true)`,
  posiciona em `origin`, add ao mundo, toca o **SFX** (1× por burst, throttled).
  - Quem chama: como `arrow.gd` é quem detecta o kill, o burst é disparado de dentro da
    `arrow.gd` chamando `player._spawn_spectral_burst(...)` (player via grupo, igual aos
    outros callbacks). Mantém um único ponto de spawn.

## SFX

Som "flecha sai do alvo morto" em
`audios/upgrades/flecha espectral/flecha espectral effect.mp3`. Toca 1× por burst (não por flecha) com throttle global
curto (~80ms) pra não empilhar quando vários inimigos morrem juntos (multi-arrow). Segue o
padrão dos outros SFX de flecha (`_play_oneshot`/`AudioStreamPlayer2D` no bus `SFX`).

## Loja / carta

- Novo id no `UPGRADE_POOL` (`wave_shop.gd`): `{"id": "spectral_arrow",
  "name": "SHOP_UPG_SPECTRAL", "max_level": 4}`.
- Mutex: adicionar a `EXCLUSIVE_PAIRS` o grupo
  `["perfuracao", "ricochet_arrow", "spectral_arrow"]` (substitui o par atual).
- Descrições por nível: `const SPECTRAL_DESCS = [SHOP_SPECTRAL_DESC_1..4]` + mapeamento no
  `_get_upgrade_desc`.
- Arte da carta (`UPGRADE_ART`): `"spectral_arrow": "res://assets/Hud/shop/upgrade/ricochete.png"`
  (placeholder reusado; trocar quando tiver arte própria).
- Pool de boas-vindas: incluir `spectral_arrow` na `FREE_UPGRADE_POOL` do `wave_manager`
  (ver [[feedback_new_upgrade_welcome_pool]]).

## i18n (`assets/i18n/translations.csv`, 4 idiomas pt/en/es/fr)

- `SHOP_UPG_SPECTRAL` (nome curto da carta).
- `SHOP_SPECTRAL_DESC_1..4` (uma por nível, descrevendo flechas/dano).

## Fora de escopo (YAGNI)

- Sem arte própria de carta/sprite (reusa ricochete; flecha usa o visual elemental atual).
- Sem crit próprio da espectral, sem stacks de Esquivando/Life Steal vindos da espectral
  (mantém simples; a espectral não credita esses sistemas extras do player — só dano +
  efeitos de contato + telemetria de dano/kill como fonte "spectral").
- Sem interação com torre/aliados como atiradores (só flechas do player geram espectral).

## Critérios de aceite

- Comprar Espectral some Perfuração/Ricochete do shop (mutex) e vice-versa.
- Matar com flecha → nasce espectral do cadáver, voa até inimigo aleatório em 180px, não
  erra, atravessa tudo, re-mira se o alvo morre antes.
- Espectral aplica o mesmo elemental da flecha atual (com opacidade fantasma) + dano %.
- Espectral que mata encadeia (60% do dano, contagem do nível); recursão termina pelo piso
  de dano; nunca passa de 120 espectrais vivas.
- L1=50%/1, L2=75%/1, L3=75%/2, L4=85%/3.
- SFX toca quando a espectral nasce do alvo morto.
- Sem o upgrade, nenhuma flecha gera espectral (regressão zero).
