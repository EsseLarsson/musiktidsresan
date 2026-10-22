-- Local isolated DB only, after 002_room_lifecycle.sql. All test data rolls back.
begin;
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000011'),('00000000-0000-0000-0000-000000000012'),('00000000-0000-0000-0000-000000000013');
do $$
declare c text; old_room text; s jsonb; rejected boolean; result jsonb;
 h uuid:='00000000-0000-0000-0000-000000000011';
 a uuid:='00000000-0000-0000-0000-000000000012';
 b uuid:='00000000-0000-0000-0000-000000000013';
begin
 perform set_config('request.jwt.claim.sub',h::text,true);c:=create_room('classic',5);perform join_room(c,'Host');
 perform set_config('request.jwt.claim.sub',a::text,true);perform join_room(c,'A');
 perform set_config('request.jwt.claim.sub',b::text,true);perform join_room(c,'B');
 if not (room_presence(c)->>b::text)::boolean then raise exception 'Heartbeat not online';end if;
 update members set last_seen_at=now()-interval '91 seconds' where code=c and user_id=a;
 if (room_presence(c)->>a::text)::boolean then raise exception 'Offline timeout failed';end if;
 rejected:=false;begin perform room_lifecycle(c,'close');exception when others then rejected:=true;end;
 if not rejected then raise exception 'Nonhost closed room';end if;
 rejected:=false;begin perform room_lifecycle(c,'remove',a);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Nonhost removed player';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform host_action(c,'start');
 perform room_lifecycle(c,'remove',a);
 perform host_action(c,'reveal');perform host_action(c,'next');
 select state into s from rooms where code=c;
 if s->'players'->((s->>'turn')::int % jsonb_array_length(s->'players'))->>'id'<>b::text then raise exception 'Classic turn did not skip removed player';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 rejected:=false;begin perform join_room(c,'A',true);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Removed player rejoined';end if;
 rejected:=false;begin perform submit_guess(c,2,0);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Removed player guessed';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);perform room_lifecycle(c,'leave');
 perform set_config('request.jwt.claim.sub',h::text,true);perform room_lifecycle(c,'close');
 if (select state->>'phase' from rooms where code=c)<>'closed' then raise exception 'Room not closed';end if;
 rejected:=false;begin perform host_action(c,'reveal');exception when others then rejected:=true;end;
 if not rejected then raise exception 'Closed room playable';end if;
 old_room:=c;
 c:=create_room('all',3);perform join_room(c,'Host');
 update rooms set updated_at=now()-interval '23 hours' where code=c;
 perform room_heartbeat(c);
 if (select updated_at<now()-interval '1 minute' from rooms where code=c) then raise exception 'Heartbeat did not preserve active room';end if;
 update rooms set updated_at=now()-interval '25 hours' where code=c;
 rejected:=false;begin perform room_heartbeat(c);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Expired room revived';end if;
 update rooms set updated_at=now()-interval '25 hours' where code=old_room;
 result:=cleanup_game_data();
 if exists(select 1 from rooms where code in (c,old_room)) or exists(select 1 from members where code in(c,old_room)) or exists(select 1 from room_secrets where code=old_room) then raise exception 'Expired room cascade cleanup failed';end if;
 raise notice 'PASS: close/remove permissions, presence timeout, classic turn skip, leave, removed-user guards, closed/expired guards, activity and cascade cleanup';
end $$;
-- Account cleanup: only old anonymous game identities with no room links.
insert into auth.users(id,is_anonymous,created_at,last_sign_in_at) values
 ('00000000-0000-0000-0000-000000000021',true,now()-interval '30 days',now()-interval '10 days'),
 ('00000000-0000-0000-0000-000000000022',false,now()-interval '30 days',now()-interval '10 days'),
 ('00000000-0000-0000-0000-000000000023',true,now()-interval '30 days',now()-interval '10 days'),
 ('00000000-0000-0000-0000-000000000024',true,now()-interval '30 days',now()-interval '10 days');
insert into game_users values
 ('00000000-0000-0000-0000-000000000021',now()-interval '10 days'),
 ('00000000-0000-0000-0000-000000000022',now()-interval '10 days'),
 ('00000000-0000-0000-0000-000000000024',now()-interval '10 days');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000024',true);
select create_room('all',3);
select cleanup_game_data();
do $$begin
 if exists(select 1 from auth.users where id='00000000-0000-0000-0000-000000000021') then raise exception 'Stale game identity survived';end if;
 if (select count(*) from auth.users where id in ('00000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000023','00000000-0000-0000-0000-000000000024'))<>3 then raise exception 'Permanent, unrelated or room-linked identity deleted';end if;
 if has_function_privilege('authenticated','public.cleanup_game_data()','EXECUTE') or has_function_privilege('authenticated','public.host_action_core(text,text)','EXECUTE') then raise exception 'Private maintenance/core RPC exposed';end if;
 raise notice 'PASS: stale anonymous game identity deleted; permanent, unrelated, room-linked accounts preserved; cleanup/core RPC private';
end $$;
rollback;
