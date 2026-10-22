begin;
create or replace function public.host_action_core(p_code text,p_action text) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms; d integer[]; sid integer; song jsonb; ps jsonb:='[]'; player_item jsonb; s jsonb;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or r.host_id<>auth.uid() then raise exception 'Bara spelledaren kan göra detta';end if;
 s:=r.state;
 if p_action='start' and s->>'phase'='lobby' then
  if jsonb_array_length(s->'players')<1 then raise exception 'Minst en spelare behövs';end if;
  select array_agg(id order by random()) into d from songs;
  if coalesce(array_length(d,1),0)<jsonb_array_length(s->'players')+2 then raise exception 'Låtbanken saknas';end if;
  for player_item in select value from jsonb_array_elements(s->'players') loop
   select to_jsonb(t) into song from songs t where id=d[1]; d:=d[2:];
   ps:=ps||jsonb_build_array(jsonb_set(player_item,'{timeline}',jsonb_build_array(song)));
  end loop;
  sid:=d[1]; d:=d[2:];
  insert into room_secrets values(p_code,d,sid) on conflict(code) do update set deck=excluded.deck,current_id=excluded.current_id;
  s:=s||jsonb_build_object('players',ps,'phase','guess','round',1,'answers','{}'::jsonb);
 elsif p_action='reveal' and s->>'phase'='guess' then
  select to_jsonb(t) into song from songs t join room_secrets z on z.current_id=t.id where z.code=p_code;
  -- score_answers trigger computes correctness and scores atomically.
  s:=s||jsonb_build_object('phase','reveal','current',song);
 elsif p_action='next' and s->>'phase'='reveal' then
  select deck into d from room_secrets where code=p_code;
  if coalesce(array_length(d,1),0)=0 or exists(select 1 from jsonb_array_elements(s->'players') p where not coalesce((p->>'removed')::boolean,false) and (p->>'score')::int >= (s->>'target')::int) then
   s:=s||jsonb_build_object('phase','finished');
  else
   sid:=d[1];d:=d[2:];update room_secrets set deck=d,current_id=sid where code=p_code;
   s:=(s-'current')||jsonb_build_object('phase','guess','round',(s->>'round')::int+1,'turn',(s->>'turn')::int+1,'answers','{}'::jsonb);
  end if;
 else raise exception 'Åtgärden gäller inte i denna fas'; end if;
 update rooms set state=s,updated_at=now() where code=p_code;
end $$;


-- Apply after schema.sql. Safe to re-run; no existing games are deleted here.
alter table public.members add column if not exists last_seen_at timestamptz;
alter table public.members add column if not exists removed boolean not null default false;
create table if not exists public.game_users (
 user_id uuid primary key references auth.users(id) on delete cascade,
 last_seen_at timestamptz not null default now()
);
alter table public.game_users enable row level security;
revoke all on public.game_users from anon,authenticated;
insert into public.game_users(user_id) select user_id from public.members union select host_id from public.rooms on conflict do nothing;

-- Register only identities used by this game. Do not clean unrelated accounts.
create or replace function public.register_game_user() returns trigger
language plpgsql security definer set search_path=public as $$
begin insert into game_users(user_id) values(new.user_id) on conflict do nothing; return new; end $$;
drop trigger if exists register_game_user on public.members;
create trigger register_game_user after insert on public.members for each row execute function public.register_game_user();

create or replace function public.room_heartbeat(p_code text) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du har inte tillgång till rummet';end if;
 if r.state->>'phase'='closed' or r.updated_at < now()-interval '24 hours' then raise exception 'Rummet är avslutat eller har gått ut';end if;
 update members set last_seen_at=now() where code=p_code and user_id=auth.uid();
 insert into game_users values(auth.uid(),now()) on conflict(user_id) do update set last_seen_at=now();
 -- Spectators and completed games cannot keep abandoned rooms alive forever.
 if r.state->>'phase'<>'finished' and (r.host_id=auth.uid() or exists(select 1 from jsonb_array_elements(r.state->'players') p where p->>'id'=auth.uid()::text and not coalesce((p->>'removed')::boolean,false))) then
  update rooms set updated_at=now() where code=p_code;
 end if;
end $$;

create or replace function public.room_presence(p_code text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du har inte tillgång till rummet';end if;
 select coalesce(jsonb_object_agg(user_id::text,coalesce(last_seen_at>now()-interval '90 seconds',false)), '{}'::jsonb) into result from members where code=p_code and not removed;
 return result;
end $$;

create or replace function public.room_lifecycle(p_code text,p_action text,p_player uuid default null) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms; s jsonb; roster jsonb; target_id uuid; idx integer; count_players integer;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null then raise exception 'Rummet finns inte';end if;
 if not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du har inte tillgång till rummet';end if;
 s:=r.state;
 if s->>'phase'='closed' then return;end if;
 if p_action='close' or (p_action='leave' and r.host_id=auth.uid()) then
  if r.host_id<>auth.uid() then raise exception 'Bara spelledaren kan avsluta';end if;
  s:=s||jsonb_build_object('phase','closed','closed_at',now());
 elsif p_action in ('remove','leave') then
  if p_action='remove' and r.host_id<>auth.uid() then raise exception 'Bara spelledaren kan ta bort spelare';end if;
  target_id:=case when p_action='leave' then auth.uid() else p_player end;
  if target_id is null or target_id=r.host_id then raise exception 'Spelledaren kan avsluta rummet i stället';end if;
  if not exists(select 1 from jsonb_array_elements(s->'players') p where p->>'id'=target_id::text) then raise exception 'Spelaren finns inte';end if;
  select jsonb_agg(case when p->>'id'=target_id::text then p||'{"removed":true}'::jsonb else p end order by ordinality) into roster from jsonb_array_elements(s->'players') with ordinality a(p,ordinality);
  s:=jsonb_set(s,'{players}',roster);
  s:=jsonb_set(s,'{answers}',coalesce(s->'answers','{}'::jsonb)-target_id::text);
  update members set removed=true,last_seen_at=null where code=p_code and user_id=target_id;
  count_players:=jsonb_array_length(roster);
  if not exists(select 1 from jsonb_array_elements(roster) p where not coalesce((p->>'removed')::boolean,false)) then
   s:=s||jsonb_build_object('phase','closed','closed_at',now());
  elsif s->>'mode'='classic' then
   idx:=(s->>'turn')::int;
   while coalesce((roster->(idx % count_players)->>'removed')::boolean,false) loop idx:=idx+1;end loop;
   s:=jsonb_set(s,'{turn}',to_jsonb(idx));
  end if;
 else raise exception 'Ogiltig åtgärd';end if;
 update rooms set state=s,updated_at=now() where code=p_code;
end $$;

-- Membership policy also excludes explicitly removed players.
drop policy if exists room_read on public.rooms;
create policy room_read on public.rooms for select to authenticated using(exists(select 1 from public.members m where m.code=rooms.code and m.user_id=auth.uid() and not m.removed));

-- Guard all old RPCs too, so cached older frontends cannot bypass expiry/removal.
do $$begin
 if to_regprocedure('public.join_room_core(text,text,boolean)') is null then alter function public.join_room(text,text,boolean) rename to join_room_core;end if;
 if to_regprocedure('public.submit_guess_core(text,integer,integer)') is null then alter function public.submit_guess(text,integer,integer) rename to submit_guess_core;end if;
end $$;
create or replace function public.join_room(p_code text,p_name text,p_observer boolean default false) returns text
language plpgsql security definer set search_path=public as $$
declare r rooms; c text;
begin
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or r.state->>'phase'='closed' then raise exception 'Rummet är avslutat eller finns inte';end if;
 if exists(select 1 from members where code=r.code and user_id=auth.uid() and removed) then raise exception 'Du har lämnat eller tagits bort från rummet';end if;
 c:=join_room_core(p_code,p_name,p_observer);perform room_heartbeat(c);return c;
end $$;
create or replace function public.host_action(p_code text,p_action text) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms; ps jsonb; idx integer; n integer;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or r.host_id<>auth.uid() then raise exception 'Bara spelledaren';end if;
 if r.state->>'phase'='closed' or r.updated_at<now()-interval '24 hours' then raise exception 'Rummet är avslutat eller har gått ut';end if;
 if p_action='start' then
  select coalesce(jsonb_agg(p),'[]'::jsonb) into ps from jsonb_array_elements(r.state->'players') p where not coalesce((p->>'removed')::boolean,false);
  update rooms set state=jsonb_set(state,'{players}',ps) where code=p_code;
 end if;
 perform host_action_core(p_code,p_action);
 select * into r from rooms where code=p_code;
 if p_action='next' and r.state->>'phase'='guess' and r.state->>'mode'='classic' then
  ps:=r.state->'players';n:=jsonb_array_length(ps);idx:=(r.state->>'turn')::int;
  while coalesce((ps->(idx % n)->>'removed')::boolean,false) loop idx:=idx+1;end loop;
  update rooms set state=jsonb_set(state,'{turn}',to_jsonb(idx)) where code=p_code;
 end if;
end $$;
create or replace function public.submit_guess(p_code text,p_round integer,p_position integer) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where code=p_code for update;
 if not found or r.updated_at<now()-interval '24 hours' or not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Rummet har gått ut eller du har lämnat';end if;
 perform submit_guess_core(p_code,p_round,p_position);
end $$;

create or replace function public.cleanup_game_data() returns jsonb
language plpgsql security definer set search_path=public as $$
declare nr integer; nu integer;
begin
 delete from rooms where updated_at<now()-interval '24 hours';get diagnostics nr=row_count;
 delete from auth.users u using game_users g where u.id=g.user_id and u.is_anonymous is true
  and g.last_seen_at<now()-interval '7 days'
  and greatest(u.created_at,coalesce(u.last_sign_in_at,u.created_at))<now()-interval '7 days'
  and not exists(select 1 from members where user_id=u.id)
  and not exists(select 1 from rooms where host_id=u.id);
 get diagnostics nu=row_count;
 return jsonb_build_object('deleted_rooms',nr,'deleted_anonymous_users',nu);
end $$;
revoke execute on function public.register_game_user(),public.host_action_core(text,text),public.join_room_core(text,text,boolean),public.submit_guess_core(text,integer,integer),public.cleanup_game_data() from public,anon,authenticated;
revoke execute on function public.room_heartbeat(text),public.room_presence(text),public.room_lifecycle(text,text,uuid),public.join_room(text,text,boolean),public.host_action(text,text),public.submit_guess(text,integer,integer) from public,anon;
grant execute on function public.room_heartbeat(text),public.room_presence(text),public.room_lifecycle(text,text,uuid),public.join_room(text,text,boolean),public.host_action(text,text),public.submit_guess(text,integer,integer) to authenticated;
commit;


