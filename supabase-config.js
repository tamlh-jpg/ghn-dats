// ============================================================
// SUPABASE CONFIGURATION - DATS
// ============================================================
// ⚠️ CẬP NHẬT 2 GIÁ TRỊ DƯỚI ĐÂY TRƯỚC KHI DEPLOY!
//
// Cách lấy:
// 1. Vào https://supabase.com → Sign in → Chọn project
// 2. Vào Settings → API
// 3. Copy "Project URL" vào SUPABASE_URL
// 4. Copy "anon public" key vào SUPABASE_ANON_KEY (⚠️ KHÔNG dùng service_role key!)
// ============================================================

const SUPABASE_URL = 'https://dlxdljidzvzbjpalhzhv.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRseGRsamlkenZ6YmpwYWxoemh2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4MzIxNDMsImV4cCI6MjEwMTQwODE0M30.KiCpL6BrtkeLfx9txUVQPU8qbotS1AWHKvzkUdMw2rI';

// ============================================================
// KHUYẾN NGHỊ KHÔNG SỬA PHẦN DƯỚI
// ============================================================

// Tạo Supabase client
const supabaseClient = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Kiểm tra cấu hình đã được điền chưa
function isSupabaseConfigured() {
  return SUPABASE_URL.includes('YOUR_PROJECT_REF') === false
    && SUPABASE_ANON_KEY.includes('YOUR_SUPABASE_ANON') === false;
}