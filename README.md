# GHN - Hệ thống Trình Ký Hồ Sơ Vận Hành (DATS)

Hệ thống nội bộ GHN để quản lý và theo dõi quy trình trình ký hồ sơ vận hành. Được xây dựng với **Supabase** (PostgreSQL + Auth + Realtime) và deploy trên **Vercel**.

---

## 🚀 HƯỚNG DẪN TRIỂN KHAI

### Bước 1: Tạo Supabase Project

1. Vào **https://supabase.com** → Đăng ký tài khoản (miễn phí)
2. Click **New Project**:
   - **Name**: `dats-ghn`
   - **Database Password**: Tạo mật khẩu mạnh (lưu lại!)
   - **Region**: Chọn **Southeast Asia (Singapore)** - gần VN nhất
   - **Pricing Plan**: Chọn **Free** ($0)
3. Đợi 2-3 phút cho project khởi tạo xong

### Bước 2: Tạo Database Schema

1. Trong Supabase Dashboard → **SQL Editor** → **New Query**
2. Copy toàn bộ nội dung file **`database-schema.sql`** trong repo này
3. Dán vào SQL Editor → click **Run**
4. Kiểm tra kết quả: 4 bảng `ho_so`, `ho_so_steps`, `admin_list`, `audit_logs` được tạo thành công

### Bước 3: Bật Google Authentication

1. Vào **Supabase Dashboard → Authentication → Providers → Google**
2. Click **Enable Google** và làm theo hướng dẫn:
   - Vào **Google Cloud Console** (https://console.cloud.google.com)
   - Tạo project (nếu chưa có)
   - Vào **APIs & Services → Credentials → Create Credentials → OAuth Client ID**
   - Application type: **Web Application**
   - Authorized redirect URIs: 
     ```
     https://[PROJECT_REF].supabase.co/auth/v1/callback
     ```
     (PROJECT_REF là mã trong URL Supabase, ví dụ: `abcdefghijklmnopqrst`)
   - Copy **Client ID** và **Client Secret** → dán lại vào Supabase
3. Click **Save**

### Bước 4: Cấu hình `supabase-config.js`

1. Mở file **`supabase-config.js`**
2. Vào **Supabase Dashboard → Settings → API**
3. Copy:
   - **Project URL** → dán vào `SUPABASE_URL`
   - **anon public** key → dán vào `SUPABASE_ANON_KEY`

```javascript
// Ví dụ sau khi điền:
const SUPABASE_URL = 'https://abcdefghijklmnopqrst.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3M...';
```

> ⚠️ **QUAN TRỌNG**: Chỉ dùng **anon public** key, KHÔNG dùng service_role key!

### Bước 5: Thêm GitHub Secrets

Vào **GitHub Repo → Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Giá trị | Mô tả |
|--------|---------|-------|
| `SUPABASE_PROJECT_REF` | `abcdefghijklmnopqrst` | Mã project trong URL Supabase |
| `SUPABASE_ANON_KEY` | `eyJhbGci...` | anon public key (giống trong supabase-config.js) |
| `SUPABASE_DB_URL` | `postgresql://postgres.abcdefghijklmnopqrst:PASSWORD@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres` | Connection string tới database |

Cách lấy `SUPABASE_DB_URL`:
1. **Supabase Dashboard → Project Settings → Database**
2. Tìm **Connection string** → copy dạng `postgresql://...`
3. Thay `[YOUR-PASSWORD]` bằng mật khẩu database bạn đã đặt ở Bước 1

### Bước 6: Deploy lên Vercel

**Cách 1: Deploy từ GitHub (khuyến nghị)**
1. Push code lên GitHub:
   ```bash
   git add .
   git commit -m "Initial deployment with Supabase"
   git push origin main
   ```

2. Vào **https://vercel.com** → **Add New Project** → Import repo này
3. Vercel sẽ tự động nhận diện và deploy

**Cách 2: Deploy trực tiếp bằng Vercel CLI**
```bash
npm install -g vercel
vercel --prod
```

### Bước 7: Kiểm tra hoạt động

1. Mở website đã deploy
2. Click **"Đăng nhập bằng Google"**
3. Chọn tài khoản **@ghn.vn**
4. Nếu là lần đầu, bạn sẽ được redirect sang Google để xác thực
5. Quay lại website → hệ thống tự động đăng nhập
6. Kiểm tra:
   - ✅ Đăng nhập thành công
   - ✅ Danh sách hồ sơ hiển thị (nếu có dữ liệu cũ, xem Bước 8)
   - ✅ Tạo hồ sơ mới hoạt động

### Bước 8: Cập nhật Database CŨ (Nếu đã chạy schema trước đó)

Nếu bạn đã chạy `database-schema.sql` ở phiên bản trước, hãy chạy thêm file **`database-migration.sql`** để cập nhật các tính năng mới:

1. Vào **Supabase Dashboard → SQL Editor → New Query**
2. Copy toàn bộ nội dung file **`database-migration.sql`** trong repo này
3. Dán vào SQL Editor → click **Run**
4. Script sẽ tự động:
   - ✅ Thêm UNIQUE constraint cho `stt` (chống trùng số thứ tự)
   - ✅ Tạo sequence cho STT tự động tăng
   - ✅ Thêm CHECK constraint đảm bảo dữ liệu nhất quán
   - ✅ Thêm UPDATE policy cho `admin_list`
   - ✅ Thêm policy cho BP VH tạo steps
   - ✅ Thêm index cho `ho_so_steps.status`
   - ✅ Tạo 4 RPC functions (transaction):
     - `add_ho_so_with_steps` - Thêm hồ sơ + steps trong 1 transaction
     - `update_ho_so_progress` - Cập nhật tiến độ + khóa hồ sơ trong 1 transaction
     - `delete_ho_so_and_reorder` - Xóa hồ sơ + sắp xếp lại STT trong 1 transaction
     - `mark_ho_so_received` - Xác nhận tiếp nhận hồ sơ

> ⚠️ Sau khi chạy migration, hãy deploy lại website để frontend dùng các RPC functions mới.

### Bước 9: Migrate dữ liệu cũ từ LocalStorage (nếu có)

**Chỉ dành cho Superadmin:**

1. Mở website trên **cùng trình duyệt đã có dữ liệu cũ** (nơi có `dats-hoso-v2` trong localStorage)
2. Đăng nhập bằng email superadmin (`tamlh@ghn.vn` đã được seed trong schema)
3. Thêm `?migrate=1` vào URL:
   ```
   https://your-site.vercel.app/?migrate=1
   ```
4. Hệ thống sẽ tự động chuyển toàn bộ dữ liệu từ localStorage lên Supabase
5. Xem thông báo thành công trong toast notification

---

## 📁 CẤU TRÚC FILE

| File | Mô tả |
|------|-------|
| `index.html` | Toàn bộ giao diện + logic (đã chuyển sang Supabase) |
| `supabase-config.js` | Cấu hình Supabase (điền URL + anon key) |
| `database-schema.sql` | Script tạo database mới (chạy 1 lần trong SQL Editor) |
| `database-migration.sql` | Script cập nhật database cũ lên phiên bản mới |
| `vercel.json` | Cấu hình deploy Vercel + security headers |
| `.github/workflows/keep-alive.yml` | Tự động ping mỗi 6h để Supabase Free không bị pause |
| `.github/workflows/daily-backup.yml` | Tự động backup database mỗi ngày |

---

## 🔒 TÍNH NĂNG BẢO MẬT

### Authentication
- ✅ **Google OAuth** - Chỉ tài khoản @ghn.vn mới đăng nhập được
- ✅ Không cần mật khẩu, dùng Google Workspace của công ty

### Authorization
- ✅ **Row Level Security (RLS)** - Database tự chặn người không có quyền
- ✅ **BP Vận hành**: Chỉ thấy hồ sơ của mình, chỉ tạo mới
- ✅ **Admin**: Thấy tất cả, duyệt, chỉnh sửa, xóa
- ✅ **Superadmin**: Quản lý danh sách admin

### Data Protection
- ✅ Dữ liệu lưu trên **Supabase Cloud** (không phải trình duyệt)
- ✅ **Backup tự động hàng ngày** qua GitHub Actions
- ✅ Không mất dữ liệu khi refresh, đổi máy, xóa trình duyệt
- ✅ **Realtime** - Admin duyệt xong, BP VH thấy ngay lập tức
- ✅ **Audit log** tự động ghi lại thao tác quan trọng

---

## 💰 CHI PHÍ

| Thành phần | Gói | Chi phí |
|-----------|-----|---------|
| Vercel | Hobby | $0 |
| Supabase | Free | $0 |
| GitHub Actions | Free (2000 phút/tháng) | $0 |
| **TỔNG** | | **$0/tháng** |

### Giới hạn gói Free:
- 500MB database (đủ cho ~100.000 hồ sơ sau tối ưu)
- 5GB băng thông/tháng
- 50.000 active users/tháng
- Project tự pause sau 7 ngày không hoạt động (đã có keep-alive tự động)

---

## ❓ KHẮC PHỤC SỰ CỐ

### Website báo "Supabase chưa được cấu hình"
→ Mở `supabase-config.js`, kiểm tra đã điền đúng `SUPABASE_URL` và `SUPABASE_ANON_KEY`

### Không đăng nhập được bằng Google
→ Kiểm tra:
1. Đã bật Google Provider trong Supabase Auth chưa?
2. Redirect URI đã đúng chưa? (`https://[ref].supabase.co/auth/v1/callback`)
3. Email có đuôi @ghn.vn không?

### Không thấy hồ sơ
→ Kiểm tra:
1. Đã chạy `database-schema.sql` chưa?
2. Đang đăng nhập bằng email đúng chưa? (BP VH chỉ thấy hồ sơ mình tạo)
3. Admin phải được thêm vào `admin_list` trước

### Mất kết nối realtime
→ Kiểm tra đã chạy `ALTER PUBLICATION supabase_realtime ADD TABLE ho_so;` trong schema chưa?

### Project Supabase bị pause
→ Vào Supabase Dashboard → Restore Project. Sau đó kiểm tra GitHub Actions keep-alive đã được cấu hình secrets chưa.

---

## 📞 HỖ TRỢ

- **Supabase Docs**: https://supabase.com/docs
- **Vercel Docs**: https://vercel.com/docs

---

© 2026 GiaoHangNhanh (GHN). DATS - Document Approval Tracking System.