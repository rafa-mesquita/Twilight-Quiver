# Wave 21 — Confronto Duplo (Gorilla + Duskrose)

**Data:** 2026-05-31
**Status:** Design aprovado (aguardando review do spec)

## Objetivo

Adicionar uma nova wave de boss (wave 21) onde o jogador enfrenta **os dois bosses ao mesmo tempo** na arena da Duskrose: o **Gorilla** (Mage Monkey) no centro e a **Duskrose** no topo. A wave só termina quando ambos morrem.

## Abordagem

**Estender o padrão atual de waves de boss** (`wave_manager.gd` já trata waves 7 e 14 com ramos hardcoded). A wave 21 entra como uma terceira wave de boss; as partes genuinamente novas (dois bosses, duas barras de HP, cinematic de múltiplos alvos, condição de vitória dupla) ficam em helpers focados novos. A lógica das waves 7/14 NÃO é alterada (risco baixo de regressão).

- Novo export `boss_dual_wave: int = 21`.
- `_is_boss_wave(num)` passa a retornar `num == 7 or num == boss_redux_wave or num == boss_dual_wave`.

## Decisões de design

### 1. Trigger, mapa e ambiente
- Wave 21 **reusa a arena da Duskrose** (`wave14_map_scene`): esconde o Map normal (grupo `map`) e instancia a arena temática — mesma lógica já usada na wave 14.
- **Limpa estruturas compradas** (torres/aliados) como na wave 14 (`_clear_alive_structures_for_boss_wave`), já que elas não pertencem à arena.
- **Bloqueia spawn de dark_ball** explicitamente na wave 21. (Por ser boss wave os spawns normais já são zerados, mas adiciona-se um guard explícito no ramo do dark_ball: `num >= 9 and num % 3 == 0 and not _is_boss_wave(num)`.)
- **Música:** **sequência de duas faixas em loop** (fornecidas pelo usuário):
  - Faixa 1: `res://audios/musics/Boss 21 wave.mp3`
  - Faixa 2: `res://audios/musics/Boss Wve 21 - 2.mp3`
  - Ordem: toca a faixa 1 inteira → ao terminar, toca a faixa 2 inteira → ao terminar, **volta pra faixa 1** e repete (loop entre as duas), enquanto a wave 21 durar.
  - Diferente das outras waves de boss (track única em loop nativo), isso precisa de um **pequeno sequenciador**: cada faixa toca SEM loop nativo; no sinal `finished` do player de música, troca pra próxima faixa da sequência. Ao fim da wave, desliga o sequenciador e restaura a track default (mesma mecânica de restauração das outras waves).
  - Exports: `boss_dual_music_1` e `boss_dual_music_2: AudioStream` apontando pros dois arquivos.

### 2. Spawn e layout dos bosses
- **Gorilla (mage_monkey):** centro da arena. **HP fixo 6000** (override em `_apply_wave_scaling`/config, como os overrides de HP já existentes para 7/14).
  - **Mantém o escudo:** invulnerável enquanto houver pelo menos um mago vivo (mecânica idêntica à da wave 7).
  - Os magos nascem de **dois spawn points novos** posicionados na arena da Duskrose (markers na cena da arena ou posições calculadas relativas ao centro).
- **Duskrose:** topo da arena. **HP fixo 8000**. Mantém o comportamento atual (patrulha horizontal no topo + invocação dinâmica de Rose Monsters + vinhas).
- **Player:** começa no **canto inferior-esquerdo** da arena (tunável; o usuário aceitou esquerdo ou direito).

### 3. Cinematic de intro
- Generalizar a maquinaria de cinematic atual (`_play_boss_intro_cinematic`, hoje com **1 alvo** via `_wave7_boss_center`) para aceitar uma **lista de alvos com hold entre eles**.
- Sequência da wave 21:
  1. **Duskrose** (topo) — segura ~3s.
  2. Pan/transição para o **Gorilla** (centro) — segura ~3s.
  3. Pan para o **player** no canto inferior-esquerdo.
- Holds (~3s cada) tunáveis.

### 4. HUD — duas barras de HP
- Hoje o HUD tem **uma** `BossHpBar` (`hud.gd`, segue um único `_current_boss` via `_update_boss_hp_bar`/`_position_boss_hp_bar_for`).
- Adicionar suporte a **dois bosses simultâneos**: duas barras **menores lado a lado na base da tela** (cada ~metade da largura), uma para o Gorilla e uma para a Duskrose, cada uma com nome + HP atual/máximo.
- Quando um boss morre, a barra dele some (ou fica zerada e some); a do outro permanece visível.
- Implementação: ou (a) instanciar uma segunda `BossHpBar` e reposicionar as duas em meia-largura, ou (b) generalizar o sistema do HUD para uma lista de bosses. Decisão fina fica para o plano de implementação; o requisito é "duas barras menores na base".

### 5. Condição de vitória e limpeza
- A wave **só termina quando OS DOIS bosses morrem**. Se um morre antes, o outro continua normalmente (a wave não encerra).
- **Morte do Gorilla** limpa os magos dele (como na wave 7, onde a morte do boss remove os minions).
- **Morte da Duskrose** limpa os Rose Monsters/vinhas dela.
- **Drops:** cada boss dropa gold escalado (regra de boss wave). Default: **~60% do drop solo cada** (soma generosa para o confronto duplo, sem dobrar). Tunável.

### 6. Tuning do escudo do Gorilla (ponto de atenção de balance)
- Como o escudo fica ativo enquanto há mago vivo **e** o Gorilla re-invoca, é preciso uma cadência/cap de magos que permita ao jogador limpar os magos e "abrir" o Gorilla mesmo sob pressão da Duskrose.
- Proposta inicial (a afinar no playtest): **horda inicial pequena (~3–4 magos)** + **re-invocação espaçada** com **cap simultâneo baixo**.
- Os dois spawn points dos magos servem para distribuir de onde eles vêm.

### 7. Dev mode / teste
- Adicionar um botão **"Boss W21"** na `WaveBar` do dev panel (ao lado dos botões **Boss W7** e **Boss W14** que já existem), chamando `_simulate_wave(21)` → `wave_manager.dev_start_wave(21)`. Pula direto pro confronto duplo (bypass das waves anteriores), pra testar o boss assim que o modelo estiver montado.

## Componentes afetados

- `scripts/systems/wave_manager.gd` — `boss_dual_wave`, `_is_boss_wave`, config de spawn da wave 21 (dois bosses), overrides de HP (6000/8000), reuso da arena/limpeza de estruturas, guard de dark_ball, spawn points dos magos, cinematic multi-alvo, condição de vitória dupla, drops, **sequenciador de música de 2 faixas** (toca faixa 1 → faixa 2 → loop; restaura default no fim da wave).
- `scripts/ui/hud.gd` (+ cena do `BossHpBar`) — suporte a duas barras menores na base.
- Cena da arena da Duskrose (`wave14_map_scene`) ou cálculo de posições — dois spawn points de mago + ponto inicial do player no canto inferior-esquerdo.
- Mage Monkey / Duskrose: reuso das mecânicas existentes (escudo, invocações) — sem mudanças de comportamento, só parametrização por wave.
- `scripts/ui/dev_panel.gd` (+ cena `WaveBar`) — botão **Wave 21** chamando `_simulate_wave(21)` (reusa `dev_start_wave`).

## Itens tunáveis (ajustar no playtest)
- HP de cada boss (6000 / 8000).
- Cadência/cap/horda inicial de magos do Gorilla.
- Holds do cinematic (~3s).
- Canto inicial do player (esquerdo/direito).
- Drops por boss (~60% cada).

## Fora de escopo
- Mudanças no comportamento intrínseco de cada boss (escudo, casts, summons ficam como já são).
- Bump de versão (só em deploy).
