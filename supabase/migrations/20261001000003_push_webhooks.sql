-- Push fan-out: Postgres → Edge Function `push` via pg_net. Apply AFTER deploying supabase/functions/push and setting
-- its secrets (see supabase/README.md). Replace <PROJECT_REF> and <WEBHOOK_SECRET> (same value as the function secret).
create extension if not exists pg_net with schema extensions;

create or replace function kinbeacon.notify_push()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform net.http_post(
    url := 'https://<PROJECT_REF>.supabase.co/functions/v1/push',
    headers := jsonb_build_object('content-type', 'application/json', 'x-webhook-secret', '<WEBHOOK_SECRET>'),
    body := jsonb_build_object('type', tg_op, 'table', tg_table_name, 'schema', tg_table_schema,
                               'record', to_jsonb(new), 'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) end)
  );
  return new;
end;
$$;

create trigger push_commands      after insert on kinbeacon.commands      for each row execute function kinbeacon.notify_push();
create trigger push_time_requests after insert or update of status on kinbeacon.time_requests for each row execute function kinbeacon.notify_push();
create trigger push_check_ins     after insert on kinbeacon.check_ins     for each row execute function kinbeacon.notify_push();
create trigger push_alerts        after insert on kinbeacon.alerts        for each row execute function kinbeacon.notify_push();
