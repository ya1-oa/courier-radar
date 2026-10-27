create extension if not exists pgcrypto;
create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(), driver_id text not null, source text not null default 'uber_eats',
  captured_at timestamptz not null default now(), payout numeric(8,2), miles numeric(7,2), eta_minutes integer,
  merchant text, is_shop boolean not null default false, item_count integer, parser_confidence numeric(4,2),
  raw_text text, lat double precision, lng double precision, zone text,
  state text not null default 'observed' check (state in ('observed','accepted','completed','rejected'))
);
create index if not exists offers_driver_time_idx on public.offers(driver_id,captured_at desc);
create index if not exists offers_zone_time_idx on public.offers(driver_id,zone,captured_at desc);
create table if not exists public.presence (
  id uuid primary key default gen_random_uuid(), driver_id text not null, captured_at timestamptz not null default now(),
  lat double precision, lng double precision, zone text, event text not null default 'heartbeat'
);
create index if not exists presence_driver_time_idx on public.presence(driver_id,captured_at desc);
alter table public.offers enable row level security;
alter table public.presence enable row level security;
alter table public.offers add column if not exists vehicle text default 'ebike';
alter table public.offers add column if not exists time_block text;
alter table public.offers add column if not exists market_cell text;
alter table public.presence add column if not exists vehicle text default 'ebike';
alter table public.presence add column if not exists market_cell text;
create index if not exists offers_market_cell_time_idx on public.offers(market_cell,captured_at desc);
create index if not exists offers_vehicle_block_idx on public.offers(vehicle,time_block,captured_at desc);
create index if not exists presence_market_cell_time_idx on public.presence(market_cell,captured_at desc);
-- Post-shift reviews: one row per LA workday (04:00 cutoff). adjustments holds that day's
-- bounded zone|block offer-rate nudges; the planner uses the product of the last 30 days.
create table if not exists public.daily_reviews (
  driver_id text not null, day date not null, tier text, score integer,
  metrics jsonb not null default '{}'::jsonb, review jsonb not null default '{}'::jsonb,
  sessions jsonb not null default '{}'::jsonb, ai jsonb, adjustments jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key (driver_id, day)
);
-- Server (secret key) access only, like every other Radar table: RLS on, no client policies.
alter table public.daily_reviews enable row level security;
