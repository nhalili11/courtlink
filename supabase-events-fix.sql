-- Run this in Supabase SQL Editor.
-- Lets ANY firm member add events to their firm's calendar (not just admin/lawyer).
-- Personal events stay private to their creator.

drop policy if exists "Users can insert events" on public.events;
create policy "Users can insert events" on public.events for insert
  with check (
    auth.role() = 'authenticated' and (
      (calendar_type = 'personal' and created_by = auth.uid())
      or (firm_id is not null and public.is_firm_member(firm_id))
    )
  );

-- Delete: you can remove an event you created, or an admin can remove any firm event.
drop policy if exists "Users can delete their events" on public.events;
create policy "Users can delete their events" on public.events for delete
  using (
    created_by = auth.uid()
    or (firm_id is not null and public.is_firm_admin(firm_id))
  );
