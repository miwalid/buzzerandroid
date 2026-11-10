begin;

create schema if not exists buzzer_private;
revoke all on schema buzzer_private from public, anon, authenticated;

create table buzzer_private.rooms (
  code text primary key,
  host uuid not null,
  expires_at timestamptz not null default (now() + interval '6 hours'),
  phase text not null default 'waiting',
  winner uuid,
  epoch integer not null default 0
);

create table buzzer_private.players (
  room text not null references buzzer_private.rooms on delete cascade,
  token uuid not null,
  id uuid not null default gen_random_uuid(),
  name text not null,
  score integer not null default 0,
  excluded boolean not null default false,
  primary key (room, token)
);

alter table buzzer_private.rooms enable row level security;
alter table buzzer_private.players enable row level security;

-- Own the private game state. The public API can invoke only this dispatcher.
create function buzzer_private.play(
  action text, room_code text, credential uuid, player_name text, expected_epoch integer
)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  current_room buzzer_private.rooms%rowtype;
  player buzzer_private.players%rowtype;
  is_host boolean;
begin
  if credential is null then
    return jsonb_build_object('error', 'credential');
  end if;

  if action = 'create' then
    delete from buzzer_private.rooms where expires_at <= now();
    loop
      room_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
      insert into buzzer_private.rooms (code, host) values (room_code, credential)
      on conflict do nothing returning * into current_room;
      exit when found;
    end loop;
  else
    if action = 'state' then
      select * into current_room from buzzer_private.rooms where code = room_code and expires_at > now();
    else
      select * into current_room from buzzer_private.rooms where code = room_code and expires_at > now() for update;
    end if;
    if not found then return jsonb_build_object('error', 'room'); end if;
  end if;

  is_host := current_room.host = credential;
  if action = 'join' and not is_host then
    player_name := btrim(player_name);
    if player_name is null or char_length(player_name) not between 1 and 30 then
      return jsonb_build_object('error', 'name');
    end if;
    if not exists (select 1 from buzzer_private.players where room = room_code and token = credential) then
      if (select count(*) from buzzer_private.players where room = room_code) >= 20 then
        return jsonb_build_object('error', 'full');
      end if;
      insert into buzzer_private.players (room, token, name) values (room_code, credential, player_name);
    end if;
  end if;

  select * into player from buzzer_private.players where room = room_code and token = credential;
  if not is_host and player.id is null then
    return jsonb_build_object('error', 'credential');
  end if;

  if action = 'close' and is_host then
    delete from buzzer_private.rooms where code = room_code;
    return jsonb_build_object('closed', true);
  elsif action = 'leave' and not is_host then
    if current_room.winner = player.id then
      update buzzer_private.rooms set phase = 'open', winner = null, epoch = epoch + 1 where code = room_code;
    end if;
    delete from buzzer_private.players where room = room_code and token = credential;
    return jsonb_build_object('closed', true);
  elsif expected_epoch = current_room.epoch then
    if action = 'open' and is_host and current_room.phase = 'waiting'
       and exists (select 1 from buzzer_private.players where room = room_code) then
      update buzzer_private.rooms set phase = 'open', epoch = epoch + 1
      where code = room_code returning * into current_room;
    elsif action = 'buzz' and not is_host and current_room.phase = 'open' and not player.excluded then
      update buzzer_private.rooms set phase = 'answer', winner = player.id, epoch = epoch + 1
      where code = room_code returning * into current_room;
    elsif is_host and current_room.phase = 'answer' and action in ('right', 'wrong') then
      if action = 'right' then
        update buzzer_private.players set score = score + 1 where room = room_code and id = current_room.winner;
      else
        update buzzer_private.players set excluded = true where room = room_code and id = current_room.winner;
      end if;
      if action = 'wrong' and exists (select 1 from buzzer_private.players where room = room_code and not excluded) then
        current_room.phase := 'open';
      else
        current_room.phase := 'waiting';
        update buzzer_private.players set excluded = false where room = room_code and excluded;
      end if;
      update buzzer_private.rooms set phase = current_room.phase, winner = null, epoch = epoch + 1
      where code = room_code returning * into current_room;
    end if;
  end if;

  -- One statement builds a consistent snapshot for clients polling during a change.
  return (
    select jsonb_build_object(
      'code', r.code, 'phase', r.phase, 'epoch', r.epoch, 'winner', r.winner,
      'excluded', coalesce((select p.excluded from buzzer_private.players p where p.room = r.code and p.token = credential), false),
      'players', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'score', p.score) order by p.score desc, p.name, p.id)
        from buzzer_private.players p where p.room = r.code), '[]'::jsonb)
    ) from buzzer_private.rooms r where r.code = room_code
  );
end;
$$;

revoke all on function buzzer_private.play(text, text, uuid, text, integer) from public, anon, authenticated;
grant usage on schema buzzer_private to anon, authenticated;
grant execute on function buzzer_private.play(text, text, uuid, text, integer) to anon, authenticated;

create function public.buzzer_play(
  action text, room_code text default null, credential uuid default null,
  player_name text default null, expected_epoch integer default null
)
returns jsonb
language sql security invoker set search_path = ''
as $$
  select buzzer_private.play(action, room_code, credential, player_name, expected_epoch);
$$;
revoke all on function public.buzzer_play(text, text, uuid, text, integer) from public, anon, authenticated;
grant execute on function public.buzzer_play(text, text, uuid, text, integer) to anon, authenticated;

commit;
