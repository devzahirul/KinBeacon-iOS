-- pgTAP tests for KinBeacon's Row Level Security and RPCs. Everything runs in one transaction and is rolled back,
-- so it is safe to run against the hosted project (SQL Editor) as well as locally (`supabase test db`).
begin;
create extension if not exists pgtap with schema extensions;
create temp table tap (line text);
grant all on tap to authenticated;

select plan(19);

insert into auth.users (id, email) values
  ('aaaaaaaa-0000-4000-8000-0000000000a1', 'kb-parent@test.invalid'),
  ('aaaaaaaa-0000-4000-8000-0000000000a2', 'kb-child@test.invalid'),
  ('aaaaaaaa-0000-4000-8000-0000000000a3', 'kb-stranger@test.invalid');

-- ---------- Parent ----------
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-0000000000a1","role":"authenticated"}', true);

insert into tap select ok(kinbeacon.create_family('The Testers', 'Sarah', 'Mom') is not null, 'parent creates a family');
insert into tap select throws_ok($$ select kinbeacon.create_family('Again', 'Sarah') $$, '23505', null, 'one family per account');
create temp table invite as select * from kinbeacon.create_child_invite('Emma', 10, 4, '👧', 0, '{"modes":[]}');
insert into tap select ok((select code from invite) ~ '^[0-9]{6}$', 'invite returns a 6-digit code');
insert into tap select is((select count(*)::int from kinbeacon.members), 2, 'parent sees both family members');
insert into tap select is((select revision from kinbeacon.controls), 1, 'default controls created at revision 1');
update kinbeacon.controls set config = '{"modes":[1]}', revision = 99;
insert into tap select is((select revision from kinbeacon.controls), 2, 'server owns the revision (client value ignored)');
insert into tap select throws_ok($$ select * from kinbeacon.pairing_codes $$, '42501', null, 'pairing codes are not readable');

-- ---------- Stranger ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-0000000000a3","role":"authenticated"}', true);
insert into tap select is((select count(*)::int from kinbeacon.members), 0, 'strangers see no members');
insert into tap select is((select count(*)::int from kinbeacon.controls), 0, 'strangers see no controls');
insert into tap select throws_ok($$ select kinbeacon.redeem_pairing_code('000000') $$, '22023', null, 'wrong code is rejected');

-- ---------- Child device ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
insert into tap select ok(kinbeacon.redeem_pairing_code((select code from invite), 'iPhone') is not null, 'child redeems the code');
insert into tap select throws_ok(format('select kinbeacon.redeem_pairing_code(%L)', (select code from invite)), '22023', null, 'codes are single-use');
insert into kinbeacon.member_status (member_id, family_id, latitude, longitude, accuracy)
  values (kinbeacon.my_member_id(), kinbeacon.my_family_id(), 37.76, -122.42, 15);
insert into tap select is((select count(*)::int from kinbeacon.member_status), 1, 'child reports its own status');
update kinbeacon.controls set config = '{"hacked":true}';
insert into tap select is((select config->>'hacked' from kinbeacon.controls), null, 'child update of controls has no effect');
insert into kinbeacon.time_requests (id, family_id, member_id, minutes)
  values ('bbbbbbbb-0000-4000-8000-0000000000b1', kinbeacon.my_family_id(), kinbeacon.my_member_id(), 15);
insert into tap select throws_ok(
  $$ insert into kinbeacon.time_requests (id, family_id, member_id, minutes, status)
     values (gen_random_uuid(), kinbeacon.my_family_id(), kinbeacon.my_member_id(), 15, 'approved') $$,
  '42501', null, 'child cannot self-approve');
insert into tap select throws_ok(
  $$ select kinbeacon.respond_to_request('bbbbbbbb-0000-4000-8000-0000000000b1', true) $$, '42501', null, 'child cannot answer requests');

-- ---------- Parent answers ----------
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
insert into tap select is((kinbeacon.respond_to_request('bbbbbbbb-0000-4000-8000-0000000000b1', true)).status, 'approved', 'parent approves');
insert into tap select is((select count(*)::int from kinbeacon.member_status), 1, 'parent sees the child status');
select kinbeacon.delete_my_account();
insert into tap select is((select count(*)::int from kinbeacon.families), 0, 'last parent deleting the account removes the family');

insert into tap select * from finish();
reset role;
-- The editor shows this result; the open transaction is discarded when the session ends (run `rollback;` locally).
select line from tap;
