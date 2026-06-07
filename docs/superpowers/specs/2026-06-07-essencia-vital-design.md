# Essência Vital — Item equipável (design)

**Data:** 2026-06-07
**Tipo:** Novo item de inventário (buff pré-jogo) com efeito de CDR global + HP extra.

## Resumo

Item equipável **Essência Vital**. Enquanto equipado, **cada status de HP comprado na
loja** passa a dar, além do HP normal:

- **+10% de CDR** (redução de cooldown), acumulável até um **teto de 50%** (5 status de HP).
- **+5 de HP máximo extra** (sem teto — continua dando +5 por status mesmo após o CDR
  bater no cap).

O CDR é **global**: afeta toda skill ativa e todo auto-cast que tenha tempo de recarga.

**Unlock:** quest composto — numa mesma run, matar o boss da wave 7 (Mage Monkey) tendo
comprado **pelo menos 2 status de HP** até aquele momento.

## Princípio de segurança (não quebra o jogo)

Tudo é **aditivo e inerte por padrão**:

- Sem o item equipado **ou** com 0 status de HP, o fator de cooldown é `1.0` → nenhum
  cooldown muda; o jogo roda idêntico ao atual.
- O CDR só "liga" quando o item está equipado **e** há ≥1 status de HP comprado.
- O +5 HP extra só é somado quando o item está equipado, no momento da compra do HP.

## Efeito — mecânica

### Definição do item (`inventory_items.gd`)

Nova entrada no `ITEMS`:

```gdscript
"essencia_vital": {
    "name": "ITEM_ESSENCIA_VITAL_NAME",
    "desc": "ITEM_ESSENCIA_VITAL_DESC",
    "icon": "res://assets/Hud/itens/essencia_vital.png",
    "effect": {"type": "hp_status_bonus", "cdr_per_level": 0.10, "cdr_cap": 0.50, "hp_per_level": 5},
    "unlock": {"type": "quest", "reqs": [
        {"stat": &"essencia_vital_unlock", "value": 1, "label": "ITEM_REQ_ESSENCIA_VITAL"},
    ]},
},
```

`apply_to_player` ganha um ramo para `hp_status_bonus` que liga uma flag no player
(`_essencia_vital_equipped = true`) e guarda os parâmetros (`_essencia_cdr_per_level`,
`_essencia_cdr_cap`, `_essencia_hp_per_level`). Espelha o padrão do `armor_dodge`
(Capacete Veloz).

### +5 HP extra por status de HP

No `apply_upgrade("hp")` do `player.gd`: depois de calcular o `hp_gain` normal da curva,
se `_essencia_vital_equipped`, soma `_essencia_hp_per_level` (5) ao `hp_gain` antes de
aplicar em `max_hp`/`hp`. Assim o HP extra entra naturalmente e o `hp_bar` já reflete.

### CDR global — fator central

Novo método no `player.gd`:

```gdscript
# Fator multiplicador de cooldown (1.0 = sem redução). Essência Vital reduz 10% por
# status de HP comprado, com teto de CDR de 50% (fator mínimo 0.5).
func cooldown_scale() -> float:
    if not _essencia_vital_equipped:
        return 1.0
    var cdr: float = minf(hp_upgrades * _essencia_cdr_per_level, _essencia_cdr_cap)
    return 1.0 - cdr
```

`hp_upgrades` já existe e conta os status de HP da run. Lido **ao vivo** → comprar mais
HP no meio da run reduz mais o cooldown a partir dali.

### Sites que aplicam o fator

Todo ponto que **reseta** um cooldown passa a multiplicar a base por `cooldown_scale()`.

**Skills/auto-cast do player** (em `player.gd`):

| Cooldown | Base |
|---|---|
| Fogo (skill direita) | `FIRE_SKILL_COOLDOWN` |
| Cadeia de Raios (skill) | `CHAIN_LIGHTNING_SKILL_COOLDOWN` |
| Cadeia de Raios (auto-bolt) | `CHAIN_AUTO_BOLT_INTERVAL` |
| Maldição (skill) | `CURSE_SKILL_TOTAL_CYCLE` — **ver nota** |
| Pedra (Terremoto Q) | `STONE_SKILL_COOLDOWN` |
| Gelo (Time Freeze Q) | `TIME_FREEZE_COOLDOWN` |
| Maré (escudo) | `TIDE_SHIELD_COOLDOWN` |
| Dash | `DASH_COOLDOWNS_BY_LEVEL[...]` |
| Fenda | `FENDA_COOLDOWNS_BY_LEVEL[...]` |
| Esquivando (habilidade) | `ESQUIVANDO_ABILITY_CD_BY_LEVEL[...]` |
| Adrenalina (habilidade) | `ADRENALINA_CD_BY_LEVEL[...]` |
| Boomerangue | `BOOMERANG_CD_BY_LEVEL[...]` |
| Garras de Tigre | `TIGER_CLAWS_CD_BY_LEVEL[...]` |

**Auto-cast de aliados:** cada aliado que reseta um intervalo de ataque
(`_attack_cd_remaining = attack_cycle_interval` na Frostwisp, e equivalentes em
`ting_turret`, `leno`, `capivara_joe`, `mini_mago`, `claudio_druida`) multiplica a base
pelo `player.cooldown_scale()` ao rearmar o timer. Os aliados já guardam ref pro player.

> **Nota — duração vs cooldown:** o CDR encurta só o *tempo de recarga*, nunca a duração
> ativa da skill. A skill de Maldição usa um ciclo composto
> `WARMUP + DURAÇÃO_DO_BEAM + COOLDOWN_AFTER`. Escalar o ciclo inteiro encurtaria o beam.
> Aplicar como: `WARMUP + DURAÇÃO + COOLDOWN_AFTER × cooldown_scale()`. As demais skills
> da tabela usam `_cd_remaining` como cooldown puro → multiplicação direta.

## Unlock — quest composto

Espelha o **Capacete Veloz** (flag de run setada no momento certo, depois consolidada em
stat persistente).

1. **Captura no momento do kill:** em `player.notify_boss_killed(boss_id)`, quando
   `boss_id == "mage_monkey"` **e** `hp_upgrades >= 2`, setar
   `stats_essencia_vital_unlock = true` (nova var de run no player, default `false`).
   - Mage Monkey é o boss das waves 7 e 14; ambos contam (é "o boss do 7"). Matar com
     ≥2 status de HP em qualquer uma satisfaz.
2. **Coleta:** `hud._collect_run_stats` adiciona
   `"essencia_vital_unlock": bool(p.stats_essencia_vital_unlock)` ao dict (espelha a linha
   de `capacete_veloz_unlock`).
3. **Consolidação persistente:** `skin_loadout.gd` ganha
   `const STAT_ESSENCIA_VITAL := &"essencia_vital_unlock"` e, no commit dos run_stats,
   grava o stat (value 1) quando o run_stat vier `true` — espelha o trecho do
   `capacete_veloz_unlock`.

`is_unlocked` do item já funciona via `unlock.type == "quest"` lendo
`SkinLoadout.get_stat(&"essencia_vital_unlock") >= 1`.

## i18n (`assets/i18n/translations.csv`)

Keys novas (pt_BR + en):

| Key | pt_BR | en |
|---|---|---|
| `ITEM_ESSENCIA_VITAL_NAME` | Essência Vital | Vital Essence |
| `ITEM_ESSENCIA_VITAL_DESC` | Cada status de HP também dá −10% de cooldown (até −50%) e +5 de HP máximo. | Each HP upgrade also grants −10% cooldown (up to −50%) and +5 max HP. |
| `ITEM_REQ_ESSENCIA_VITAL` | Vença o boss da wave 7 com ao menos 2 status de HP | Beat the wave 7 boss with at least 2 HP upgrades |

(Textos finais ajustáveis; manter as duas colunas preenchidas.)

## Arte

Ícone em `assets/Hud/itens/essencia_vital.png`, mesmo padrão/resolução dos demais itens.
Ao reabrir o editor, o Godot gera o `.import`.

## Fora de escopo (YAGNI)

- Sem sistema central de cooldown novo além do método `cooldown_scale()` — não vamos
  refatorar cada skill para um wrapper.
- Sem teto pro HP extra (só o CDR tem cap).
- Sem mudança na loja meta de pétalas (item é `quest`, não `shop`).
- Sem bump de versão agora (só em deploy).

## Critérios de aceite

- Item aparece travado no inventário até cumprir a quest; tooltip mostra o requisito.
- Equipado, cada status de HP comprado dá +5 HP e a barra de cooldown das skills encolhe
  proporcionalmente (10% por status, parando em 50%).
- Sem o item, nenhum cooldown muda (regressão zero).
- Maldição: o beam mantém duração cheia; só a recarga encurta.
- Unlock dispara ao matar o Mage Monkey com ≥2 status de HP na mesma run.
