-- Private bearer code for recovering ONE member/host in ONE room.
create table if not exists public.room_recovery (
 token uuid primary key default gen_random_uuid(),
 code text not null references public.rooms(code) on delete cascade,
 user_id uuid not null references auth.users(id),
 unique(code,user_id)
);
alter table public.room_recovery enable row level security;
revoke all on public.room_recovery from public,anon,authenticated;
create index if not exists room_recovery_user_idx on public.room_recovery(user_id);

create or replace function public.connection_ticket(p_code text) returns text
language plpgsql security definer set search_path=public as $$
declare t uuid; r rooms;
begin
 select * into r from rooms where code=p_code for update;
 if not found or r.state->>'phase'='closed' or r.updated_at<now()-interval '24 hours' then raise exception 'Rummet är avslutat eller har gått ut';end if;
 if auth.uid() is null or not exists(select 1 from members where code=p_code and user_id=auth.uid() and not removed) then raise exception 'Du tillhör inte rummet';end if;
 insert into room_recovery(code,user_id) values(p_code,auth.uid()) on conflict(code,user_id) do nothing;
 select token into t from room_recovery where code=p_code and user_id=auth.uid();return t::text;
end $$;

create or replace function public.recover_room(p_code text,p_ticket text) returns text
language plpgsql security definer set search_path=public as $$
declare r rooms; old_id uuid; new_id uuid:=auth.uid(); ps jsonb; ans jsonb;
begin
 if new_id is null then raise exception 'Logga in först';end if;
 select * into r from rooms where code=upper(trim(p_code)) for update;
 if not found or r.state->>'phase'='closed' or r.updated_at<now()-interval '24 hours' then raise exception 'Rummet är avslutat eller har gått ut';end if;
 select user_id into old_id from room_recovery where code=r.code and token::text=lower(trim(p_ticket));
 if old_id is null or not exists(select 1 from members where code=r.code and user_id=old_id and not removed) then raise exception 'Återanslutningskoden är felaktig eller spärrad';end if;
 if old_id=new_id then return r.code;end if;
 if exists(select 1 from members where code=r.code and user_id=new_id) then raise exception 'Den här webbläsaren har redan en annan plats i rummet';end if;
 select jsonb_agg(case when p->>'id'=old_id::text then jsonb_set(p,'{id}',to_jsonb(new_id::text)) else p end order by ordinality) into ps from jsonb_array_elements(r.state->'players') with ordinality a(p,ordinality);
 ans:=r.state->'answers';
 if ans ? old_id::text then ans:=(ans-old_id::text)||jsonb_build_object(new_id::text,ans->old_id::text);end if;
 update members set user_id=new_id,last_seen_at=now() where code=r.code and user_id=old_id;
 insert into game_users(user_id) values(new_id) on conflict(user_id) do update set last_seen_at=now();
 update room_recovery set user_id=new_id,token=gen_random_uuid() where code=r.code and user_id=old_id;
 -- Avoid a guess->reveal transition: existing scoring trigger must not rescore.
 update rooms set host_id=case when host_id=old_id then new_id else host_id end,
  state=jsonb_set(jsonb_set(state,'{players}',coalesce(ps,'[]'::jsonb)),'{answers}',coalesce(ans,'{}'::jsonb)),updated_at=now() where code=r.code;
 return r.code;
end $$;

create or replace function public.set_room_target(p_code text,p_target integer) returns void
language plpgsql security definer set search_path=public as $$
declare r rooms;
begin
 select * into r from rooms where code=p_code for update;
 if not found or auth.uid() is null or r.host_id<>auth.uid() then raise exception 'Bara spelledaren kan ändra maxpoängen';end if;
 if r.state->>'phase'<>'lobby' or r.updated_at<now()-interval '24 hours' then raise exception 'Maxpoäng kan ändras före start';end if;
 if p_target is null or p_target not between 1 and 20 then raise exception 'Välj ett heltal från 1 till 20';end if;
 update rooms set state=jsonb_set(state,'{target}',to_jsonb(p_target)),updated_at=now() where code=p_code;
end $$;
revoke execute on function public.connection_ticket(text),public.recover_room(text,text),public.set_room_target(text,integer) from public,anon;
grant execute on function public.connection_ticket(text),public.recover_room(text,text),public.set_room_target(text,integer) to authenticated;
