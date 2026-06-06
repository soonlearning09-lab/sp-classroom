-- ============================================================================
-- SP-CLASSROOM — Data integrity constraints
-- ----------------------------------------------------------------------------
-- เสริมความถูกต้องของข้อมูลที่ระดับฐานข้อมูล (กันข้อมูลเพี้ยนแม้ client มีบั๊ก)
-- เขียนแบบ defensive: ถ้า constraint มีอยู่แล้ว หรือข้อมูลเดิมขัด จะ NOTICE แล้วข้าม
-- ไม่ทำให้ทั้ง migration ล้ม (เหมาะกับช่วง pre-launch)
--
-- enum ยืนยันจากโค้ดแอป:
--   items.type        ∈ {lesson, assignment, exam}
--   attendance.status ∈ {on_time, late, online, absent}   ("ล้าง" = ลบแถว)
-- ============================================================================

-- helper: เพิ่ม constraint แบบไม่ล้มถ้าซ้ำ/ขัด
create or replace function pg_temp.add_constraint_safe(p_sql text, p_label text)
returns void language plpgsql as $$
begin
  execute p_sql;
  raise notice 'OK: %', p_label;
exception
  when duplicate_object then raise notice 'SKIP (มีอยู่แล้ว): %', p_label;
  when others           then raise notice 'SKIP (%): %', sqlerrm, p_label;
end$$;

-- ----------------------------------------------------------------------------
-- CHECK constraints (ค่าที่อนุญาต)
-- ----------------------------------------------------------------------------
select pg_temp.add_constraint_safe(
  $q$alter table public.items add constraint items_type_chk
     check (type in ('lesson','assignment','exam'))$q$, 'items.type');

select pg_temp.add_constraint_safe(
  $q$alter table public.attendance add constraint attendance_status_chk
     check (status in ('on_time','late','online','absent'))$q$, 'attendance.status');

select pg_temp.add_constraint_safe(
  $q$alter table public.exam_scores add constraint exam_scores_score_chk
     check (score >= 0)$q$, 'exam_scores.score >= 0');

select pg_temp.add_constraint_safe(
  $q$alter table public.items add constraint items_max_score_chk
     check (max_score is null or max_score >= 0)$q$, 'items.max_score >= 0');

-- ----------------------------------------------------------------------------
-- UNIQUE constraints (จำเป็นต่อ upsert onConflict ในโค้ด)
--   ใช้ unique index IF NOT EXISTS — ปลอดภัยถ้ามีอยู่แล้ว
-- ----------------------------------------------------------------------------
create unique index if not exists progress_student_item_uidx
  on public.progress (student_id, item_id);

create unique index if not exists attendance_student_subject_date_uidx
  on public.attendance (student_id, subject_id, attend_date);

create unique index if not exists enrollments_student_subject_uidx
  on public.enrollments (student_id, subject_id);

-- ----------------------------------------------------------------------------
-- Index ช่วย performance ของ query ที่ใช้บ่อย (กรอง student_id / soft-delete)
-- ----------------------------------------------------------------------------
create index if not exists submissions_student_idx  on public.submissions (student_id);
create index if not exists submissions_item_idx     on public.submissions (item_id);
create index if not exists exam_scores_student_idx   on public.exam_scores (student_id);
create index if not exists attendance_student_idx    on public.attendance (student_id);
create index if not exists progress_student_idx      on public.progress (student_id);

-- ============================================================================
-- จบ migration. ตรวจผลได้จาก NOTICE ที่ขึ้นระหว่างรัน
-- ============================================================================
