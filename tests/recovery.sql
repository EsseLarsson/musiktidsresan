-- Local isolated database only. Roll back all identities and rooms.
begin;
insert into auth.users(id) values('00000000-0000-0000-0000-000000000031'),('00000000-0000-0000-0000-000000000032'),('00000000-0000-0000-0000-000000000033'),('00000000-0000-0000-0000-000000000034');
do $$
declare c text;t text;host_ticket text;s jsonb;refused boolean;
 h uuid:='00000000-0000-0000-0000-000000000031';
 p uuid:='00000000-0000-0000-0000-000000000032';
 fresh uuid:='00000000-0000-0000-0000-000000000033';
 host_new uuid:='00000000-0000-0000-0000-000000000034';
begin
 perform set_config('request.jwt.claim.sub',h::text,true);c:=create_room('all',7);host_ticket:=connection_ticket(c);
 perform set_room_target(c,9);
 if (select (state->>'target')::int from rooms where code=c)<>9 then raise exception 'Target not saved';end if;
 refused:=false;begin perform set_room_target(c,21);exception when others then refused:=true;end;
 if not refused then raise exception 'Invalid target accepted';end if;
 perform set_config('request.jwt.claim.sub',p::text,true);perform join_room(c,'Spelare');t:=connection_ticket(c);
 refused:=false;begin perform set_room_target(c,4);exception when others then refused:=true;end;
 if not refused then raise exception 'Nonhost changed target';end if;
 perform set_config('request.jwt.claim.sub',h::text,true);perform host_action(c,'start');
 refused:=false;begin perform set_room_target(c,4);exception when others then refused:=true;end;
 if not refused then raise exception 'Target changed after start';end if;
 -- Put recognizable test score and locked answer on the player before recovery.
 update rooms set state=jsonb_set(jsonb_set(state,'{players,0,score}','2'),array['answers',p::text],'{"position":0}') where code=c;
 perform set_config('request.jwt.claim.sub',fresh::text,true);
 refused:=false;begin perform recover_room(c,'wrong');exception when others then refused:=true;end;
 if not refused then raise exception 'Invalid secret accepted';end if;
 perform recover_room(c,t);select state into s from rooms where code=c;
 if s->'players'->0->>'id'<>fresh::text or (s->'players'->0->>'score')::int<>2 or not (s->'answers' ? fresh::text) or s->'answers' ? p::text then raise exception 'Score/locked answer lost';end if;
 if connection_ticket(c)=t then raise exception 'Secret not rotated';end if;
 perform set_config('request.jwt.claim.sub',host_new::text,true);perform recover_room(c,host_ticket);
 if (select host_id from rooms where code=c)<>host_new then raise exception 'Host recovery failed';end if;
 host_ticket:=connection_ticket(c);perform room_lifecycle(c,'remove',fresh);
 perform set_config('request.jwt.claim.sub',fresh::text,true);
 refused:=false;begin perform connection_ticket(c);exception when others then refused:=true;end;
 if not refused then raise exception 'Removed identity recovered';end if;
 perform set_config('request.jwt.claim.sub',host_new::text,true);perform room_lifecycle(c,'close');
 refused:=false;begin perform recover_room(c,host_ticket);exception when others then refused:=true;end;
 if not refused then raise exception 'Closed room recovered';end if;
 if has_table_privilege('authenticated','public.room_recovery','SELECT') then raise exception 'Recovery secrets exposed';end if;
 raise notice 'PASS: target authorization/range/start lock, private recovery, score/answers preserved, host recovery, rotation, removed/closed rejection';
end $$;
rollback;
