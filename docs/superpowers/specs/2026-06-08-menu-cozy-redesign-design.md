# Redesign do Main Menu — cena cozy animada (player + Ting descansando)

> Data: 2026-06-08
> Status: **decisão de layout fechada + specs de arte definidos. Arte em produção pelo Rafa. Implementação no `.tscn` pendente (aguardando frames ou placeholder).**

## Objetivo

Trocar o menu principal (hoje uma coluna centralizada sobre fundo liso) por uma cena **cozy animada**: o player e o **Mecânico Ting** descansando juntos, com alguns frames de animação (vibe aconchegante — respiração, piscar, fogueira tremeluzindo, etc).

## Decisão de layout (FECHADA)

**Menu (botões) na ESQUERDA, arte grande na DIREITA. Informações secundárias (versão, etc) num canto discreto.**

Os personagens devem estar **virados/recostados pra ESQUERDA**, olhando na direção dos botões — a direção do olhar guia o olho do jogador pro menu.

### Por quê (resumo da pesquisa)

- Jogo é **pt_BR + en** → leitura **esquerda→direita, cima→baixo**.
- Padrões de leitura (Gutenberg / Z / F): olho **entra no canto superior-esquerdo** e **descansa no inferior-direito**.
- **Botões à esquerda** = jogador acha o "Jogar" de cara; lista vertical à esquerda é o modelo mental padrão pra navegação por teclado/controle (não precisa atravessar a tela).
- **Arte à direita** = ocupa a zona maior e ganha o olhar de "descanso" → atmosfera sem competir com a leitura.
- **Exceção considerada e descartada (por ora):** modo "mood-first" (arte à esquerda / menu à direita, vibe Spiritfarer/Gris) — válido se a intenção fosse a pessoa *sentir a cena antes de pensar em clicar*. Ficou como alternativa, não o escolhido.

Fontes: Vanseo Design (Gutenberg/Z/F), UX Planet (left-align buttons), UX Movement (Z-pattern CTA), Game UI Database (title screens), Creative Bloq (trend de menu indie).

## Specs de arte (pixel art)

Dados reais do projeto (confirmados):
- **Viewport:** 1920×1080, `display/window/stretch/mode = "viewport"`, filtro **Nearest** (`rendering/textures/canvas_textures/default_texture_filter = 0`). Pixel art puro.
- **Player nativo:** **32×32 px** (sheet `assets/source/Player sprite-Sheet.png` = 160×96 = 5×3 frames de 32).
- **Ting:** sheet `assets/aliados/Mecanico Ting/mecanico-ting-Sheet.png` = 64×128 (frames de 32 de largura).

### Resolução-base (NÃO desenhar direto em 1920×1080)

Desenhar numa base baixa que divide 1920×1080 por inteiro e deixar o Godot escalar com Nearest:

| Base | Escala | Vira | Nota |
|---|---|---|---|
| **480 × 270** | **×4** | 1920×1080 | 🟢 **RECOMENDADO** — cozy, chunky, trampo gerenciável |
| 640 × 360 | ×3 | 1920×1080 | pixel art mais fino/detalhado |
| 960 × 540 | ×2 | 1920×1080 | muito detalhe, bem mais trabalho |
| 320 × 180 | ×6 | 1920×1080 | super chunky, personagens grandões |

**Recomendado: cena inteira (fundo + player + Ting) num canvas único de `480×270`, escala ×4.** Fundo, personagens e parallax/animação compartilham o mesmo grid de pixel — nada de "resolução misturada".

### Composição no canvas 480×270

- **Esquerda ~40% (≈ 0–190 px):** zona calma pro menu (botões). Cenário leve ok, mas sem competir com o texto.
- **Direita ~60% (≈ 190–480 px):** player + Ting descansando, virados pra esquerda.
- A dupla pode ser **maior/mais detalhada** que os 32px do jogo (é key art de menu, normal). Cluster dos dois em torno de **~180×150 px** nesse canvas dá presença sem engolir o menu.

### Animação

- **Todo frame = mesmo tamanho de canvas** (ex: 480×270). Não cortar por personagem.
- Exportar como **sprite sheet horizontal** (frame1 | frame2 | … lado a lado) ou frames soltos → entra num `AnimatedSprite2D`/`SpriteFrames`.
- Loop cozy: **4–8 frames a ~6–10 fps** já dá o clima.
- Import no Godot: **Filter = Off** (Nearest) pra não borrar.

### Alternativa de produção (menos retrabalho)

Fundo full-screen em 480×270 ×4 + personagens animados como **sprite sheet separado** por cima (mesma base de pixel). Bom se quiser iterar só na animação da dupla sem mexer no fundo.

## Implementação (pendente)

Estado atual de [scenes/ui/main_menu.tscn](scenes/ui/main_menu.tscn):
- Raiz `Control` → `Bg` (ColorRect, fundo liso) + `Center` (CenterContainer) → `VBox` com `Logo` + botões: `StartButton`, `SkinsButton`, `LojaButton`, `LeaderboardButton`, `SettingsButton`, `DevButton`, `QuitButton`.
- `VersionLabel` no canto inferior-direito. `Cursor` instanciado. `NicknamePrompt` overlay.

Plano:
1. Tirar a `VBox` da `CenterContainer` e **ancorar à esquerda** (faixa de ~35–40% da largura). Manter o `Logo` no topo dessa coluna (ou acima dela).
2. Trocar/cobrir o `Bg` ColorRect por um `TextureRect` (fundo) + `AnimatedSprite2D` (cena animada) ocupando a direita ~60% (ou full-screen, com a coluna do menu por cima numa faixa levemente escurecida pra legibilidade).
3. Garantir que os botões **não cubram** os personagens.
4. `VersionLabel` continua discreto (canto). Cuidar de não conflitar com a arte.
5. Manter import Nearest/Filter Off na arte nova.

Quando tiver arte (ou placeholder), montar o `.tscn` com a coluna à esquerda + `AnimatedSprite2D` à direita no grid certo.

## Pendências

- [ ] Rafa: finalizar arte cozy (player + Ting) + frames de animação no grid 480×270 (×4).
- [ ] Implementar layout assimétrico no `main_menu.tscn` (menu esquerda / arte direita).
- [ ] Wire do `AnimatedSprite2D`/`SpriteFrames` + autoplay do loop no menu.
