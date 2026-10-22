-- Run against an empty local test DB after bootstrap.sql, schema.sql and seed.sql.
-- Everything in this test is rolled back. Raises an error on failed assertions.
begin;
insert into auth.users values('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
do $$
declare c text; s jsonb; y integer; a integer; b integer; pos integer; i integer; rejected boolean;
begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 c:=create_room('all',1);perform set_config('test.room',c,true);
 perform join_room(c,'Ada');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 perform join_room(c,'Bo');perform join_room(c,'Bo');
 if (select jsonb_array_length(state->'players') from rooms where code=c)<>2 then raise exception 'Duplicate join';end if;
 rejected:=false;begin perform host_action(c,'start');exception when others then rejected:=true;end;
 if not rejected then raise exception 'Non-host started game';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 perform host_action(c,'start');select state into s from rooms where code=c;
 if s->>'phase'<>'guess' or s ? 'current' then raise exception 'Start phase / secret leak';end if;
 select t.year into y from songs t join room_secrets z on z.current_id=t.id where z.code=c;
 a:=(s->'players'->0->'timeline'->0->>'year')::int;b:=(s->'players'->1->'timeline'->0->>'year')::int;
 pos:=case when y<=a then 0 else 1 end;
 perform submit_guess(c,1,pos);
 rejected:=false;begin perform submit_guess(c,1,pos);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Duplicate guess accepted';end if;
 if (select state->'answers'->'00000000-0000-0000-0000-000000000001' ? 'correct' from rooms where code=c) then raise exception 'Correctness leaked';end if;
 rejected:=false;begin perform submit_guess(c,0,0);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Stale round accepted';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 rejected:=false;begin perform submit_guess(c,1,99);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Invalid position accepted';end if;
 rejected:=false;begin perform submit_guess(c,1,null);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Null position accepted';end if;
 rejected:=false;begin perform submit_guess(c,null,0);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Null round accepted';end if;
 rejected:=false;begin perform music_card(c);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Player read music card';end if;
 perform submit_guess(c,1,case when y<=b then 0 else 1 end);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 perform host_action(c,'reveal');select state into s from rooms where code=c;
 if s->>'phase'<>'reveal' or (s->'players'->0->>'score')::int<>1 or (s->'players'->1->>'score')::int<>1 then raise exception 'Simultaneous scoring incorrect: %',s;end if;
 if jsonb_array_length(s->'players'->0->'timeline')<>2 then raise exception 'Card missing';end if;
 rejected:=false;begin perform host_action(c,'reveal');exception when others then rejected:=true;end;
 if not rejected then raise exception 'Double reveal accepted';end if;
 perform host_action(c,'next');
 if (select state->>'phase' from rooms where code=c)<>'finished' then raise exception 'Victory not detected';end if;
 -- Classical mode, no submission, turn changes, late join and guessing restrictions.
 c:=create_room('classic',3);perform join_room(c,'Ada');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);perform join_room(c,'Bo');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);perform host_action(c,'start');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000002',true);
 rejected:=false;begin perform submit_guess(c,1,0);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Wrong classic player accepted';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
 rejected:=false;begin perform join_room(c,'Late');exception when others then rejected:=true;end;
 if not rejected then raise exception 'Late player accepted';end if;
 perform join_room(c,'',true);
 rejected:=false;begin perform submit_guess(c,1,0);exception when others then rejected:=true;end;
 if not rejected then raise exception 'Observer guess accepted';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 perform host_action(c,'reveal');perform host_action(c,'next');select state into s from rooms where code=c;
 if (s->>'turn')::int<>1 or (s->>'round')::int<>2 or (s->'players'->0->>'score')::int<>0 then raise exception 'Turn or unanswered scoring failed';end if;
 raise notice 'PASS: multiplayer phases, classic/all scoring, secrets, idempotent join, stale/duplicate/invalid guesses, host authorization, late join, observers, turn rotation and victory.';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
do $$begin
 if (select count(*) from rooms)=0 then raise exception 'Member cannot see own rooms';end if;
 if has_table_privilege('authenticated','public.rooms','UPDATE') or has_table_privilege('authenticated','public.room_secrets','SELECT') then raise exception 'Excess privileges';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000099',true);
do $$begin
 if (select count(*) from rooms)<>0 then raise exception 'RLS leaked room to outsider';end if;
 raise notice 'PASS: RLS room visibility and no direct room writes / secret reads.';
end $$;
rollback;
