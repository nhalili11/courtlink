-- Run this in Supabase SQL Editor to add multi-firm support

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

-- 3. Add firm_id and calendar_type to events
alter table public.events
  add column if not exists firm_id uuid references public.firms on delete cascade,
  add column if not exists calendar_type text default 'firm';

-- 4. Add full_name to profiles if not there
alter table public.profiles
  add column if not exists full_name text;

-- 5. RLS
alter table public.firms enable row level security;
alter table public.firm_members enable row level security;

-- Firms: any authenticated user can read (needed to look up by invite code)
drop policy if exists "Authenticated can read firms" on public.firms;
create policy "Authenticated can read firms"
  on public.firms for select using (auth.role() = 'authenticated');

drop policy if exists "Authenticated users can create firms" on public.firms;
create policy "Authenticated users can create firms"
  on public.firms for insert with check (auth.role() = 'authenticated');

drop policy if exists "Firm admins can update their firm" on public.firms;
create policy "Firm admins can update their firm"
  on public.firms for update
  using (exists (select 1 from public.firm_members where firm_id = firms.id and user_id = auth.uid() and role = 'admin'));

-- Firm members: members can read members of their firms
drop policy if exists "Members can read their firm members" on public.firm_members;
create policy "Members can read their firm members"
  on public.firm_members for select
  using (exists (select 1 from public.firm_members fm where fm.firm_id = firm_members.firm_id and fm.user_id = auth.uid()));

drop policy if exists "Users can join firms" on public.firm_members;
create policy "Users can join firms"
  on public.firm_members for insert
  with check (auth.role() = 'authenticated' and user_id = auth.uid());

drop policy if exists "Members can update status or admins update roles" on public.firm_members;
create policy "Members can update status or admins update roles"
  on public.firm_members for update
  using (
    user_id = auth.uid()
    or exists (select 1 from public.firm_members fm where fm.firm_id = firm_members.firm_id and fm.user_id = auth.uid() and fm.role = 'admin')
  );

drop policy if exists "Admins can remove members or users can leave" on public.firm_members;
create policy "Admins can remove members or users can leave"
  on public.firm_members for delete
  using (
    user_id = auth.uid()
    or exists (select 1 from public.firm_members fm where fm.firm_id = firm_members.firm_id and fm.user_id = auth.uid() and fm.role = 'admin')
  );

-- 6. Update events policies
drop policy if exists "Lawyers and admins can insert events" on public.events;
drop policy if exists "Users can read their events" on public.events;
drop policy if exists "Authenticated users can read events" on public.events;
drop policy if exists "Lawyers and admins can delete events" on public.events;
drop policy if exists "Users can insert events" on public.events;
drop policy if exists "Users can delete their events" on public.events;

create policy "Users can read their events"
  on public.events for select
  using (
    (calendar_type = 'personal' and created_by = auth.uid())
    or (firm_id is not null and exists (select 1 from public.firm_members where firm_id = events.firm_id and user_id = auth.uid()))
  );

create policy "Users can insert events"
  on public.events for insert
  with check (
    auth.role() = 'authenticated' and (
      (calendar_type = 'personal' and created_by = auth.uid())
      or (firm_id is not null and exists (
        select 1 from public.firm_members
        where firm_id = events.firm_id and user_id = auth.uid() and role in ('admin','lawyer')
      ))
    )
  );

create policy "Users can delete their events"
  on public.events for delete
  using (
    created_by = auth.uid()
    or exists (
      select 1 from public.firm_members
      where firm_id = events.firm_id and user_id = auth.uid() and role in ('admin','lawyer')
    )
  );

-- Profiles: users can update their own
drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
  on public.profiles for update
  using (id = auth.uid());

-- 7. Realtime for presence
alter publication supabase_realtime add table public.firm_members;
alter publication supabase_realtime add table public.firms;
