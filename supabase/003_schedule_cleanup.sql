-- Run in Supabase SQL Editor AFTER migrations/002_room_lifecycle.sql.
-- Schedule only; no room/user deletion is performed immediately.
create extension if not exists pg_cron;
select cron.schedule('musiktidsresan-cleanup','17 * * * *','select public.cleanup_game_data();');
-- Inspect activation:
select jobid,jobname,schedule,active from cron.job where jobname='musiktidsresan-cleanup';
