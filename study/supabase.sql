-- Schema for /study sync. Run once in Supabase: Dashboard → SQL Editor → New query → paste → Run.

-- One row per deck or card. `data` holds the object as the app stores it;
-- `updated_at` (ms since epoch) decides which version wins when devices disagree.
create table if not exists public.study_items (
  user_id    uuid    not null default auth.uid() references auth.users on delete cascade,
  id         text    not null,
  kind       text    not null check (kind in ('deck', 'card')),
  data       jsonb,
  updated_at bigint  not null,
  deleted    boolean not null default false,
  primary key (user_id, id)
);

-- Each signed-in user can only see and change their own rows.
alter table public.study_items enable row level security;

drop policy if exists "own rows" on public.study_items;
create policy "own rows" on public.study_items
  for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, insert, update, delete on public.study_items to authenticated;
revoke all on public.study_items from anon;

-- Upsert a batch of rows, keeping whichever version is newer.
create or replace function public.study_push(items jsonb)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.study_items as t (user_id, id, kind, data, updated_at, deleted)
  select auth.uid(), i->>'id', i->>'kind', i->'data', (i->>'updated_at')::bigint, coalesce((i->>'deleted')::boolean, false)
  from jsonb_array_elements(items) as i
  on conflict (user_id, id) do update
    set kind = excluded.kind, data = excluded.data, updated_at = excluded.updated_at, deleted = excluded.deleted
    where t.updated_at < excluded.updated_at;
$$;

revoke execute on function public.study_push(jsonb) from public, anon;
grant execute on function public.study_push(jsonb) to authenticated;
