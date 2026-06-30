-- Run this in Supabase SQL Editor to allow the new member titles.
alter table public.firm_members drop constraint if exists firm_members_role_check;
alter table public.firm_members add constraint firm_members_role_check
  check (role in ('admin','lawyer','student','legal_support','office_management','other'));
