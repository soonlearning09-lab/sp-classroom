# SP - CLASSROOM

PWA ระบบติดตามผลการเรียน · Vanilla JS + Vite + Supabase
Live: https://soonlearning09-lab.github.io/sp-classroom/

---

## 🚀 เริ่มพัฒนา

```bash
npm install          # ติดตั้ง dependencies (ครั้งแรก)
npm run dev          # dev server (hot reload) → http://localhost:5173/sp-classroom/
npm run build        # build เป็น dist/
npm run preview      # ดู build จริงก่อน deploy → http://localhost:4173/sp-classroom/
```

ต้องมีไฟล์ `.env` (คัดลอกจาก `.env.example`) ใส่ค่า Supabase:
```
VITE_SUPABASE_URL=https://tscqakpzozrzkxtiwsrs.supabase.co
VITE_SUPABASE_ANON_KEY=<anon key>
```

## 📁 โครงสร้าง

```
index.html              # HTML shell (head + body markup + <script module>)
src/
  main.js               # โค้ดแอปทั้งหมด (ฟังก์ชัน + state + init)
  style.css             # CSS ทั้งหมด
public/                 # ไฟล์ที่ copy ตรง ๆ ไป dist (ไม่ผ่าน hash)
  manifest.json · icon.svg · service-worker.js
supabase/               # ⭐ ความปลอดภัยข้อมูล — ดู supabase/README.md
  migrations/*.sql · SCHEMA.md · README.md
.github/workflows/deploy.yml   # CI/CD → GitHub Pages
vite.config.js          # base = '/sp-classroom/' (สำคัญ!)
```

> หมายเหตุสถาปัตยกรรม: ฟังก์ชันทั้งหมดอยู่ใน `src/main.js` และถูก expose ขึ้น `window`
> (ก้อน `Object.assign(window, {...})` ท้ายไฟล์) เพื่อให้ inline `onclick=""` ที่ generate
> จาก template string ทำงานได้ — ตั้งใจคงรูปแบบเดิมไว้เพื่อความเสี่ยงต่ำ

---

## ✅ สิ่งที่ต้องทำเพื่อให้ใช้งานจริงได้ (Action items)

### 1. 🔴 ความปลอดภัยข้อมูล — ทำก่อนเปิดใช้จริง (สำคัญสุด)
ฐานข้อมูลยังไม่เปิด RLS → ตอนนี้ใครก็แก้/ลบข้อมูลได้ผ่าน API ตรง
👉 ทำตาม **`supabase/README.md`** (apply migration 2 ไฟล์ + verify + เปิด backup)

### 2. ตั้งค่า deploy (ครั้งเดียว)
- GitHub repo → **Settings → Pages → Source** เปลี่ยนเป็น **"GitHub Actions"**
  (จากเดิม "Deploy from a branch")
- GitHub repo → **Settings → Secrets and variables → Actions** เพิ่ม 2 secrets:
  - `VITE_SUPABASE_URL`
  - `VITE_SUPABASE_ANON_KEY`
- หลังจากนั้นทุก push ขึ้น `main` จะ build + deploy อัตโนมัติผ่าน workflow

### 3. ทดสอบในเบราว์เซอร์จริง (หลัง apply RLS)
รัน `npm run preview` แล้วล็อกอินด้วยแต่ละ role ไล่ทุกหน้า
ตาม checklist ใน `supabase/README.md` (admin / student / viewer / pending)

---

## 📌 หมายเหตุ
- `.env` ไม่ถูก commit (อยู่ใน .gitignore) — ค่า anon key เปิดเผยได้แต่ไม่ควร hardcode
- service worker cache version อยู่ที่ `public/service-worker.js` (`sp-classroom-v11`)
  bump เลขเมื่อ deploy ใหญ่ ๆ ที่อยากบังคับ client โหลดใหม่ (ปกติ Vite hash จัดการให้แล้ว)
