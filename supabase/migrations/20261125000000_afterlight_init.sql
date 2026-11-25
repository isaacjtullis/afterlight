-- Afterlight: cloud saves and server-resolved jobs.
-- Players sign in anonymously from the app. Every row belongs to auth.uid().

-- Saves ---------------------------------------------------------------------

create table if not exists public.saves (
  user_id   uuid primary key references auth.users (id) on delete cascade,
  version   integer not null default 1,
  data      jsonb not null,
  saved_at  timestamptz not null default now()
);

alter table public.saves enable row level security;

create policy "read own save"   on public.saves for select using (auth.uid() = user_id);
create policy "insert own save" on public.saves for insert with check (auth.uid() = user_id);
create policy "update own save" on public.saves for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Write a save. Pass the version you last saw, or -1 to overwrite.
-- Raises 'save_conflict' when another device saved in between.
create or replace function public.save_game(p_data text, p_expected_version integer)
returns integer
language plpgsql
security invoker
set search_path = public
as $$
declare
  v integer;
begin
  insert into public.saves (user_id, version, data, saved_at)
  values (auth.uid(), 1, p_data::jsonb, now())
  on conflict (user_id) do update
    set version = saves.version + 1, data = excluded.data, saved_at = now()
    where p_expected_version < 0 or saves.version = p_expected_version
  returning version into v;
  if v is null then
    raise exception 'save_conflict' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

create or replace function public.load_game()
returns table (version integer, data text, saved_at timestamptz)
language sql
stable
security invoker
set search_path = public
as $$
  select s.version, s.data::text, s.saved_at from public.saves s where s.user_id = auth.uid();
$$;

-- Jobs ----------------------------------------------------------------------
-- A job is a fully worked-out plan (every step's duration and stamina cost).
-- The server owns the clock: it records when the job started and, on claim,
-- counts how many steps fit in the elapsed time. A claimed job never changes again,
-- so the same work can't pay out twice.

create table if not exists public.jobs (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  kind        text not null,
  title       text not null,
  plan        jsonb not null,
  status      text not null default 'active' check (status in ('active', 'claimed')),
  started_at  timestamptz not null default now(),
  completed   integer,
  claimed_at  timestamptz
);

create index if not exists jobs_user_status on public.jobs (user_id, status);
-- At most one active job per player.
create unique index if not exists jobs_one_active on public.jobs (user_id) where status = 'active';

alter table public.jobs enable row level security;
create policy "read own jobs"   on public.jobs for select using (auth.uid() = user_id);
create policy "insert own jobs" on public.jobs for insert with check (auth.uid() = user_id);
create policy "update own jobs" on public.jobs for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Mirrors JobResolver.completedSteps in AfterlightCore exactly.
create or replace function public.job_steps_done(p_plan jsonb, p_elapsed double precision)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  n integer := 0;
  t integer := 0;
  s integer := 0;
  budget integer := coalesce((p_plan ->> 'staminaBudget')::integer, 0);
  pause integer := (p_plan ->> 'pauseIndex')::integer;
  step record;
begin
  for step in
    select value, ordinality - 1 as i
    from jsonb_array_elements(p_plan -> 'steps') with ordinality
    order by ordinality
  loop
    exit when pause is not null and step.i >= pause;
    t := t + (step.value ->> 'seconds')::integer;
    s := s + (step.value ->> 'stamina')::integer;
    exit when t > p_elapsed or s > budget;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Start a job and return the server start time (epoch seconds).
create or replace function public.start_job(p_id uuid, p_kind text, p_title text, p_plan text)
returns double precision
language plpgsql
security invoker
set search_path = public
as $$
declare
  started timestamptz;
begin
  insert into public.jobs (id, user_id, kind, title, plan)
  values (p_id, auth.uid(), p_kind, p_title, p_plan::jsonb)
  returning started_at into started;
  return extract(epoch from started);
end;
$$;

-- Progress so far, without ending the job.
create or replace function public.job_progress(p_id uuid)
returns integer
language sql
stable
security invoker
set search_path = public
as $$
  select case when j.status = 'claimed' then j.completed
              else public.job_steps_done(j.plan, extract(epoch from (now() - j.started_at))) end
  from public.jobs j where j.id = p_id and j.user_id = auth.uid();
$$;

-- End the job and lock in how much got done. Claiming again returns the same answer.
create or replace function public.claim_job(p_id uuid)
returns json
language plpgsql
security invoker
set search_path = public
as $$
declare
  j public.jobs;
  n integer;
begin
  select * into j from public.jobs where id = p_id and user_id = auth.uid() for update;
  if not found then
    raise exception 'job_not_found' using errcode = 'P0002';
  end if;
  if j.status = 'claimed' then
    return json_build_object('completed', j.completed, 'started_epoch', extract(epoch from j.started_at), 'already_claimed', true);
  end if;
  n := public.job_steps_done(j.plan, extract(epoch from (now() - j.started_at)));
  update public.jobs set status = 'claimed', completed = n, claimed_at = now() where id = p_id;
  return json_build_object('completed', n, 'started_epoch', extract(epoch from j.started_at), 'already_claimed', false);
end;
$$;

grant execute on function public.save_game(text, integer) to authenticated;
grant execute on function public.load_game() to authenticated;
grant execute on function public.start_job(uuid, text, text, text) to authenticated;
grant execute on function public.job_progress(uuid) to authenticated;
grant execute on function public.claim_job(uuid) to authenticated;
grant execute on function public.job_steps_done(jsonb, double precision) to authenticated;
