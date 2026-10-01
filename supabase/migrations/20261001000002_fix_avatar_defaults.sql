-- Fix: the original migration was pasted through a non-UTF-8 clipboard, which corrupted the '🙂' avatar defaults.
-- Defaults are now written as an ASCII-safe Unicode escape (U&'\+01F642'), immune to copy/paste encoding.
alter table kinbeacon.members alter column avatar_emoji set default U&'\+01F642';
update kinbeacon.members set avatar_emoji = U&'\+01F642' where avatar_emoji ~ '[\u00C0-\u00FF]';

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
