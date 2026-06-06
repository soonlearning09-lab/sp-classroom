# SP-CLASSROOM — Database & Security

โฟลเดอร์นี้คือ "แหล่งความจริง" ของโครงสร้างฐานข้อมูลและกฎความปลอดภัย (RLS)
ของ Supabase project **SP-TRACKING** (`tscqakpzozrzkxtiwsrs`)

## ⚠️ เร่งด่วน — ทำไมต้อง apply migration นี้

ก่อนหน้านี้ฐานข้อมูล **ยังไม่ได้เปิด RLS** แปลว่า anon key (ซึ่งฝังอยู่ในโค้ดหน้าเว็บ
ที่เป็น public repo) สามารถ **อ่าน / แก้ / ลบ ข้อมูลนักเรียนทุกคนได้** ผ่าน Supabase API
โดยตรง โดยไม่ต้องผ่านหน้าแอป การเช็คสิทธิ์ `isAdmin` ในโค้ดเป็นแค่การซ่อนปุ่มฝั่งหน้าจอ
ซึ่ง bypass ได้ทันที **ห้ามเปิดใช้งานจริงกับข้อมูลนักเรียนจริงก่อน apply migration นี้**

---

## ไฟล์ในโฟลเดอร์

| ไฟล์ | หน้าที่ |
|------|---------|
| `migrations/20260606000001_security_rls.sql` | เปิด RLS ทุกตาราง + policy ตามสิทธิ์ + storage policy + trigger กันยกระดับสิทธิ์ |
| `migrations/20260606000002_constraints.sql` | CHECK / UNIQUE / index เสริมความถูกต้องของข้อมูล |
| `SCHEMA.md` | เอกสารโครงสร้างตาราง (อนุมานจากโค้ดแอป) |

---

## โมเดลสิทธิ์ (สรุป)

| Role | หลักสูตร | ข้อมูลนักเรียน | เกรด/เช็คชื่อ |
|------|----------|----------------|---------------|
| **admin** | อ่าน+เขียน | อ่าน+เขียนทุกคน | เขียนได้ |
| **viewer** | อ่าน | อ่านทุกคน | อ่าน |
| **student** | อ่าน | อ่าน+เขียนเฉพาะของตัวเอง (ติ๊กงาน/ส่งไฟล์) | อ่านเฉพาะของตัวเอง |
| **pending** | — | — (เห็นแค่ profile ตัวเอง) | — |

บังคับด้วย helper ฝั่ง DB: `is_admin()`, `is_staff()`, `is_approved()`, `current_student_id()`

---

## วิธี Apply

### ตัวเลือก A — Supabase SQL Editor (ง่ายสุด แนะนำสำหรับครั้งแรก)
1. เปิด https://supabase.com/dashboard/project/tscqakpzozrzkxtiwsrs/sql/new
2. คัดลอกเนื้อหา `migrations/20260606000001_security_rls.sql` ทั้งไฟล์ → วาง → **Run**
3. ทำซ้ำกับ `migrations/20260606000002_constraints.sql` (ดูข้อความ NOTICE ว่าอันไหน OK/SKIP)

### ตัวเลือก B — Supabase CLI (เก็บเป็น migration history)
```bash
# login แล้ว และ link project ไว้ (ทำครั้งเดียว — จะถามรหัสผ่าน DB)
supabase link --project-ref tscqakpzozrzkxtiwsrs
supabase db push        # apply ทุกไฟล์ใน migrations/
```
> หมายเหตุ: `db push` ต้องใช้รหัสผ่านฐานข้อมูล (ตั้งไว้ตอนสร้าง project)
> ดูได้ที่ Dashboard → Settings → Database → Connection string

---

## ✅ Verify checklist (ทดสอบหลัง apply)

### 1) ยืนยันว่า RLS เปิดครบ
รันใน SQL Editor:
```sql
select tablename, rowsecurity from pg_tables
where schemaname = 'public' order by tablename;
```
ทุกแถวต้อง `rowsecurity = true`

### 2) ทดสอบฝั่งแอป (สำคัญสุด — ต้องไม่ทำให้ฟังก์ชันเดิมพัง)
ล็อกอินด้วยแต่ละ role แล้วไล่ทุกหน้า:
- [ ] **admin**: เพิ่ม/แก้/ลบ วิชา·บท·หัวข้อ·รายการ ได้, จัดการนักเรียนได้, ติ๊กความคืบหน้า, บันทึกคะแนน, เช็คชื่อ, อนุมัติ user ได้
- [ ] **student**: เห็นเฉพาะข้อมูลตัวเอง, ติ๊กงาน/อัปโหลดไฟล์ของตัวเองได้, **แก้คะแนน/เช็คชื่อไม่ได้**, มองไม่เห็นข้อมูลคนอื่น
- [ ] **viewer**: ดูได้ทุกหน้า แต่กดแก้ไม่ได้
- [ ] **pending**: ค้างหน้า "รออนุมัติ"

### 3) ทดสอบความปลอดภัยจริง (พิสูจน์ว่า bypass ไม่ได้)
ล็อกอินเป็น **student** แล้วเปิด DevTools Console บนหน้าแอป รันคำสั่งนี้
(พยายามอ่านข้อมูลนักเรียนคนอื่นตรง ๆ ผ่าน Supabase client):
```js
// ควรได้ data = [] (อ่านได้แต่ของตัวเอง) ไม่ใช่ข้อมูลทุกคน
await sb.from('students').select('*').then(console.log)
// ลองแก้คะแนนคนอื่น — ควร error / 0 rows
await sb.from('exam_scores').insert({student_id:'<id-คนอื่น>', item_id:'x', score:100}).then(console.log)
```
ถ้ายังเห็นข้อมูลคนอื่นหรือแก้ได้ = policy ยังไม่ครอบคลุม ให้แจ้งกลับมาตรวจ

---

## 💾 Backup (อย่าข้าม)

1. **เปิด auto-backup ของ Supabase**
   Dashboard → Settings → Database → Backups
   - Free plan: มี daily backup เก็บ 7 วัน (เปิดให้อยู่แล้วบางกรณี — ตรวจสอบ)
   - Pro plan: เปิด **PITR (Point-in-Time Recovery)** ได้ แนะนำถ้าข้อมูลสำคัญ
2. **Export สำรองเองเป็นระยะ** (กันเหนียว):
   ```bash
   supabase db dump --linked -f backup_YYYYMMDD.sql            # โครงสร้าง
   supabase db dump --linked --data-only -f data_YYYYMMDD.sql  # ข้อมูล
   ```
   เก็บไฟล์ไว้นอก repo (อย่า commit ข้อมูลนักเรียนขึ้น public repo)

---

## หมายเหตุการพัฒนาต่อ

- โค้ดแอปฝั่ง client เดิม (`isAdmin` ฯลฯ) **ยังคงไว้ได้** — ใช้สำหรับ UX (ซ่อนปุ่ม)
  แต่ความปลอดภัยจริงอยู่ที่ RLS ชั้นนี้แล้ว
- ถ้าเพิ่มตาราง/คอลัมน์ใหม่ ต้องเขียน policy ให้ตารางนั้นด้วยทุกครั้ง
  (ตารางที่เปิด RLS แต่ไม่มี policy = ไม่มีใครเข้าถึงได้เลย ยกเว้น service_role)
