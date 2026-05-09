# Site de distribuição — Twilight Quiver

Spec do site próprio pra distribuir builds versionadas pros testers, mantendo o repositório do jogo privado.

## Objetivo

- Repo do jogo **fechado** — código-fonte só pra equipe interna.
- Testers conseguem baixar builds **versionadas** (Windows, macOS, web) por uma página própria.
- Versionamento alinhado com `application/config/version` do [project.godot](project.godot) (regra em [CLAUDE.md](CLAUDE.md)).
- Reaproveita o Supabase que já existe (Auth + Storage + tabela `runs` do leaderboard).

## Usuários

| Papel       | O que faz                                                       |
| ----------- | --------------------------------------------------------------- |
| **Tester**  | Loga, vê lista de versões, baixa o build da plataforma dele.    |
| **Admin**   | Faz upload de nova versão + release notes. Convida testers.     |

## Páginas / fluxos

1. **`/`** (landing pública)
   - Hero com nome do jogo, logo, GIF/screenshots.
   - Botão "Entrar" → `/login`.
   - **Não mostra builds.** Quem chegar sem login não baixa nada.

2. **`/login`**
   - Magic link por email (Supabase Auth).
   - Só emails autorizados (whitelist em tabela `testers` ou domain restriction).
   - Após login → `/downloads`.

3. **`/downloads`** (gated)
   - Lista de releases ordenadas por data desc.
   - Versão mais recente em destaque ("Latest").
   - Pra cada release: versão, data, release notes (markdown), botões de download por plataforma.
   - Botão de download chama Edge Function (ou cliente direto) que gera signed URL temporária do Supabase Storage.

4. **`/admin`** (gated, só admins)
   - Form pra criar nova release: versão, notes (markdown), upload de zips por plataforma.
   - Lista de testers, com convite por email.
   - Toggle "is_latest" pra marcar a versão atual.

5. **`/leaderboard`** (opcional, gated)
   - Espelha o leaderboard do jogo lendo da mesma tabela `runs`.
   - Filtro por versão (igual o que existe no jogo).
   - Útil pra acompanhar testes sem abrir o jogo.

## Autenticação

**Stack:** Supabase Auth com **magic link** (passwordless).

- Tester clica em "Entrar com email" → recebe link no inbox → clica → loga.
- **Whitelist obrigatória.** Tabela `testers (email text primary key, role text default 'tester', invited_at timestamptz)`.
  - Trigger ou RLS policy que rejeita login se email não está em `testers`.
  - Roles: `tester`, `admin`.
- **Sessão persistente** — tester loga uma vez no navegador, continua logado.

## Storage

**Stack:** Supabase Storage, bucket **privado** chamado `builds`.

Estrutura:
```
builds/
  pre-alpha-0.0.1/
    twilight-quiver-windows.zip
    twilight-quiver-macos.zip
    twilight-quiver-web.zip
  pre-alpha-0.1.0/
    ...
```

- Bucket privado — sem URLs públicas.
- Download = chamada autenticada que gera **signed URL** com TTL curto (5–10 min).
- RLS na tabela `releases`: só usuário autenticado e em `testers` pode ver linhas.

## Modelo de dados (novas tabelas no Supabase)

```sql
-- Whitelist de testers
create table testers (
  email      text primary key,
  role       text not null default 'tester' check (role in ('tester', 'admin')),
  invited_at timestamptz not null default now()
);

-- Releases
create table releases (
  id            uuid primary key default gen_random_uuid(),
  version       text not null unique,        -- "pre-alpha-0.0.1"
  released_at   timestamptz not null default now(),
  notes         text,                         -- markdown
  is_latest     boolean not null default false,
  windows_path  text,                         -- ex: "pre-alpha-0.0.1/twilight-quiver-windows.zip"
  macos_path    text,
  web_path      text,                         -- pode ser apontado pra um path do bucket OU
                                              -- subir o build web e expor diretamente
  published     boolean not null default false  -- false = rascunho, só admin vê
);

-- RLS: só authenticated user em testers pode ler releases publicadas.
alter table releases enable row level security;
create policy "testers read published" on releases for select
  to authenticated
  using (published = true and auth.email() in (select email from testers));

-- Storage policy: signed URLs só pra paths que tester tem direito.
-- (Mais simples: deixa só authenticated chamar storage.objects, e a aplicação valida)
```

## Workflow de release (admin)

Manual no início, automatizável depois.

### Manual (início)

1. Dev sobe `application/config/version` no `project.godot` ([regra do CLAUDE.md](CLAUDE.md)).
2. Build local: `Project → Export` no Godot, gera os zips.
3. Login em `/admin` no site.
4. "New Release" → preenche versão, notes em markdown, anexa os zips.
5. Toggle `is_latest = true`, `published = true`.
6. Tester recebe email opcional ("nova versão disponível") via Supabase Edge Function.

### Automatizado (depois)

Reativa o [.github/workflows/deploy.yml](.github/workflows/deploy.yml) com:
- Build (já está pronto no workflow).
- Step extra: usa Supabase API + service_role key (em GitHub secret) pra:
  - Upload dos zips no Storage.
  - Insert linha em `releases` com versão lida do project.godot.
  - Marca `is_latest=true` no novo, `false` nos antigos.

## Stack sugerida

| Camada       | Tech                                              |
| ------------ | ------------------------------------------------- |
| Frontend     | **SvelteKit** ou **Next.js** (ambos rápidos)      |
| Estilo       | Tailwind CSS                                      |
| Auth + DB    | Supabase                                          |
| Storage      | Supabase Storage                                  |
| Hosting      | **Vercel** ou **Netlify** (free tier basta)       |
| Domínio      | `.com.br` ou `.gg`/`.studio` se quiser temático   |
| CI           | GitHub Actions do projeto do site (não do jogo)   |

Repo do **site** é separado do repo do **jogo** — site pode ser público (não tem código do jogo, só interface). Repo do jogo continua privado.

## Decisões em aberto

- [ ] **Login: magic link ou email+senha?** Magic link é mais simples, senha permite "esquecer email" recovery.
- [ ] **Web build embed na página ou só download?** Se embed, joga direto no navegador sem download.
- [ ] **Release notes em markdown direto no admin, ou puxar do CHANGELOG.md do repo do jogo?**
- [ ] **Admin pode mexer em release antiga (corrigir notes, re-upload)?** Recomendo sim, com `updated_at`.
- [ ] **Quanto tempo guardar versões antigas?** Storage tem custo. Sugiro: manter as 5 últimas + a "stable" mais recente.
- [ ] **Telemetria opcional** — quem baixou qual versão? Útil pra saber quem testar bug em qual build. Adiciona tabela `downloads (tester_email, version, downloaded_at)`.
- [ ] **Notificação de nova release** — email automático via Supabase trigger? Discord webhook?

## Próximos passos

1. Cria o repo separado do site (privado também ou público — tanto faz, não tem código sensível).
2. Roda as migrations SQL no Supabase (tabelas `testers`, `releases`).
3. Cria o bucket `builds` (privado) no Supabase Storage.
4. Implementa as páginas na ordem: `/login` → `/downloads` → `/admin`.
5. Faz o primeiro upload manual da `pre-alpha-0.0.1` pra validar fluxo end-to-end.
6. Convida 1–2 testers e itera com base no feedback.
