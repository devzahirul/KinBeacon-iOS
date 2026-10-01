-- =================================================================================================================
-- KinBeacon backend — everything lives in the `kinbeacon` schema so the Supabase project can be shared with other
-- apps (it shares one with NovaShop and FlowMoney) without touching their tables. Only `auth.users` is shared.
--
-- Security model
--   • Signed-in users only (`authenticated`); `anon` has no access at all.
--   • Row Level Security on every table: you see your own family, only parents change family settings, a child
--     device writes only its own member's rows.
--   • Multi-row invariants (create family, invite + pair a child, answer a request, delete account) are
--     SECURITY DEFINER functions with `search_path = ''`, so clients can't half-apply them.
-- =================================================================================================================

create schema if not exists kinbeacon;
revoke all on schema kinbeacon from public, anon;
grant usage on schema kinbeacon to authenticated, service_role;

-- -----------------------------------------------------------------------------------------------------------------
-- Tables
-- -----------------------------------------------------------------------------------------------------------------

create table kinbeacon.families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 60),
  created_by  uuid not null references auth.users (id) on delete cascade,
  created_at  timestamptz not null default now()
);

create table kinbeacon.members (
  id              uuid primary key default gen_random_uuid(),
  family_id       uuid not null references kinbeacon.families (id) on delete cascade,
  user_id         uuid unique references auth.users (id) on delete set null,  -- null until a child device pairs
  role            text not null check (role in ('parent', 'child')),
  name            text not null check (char_length(name) between 1 and 40),
  relationship    text check (char_length(relationship) <= 20),
  grade           int check (grade between 0 and 12),
  age             int check (age between 1 and 25),
  avatar_emoji    text not null default U&'\+01F642' check (char_length(avatar_emoji) <= 16),
  avatar_palette  int not null default 0 check (avatar_palette between 0 and 7),
  device_model    text check (char_length(device_model) <= 40),
  created_at      timestamptz not null default now()
);
create index members_family_idx on kinbeacon.members (family_id);

create table kinbeacon.places (
  id                     uuid primary key default gen_random_uuid(),
  family_id              uuid not null references kinbeacon.families (id) on delete cascade,
  name                   text not null check (char_length(name) between 1 and 60),
  kind                   text not null check (kind in ('home', 'school', 'park', 'other')),
  latitude               double precision not null check (latitude between -90 and 90),
  longitude              double precision not null check (longitude between -180 and 180),
  radius                 double precision not null default 150 check (radius between 100 and 2000),
  address                text not null default '' check (char_length(address) <= 120),
  notifies_on_arrival    boolean not null default true,
  notifies_on_departure  boolean not null default true,
  created_at             timestamptz not null default now()
);
create index places_family_idx on kinbeacon.places (family_id);

-- Latest known state of each member (one row per member, upserted by that member's device).
create table kinbeacon.member_status (
  member_id         uuid primary key references kinbeacon.members (id) on delete cascade,
  family_id         uuid not null references kinbeacon.families (id) on delete cascade,
  latitude          double precision check (latitude between -90 and 90),
  longitude         double precision check (longitude between -180 and 180),
  accuracy          double precision,
  speed             double precision,
  is_stationary     boolean not null default false,
  location_at       timestamptz,
  place_id          uuid references kinbeacon.places (id) on delete set null,
  battery_level     real check (battery_level between 0 and 1),
  battery_charging  boolean not null default false,
  permissions       jsonb not null default '{}'::jsonb,
  last_seen         timestamptz not null default now()
);
create index member_status_family_idx on kinbeacon.member_status (family_id);

create table kinbeacon.location_samples (
  id             bigint generated always as identity primary key,
  member_id      uuid not null references kinbeacon.members (id) on delete cascade,
  family_id      uuid not null references kinbeacon.families (id) on delete cascade,
  latitude       double precision not null check (latitude between -90 and 90),
  longitude      double precision not null check (longitude between -180 and 180),
  accuracy       double precision not null,
  speed          double precision,
  is_stationary  boolean not null default false,
  recorded_at    timestamptz not null
);
create index location_samples_member_time_idx on kinbeacon.location_samples (member_id, recorded_at desc);

-- One controls document per child. `config` is the app's ControlsConfiguration JSON; `revision` is server-owned.
create table kinbeacon.controls (
  member_id   uuid primary key references kinbeacon.members (id) on delete cascade,
  family_id   uuid not null references kinbeacon.families (id) on delete cascade,
  revision    int not null default 1,
  config      jsonb not null,
  updated_at  timestamptz not null default now()
);

create table kinbeacon.time_requests (
  id              uuid primary key,  -- client-generated: retries from the device outbox are idempotent
  family_id       uuid not null references kinbeacon.families (id) on delete cascade,
  member_id       uuid not null references kinbeacon.members (id) on delete cascade,
  minutes         int not null check (minutes in (15, 30, 60)),
  message         text check (char_length(message) <= 200),
  app_name        text check (char_length(app_name) <= 60),
  status          text not null default 'pending' check (status in ('pending', 'approved', 'denied', 'expired')),
  approved_until  timestamptz,
  created_at      timestamptz not null default now(),
  responded_at    timestamptz,
  responded_by    uuid references kinbeacon.members (id) on delete set null
);
create index time_requests_family_idx on kinbeacon.time_requests (family_id, created_at desc);

create table kinbeacon.check_ins (
  id          uuid primary key,
  family_id   uuid not null references kinbeacon.families (id) on delete cascade,
  member_id   uuid not null references kinbeacon.members (id) on delete cascade,
  kind        text not null check (kind in ('imOK', 'pickedUp', 'onMyWay', 'needHelp')),
  message     text check (char_length(message) <= 200),
  latitude    double precision,
  longitude   double precision,
  created_at  timestamptz not null default now()
);
create index check_ins_family_idx on kinbeacon.check_ins (family_id, created_at desc);

create table kinbeacon.alerts (
  id           uuid primary key,
  family_id    uuid not null references kinbeacon.families (id) on delete cascade,
  member_id    uuid not null references kinbeacon.members (id) on delete cascade,
  kind         text not null check (kind in ('locationPermissionOff', 'notificationsOff', 'deviceProtectionOff', 'sos', 'needHelp', 'lowBattery')),
  latitude     double precision,
  longitude    double precision,
  created_at   timestamptz not null default now(),
  resolved_at  timestamptz
);
create index alerts_open_idx on kinbeacon.alerts (family_id) where resolved_at is null;

-- Remote commands. The APNs push is only a doorbell carrying the id; the device reads the command itself over an
-- authenticated, RLS-protected connection, so a push payload can never carry an instruction on its own.
create table kinbeacon.commands (
  id            uuid primary key default gen_random_uuid(),
  family_id     uuid not null references kinbeacon.families (id) on delete cascade,
  target        uuid not null references kinbeacon.members (id) on delete cascade,
  action        jsonb not null,
  issued_by     uuid references kinbeacon.members (id) on delete set null,
  issued_at     timestamptz not null default now(),
  expires_at    timestamptz not null default now() + interval '1 hour',
  delivered_at  timestamptz
);
create index commands_pending_idx on kinbeacon.commands (target) where delivered_at is null;

create table kinbeacon.device_tokens (
  user_id     uuid not null references auth.users (id) on delete cascade,
  token       text not null check (char_length(token) between 32 and 200),
  environment text not null default 'production' check (environment in ('sandbox', 'production')),
  updated_at  timestamptz not null default now(),
  primary key (user_id, token)
);

-- Pairing codes are never readable by clients; only the functions below touch them.
create table kinbeacon.pairing_codes (
  code        text primary key check (code ~ '^[0-9]{6}$'),
  family_id   uuid not null references kinbeacon.families (id) on delete cascade,
  member_id   uuid not null references kinbeacon.members (id) on delete cascade,
  expires_at  timestamptz not null,
  used_at     timestamptz
);

create table kinbeacon.pairing_attempts (
  user_id       uuid not null references auth.users (id) on delete cascade,
  attempted_at  timestamptz not null default now()
);
create index pairing_attempts_user_idx on kinbeacon.pairing_attempts (user_id, attempted_at desc);

-- -----------------------------------------------------------------------------------------------------------------
-- Helpers (SECURITY DEFINER so policies can call them without recursing into members' own RLS)
-- -----------------------------------------------------------------------------------------------------------------

create or replace function kinbeacon.my_member_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select id from kinbeacon.members where user_id = auth.uid()
$$;

create or replace function kinbeacon.my_family_id()
returns uuid language sql stable security definer set search_path = '' as $$
  select family_id from kinbeacon.members where user_id = auth.uid()
$$;

create or replace function kinbeacon.is_parent_of(fid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from kinbeacon.members where user_id = auth.uid() and family_id = fid and role = 'parent')
$$;

-- -----------------------------------------------------------------------------------------------------------------
-- Row Level Security
-- -----------------------------------------------------------------------------------------------------------------

alter table kinbeacon.families         enable row level security;
alter table kinbeacon.members          enable row level security;
alter table kinbeacon.places           enable row level security;
alter table kinbeacon.member_status    enable row level security;
alter table kinbeacon.location_samples enable row level security;
alter table kinbeacon.controls         enable row level security;
alter table kinbeacon.time_requests    enable row level security;
alter table kinbeacon.check_ins        enable row level security;
alter table kinbeacon.alerts           enable row level security;
alter table kinbeacon.commands         enable row level security;
alter table kinbeacon.device_tokens    enable row level security;
alter table kinbeacon.pairing_codes    enable row level security;
alter table kinbeacon.pairing_attempts enable row level security;

create policy families_read   on kinbeacon.families for select to authenticated using (id = kinbeacon.my_family_id());
create policy families_rename on kinbeacon.families for update to authenticated
  using (kinbeacon.is_parent_of(id)) with check (kinbeacon.is_parent_of(id));

create policy members_read   on kinbeacon.members for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy members_update on kinbeacon.members for update to authenticated
  using (kinbeacon.is_parent_of(family_id) or user_id = auth.uid())
  with check (family_id = kinbeacon.my_family_id());
create policy members_delete on kinbeacon.members for delete to authenticated
  using (kinbeacon.is_parent_of(family_id) and role = 'child');

create policy places_read  on kinbeacon.places for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy places_write on kinbeacon.places for all to authenticated
  using (kinbeacon.is_parent_of(family_id)) with check (kinbeacon.is_parent_of(family_id));

create policy status_read  on kinbeacon.member_status for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy status_write on kinbeacon.member_status for insert to authenticated
  with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id());
create policy status_update on kinbeacon.member_status for update to authenticated
  using (member_id = kinbeacon.my_member_id()) with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id());

create policy samples_read  on kinbeacon.location_samples for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy samples_write on kinbeacon.location_samples for insert to authenticated
  with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id());

create policy controls_read  on kinbeacon.controls for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy controls_write on kinbeacon.controls for all to authenticated
  using (kinbeacon.is_parent_of(family_id)) with check (kinbeacon.is_parent_of(family_id));

create policy requests_read  on kinbeacon.time_requests for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy requests_write on kinbeacon.time_requests for insert to authenticated
  with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id() and status = 'pending');

create policy checkins_read  on kinbeacon.check_ins for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy checkins_write on kinbeacon.check_ins for insert to authenticated
  with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id());

create policy alerts_read    on kinbeacon.alerts for select to authenticated using (family_id = kinbeacon.my_family_id());
create policy alerts_write   on kinbeacon.alerts for insert to authenticated
  with check (member_id = kinbeacon.my_member_id() and family_id = kinbeacon.my_family_id());
create policy alerts_resolve on kinbeacon.alerts for update to authenticated
  using (kinbeacon.is_parent_of(family_id) or member_id = kinbeacon.my_member_id())
  with check (family_id = kinbeacon.my_family_id());

create policy commands_read on kinbeacon.commands for select to authenticated
  using (target = kinbeacon.my_member_id() or kinbeacon.is_parent_of(family_id));
create policy commands_send on kinbeacon.commands for insert to authenticated
  with check (kinbeacon.is_parent_of(family_id) and issued_by = kinbeacon.my_member_id()
              and exists (select 1 from kinbeacon.members m where m.id = target and m.family_id = commands.family_id));
create policy commands_ack on kinbeacon.commands for update to authenticated
  using (target = kinbeacon.my_member_id()) with check (target = kinbeacon.my_member_id());

create policy tokens_own on kinbeacon.device_tokens for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
-- pairing_codes / pairing_attempts: no policies → no direct client access.

grant select, insert, update, delete on all tables in schema kinbeacon to authenticated;
revoke all on kinbeacon.pairing_codes, kinbeacon.pairing_attempts from authenticated;
grant usage on all sequences in schema kinbeacon to authenticated;
grant all on all tables in schema kinbeacon to service_role;

-- -----------------------------------------------------------------------------------------------------------------
-- Triggers
-- -----------------------------------------------------------------------------------------------------------------

-- The server owns `revision`: every save bumps it, so devices can ignore stale documents.
create or replace function kinbeacon.bump_controls_revision()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    new.revision := old.revision + 1;
  end if;
  new.updated_at := now();
  return new;
end;
$$;
create trigger controls_revision before insert or update on kinbeacon.controls
  for each row execute function kinbeacon.bump_controls_revision();

-- Data minimisation: location history older than 30 days is deleted as new history arrives.
create or replace function kinbeacon.prune_location_history()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from kinbeacon.location_samples where recorded_at < now() - interval '30 days';
  return null;
end;
$$;
create trigger location_retention after insert on kinbeacon.location_samples
  for each statement execute function kinbeacon.prune_location_history();

-- -----------------------------------------------------------------------------------------------------------------
-- RPCs
-- -----------------------------------------------------------------------------------------------------------------

create or replace function kinbeacon.create_family(family_name text, parent_name text, relationship text default null,
                                                   avatar_emoji text default U&'\+01F642', avatar_palette int default 3)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  fid uuid;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if exists (select 1 from kinbeacon.members where user_id = uid) then
    raise exception 'already in a family' using errcode = '23505';
  end if;
  insert into kinbeacon.families (name, created_by) values (trim(family_name), uid) returning id into fid;
  insert into kinbeacon.members (family_id, user_id, role, name, relationship, avatar_emoji, avatar_palette)
  values (fid, uid, 'parent', trim(parent_name), nullif(trim(relationship), ''), avatar_emoji, avatar_palette);
  return fid;
end;
$$;

-- Parent adds a child: creates the member + default controls and a 6-digit, 10-minute, single-use pairing code.
create or replace function kinbeacon.create_child_invite(child_name text, age int default null, grade int default null,
                                                         avatar_emoji text default U&'\+01F642', avatar_palette int default 0,
                                                         controls jsonb default '{}'::jsonb)
returns table (code text, member_id uuid, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  fid uuid := kinbeacon.my_family_id();
  mid uuid;
  new_code text;
  expiry timestamptz := now() + interval '10 minutes';
begin
  if fid is null or not kinbeacon.is_parent_of(fid) then
    raise exception 'only parents can invite' using errcode = '42501';
  end if;
  insert into kinbeacon.members (family_id, role, name, age, grade, avatar_emoji, avatar_palette)
  values (fid, 'child', trim(child_name), age, grade, avatar_emoji, avatar_palette) returning id into mid;
  insert into kinbeacon.controls (member_id, family_id, config) values (mid, fid, controls);
  loop
    new_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from kinbeacon.pairing_codes p where p.code = new_code and p.used_at is null and p.expires_at > now());
  end loop;
  delete from kinbeacon.pairing_codes p where p.code = new_code;
  insert into kinbeacon.pairing_codes (code, family_id, member_id, expires_at) values (new_code, fid, mid, expiry);
  return query select new_code, mid, expiry;
end;
$$;

-- New code for an existing, not-yet-paired child (the old code is invalidated).
create or replace function kinbeacon.refresh_child_invite(child_member uuid)
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  fid uuid := kinbeacon.my_family_id();
  new_code text;
  expiry timestamptz := now() + interval '10 minutes';
begin
  if not exists (select 1 from kinbeacon.members m where m.id = child_member and m.family_id = fid and m.role = 'child')
     or not kinbeacon.is_parent_of(fid) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  delete from kinbeacon.pairing_codes p where p.member_id = child_member;
  loop
    new_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
    exit when not exists (select 1 from kinbeacon.pairing_codes p where p.code = new_code and p.used_at is null and p.expires_at > now());
  end loop;
  delete from kinbeacon.pairing_codes p where p.code = new_code;
  insert into kinbeacon.pairing_codes (code, family_id, member_id, expires_at) values (new_code, fid, child_member, expiry);
  return query select new_code, expiry;
end;
$$;

-- Child device redeems a code. Brute force is capped at 5 attempts per 10 minutes per account.
create or replace function kinbeacon.redeem_pairing_code(pairing_code text, device_model text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  invite kinbeacon.pairing_codes%rowtype;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  if (select count(*) from kinbeacon.pairing_attempts a where a.user_id = uid and a.attempted_at > now() - interval '10 minutes') >= 5 then
    raise exception 'too many attempts' using errcode = '54000';
  end if;
  insert into kinbeacon.pairing_attempts (user_id) values (uid);
  select * into invite from kinbeacon.pairing_codes p
   where p.code = pairing_code and p.used_at is null and p.expires_at > now() for update;
  if not found then raise exception 'invalid or expired code' using errcode = '22023'; end if;
  if exists (select 1 from kinbeacon.members m where m.user_id = uid) then
    raise exception 'device already paired' using errcode = '23505';
  end if;
  update kinbeacon.members m set user_id = uid, device_model = left(redeem_pairing_code.device_model, 40)
   where m.id = invite.member_id and m.user_id is null;
  if not found then raise exception 'child already paired' using errcode = '23505'; end if;
  update kinbeacon.pairing_codes p set used_at = now() where p.code = invite.code;
  delete from kinbeacon.pairing_attempts a where a.user_id = uid;
  return invite.member_id;
end;
$$;

-- Parent answers an extra-time request (validated state transition, server clock).
create or replace function kinbeacon.respond_to_request(request_id uuid, approve boolean)
returns kinbeacon.time_requests language plpgsql security definer set search_path = '' as $$
declare
  req kinbeacon.time_requests%rowtype;
begin
  select * into req from kinbeacon.time_requests r where r.id = request_id for update;
  if not found or not kinbeacon.is_parent_of(req.family_id) then
    raise exception 'not allowed' using errcode = '42501';
  end if;
  if req.status = 'pending' and req.created_at < now() - interval '30 minutes' then
    update kinbeacon.time_requests r set status = 'expired' where r.id = request_id returning * into req;
  elsif req.status = 'pending' then
    update kinbeacon.time_requests r
       set status = case when approve then 'approved' else 'denied' end,
           approved_until = case when approve then now() + make_interval(mins => req.minutes) end,
           responded_at = now(),
           responded_by = kinbeacon.my_member_id()
     where r.id = request_id returning * into req;
  end if;
  return req;
end;
$$;

-- App Store guideline 5.1.1(v): in-app account deletion. Deletes this user's KinBeacon data (and the whole family when
-- the last parent leaves). The shared auth login is kept because other apps in this project use it.
create or replace function kinbeacon.delete_my_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  uid uuid := auth.uid();
  me kinbeacon.members%rowtype;
begin
  if uid is null then raise exception 'not authenticated' using errcode = '28000'; end if;
  select * into me from kinbeacon.members where user_id = uid;
  if found then
    if me.role = 'parent' and not exists (
      select 1 from kinbeacon.members m where m.family_id = me.family_id and m.role = 'parent' and m.id <> me.id) then
      delete from kinbeacon.families f where f.id = me.family_id;  -- cascades to every family row
    else
      delete from kinbeacon.members m where m.id = me.id;
    end if;
  end if;
  delete from kinbeacon.device_tokens t where t.user_id = uid;
  delete from kinbeacon.pairing_attempts a where a.user_id = uid;
end;
$$;

revoke all on function kinbeacon.create_family, kinbeacon.create_child_invite, kinbeacon.refresh_child_invite,
  kinbeacon.redeem_pairing_code, kinbeacon.respond_to_request, kinbeacon.delete_my_account,
  kinbeacon.my_member_id, kinbeacon.my_family_id, kinbeacon.is_parent_of from public, anon;
grant execute on function kinbeacon.create_family, kinbeacon.create_child_invite, kinbeacon.refresh_child_invite,
  kinbeacon.redeem_pairing_code, kinbeacon.respond_to_request, kinbeacon.delete_my_account,
  kinbeacon.my_member_id, kinbeacon.my_family_id, kinbeacon.is_parent_of to authenticated;

-- -----------------------------------------------------------------------------------------------------------------
-- Realtime: family screens and child devices subscribe to these (RLS applies to every change event).
-- -----------------------------------------------------------------------------------------------------------------
alter publication supabase_realtime add table
  kinbeacon.members, kinbeacon.places, kinbeacon.member_status, kinbeacon.controls,
  kinbeacon.time_requests, kinbeacon.check_ins, kinbeacon.alerts, kinbeacon.commands;
