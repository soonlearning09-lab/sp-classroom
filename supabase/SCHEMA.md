# SP-CLASSROOM — Schema Reference

> ⚠️ เอกสารนี้ **อนุมานจากการอ่านโค้ดแอป** (insert/update/select ทุกจุดใน `index.html`)
> ไม่ได้ dump จากฐานข้อมูลจริง — ชนิดข้อมูล (type) เป็นการคาดการณ์ที่สมเหตุสมผล
> โครงสร้างที่แน่นอนให้ยึดจาก Supabase Dashboard → Table Editor
> ถ้าต้องการ snapshot จริง: `supabase db dump --linked -f schema.sql`

## ลำดับชั้นหลักสูตร
```
subjects (วิชา)
  └─ chapters (บท)        chapters.subject_id → subjects.id
       └─ topics (หัวข้อ)   topics.chapter_id  → chapters.id
            └─ items (รายการ: บทเรียน/งาน/สอบ)  items.topic_id → topics.id

tracks (คอร์ส/แทร็ก)  ──  students.track_id → tracks.id
```

## ตาราง

### profiles  — บัญชีผู้ใช้ (1:1 กับ auth.users)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | = auth.users.id |
| email | text | |
| display_name | text | ตั้งตอน register |
| role | text | `pending` \| `student` \| `viewer` \| `admin` |
| approved | boolean | admin อนุมัติแล้วหรือยัง |
| student_id | uuid FK→students.id | ผูกเมื่อ role=student |

### students — นักเรียน
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| nickname | text | ชื่อเล่น |
| grade | text | ชั้น (ค่าอิสระ) |
| track_id | uuid FK→tracks.id | ไม่บังคับ |
| note | text | หมายเหตุ |
| deleted_at | timestamptz | soft-delete |
| created_at | timestamptz | |

### subjects — วิชา
`id` uuid PK · `name` text · `icon` text · `color` text · `order_index` int

### tracks — คอร์ส
`id` uuid PK · `name` text · `description` text · `deleted_at` timestamptz · `created_at` timestamptz

### chapters — บท
`id` uuid PK · `name` text · `subject_id` uuid FK→subjects · `order_index` int · `deleted_at` timestamptz

### topics — หัวข้อ
`id` uuid PK · `name` text · `chapter_id` uuid FK→chapters · `order_index` int · `deleted_at` timestamptz

### items — รายการเรียน (บทเรียน/งาน/สอบ)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| topic_id | uuid FK→topics.id | |
| type | text | `lesson` \| `assignment` \| `exam` |
| title | text | |
| order_index | int | |
| deadline | timestamptz | เฉพาะ assignment |
| max_score | numeric | เฉพาะ exam |
| url | text | YouTube (lesson) / Google Form (exam) |
| deleted_at | timestamptz | |
| created_at | timestamptz | |

### enrollments — การลงทะเบียนวิชา
`id` uuid PK · `student_id` uuid FK→students · `subject_id` uuid FK→subjects
🔑 unique(student_id, subject_id)

### progress — ความคืบหน้า (ติ๊กงาน/บทเรียน)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| student_id | uuid FK→students | |
| item_id | uuid FK→items | |
| completed | boolean | |
| submitted_at | timestamptz | เวลาที่ติ๊กเสร็จ |
| updated_by | uuid FK→auth.users | |
| updated_at | timestamptz | |

🔑 unique(student_id, item_id) — ใช้กับ upsert

### submissions — ไฟล์ที่ส่ง (คู่กับ Storage bucket `submissions`)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| item_id | uuid FK→items | |
| student_id | uuid FK→students | |
| file_path | text | path ใน storage = `{itemId}/{studentId}/{ts}-{name}` |
| file_name | text | |
| file_size | bigint | |
| mime_type | text | |
| uploaded_at | timestamptz | |

### exam_scores — คะแนนสอบ (หลายครั้งต่อ item ได้)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| student_id | uuid FK→students | |
| item_id | uuid FK→items | |
| score | numeric | ≥ 0 |
| attempt_no | int | ครั้งที่สอบ |
| exam_date | date | |
| note | text | |
| updated_by | uuid FK→auth.users | |

### attendance — เช็คชื่อ (ต่อ วิชา-วัน)
| column | type | หมายเหตุ |
|--------|------|----------|
| id | uuid PK | |
| student_id | uuid FK→students | |
| subject_id | uuid FK→subjects | |
| attend_date | date | |
| status | text | `on_time` \| `late` \| `online` \| `absent` |
| updated_by | uuid FK→auth.users | |
| updated_at | timestamptz | |

🔑 unique(student_id, subject_id, attend_date) — ใช้กับ upsert

## Storage
- bucket **`submissions`** — ไฟล์งานนักเรียน
  path = `{itemId}/{studentId}/{timestamp}-{safeName}`
  → segment ที่ 2 ของ path คือ `studentId` (ใช้ใน storage RLS policy)
