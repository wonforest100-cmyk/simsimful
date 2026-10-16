-- =====================================================================
--  국비 교부신청서 작성기 — Supabase 초기 설정
--  Supabase 대시보드 › SQL Editor › New query 에 전체를 붙여넣고 Run.
--  여러 번 실행해도 안전합니다(이미 있는 것은 건너뜀).
-- =====================================================================

-- 1) 회원 명단 — 회원가입하면 자동으로 등록되어 바로 사용 가능. 관리자는 '승인 취소'로 특정 사람을 막을 수 있음
create table if not exists public.app_members (
  email      text primary key,
  name       text,
  created_at timestamptz not null default now()
);
alter table public.app_members add column if not exists approved boolean not null default false;
alter table public.app_members add column if not exists role     text    not null default 'member';

-- 2) 팀이 함께 쓰는 자료 한 벌 (id = 'main' 한 줄에 전체 자료를 JSON으로 저장)
create table if not exists public.app_state (
  id         text primary key,
  data       jsonb not null,
  version    integer not null default 1,
  updated_at timestamptz not null default now(),
  updated_by text
);

-- 3) 저장할 때마다 바로 이전 자료를 보관 (되돌리기용, 최근 300개 유지)
create table if not exists public.app_state_history (
  hid      bigint generated always as identity primary key,
  id       text not null,
  data     jsonb not null,
  version  integer not null,
  saved_at timestamptz not null,
  saved_by text
);
create index if not exists app_state_history_id_hid on public.app_state_history (id, hid desc);

-- 4) 휴면 방지용 접속 기록 (GitHub Actions가 2일마다 호출)
create table if not exists public.keepalive (
  id        integer primary key default 1,
  pinged_at timestamptz not null default now(),
  count     bigint not null default 0
);

-- ---------------------------------------------------------------------
-- 함수
-- ---------------------------------------------------------------------
-- 로그인한 사람이 승인된 회원인지 / 관리자인지
create or replace function public.is_member()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_members m
                  where m.email = lower(coalesce(auth.jwt() ->> 'email', '')) and m.approved);
$$;
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.app_members m
                  where m.email = lower(coalesce(auth.jwt() ->> 'email', '')) and m.approved and m.role = 'admin');
$$;

-- 회원가입하면 명단에 자동 등록 (바로 사용 가능)
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.app_members (email, name, approved, role)
  values (lower(new.email), coalesce(new.raw_user_meta_data ->> 'name', ''), true, 'member')
  on conflict (email) do update set name = coalesce(nullif(public.app_members.name, ''), excluded.name);
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- 저장 직전: 이전 자료를 기록에 넣고, 저장 시각·저장한 사람을 서버가 채움
create or replace function public.app_state_before_write()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'UPDATE' then
    insert into public.app_state_history (id, data, version, saved_at, saved_by)
    values (old.id, old.data, old.version, old.updated_at, old.updated_by);
    delete from public.app_state_history
     where id = old.id and hid in (
       select hid from public.app_state_history where id = old.id order by hid desc offset 300);
  end if;
  new.updated_at := now();
  new.updated_by := coalesce(auth.jwt() ->> 'email', new.updated_by);
  return new;
end $$;

drop trigger if exists trg_app_state_before_write on public.app_state;
create trigger trg_app_state_before_write
  before insert or update on public.app_state
  for each row execute function public.app_state_before_write();

-- 휴면 방지: 실제로 DB에 한 번 쓰기를 해서 '활동'으로 남김. 자료는 건드리지 않음.
create or replace function public.keepalive()
returns timestamptz language sql volatile security definer set search_path = public as $$
  insert into public.keepalive (id, pinged_at, count) values (1, now(), 1)
  on conflict (id) do update set pinged_at = excluded.pinged_at, count = public.keepalive.count + 1
  returning pinged_at;
$$;
revoke all on function public.keepalive() from public;
grant execute on function public.keepalive() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 접근 권한 (RLS): app_members에 등록된 로그인 사용자만
-- ---------------------------------------------------------------------
alter table public.app_members       enable row level security;
alter table public.app_state         enable row level security;
alter table public.app_state_history enable row level security;
alter table public.keepalive         enable row level security;   -- 정책 없음 = 직접 접근 불가(함수로만)

drop policy if exists members_read   on public.app_members;
drop policy if exists members_insert on public.app_members;
drop policy if exists members_update on public.app_members;
drop policy if exists members_delete on public.app_members;
-- 본인 줄은 누구나(승인 대기 확인용), 전체 명단은 승인된 회원이 볼 수 있음. 승인·권한 변경·삭제는 관리자만
create policy members_read   on public.app_members for select to authenticated
  using (public.is_member() or email = lower(coalesce(auth.jwt() ->> 'email', '')));
create policy members_insert on public.app_members for insert to authenticated with check (public.is_admin());
create policy members_update on public.app_members for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy members_delete on public.app_members for delete to authenticated using (public.is_admin());

drop policy if exists state_read    on public.app_state;
drop policy if exists state_insert  on public.app_state;
drop policy if exists state_update  on public.app_state;
create policy state_read    on public.app_state         for select to authenticated using (public.is_member());
create policy state_insert  on public.app_state         for insert to authenticated with check (public.is_member());
create policy state_update  on public.app_state         for update to authenticated using (public.is_member()) with check (public.is_member());

drop policy if exists history_read  on public.app_state_history;
create policy history_read  on public.app_state_history for select to authenticated using (public.is_member());

grant select, insert, update, delete on public.app_members to authenticated;
grant select, insert, update on public.app_state         to authenticated;
grant select                 on public.app_state_history to authenticated;

-- ---------------------------------------------------------------------
-- 5) 첫 관리자 등록 — 아래 이메일을 본인 주소로 바꿔서 실행하세요
--    (나머지 사람은 작성기에서 회원가입하면 이메일 인증 후 바로 사용할 수 있습니다)
-- ---------------------------------------------------------------------
insert into public.app_members (email, name, approved, role) values
  (lower('your-email@example.com'), '관리자', true, 'admin')
on conflict (email) do update set approved = true, role = 'admin';

-- 확인용
select 'members' as what, count(*) from public.app_members
union all select 'state rows', count(*) from public.app_state;
