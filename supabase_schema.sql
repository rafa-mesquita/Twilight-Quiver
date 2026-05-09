-- Twilight Quiver leaderboard schema.
-- Rode esse SQL uma vez no SQL Editor do Supabase (Dashboard → SQL Editor → New query).

create table if not exists runs (
  id            uuid primary key default gen_random_uuid(),
  created_at    timestamptz not null default now(),
  nickname      text not null check (char_length(nickname) between 1 and 24),
  version       text not null,
  wave          int  not null check (wave >= 0),
  time_ms       int  not null check (time_ms >= 0),
  kills         int  not null check (kills >= 0),
  allies        int  not null check (allies >= 0),
  dmg_dealt     int  not null check (dmg_dealt >= 0),
  dmg_taken     int  not null check (dmg_taken >= 0),
  score         int  not null default 0
);

-- Migração pra projetos que rodaram a versão antiga do schema (sem score).
alter table runs add column if not exists score int not null default 0;

-- Indexes pra ordenar o leaderboard.
create index if not exists runs_score_idx     on runs (score desc);
create index if not exists runs_wave_time_idx on runs (wave desc, time_ms asc);
create index if not exists runs_version_idx   on runs (version);

-- RLS: anon pode INSERT (cliente do jogo manda score) e SELECT (ler leaderboard).
-- UPDATE/DELETE bloqueado pra anon — só admin via service_role pode editar.
alter table runs enable row level security;

drop policy if exists "anon insert" on runs;
drop policy if exists "anon select" on runs;

create policy "anon insert" on runs
  for insert to anon with check (true);

create policy "anon select" on runs
  for select to anon using (true);
