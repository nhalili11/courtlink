-- Run this in Supabase SQL Editor to add client records.

-- Clients (one row per person)
create table if not exists public.clients (
  id text primary key,
  firm_id uuid references public.firms on delete cascade not null,
  name text not null,
  date_of_birth text,
  is_youth boolean default false,
  notes text,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz default now()
);

-- Client matters (one row per jurisdiction / set of charges — a client can have many)
create table if not exists public.client_matters (
  id text primary key,
  client_id text references public.clients on delete cascade not null,
  firm_id uuid references public.firms on delete cascade not null,
  jurisdiction text,
  charges text,
  file_number text,
  created_at timestamptz default now()
);

alter table public.clients enable row level security;
alter table public.client_matters enable row level security;

-- Any firm member can read/write their firm's clients
drop policy if exists "members read clients" on public.clients;
create policy "members read clients" on public.clients for select using (public.is_firm_member(firm_id));
drop policy if exists "members insert clients" on public.clients;
create policy "members insert clients" on public.clients for insert with check (public.is_firm_member(firm_id));
drop policy if exists "members update clients" on public.clients;
create policy "members update clients" on public.clients for update using (public.is_firm_member(firm_id));
drop policy if exists "members delete clients" on public.clients;
create policy "members delete clients" on public.clients for delete using (public.is_firm_member(firm_id));

drop policy if exists "members read matters" on public.client_matters;
create policy "members read matters" on public.client_matters for select using (public.is_firm_member(firm_id));
drop policy if exists "members insert matters" on public.client_matters;
create policy "members insert matters" on public.client_matters for insert with check (public.is_firm_member(firm_id));
drop policy if exists "members update matters" on public.client_matters;
create policy "members update matters" on public.client_matters for update using (public.is_firm_member(firm_id));
drop policy if exists "members delete matters" on public.client_matters;
create policy "members delete matters" on public.client_matters for delete using (public.is_firm_member(firm_id));

do $$ begin alter publication supabase_realtime add table public.clients; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.client_matters; exception when duplicate_object then null; end $$;
