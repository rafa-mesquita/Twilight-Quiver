# Skin Sputnik — peças compartilhadas com Warrior + unlock "round sem flecha"

**Data:** 2026-06-02
**Status:** Aprovado, pronto pra plano de implementação

## Resumo

Nova skin **Sputnik**. Compartilha **arco (bow)**, **aljava (quiver)** e **capa+máscara
(cape)** com o Warrior; tem body/legs/shirt/hair próprios. Desbloqueia ao **passar de um
round sem atirar nenhuma flecha** (só o botão de disparo do mouse conta — skills como
Garra de Tigre / Boomerang / dash são livres).

Grafia oficial: **Sputnik** (padroniza in-game e HUD; o fonte HUD `Sputkin.aseprite` é
renomeado/exportado como Sputnik).

## Decisões de design (já travadas)

- **Grafia:** Sputnik (não "Sputkin"/"Sputnkin").
- **Semântica do unlock:** só o disparo manual (botão do mouse → `_release_arrow`)
  desqualifica o round. O auto-ataque do dash (`_dash_auto_attack_volley`), que dispara
  flechas sem o botão, **é permitido**. Torres/aliados nunca contaram (não são o player).
- **Round válido:** qualquer round (qualquer wave concluída com zero disparos manuais).
  O gate natural é precisar de uma skill ofensiva comprada.

## Estado dos assets

Os dois `.aseprite` fonte já existem, mas **nada foi exportado** pros PNGs de runtime:

- In-game: `assets/player/fullSkins/Sputnik.aseprite`
- HUD shop: `assets/Hud/playerHud/Sputkin.aseprite` (renomear fonte → `Sputnik.aseprite`)

Exportação segue o workflow de skin tinting já estabelecido (export de layers do
`.aseprite`). Peças próprias do Sputnik: body, legs, shirt, hair. Bow/quiver/cape vêm da
peça compartilhada com Warrior (abaixo).

## Parte 1 — Peças compartilhadas com Warrior (rename)

Hoje o Warrior tem bow/quiver/cape próprios nomeados `Warrior`. Viram peça **compartilhada**
`Sputnik_Warrior` (mesmo padrão de `Hawk_Skeleton`).

- Renomear (arquivo + `.import`):
  - `bow/Warrior_front.png` → `bow/Sputnik_Warrior_front.png`
  - `bow/Warrior_back.png` → `bow/Sputnik_Warrior_back.png`
  - `quiver/Warrior.png` → `quiver/Sputnik_Warrior.png`
  - `cape/Warrior.png` → `cape/Sputnik_Warrior.png`
- `KIT_PART_OVERRIDE` (skin_loadout.gd):
  - `Warrior`: adicionar `bow/quiver/cape → "Sputnik_Warrior"` (mantém `body → Green_Eyes`).
  - `Sputnik`: `bow/quiver/cape → "Sputnik_Warrior"` (body/legs/shirt/hair próprios).
- `SHARED_PART_NAMES` += `"Sputnik_Warrior"` (não aparece como card de kit próprio).
- `PART_NAME_MIGRATIONS` (bow/quiver/cape): `"Warrior" → "Sputnik_Warrior"` (saves antigos
  que equiparam essas peças continuam resolvendo).

## Parte 2 — Unlock "round sem flecha"

Espelha o mecanismo do flawless-W3 (`wave_manager._finish_wave` setando flag no player).

- **player.gd:**
  - Nova var `fired_arrow_this_wave: bool = false`.
  - Setar `true` em `_release_arrow()` (disparo manual). NÃO setar no
    `_dash_auto_attack_volley`.
  - Nova var persistente-de-run `stats_no_arrow_round: bool = false`.
- **wave_manager.gd:**
  - `_start_next_wave()`: resetar `player.fired_arrow_this_wave = false` no começo da wave.
  - `_finish_wave()`: se `wave_number >= 1` e `not player.fired_arrow_this_wave` →
    `player.stats_no_arrow_round = true`.
- **hud.gd `_collect_run_stats`:** incluir `"no_arrow_round": bool(p.stats_no_arrow_round)`.
- **skin_loadout.gd:**
  - `const STAT_NO_ARROW_ROUND := &"no_arrow_round_done"` (flag 0/1).
  - `record_run`: se `run_stats.no_arrow_round` e stat < 1 → `set_stat(STAT_NO_ARROW_ROUND, 1)`.
  - `_is_quest_satisfied`: case `"no_arrow_round"` → `get_stat(STAT_NO_ARROW_ROUND) >= value`.
  - `SKIN_QUESTS["Sputnik"] = {type:"no_arrow_round", value:1, label:"PLAYER_QUEST_SPUTNIK", hidden:false}`.

## Parte 3 — i18n

`assets/i18n/translations.csv`, nova key `PLAYER_QUEST_SPUTNIK` (pt/en/es/fr):
"Passe de um round sem atirar nenhuma flecha" + traduções.

## Arquivos afetados

| Arquivo | Mudança |
|---|---|
| `assets/player/{bow,quiver,cape}/` | Renomear peças Warrior → Sputnik_Warrior (+`.import`). |
| `assets/player/{skin,legs,shirt,hair}/Sputnik.png` | Novos PNGs do in-game (export do fullSkins). |
| `assets/Hud/playerHud/` (subpastas) | Layers HUD do Sputnik exportados. |
| `scripts/systems/skin_loadout.gd` | KIT_PART_OVERRIDE, SHARED_PART_NAMES, PART_NAME_MIGRATIONS, SKIN_QUESTS, STAT_NO_ARROW_ROUND, record_run, _is_quest_satisfied. |
| `scripts/player/player.gd` | `fired_arrow_this_wave`, `stats_no_arrow_round`, set em `_release_arrow`. |
| `scripts/systems/wave_manager.gd` | reset no `_start_next_wave`, check no `_finish_wave`. |
| `assets/i18n/translations.csv` | `PLAYER_QUEST_SPUTNIK` (4 línguas). |

## Fora de escopo

- Sem bump de versão (não é deploy; ver CLAUDE.md).
- Não mexer no comportamento do dash auto-attack (só não conta pro desafio).
- Não alterar a cadeia de unlock genérica (record_run/hud já funcionam).

## Critérios de aceite

1. Sputnik aparece na seleção de skins com body/legs/shirt/hair próprios e
   bow/quiver/cape idênticos aos do Warrior (peça `Sputnik_Warrior`).
2. Equipar Warrior continua funcionando; saves antigos com bow/quiver/cape "Warrior"
   migram pra "Sputnik_Warrior" sem quebrar.
3. Concluir qualquer wave (≥1) sem disparo manual de flecha desbloqueia a Sputnik no death.
4. Disparar manualmente ao menos 1 flecha na wave invalida o round; flechas do dash
   auto-attack NÃO invalidam.
5. Quest aparece com label traduzido nas 4 línguas enquanto bloqueada.
6. HUD shop mostra a arte do Sputnik (card de seleção).
