-- ============================================================================
-- SP-CLASSROOM — Row Level Security (RLS)
-- ----------------------------------------------------------------------------
-- ปิดช่องโหว่ร้ายแรง: ก่อนหน้านี้ทุกตารางเปิดให้ anon key (ซึ่งอยู่ในโค้ด public)
-- อ่าน/แก้/ลบข้อมูลได้อิสระ การเช็คสิทธิ์อยู่ฝั่ง client เท่านั้น (bypass ได้)
-- migration นี้บังคับสิทธิ์ที่ระดับฐานข้อมูล
--
-- โมเดลสิทธิ์ (role เก็บใน public.profiles.role):
--   admin   → อ่าน/เขียนได้ทุกอย่าง
--   viewer  → อ่านได้ทุกอย่าง (read-only) เขียนไม่ได้
--   student → อ่าน/เขียนเฉพาะข้อมูลของตัวเอง + อ่านหลักสูตร; เกรด/เช็คชื่อแก้ไม่ได้
--   pending → เข้าถึงได้แค่ profile แถวตัวเอง
--
-- หมายเหตุ schema: column ที่ policy อ้างอิงยืนยันจากโค้ดแอปทั้งหมด
--   profiles(id, role, approved, student_id) · students(id, deleted_at)
--   *(student_id) ในตารางข้อมูลนักเรียน · storage path = {itemId}/{studentId}/{file}
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Helper functions  (SECURITY DEFINER เพื่ออ่าน profiles โดยไม่ติด RLS ของตัวเอง)
-- ----------------------------------------------------------------------------
create or replace function public.is_approved()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and approved = true
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and approved = true and role = 'admin'
  );
$$;

-- staff = อ่านข้อมูลทุกคนได้ (admin เขียนได้ด้วย, viewer อ่านอย่างเดียว)
create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.profiles
    where id = auth.uid() and approved = true and role in ('admin','viewer')
  );
$$;

-- student_id ที่ผูกกับ user ปัจจุบัน (null ถ้าไม่ใช่ student)
create or replace function public.current_student_id()
returns uuid language sql stable security definer set search_path = public as $$
  select student_id from public.profiles where id = auth.uid();
$$;

revoke all on function public.is_approved(), public.is_admin(),
                       public.is_staff(), public.current_student_id() from public;
grant execute on function public.is_approved(), public.is_admin(),
                          public.is_staff(), public.current_student_id() to authenticated;

-- ----------------------------------------------------------------------------
-- 2) เปิด RLS ทุกตาราง
-- ----------------------------------------------------------------------------
alter table public.profiles    enable row level security;
alter table public.subjects    enable row level security;
alter table public.tracks      enable row level security;
alter table public.chapters    enable row level security;
alter table public.topics      enable row level security;
alter table public.items       enable row level security;
alter table public.students    enable row level security;
alter table public.enrollments enable row level security;
alter table public.progress    enable row level security;
alter table public.submissions enable row level security;
alter table public.exam_scores enable row level security;
alter table public.attendance  enable row level security;

-- ----------------------------------------------------------------------------
-- 3) PROFILES
--    อ่าน: ตัวเอง หรือ staff   |   เขียน: admin จัดการทุกแถว, ผู้ใช้แก้แถวตัวเอง
--    (การกัน user ยกระดับ role/approved ของตัวเอง อยู่ใน trigger ข้อ 5)
-- ----------------------------------------------------------------------------
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_staff());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists profiles_admin_all on public.profiles;
create policy profiles_admin_all on public.profiles for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 4) หลักสูตร (subjects/tracks/chapters/topics/items)
--    อ่าน: ทุกคนที่ approved   |   เขียน: admin เท่านั้น
-- ----------------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['subjects','tracks','chapters','topics','items'] loop
    execute format('drop policy if exists %I_read on public.%I', t, t);
    execute format($f$create policy %I_read on public.%I for select to authenticated
                     using (public.is_approved())$f$, t, t);
    execute format('drop policy if exists %I_admin_write on public.%I', t, t);
    execute format($f$create policy %I_admin_write on public.%I for all to authenticated
                     using (public.is_admin()) with check (public.is_admin())$f$, t, t);
  end loop;
end$$;

-- ----------------------------------------------------------------------------
-- 5) STUDENTS — อ่าน: staff หรือ student เจ้าของแถว | เขียน: admin
-- ----------------------------------------------------------------------------
drop policy if exists students_select on public.students;
create policy students_select on public.students for select to authenticated
  using (public.is_staff() or id = public.current_student_id());

drop policy if exists students_admin_write on public.students;
create policy students_admin_write on public.students for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 6) ENROLLMENTS — อ่าน: staff หรือเจ้าของ | เขียน: admin
-- ----------------------------------------------------------------------------
drop policy if exists enrollments_select on public.enrollments;
create policy enrollments_select on public.enrollments for select to authenticated
  using (public.is_staff() or student_id = public.current_student_id());

drop policy if exists enrollments_admin_write on public.enrollments;
create policy enrollments_admin_write on public.enrollments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 7) PROGRESS — student แก้ของตัวเองได้ (ติ๊กความคืบหน้า), admin ทุกแถว
-- ----------------------------------------------------------------------------
drop policy if exists progress_select on public.progress;
create policy progress_select on public.progress for select to authenticated
  using (public.is_staff() or student_id = public.current_student_id());

drop policy if exists progress_insert on public.progress;
create policy progress_insert on public.progress for insert to authenticated
  with check (public.is_admin() or student_id = public.current_student_id());

drop policy if exists progress_update on public.progress;
create policy progress_update on public.progress for update to authenticated
  using (public.is_admin() or student_id = public.current_student_id())
  with check (public.is_admin() or student_id = public.current_student_id());

drop policy if exists progress_delete on public.progress;
create policy progress_delete on public.progress for delete to authenticated
  using (public.is_admin());

-- ----------------------------------------------------------------------------
-- 8) SUBMISSIONS (DB rows) — student จัดการของตัวเอง, admin ทุกแถว
-- ----------------------------------------------------------------------------
drop policy if exists submissions_select on public.submissions;
create policy submissions_select on public.submissions for select to authenticated
  using (public.is_staff() or student_id = public.current_student_id());

drop policy if exists submissions_insert on public.submissions;
create policy submissions_insert on public.submissions for insert to authenticated
  with check (public.is_admin() or student_id = public.current_student_id());

drop policy if exists submissions_delete on public.submissions;
create policy submissions_delete on public.submissions for delete to authenticated
  using (public.is_admin() or student_id = public.current_student_id());

-- ----------------------------------------------------------------------------
-- 9) EXAM_SCORES — เขียนเฉพาะ admin (เกรด), student อ่านของตัวเอง
-- ----------------------------------------------------------------------------
drop policy if exists exam_scores_select on public.exam_scores;
create policy exam_scores_select on public.exam_scores for select to authenticated
  using (public.is_staff() or student_id = public.current_student_id());

drop policy if exists exam_scores_admin_write on public.exam_scores;
create policy exam_scores_admin_write on public.exam_scores for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 10) ATTENDANCE — เขียนเฉพาะ admin (เช็คชื่อ), student อ่านของตัวเอง
-- ----------------------------------------------------------------------------
drop policy if exists attendance_select on public.attendance;
create policy attendance_select on public.attendance for select to authenticated
  using (public.is_staff() or student_id = public.current_student_id());

drop policy if exists attendance_admin_write on public.attendance;
create policy attendance_admin_write on public.attendance for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----------------------------------------------------------------------------
-- 11) Trigger กัน user ยกระดับสิทธิ์ตัวเอง
--     ถ้าไม่ใช่ admin → ห้ามแก้ role / approved / student_id ของแถวตัวเอง
--     (อนุญาตเฉพาะ display_name ฯลฯ ตาม flow register ที่มีอยู่)
-- ----------------------------------------------------------------------------
create or replace function public.guard_profile_privilege()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if public.is_admin() then
    return new;  -- admin แก้ได้ทุก field
  end if;
  -- non-admin: ล็อก field ที่อ่อนไหวไว้ตามค่าเดิม
  new.role       := old.role;
  new.approved   := old.approved;
  new.student_id := old.student_id;
  return new;
end$$;

drop trigger if exists trg_guard_profile_privilege on public.profiles;
create trigger trg_guard_profile_privilege
  before update on public.profiles
  for each row execute function public.guard_profile_privilege();

-- ----------------------------------------------------------------------------
-- 12) STORAGE — bucket 'submissions'   path = {itemId}/{studentId}/{file}
--     foldername(name)[2] = studentId
-- ----------------------------------------------------------------------------
drop policy if exists submissions_storage_read   on storage.objects;
drop policy if exists submissions_storage_insert  on storage.objects;
drop policy if exists submissions_storage_delete  on storage.objects;

create policy submissions_storage_read on storage.objects for select to authenticated
  using (
    bucket_id = 'submissions' and (
      public.is_staff()
      or (storage.foldername(name))[2] = public.current_student_id()::text
    )
  );

create policy submissions_storage_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'submissions' and (
      public.is_admin()
      or (storage.foldername(name))[2] = public.current_student_id()::text
    )
  );

create policy submissions_storage_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'submissions' and (
      public.is_admin()
      or (storage.foldername(name))[2] = public.current_student_id()::text
    )
  );

-- ============================================================================
-- จบ migration. ตรวจสอบ: ทุกตารางต้อง rowsecurity = true
--   select tablename, rowsecurity from pg_tables where schemaname='public';
-- ============================================================================
