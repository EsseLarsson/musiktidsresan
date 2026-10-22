-- Run once in Supabase SQL Editor, then seed.sql. Enable Anonymous Sign-ins.
create table public.songs (id integer primary key, title text not null, artist text not null, year integer not null check(year between 1926 and 2026), source text not null);
create table public.rooms (code text primary key, host_id uuid not null references auth.users, state jsonb not null, updated_at timestamptz not null default now());
create table public.members (code text references public.rooms on delete cascade, user_id uuid references auth.users, primary key(code,user_id));
create table public.room_secrets (code text primary key references public.rooms on delete cascade, deck integer[] not null, current_id integer);
alter table public.songs enable row level security;
alter table public.rooms enable row level security;
alter table public.members enable row level security;
alter table public.room_secrets enable row level security;
create policy song_read on public.songs for select to authenticated using(true);
create policy member_read on public.members for select to authenticated using(user_id=auth.uid());
create policy room_read on public.rooms for select to authenticated using(exists(select 1 from public.members m where m.code=rooms.code and m.user_id=auth.uid()));
revoke all on public.rooms,public.members,public.room_secrets,public.songs from anon,authenticated;
grant select on public.rooms,public.members,public.songs to authenticated;
alter publication supabase_realtime add table public.rooms;

create or replace function public.create_room(p_mode text, p_target integer default 5) returns text
language plpgsql security definer set search_path=public as $$
declare c text;
begin
 if auth.uid() is null then raise exception 'Logga in först'; end if;
 if p_mode is null or p_target is null or p_mode not in ('classic','all') or p_target not between 1 and 20 then raise exception 'Ogiltiga regler'; end if;
 loop
  c:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  begin
   insert into rooms values(c,auth.uid(),jsonb_build_object('phase','lobby','mode',p_mode,'target',p_target,'players','[]'::jsonb,'round',0,'turn',0,'answers','{}'::jsonb),now());
   exit;
  exception when unique_violation then null;
  end;
 end loop;
 insert into members values(c,auth.uid());
 return c;
end $$;

create or replace function public.join_room(p_code text,p_name text,p_observer boolean default false) returns text
language plpgsql security definer set search_path=public as $$
declare r rooms; n text:=trim(coalesce(p_name,''));
begin
 if auth.uid() is null then raise exception 'Logga in först'; end if;
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found then raise exception 'Rummet finns inte'; end if;
 if r.updated_at < now()-interval '24 hours' then raise exception 'Rummet har gått ut';end if;
 if not p_observer and not exists(select 1 from jsonb_array_elements(r.state->'players') p where p->>'id'=auth.uid()::text) then
  if r.state->>'phase'<>'lobby' then raise exception 'Spelet har redan börjat. Anslut som TV.'; end if;
  if length(n) not between 1 and 24 then raise exception 'Namn måste vara 1–24 tecken'; end if;
  if jsonb_array_length(r.state->'players')>=12 then raise exception 'Rummet är fullt'; end if;
  r.state:=jsonb_set(r.state,'{players}',(r.state->'players')||jsonb_build_array(jsonb_build_object('id',auth.uid(),'name',n,'score',0,'timeline','[]'::jsonb)));
  update rooms set state=r.state,updated_at=now() where code=r.code;
 end if;
 insert into members values(r.code,auth.uid()) on conflict do nothing;
 return r.code;
end $$;

create or replace function public.host_action(p_code text,p_action text) returns void
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
  if coalesce(array_length(d,1),0)=0 or exists(select 1 from jsonb_array_elements(s->'players') p where (p->>'score')::int >= (s->>'target')::int) then
   s:=s||jsonb_build_object('phase','finished');
  else
   sid:=d[1];d:=d[2:];update room_secrets set deck=d,current_id=sid where code=p_code;
   s:=(s-'current')||jsonb_build_object('phase','guess','round',(s->>'round')::int+1,'turn',(s->>'turn')::int+1,'answers','{}'::jsonb);
  end if;
 else raise exception 'Åtgärden gäller inte i denna fas'; end if;
 update rooms set state=s,updated_at=now() where code=p_code;
end $$;

create or replace function public.submit_guess(p_code text,p_round integer,p_position integer) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms; p jsonb; s jsonb; y integer; n integer; ok boolean; idx integer;
begin
 select * into r from rooms where code=p_code for update; s:=r.state;
 if not found or p_round is null or s->>'phase'<>'guess' or (s->>'round')::int<>p_round then raise exception 'Rundan är stängd';end if;
 select value into p from jsonb_array_elements(s->'players') where value->>'id'=auth.uid()::text;
 if p is null then raise exception 'Du är inte spelare';end if;
 if s->'answers' ? auth.uid()::text then raise exception 'Svaret är redan låst';end if;
 idx:=(s->>'turn')::int % jsonb_array_length(s->'players');
 if s->>'mode'='classic' and s->'players'->idx->>'id'<>auth.uid()::text then raise exception 'Vänta på din tur';end if;
 n:=jsonb_array_length(p->'timeline');
 if p_position is null or p_position<0 or p_position>n then raise exception 'Ogiltig placering';end if;
 select t.year into y from songs t join room_secrets z on z.current_id=t.id where z.code=p_code;
 ok:=(p_position=0 or (p->'timeline'->(p_position-1)->>'year')::int<=y) and (p_position=n or y<=(p->'timeline'->p_position->>'year')::int);
 -- Do not publish correctness until host reveals. Store only position publicly.
 update rooms set state=jsonb_set(s,array['answers',auth.uid()::text],jsonb_build_object('position',p_position)),updated_at=now() where code=p_code;
end $$;

-- Recompute correctness server-side at reveal, via trigger before room update.
create or replace function public.score_answers() returns trigger language plpgsql security definer set search_path=public as $$
declare p jsonb; a jsonb; pos integer; y integer; n integer; ok boolean; ps jsonb:='[]'::jsonb;
begin
 if old.state->>'phase'='guess' and new.state->>'phase'='reveal' then
  y:=(new.state->'current'->>'year')::int;
  for p in select value from jsonb_array_elements(old.state->'players') loop
   a:=old.state->'answers'->(p->>'id');ok:=false;
   if a is not null then
    pos:=(a->>'position')::int;n:=jsonb_array_length(p->'timeline');
    ok:=(pos=0 or (p->'timeline'->(pos-1)->>'year')::int<=y) and (pos=n or y<=(p->'timeline'->pos->>'year')::int);
    new.state:=jsonb_set(new.state,array['answers',p->>'id','correct'],to_jsonb(ok));
   end if;
   if ok then
    select jsonb_agg(v order by (v->>'year')::int,v->>'title') into a from jsonb_array_elements((p->'timeline')||jsonb_build_array(new.state->'current')) v;
    p:=p||jsonb_build_object('timeline',a,'score',(p->>'score')::int+1);
   end if;
   ps:=ps||jsonb_build_array(p);
  end loop;
  new.state:=jsonb_set(new.state,'{players}',ps);
 end if;
 return new;
end $$;
create trigger score_answers before update on public.rooms for each row execute function public.score_answers();

create or replace function public.music_card(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if not exists(select 1 from rooms where code=p_code and host_id=auth.uid()) then raise exception 'Bara spelledaren';end if;
 select to_jsonb(t) into result from songs t join room_secrets z on z.current_id=t.id where z.code=p_code;
 return result;
end $$;
revoke execute on function public.create_room(text,integer),public.join_room(text,text,boolean),public.host_action(text,text),public.submit_guess(text,integer,integer),public.music_card(text),public.score_answers() from public,anon;
grant execute on function public.create_room(text,integer),public.join_room(text,text,boolean),public.host_action(text,text),public.submit_guess(text,integer,integer),public.music_card(text) to authenticated;
-- Maintenance (SQL Editor): delete from public.rooms where updated_at < now()-interval '24 hours';
