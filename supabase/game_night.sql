alter table public.songs add column if not exists spotify_url text;
create table if not exists public.room_song_links(code text references public.rooms on delete cascade,song_id int references public.songs,url text not null,primary key(code,song_id));
create table if not exists public.song_reports(id uuid primary key default gen_random_uuid(),song_id int references public.songs,reporter uuid references auth.users on delete set null,note text not null,proposed_url text,created_at timestamptz default now());
create index if not exists song_reports_reporter_date on public.song_reports(reporter,created_at);
create table if not exists public.room_song_history(code text references public.rooms on delete cascade,song_id int references public.songs,primary key(code,song_id));
create table if not exists public.room_backup(code text primary key,user_id uuid not null,foreign key(code,user_id) references public.members(code,user_id) on update cascade on delete cascade);
alter table public.room_song_links enable row level security;
alter table public.song_reports enable row level security;
alter table public.room_song_history enable row level security;
alter table public.room_backup enable row level security;
revoke all on public.room_song_links,public.song_reports,public.room_song_history,public.room_backup from public,anon,authenticated;

create or replace function public.game_night_tools(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r rooms; b uuid; seen timestamptz;
begin
 select * into r from rooms where code=p_code;
 if not found or auth.uid() is null or not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du tillhör inte rummet';end if;
 select user_id into b from room_backup where code=p_code;
 select last_seen_at into seen from members where code=p_code and user_id=r.host_id;
 return jsonb_build_object('backup',b,'can_claim',b=auth.uid() and coalesce(seen<now()-interval '2 minutes',true),'used_songs',(select count(*) from room_song_history where code=p_code));
end $$;
create or replace function public.change_host(p_code text,p_player uuid,p_backup boolean default false) returns void language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or r.host_id<>auth.uid() or r.state->>'phase'='closed' or r.updated_at<now()-interval '24 hours' then raise exception 'Bara spelledaren i ett aktivt rum kan överlämna';end if;
 if p_player is null or p_player=r.host_id or not exists(select 1 from members m,jsonb_array_elements(r.state->'players') p where m.code=p_code and m.user_id=p_player and not m.removed and p->>'id'=p_player::text and not coalesce((p->>'removed')::boolean,false) and m.last_seen_at>now()-interval '90 seconds') then raise exception 'Välj en ansluten spelare';end if;
 if p_backup then insert into room_backup values(p_code,p_player) on conflict(code) do update set user_id=excluded.user_id;
 else update rooms set host_id=p_player,updated_at=now() where code=p_code;delete from room_backup where code=p_code;end if;
end $$;
create or replace function public.claim_host(p_code text) returns void language plpgsql security definer set search_path=public as $$
declare r rooms; t jsonb;
begin
 select * into r from rooms where code=p_code for update;t:=game_night_tools(p_code);
 if r.state->>'phase'='closed' or r.updated_at<now()-interval '24 hours' or not coalesce((t->>'can_claim')::boolean,false) then raise exception 'Endast utsedd reserv får ta över efter två minuters avbrott';end if;
 update rooms set host_id=auth.uid(),updated_at=now() where code=p_code;delete from room_backup where code=p_code;
end $$;
create or replace function public.music_card(p_code text) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
 if auth.uid() is null or not exists(select 1 from rooms where code=p_code and host_id=auth.uid() and state->>'phase'='guess') then raise exception 'Bara spelledaren under en pågående runda';end if;
 select to_jsonb(t)||jsonb_build_object('spotify_url',coalesce(l.url,t.spotify_url),'link_status',case when l.url is not null then 'room' when t.spotify_url is not null then 'catalog' else 'search' end) into result from songs t join room_secrets z on z.current_id=t.id left join room_song_links l on l.code=p_code and l.song_id=t.id where z.code=p_code;return result;
end $$;
create or replace function public.save_room_song_link(p_code text,p_song int,p_url text) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not exists(select 1 from rooms r join room_secrets s using(code) where r.code=p_code and r.host_id=auth.uid() and r.state->>'phase'='guess' and s.current_id=p_song) then raise exception 'Bara spelledaren kan välja länk för aktuell låt';end if;
 if p_url is null or p_url !~ '^https://open[.]spotify[.]com/track/[A-Za-z0-9]{22}$' then raise exception 'Klistra in en Spotify-länk till en bestämd låt';end if;
 insert into room_song_links values(p_code,p_song,p_url) on conflict(code,song_id) do update set url=excluded.url;
end $$;
create or replace function public.report_song(p_code text,p_song int,p_note text,p_url text default null) returns void language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where code=p_code;
 if auth.uid() is null or not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du tillhör inte rummet';end if;
 if not coalesce(r.state->'current'->>'id'=p_song::text or (r.host_id=auth.uid() and exists(select 1 from room_secrets where code=p_code and current_id=p_song)),false) then raise exception 'Rapportera den aktuella låten';end if;
 if p_note is null or length(trim(p_note)) not between 3 and 500 then raise exception 'Beskriv felet med 3–500 tecken';end if;
 if p_url is not null and p_url !~ '^https://open[.]spotify[.]com/track/[A-Za-z0-9]{22}$' then raise exception 'Ogiltig Spotify-länk';end if;
 perform pg_advisory_xact_lock(hashtext(auth.uid()::text));
 if (select count(*) from song_reports where reporter=auth.uid() and created_at>now()-interval '1 day')>=20 then raise exception 'Högst 20 rapporter per dygn';end if;
 insert into song_reports(song_id,reporter,note,proposed_url) values(p_song,auth.uid(),trim(p_note),p_url);
end $$;
create or replace function public.record_room_songs() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.state=old.state then return new;end if;
 insert into room_song_history select new.code,(t->>'id')::int from jsonb_array_elements(new.state->'players') p cross join lateral jsonb_array_elements(p->'timeline') t on conflict do nothing;
 if new.state->>'phase' in ('guess','reveal','finished') then insert into room_song_history select new.code,current_id from room_secrets where code=new.code and current_id is not null on conflict do nothing;end if;
 return new;
end $$;
drop trigger if exists record_room_songs on public.rooms;
create trigger record_room_songs after update on public.rooms for each row execute function public.record_room_songs();
-- Backfill already drawn cards for active rooms.
insert into room_song_history select r.code,(t->>'id')::int from rooms r cross join lateral jsonb_array_elements(r.state->'players') p cross join lateral jsonb_array_elements(p->'timeline') t on conflict do nothing;
insert into room_song_history select code,current_id from room_secrets where current_id is not null on conflict do nothing;
do $$declare src text;begin
 src:=pg_get_functiondef('public.host_action_core(text,text)'::regprocedure);
 src:=replace(src,'select array_agg(id order by random()) into d from songs;','select array_agg(id order by random()) into d from songs where not exists(select 1 from room_song_history h where h.code=p_code and h.song_id=songs.id);');execute src;
end $$;
create or replace function public.rematch_room(p_code text) returns void language plpgsql security definer set search_path=public as $$
declare r rooms;ps jsonb;n int;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or r.host_id<>auth.uid() or r.state->>'phase'<>'finished' then raise exception 'Bara spelledaren kan starta revansch efter avslutat spel';end if;
 select coalesce(jsonb_agg(p||jsonb_build_object('score',0,'timeline','[]'::jsonb)),'[]'::jsonb) into ps from jsonb_array_elements(r.state->'players') p where not coalesce((p->>'removed')::boolean,false);
 n:=jsonb_array_length(ps);
 if n=0 then raise exception 'Minst en spelare behövs';end if;
 if (select count(*) from songs where id not in(select song_id from room_song_history where code=p_code))<n+2 then raise exception 'För få ospelade låtar. Skapa ett nytt rum för att återställa kortleken.';end if;
 update rooms set state=jsonb_build_object('mode',r.state->>'mode','target',(r.state->>'target')::int,'phase','lobby','players',ps,'round',0,'turn',0,'answers','{}'::jsonb,'match',coalesce((r.state->>'match')::int,1)+1),updated_at=now() where code=p_code;
end $$;
revoke execute on function public.game_night_tools(text),public.change_host(text,uuid,boolean),public.claim_host(text),public.save_room_song_link(text,int,text),public.report_song(text,int,text,text),public.rematch_room(text),public.record_room_songs() from public,anon;
revoke execute on function public.record_room_songs() from authenticated;
grant execute on function public.game_night_tools(text),public.change_host(text,uuid,boolean),public.claim_host(text),public.save_room_song_link(text,int,text),public.report_song(text,int,text,text),public.rematch_room(text) to authenticated;
-- Checked against Spotify's own track pages; not a claim of catalog-wide review.
update public.songs set spotify_url='https://open.spotify.com/track/2TxCwUlqaOH3TIyJqGgR91' where title='Mamma Mia' and artist='ABBA' and year=1975;
update public.songs set spotify_url='https://open.spotify.com/track/1KPMTL3BRLBWrNY8fveVy6' where title='Killer Queen' and artist='Queen' and year=1974;
