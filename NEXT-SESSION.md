# Próxima Sessão

> Última atualização: 2026-05-03 (sessão noturna)
> Sessão anterior: bootstrap do projeto Godot — player com WASD/ataque, flecha, HP, HUD, e dois tipos de inimigo placeholder

## Estado atual
- Projeto Godot 4.6 funcional em `c:\Users\rafam\Desktop\Rpositórios Github - claude\Pessoal\Jogo novo\`
- F5 abre uma cena de teste com 1 player jogável + 2 melees + 2 archers placeholder + HUD com barra de HP
- Sprite do player implementada (idle/walk/attack a partir de `assets/player.png`, sheet 160x96 com frames 32x32 — 3/4/5 frames respectivamente, colunas restantes são vazias)
- Não é repositório git (ainda)

## Por onde começar
1. **Validar a build atual com o usuário** — ele encerrou dizendo "ótimo início". Antes de adicionar mais coisa, perguntar o que ele achou de feel/balance dos inimigos placeholder (dano, velocidade, distância do archer, etc.) e ajustar via `@export` antes de partir pra cima.
2. **Decidir mecânica da skill (botão direito)** — hoje só faz `print`. Discutir com o usuário: o que é a skill? Múltiplas? Sistema de seleção? Cooldown? Animação própria ou usa attack?
3. **Cenário/tilemap** — usuário falou que vai discutir cenário "depois". Provavelmente próximo passo natural: TileMap com tiles que ele desenha, ou começar com chão/borda procedural pra testar feel de movimentação.
4. **Sprites de inimigos** — ele vai desenhar. Hoje são quadrados coloridos (vermelho=melee, laranja=archer). Quando ele tiver sprites prontos, é só trocar `Body` (Polygon2D) por AnimatedSprite2D no `.tscn` correspondente, mesma estrutura do player.

## Contexto crítico

### Estilo do jogo
**Não é isométrico de verdade** — apesar do usuário ter usado o termo "isometric" na primeira mensagem, a referência (`Ref.gif`) é top-down 2D pixel art (Soul Knight / Vampire Survivors). Tudo está implementado como top-down. **Não trazer isso à tona** a não ser que vire relevante; já foi notado e o usuário concordou seguindo nesse estilo.

### Sprite do player
- Sheet: 160x96, frames 32x32
- **Tem células vazias** que o usuário deixou na sheet. Layout real:
  - Row 0 (idle): 3 frames usados (col 0–2), col 3 e 4 transparentes
  - Row 1 (walk): 4 frames usados (col 0–3), col 4 transparente
  - Row 2 (attack): 5 frames usados (col 0–4)
- O `player.tscn` já está configurado com a quantidade certa de frames por anim. Se o usuário **redesenhar a sheet com mais frames**, vai precisar adicionar AtlasTexture sub_resources e atualizar o array de frames em `scenes/player.tscn`.
- Sprite tem **uma direção só** (lateral). Flip horizontal trata esquerda/direita. Frente/costas: usuário vai precisar desenhar frames adicionais e a gente troca a lógica de animação por ângulo (hoje é só `flip_h`).

### Decisões de feel (importantes, não revertir sem checar)
- **Player trava durante o cast**: enquanto a anim de attack roda, WASD não se move. Decisão do usuário, ele queria a sensação de "comprometimento" ao atirar.
- **Direção da flecha trava no clique**: capturada em `_start_attack`, não recalculada no release. Usuário foi explícito sobre isso.
- **Sprite NÃO segue o mouse**: vira só pela direção do movimento. Durante o ataque, vira pra direção travada do clique. Quando parado e sem atacar, mantém o último facing.
- **Flecha sai do final do arco**: muzzle position espelha com `flip_h` (lado certo do boneco).
- **Cooldown de attack = 1.0s**, **draw release no frame 4** da animação de attack (8fps → ~0.5s pra soltar).

### Camera/blur
- **Smoothing OFF** intencionalmente. Era o que causava o "blur ao andar" que o usuário reportou (posições fracionárias da câmera mesmo com pixel snap ligado). NÃO religar smoothing sem antes resolver isso de outra forma.
- Zoom = `Vector2(1.5, 1.5)`. Usuário achou 2x demais e 1x pouco.
- `snap_2d_transforms_to_pixel` e `snap_2d_vertices_to_pixel` ligados em `project.godot`.
- `window/stretch/scale_mode="integer"` pra upscale crisp.

### Layers de colisão
- Layer 1 = player
- Layer 2 = walls/obstacles
- Layer 3 = enemies (bit value 4)
- Player CharacterBody2D: `layer=1, mask=2`
- Enemy CharacterBody2D: `layer=4, mask=2`
- Player arrow Area2D: `mask=6` (walls + enemies)
- Enemy arrow Area2D: `mask=3` (walls + player)

### Gotcha: editar .tscn com Godot aberto
Se o Godot estiver com a cena aberta no editor, salvar pelo Godot **sobrescreve** edições feitas em disco fora dele. Aconteceu nesta sessão com `main.tscn` (zoom voltou pra 2x sozinho). Antes de editar `.tscn` por código, fechar o tab da cena no Godot ou pedir pro usuário fazer `Project → Reload Current Project` antes.

## Pendências conhecidas
- [ ] Skill (botão direito) é só `print` — decidir mecânica
- [ ] Sprites dos inimigos (usuário vai desenhar; hoje são quadrados)
- [ ] Cenário/tilemap (não tem nada além de 3 obstáculos placeholder)
- [ ] Sistema de hordas / spawn de inimigos (hoje os 4 inimigos são instâncias fixas na main)
- [ ] Sistema de evoluções/pickups ao matar inimigos (mecânica core do roguelike, ainda não começou)
- [ ] Player não tem feedback visual ao tomar dano (sem flash, sem invul frames)
- [ ] Player não morre de fato quando HP=0 (só dá `print("player morreu")`)
- [ ] Sprite do player só tem 1 direção; sem frames de frente/costas
- [ ] Não tem música nem SFX
- [ ] Projeto não é git repo

## Arquivos / locais relevantes

### Configuração
- `project.godot` — input map (WASD, attack=LMB, skill=RMB), 2D snap, integer scale, viewport 480x270 → janela 1280x720

### Player
- `scripts/player.gd` — toda a lógica do player, signals `hp_changed` e `died`, group "player"
- `scenes/player.tscn` — SpriteFrames com 3 anims, AttackTimer, Muzzle marker
- `assets/player.png` — sheet do usuário (cópia do `Player sprite-Sheet.png` do root)

### Projéteis
- `scripts/arrow.gd` — script único usado pelas duas flechas, chama `take_damage` no body
- `scenes/arrow.tscn` — flecha do player (amarela, mask=6, dano=25)
- `scenes/enemy_arrow.tscn` — flecha inimiga (vermelha, mask=3, dano=12, mais lenta)

### Inimigos
- `scripts/melee_enemy.gd` + `scenes/melee_enemy.tscn` — vermelho, persegue, bate corpo a corpo
- `scripts/archer_enemy.gd` + `scenes/archer_enemy.tscn` — laranja, mantém distância ~110px, atira a cada 1.6s

### UI
- `scripts/hud.gd` + `scenes/hud.tscn` — CanvasLayer com ProgressBar de HP (canto superior esquerdo)

### Cena principal
- `scenes/main.tscn` — Player + 3 obstáculos placeholder (roxos) + 2 melees + 2 archers + HUD

## Comandos úteis
Não tem CLI/build steps próprios — tudo é feito pelo editor do Godot.

```
# No Godot:
F5                              # Roda a main.tscn
Ctrl+S                          # Salva cena atual
Project → Reload Current Project  # Recarrega após edits externos
Scene → Reload Saved Scene      # Reload só do tab atual
```
