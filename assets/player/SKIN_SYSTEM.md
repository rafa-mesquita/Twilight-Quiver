# Sistema de skins do player

Skins do player são layered: cada slot é um spritesheet PNG separado, sincronizado com o body. UI em `/skins` (botão no main menu) deixa o jogador trocar/remover peças.

## Slots

| Slot     | Pasta                  | Removível? | Notas                                             |
| -------- | ---------------------- | ---------- | ------------------------------------------------- |
| `body`   | `assets/player/skin/`  | Não        | Pele do personagem; substitui o sprite mestre.    |
| `legs`   | `assets/player/legs/`  | Não        | Calças.                                           |
| `shirt`  | `assets/player/shirt/` | Sim        | Camisa.                                           |
| `alfaja` | `assets/player/alfaja/`| Sim        | Faixa/sash. Pasta criada quando você fizer.       |
| `cape`   | `assets/player/cape/`  | Sim        | Capa atrás.                                       |
| `quiver` | `assets/player/quiver/`| Sim        | Aljava nas costas.                                |
| `hair`   | `assets/player/hair/`  | Sim        | Cabelo.                                           |
| `bow`    | `assets/player/bow/`   | Não        | Arco. Pode ter `_back.png` pareado (ver abaixo).  |

## Adicionar uma variante

1. **Exportar do Aseprite:** isole o layer da peça e exporte o spritesheet com o **mesmo layout de frames do body** (32×32 frames, mesma ordem das tags Idle/WALK/Atack/etc).
2. **Salvar PNG na pasta do slot.** Nome do arquivo vira o display name na UI.
   - `cape/Roxa.png` → mostra "Roxa" no menu.
3. **Pronto.** Abre o jogo, vai em Skins, navega com `<` `>`.

> **CRÍTICO:** Todos os PNGs de qualquer slot precisam ter EXATAMENTE o mesmo layout de frames que o body. SkinManager copia as `region` do body e só troca a textura — se a posição dos frames for diferente, vai sair errado.

## Bow: 2 PNGs por variante (front + back)

O arco tem partes que renderizam **atrás** do corpo (corda, parte de baixo) e **na frente** (mão segurando, parte de cima). Pra preservar isso:

- `bow/<Variant>_front.png` — parte da frente (renderizado em cima de tudo)
- `bow/<Variant>_back.png`  — parte de trás (renderizado **atrás** do body)

Ou se quiser usar só um:

- `bow/<Variant>.png` — sem `_front`/`_back`. Renderizado só na frente. (Sem back, perde o efeito layered.)

O sistema parea automaticamente: pra cada PNG sem `_back` no nome, procura um `<mesmo_nome>_back.png` no mesmo diretório.

## Body (caso especial)

`body` é a pele/silhueta do personagem. Substitui o `sprite_frames` do `AnimatedSprite2D` mestre em runtime, em vez de ser só layer em cima.

O body PNG tem que conter SÓ a pele do personagem (sem cabelo/roupa/etc). Se você não criar nenhum body, o jogo usa o `player.png` original (com tudo bakeado) — fica funcional mas o sistema layered não rende.

## Adicionar um novo slot

1. Cria a pasta `assets/player/<novo_slot>/` e bota PNGs lá.
2. Em [scripts/systems/skin_loadout.gd](../../scripts/systems/skin_loadout.gd):
   - Adiciona o slot em `SLOTS` (ordem importa pra UI).
   - Se removível, também em `REMOVABLE_SLOTS`.
   - Adiciona em `SLOT_TO_DIR` (mapeamento slot → pasta).
3. Em [scripts/systems/skin_manager.gd](../../scripts/systems/skin_manager.gd):
   - Adiciona em `SLOT_TO_NODE`.
4. Em [scenes/player/player.tscn](../../scenes/player/player.tscn):
   - Adiciona um `AnimatedSprite2D` filho de `Skin` com o nome correspondente, `visible = false`, `offset = Vector2(0, -16)`.
   - Posição na ordem dos filhos define z-order (primeiros = atrás).
5. Em [scripts/ui/skin_select.gd](../../scripts/ui/skin_select.gd):
   - Adiciona o label amigável em `_SLOT_LABELS`.
