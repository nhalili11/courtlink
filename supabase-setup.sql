-- Run this entire file in your Supabase SQL Editor (supabase.com → your project → SQL Editor)

-- 1. Profiles table (stores name + role for each user)
create table if not exists public.profiles (
  id uuid references auth.users on delete cascade primary key,
  email text,
  full_name text,
  role text not null default 'lawyer' check (role in ('admin','lawyer','viewer')),
  created_at timestamptz default now()
);

-- 2. Events table
create table if not exists public.events (
  id text primary key,
  client_name text not null,
  client_file text,
  date text not null,
  time text,
  hearing_type text default 'other',
  jurisdiction text,
  courthouse text,
  courtroom text,
  judge text,
  attendees text default 'all',
  notes text,
  created_by uuid references auth.users on delete set null,
  created_at timestamptz default now()
);

-- 3. Auto-create a profile row when a user signs up
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email, full_name, role)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    'lawyer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 4. Enable Row Level Security (only logged-in firm members can access data)
alter table public.profiles enable row level security;
alter table public.events enable row level security;

-- 5. Policies: any authenticated user can read everything
create policy "Authenticated users can read profiles"
  on public.profiles for select using (auth.role() = 'authenticated');

create policy "Authenticated users can read events"
  on public.events for select using (auth.role() = 'authenticated');

-- 6. Policies: lawyers and admins can insert/update/delete events
create policy "Lawyers and admins can insert events"
  on public.events for insert
  with check (
    auth.role() = 'authenticated' and
    exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','lawyer'))
  );

create policy "Lawyers and admins can delete events"
  on public.events for delete
  using (
    exists (select 1 from public.profiles where id = auth.uid() and role in ('admin','lawyer'))
  );

-- 7. Admins can update roles
create policy "Admins can update profiles"
  on public.profiles for update
  using (
    exists (select 1 from public.profiles where id = auth.uid() and role = 'admin')
  );

-- 8. Enable realtime on the events table
alter publication supabase_realtime add table public.events;

-- DONE. After running this, make yourself admin by running:
-- update public.profiles set role = 'admin' where email = 'your@email.com';
