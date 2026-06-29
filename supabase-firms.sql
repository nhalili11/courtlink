-- Run this entire file in your Supabase SQL Editor (safe to re-run).

-- 1. Firms table
create table if not exists public.firms (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  logo_url text,
  primary_color text default '#4361EE',
  bg_color text default '#F0F4FE',
  name_color text default '#1E293B',
  invite_code text unique not null,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz default now()
);

-- 2. Firm members table
create table if not exists public.firm_members (
  id uuid default gen_random_uuid() primary key,
  firm_id uuid references public.firms on delete cascade not null,
  user_id uuid references auth.users on delete cascade not null,
  role text not null default 'lawyer' check (role in ('admin','lawyer','student','other')),
  status text not null default 'offline',
  status_updated_at timestamptz default now(),
  joined_at timestamptz default now(),
  unique(firm_id, user_id)
);

-- 3. Add columns to events
alter table public.events
  add column if not exists firm_id uuid references public.firms on delete cascade,
  add column if not exists calendar_type text default 'firm';

alter table public.profiles
  add column if not exists full_name text;

-- 4. Helper function (SECURITY DEFINER avoids RLS infinite recursion)
create or replace function public.is_firm_member(fid uuid)
returns boolean language sql security definer stable as $$
  select exists (select 1 from public.firm_members where firm_id = fid and user_id = auth.uid());
$$;

create or replace function public.is_firm_admin(fid uuid)
returns boolean language sql security definer stable as $$
  select exists (select 1 from public.firm_members where firm_id = fid and user_id = auth.uid() and role = 'admin');
$$;

create or replace function public.can_edit_firm(fid uuid)
returns boolean language sql security definer stable as $$
  select exists (select 1 from public.firm_members where firm_id = fid and user_id = auth.uid() and role in ('admin','lawyer'));
$$;

-- 5. Enable RLS
alter table public.firms enable row level security;
alter table public.firm_members enable row level security;

-- 6. Firms policies
drop policy if exists "read firms" on public.firms;
create policy "read firms" on public.firms for select using (auth.role() = 'authenticated');

drop policy if exists "create firms" on public.firms;
create policy "create firms" on public.firms for insert with check (auth.role() = 'authenticated');

drop policy if exists "update firms" on public.firms;
create policy "update firms" on public.firms for update using (public.is_firm_admin(id));

-- 7. Firm members policies (use helper functions — no recursion)
drop policy if exists "read members" on public.firm_members;
create policy "read members" on public.firm_members for select using (public.is_firm_member(firm_id));

drop policy if exists "join firm" on public.firm_members;
create policy "join firm" on public.firm_members for insert
  with check (auth.role() = 'authenticated' and user_id = auth.uid());

drop policy if exists "update members" on public.firm_members;
create policy "update members" on public.firm_members for update
  using (user_id = auth.uid() or public.is_firm_admin(firm_id));

drop policy if exists "delete members" on public.firm_members;
create policy "delete members" on public.firm_members for delete
  using (user_id = auth.uid() or public.is_firm_admin(firm_id));

-- 8. Events policies
drop policy if exists "Lawyers and admins can insert events" on public.events;
drop policy if exists "Authenticated users can read events" on public.events;
drop policy if exists "Lawyers and admins can delete events" on public.events;
drop policy if exists "Users can read their events" on public.events;
drop policy if exists "Users can insert events" on public.events;
drop policy if exists "Users can delete their events" on public.events;

create policy "Users can read their events" on public.events for select
  using (
    (calendar_type = 'personal' and created_by = auth.uid())
    or (firm_id is not null and public.is_firm_member(firm_id))
  );

create policy "Users can insert events" on public.events for insert
  with check (
    auth.role() = 'authenticated' and (
      (calendar_type = 'personal' and created_by = auth.uid())
      or (firm_id is not null and public.can_edit_firm(firm_id))
    )
  );

create policy "Users can delete their events" on public.events for delete
  using (created_by = auth.uid() or (firm_id is not null and public.can_edit_firm(firm_id)));

-- 9. Profiles: users can update their own
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile" on public.profiles for update using (id = auth.uid());

-- 10. Realtime
do $$ begin
  alter publication supabase_realtime add table public.firm_members;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.firms;
exception when duplicate_object then null; end $$;
