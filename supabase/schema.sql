create extension if not exists pgcrypto;
create table if not exists public.profiles(id uuid primary key references auth.users(id) on delete cascade,display_name text,role text not null default 'user' check(role in('user','admin')),created_at timestamptz not null default now());
create table if not exists public.wallets(user_id uuid primary key references auth.users(id) on delete cascade,balance bigint not null default 0 check(balance>=0),lifetime_earned bigint not null default 0 check(lifetime_earned>=0),updated_at timestamptz not null default now());
create table if not exists public.reward_ledger(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,event_type text not null check(event_type in('earn','redeem','adjustment','reversal')),points bigint not null check(points<>0),reference text unique,description text,created_at timestamptz not null default now());
create table if not exists public.ad_sessions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,provider text not null,provider_event_id text unique,status text not null default 'pending' check(status in('pending','verified','rejected')),points bigint not null default 0 check(points>=0),created_at timestamptz not null default now(),verified_at timestamptz);
create table if not exists public.withdrawal_requests(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,points bigint not null check(points>0),payout_method text not null check(payout_method in('upi','redeem_code')),payout_details jsonb not null default '{}'::jsonb,status text not null default 'pending' check(status in('pending','approved','rejected','paid')),created_at timestamptz not null default now(),reviewed_at timestamptz);
create table if not exists public.referrals(id uuid primary key default gen_random_uuid(),referrer_id uuid not null references auth.users(id) on delete cascade,referred_id uuid not null unique references auth.users(id) on delete cascade,status text not null default 'pending' check(status in('pending','qualified','rewarded','rejected')),created_at timestamptz not null default now(),check(referrer_id<>referred_id));
create table if not exists public.reward_catalog(id uuid primary key default gen_random_uuid(),title text not null,description text,points_cost bigint not null check(points_cost>0),reward_type text not null check(reward_type in('upi','redeem_code')),active boolean not null default false,created_at timestamptz not null default now());
create table if not exists public.redemptions(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,reward_id uuid references public.reward_catalog(id),points_spent bigint not null check(points_spent>0),status text not null default 'pending' check(status in('pending','approved','rejected','fulfilled')),created_at timestamptz not null default now());
create table if not exists public.provider_settings(id uuid primary key default gen_random_uuid(),provider text not null unique,enabled boolean not null default false,config jsonb not null default '{}'::jsonb,updated_at timestamptz not null default now());
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$ begin insert into public.profiles(id,display_name) values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1))) on conflict(id) do nothing;insert into public.wallets(user_id) values(new.id) on conflict(user_id) do nothing;return new;end;$$;
drop trigger if exists on_auth_user_created on auth.users;create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();
alter table public.profiles enable row level security;alter table public.wallets enable row level security;alter table public.reward_ledger enable row level security;alter table public.ad_sessions enable row level security;alter table public.withdrawal_requests enable row level security;alter table public.referrals enable row level security;alter table public.reward_catalog enable row level security;alter table public.redemptions enable row level security;alter table public.provider_settings enable row level security;
drop policy if exists "profile own read" on public.profiles;create policy "profile own read" on public.profiles for select to authenticated using((select auth.uid())=id);
drop policy if exists "wallet own read" on public.wallets;create policy "wallet own read" on public.wallets for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "ledger own read" on public.reward_ledger;create policy "ledger own read" on public.reward_ledger for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "sessions own read" on public.ad_sessions;create policy "sessions own read" on public.ad_sessions for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "withdrawals own read" on public.withdrawal_requests;create policy "withdrawals own read" on public.withdrawal_requests for select to authenticated using((select auth.uid())=user_id);
drop policy if exists "referrals own read" on public.referrals;create policy "referrals own read" on public.referrals for select to authenticated using((select auth.uid())=referrer_id or(select auth.uid())=referred_id);
drop policy if exists "catalog active read" on public.reward_catalog;create policy "catalog active read" on public.reward_catalog for select to authenticated using(active=true);
drop policy if exists "redemptions own read" on public.redemptions;create policy "redemptions own read" on public.redemptions for select to authenticated using((select auth.uid())=user_id);
grant select on public.profiles,public.wallets,public.reward_ledger,public.ad_sessions,public.withdrawal_requests,public.referrals,public.reward_catalog,public.redemptions to authenticated;grant usage on schema public to authenticated;
-- No client insert/update/delete policies on points, ledger, ad events or payouts. Server-side signed provider callbacks only.
-- Trigger functions are invoked by PostgreSQL triggers, not directly by client roles.
revoke all on function public.handle_new_user() from public, anon, authenticated;


-- Redeem-code inventory: codes are never directly readable through the Data API.
alter table public.redemptions add column if not exists delivered_code text;
create table if not exists public.reward_code_inventory (
 id uuid primary key default gen_random_uuid(),
 reward_id uuid not null references public.reward_catalog(id) on delete cascade,
 code_value text not null,
 claimed_by uuid references auth.users(id) on delete set null,
 claimed_at timestamptz,
 created_at timestamptz not null default now(),
 unique(reward_id,code_value)
);
alter table public.reward_code_inventory enable row level security;
revoke all on public.reward_code_inventory from anon, authenticated;
create or replace function public.admin_add_reward_code(p_reward_id uuid,p_code text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_code text := trim(coalesce(p_code,''));
begin
 if not public.is_current_user_admin() then raise exception 'Admin access required'; end if;
 if length(v_code)<4 or length(v_code)>160 then raise exception 'Code must be 4 to 160 characters'; end if;
 if not exists(select 1 from public.reward_catalog where id=p_reward_id and reward_type='redeem_code') then raise exception 'Select an existing redeem-code reward'; end if;
 insert into public.reward_code_inventory(reward_id,code_value) values(p_reward_id,v_code);
end;
$$;
revoke all on function public.admin_add_reward_code(uuid,text) from public, anon;
grant execute on function public.admin_add_reward_code(uuid,text) to authenticated;
create or replace function public.redeem_reward(p_reward_id uuid)
returns table(redemption_id uuid, delivered_code text, points_spent bigint)
language plpgsql security definer set search_path=''
as $$
declare v_user uuid := auth.uid(); v_reward public.reward_catalog%rowtype; v_code_row public.reward_code_inventory%rowtype; v_redemption uuid;
begin
 if v_user is null then raise exception 'Please sign in'; end if;
 select * into v_reward from public.reward_catalog where id=p_reward_id and active=true for share;
 if not found then raise exception 'Reward is unavailable'; end if;
 if v_reward.reward_type <> 'redeem_code' then raise exception 'Use the wallet withdrawal page for UPI rewards'; end if;
 select * into v_code_row from public.reward_code_inventory where reward_id=p_reward_id and claimed_by is null order by created_at for update skip locked limit 1;
 if not found then raise exception 'This reward is temporarily out of stock'; end if;
 update public.wallets set balance=balance-v_reward.points_cost,updated_at=now() where user_id=v_user and balance>=v_reward.points_cost;
 if not found then raise exception 'Insufficient points balance'; end if;
 update public.reward_code_inventory set claimed_by=v_user,claimed_at=now() where id=v_code_row.id;
 insert into public.redemptions(user_id,reward_id,points_spent,status,delivered_code) values(v_user,p_reward_id,v_reward.points_cost,'fulfilled',v_code_row.code_value) returning id into v_redemption;
 insert into public.reward_ledger(user_id,event_type,points,reference,description) values(v_user,'redeem',-v_reward.points_cost,'reward-redemption:'||v_redemption::text,'Redeemed reward: '||v_reward.title);
 return query select v_redemption,v_code_row.code_value,v_reward.points_cost;
end;
$$;
revoke all on function public.redeem_reward(uuid) from public, anon;
grant execute on function public.redeem_reward(uuid) to authenticated;


-- Referral attribution. Reward credit remains disabled until verified qualification and anti-abuse rules are live.
alter table public.profiles add column if not exists referral_code text;
create unique index if not exists profiles_referral_code_unique on public.profiles(referral_code) where referral_code is not null;
update public.profiles set referral_code=upper(substr(encode(gen_random_bytes(8),'hex'),1,10)) where referral_code is null;
create or replace function public.capture_new_user_referral()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_code text := upper(trim(coalesce(new.raw_user_meta_data->>'referral_code',''))); v_referrer uuid;
begin
 update public.profiles set referral_code=coalesce(referral_code,upper(substr(encode(gen_random_bytes(8),'hex'),1,10))) where id=new.id;
 if v_code<>'' then
  select id into v_referrer from public.profiles where referral_code=v_code and id<>new.id limit 1;
  if v_referrer is not null then
   insert into public.referrals(referrer_id,referred_id,status) values(v_referrer,new.id,'pending') on conflict(referred_id) do nothing;
  end if;
 end if;
 return new;
end;
$$;
revoke all on function public.capture_new_user_referral() from public,anon,authenticated;
drop trigger if exists on_auth_user_referral on auth.users;
create trigger on_auth_user_referral after insert on auth.users for each row execute function public.capture_new_user_referral();


-- Referral attribution and secure admin reward creation.
alter table public.profiles add column if not exists referral_code text;
create unique index if not exists profiles_referral_code_unique on public.profiles(referral_code) where referral_code is not null;
update public.profiles set referral_code=upper(substr(encode(gen_random_bytes(6),'hex'),1,10)) where referral_code is null;
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_code text; v_referral text := upper(trim(coalesce(new.raw_user_meta_data->>'referral_code','')));
begin
 loop
  v_code := upper(substr(encode(gen_random_bytes(6),'hex'),1,10));
  exit when not exists(select 1 from public.profiles where referral_code=v_code);
 end loop;
 insert into public.profiles(id,display_name,referral_code)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1)),v_code)
 on conflict(id) do nothing;
 insert into public.wallets(user_id) values(new.id) on conflict(user_id) do nothing;
 if v_referral<>'' then
  insert into public.referrals(referrer_id,referred_id,status)
  select p.id,new.id,'pending' from public.profiles p where p.referral_code=v_referral and p.id<>new.id
  on conflict(referred_id) do nothing;
 end if;
 return new;
end;
$$;
revoke all on function public.handle_new_user() from public,anon,authenticated;
drop trigger if exists on_auth_user_referral on auth.users;
create or replace function public.admin_create_reward(p_title text,p_description text,p_points_cost bigint,p_reward_type text,p_active boolean)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
 if not public.is_current_user_admin() then raise exception 'Admin access required'; end if;
 if length(trim(coalesce(p_title,'')))<2 or length(p_title)>80 then raise exception 'Reward title must be 2 to 80 characters'; end if;
 if p_points_cost is null or p_points_cost<1 then raise exception 'Points cost must be positive'; end if;
 if p_reward_type not in ('upi','redeem_code') then raise exception 'Invalid reward type'; end if;
 insert into public.reward_catalog(title,description,points_cost,reward_type,active)
 values(trim(p_title),nullif(trim(coalesce(p_description,'')),''),p_points_cost,p_reward_type,coalesce(p_active,false))
 returning id into v_id;
 return v_id;
end;
$$;
revoke all on function public.admin_create_reward(text,text,bigint,text,boolean) from public,anon;
grant execute on function public.admin_create_reward(text,text,bigint,text,boolean) to authenticated;


-- Admin dashboard read policies. These grant read-only access only after the
-- database-side role check; normal users continue to see only their own rows.
drop policy if exists "admin read all wallets" on public.wallets;
create policy "admin read all wallets" on public.wallets for select to authenticated using(public.is_current_user_admin());
drop policy if exists "admin read all withdrawals" on public.withdrawal_requests;
create policy "admin read all withdrawals" on public.withdrawal_requests for select to authenticated using(public.is_current_user_admin());
drop policy if exists "admin read all redemptions" on public.redemptions;
create policy "admin read all redemptions" on public.redemptions for select to authenticated using(public.is_current_user_admin());
drop policy if exists "admin read all referrals" on public.referrals;
create policy "admin read all referrals" on public.referrals for select to authenticated using(public.is_current_user_admin());
drop policy if exists "admin read all rewards" on public.reward_catalog;
create policy "admin read all rewards" on public.reward_catalog for select to authenticated using(public.is_current_user_admin());
