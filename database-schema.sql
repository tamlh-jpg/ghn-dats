-- ============================================================
-- DATS - DATABASE SCHEMA FOR SUPABASE (FREE TIER OPTIMIZED)
-- ============================================================
-- Run this script in: Supabase Dashboard → SQL Editor → New Query
-- ============================================================

-- ========== 0. SEQUENCE CHO STT (CHỐNG TRÙNG SỐ THỨ TỰ) ==========
CREATE SEQUENCE IF NOT EXISTS ho_so_stt_seq;

-- ========== 1. BẢNG HỒ SƠ ==========
CREATE TABLE IF NOT EXISTS ho_so (
  id BIGSERIAL PRIMARY KEY,
  stt INTEGER NOT NULL DEFAULT nextval('ho_so_stt_seq'),
  loai_hs TEXT NOT NULL CHECK (loai_hs IN ('Hợp Đồng', 'Phụ Lục', 'BBTL')),
  vung TEXT NOT NULL,
  tinh TEXT NOT NULL,
  nguoi_gui TEXT NOT NULL,
  nguoi_gui_email TEXT NOT NULL,
  ncc TEXT NOT NULL,
  noi_dung TEXT NOT NULL,
  ngay_nhan DATE NOT NULL,
  doc_code TEXT DEFAULT '',
  trang_thai TEXT DEFAULT 'In Progress',
  admin_received BOOLEAN DEFAULT FALSE,
  admin_received_date DATE,
  admin_received_time TEXT,
  locked BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  -- Ràng buộc dữ liệu nhất quán
  CONSTRAINT unique_stt UNIQUE (stt),
  CONSTRAINT chk_admin_received CHECK ((admin_received = FALSE) OR (admin_received_date IS NOT NULL)),
  CONSTRAINT chk_locked_done CHECK ((locked = FALSE) OR (trang_thai LIKE 'Done%'))
);

-- ========== 2. BẢNG TIẾN TRÌNH DUYỆT ==========
CREATE TABLE IF NOT EXISTS ho_so_steps (
  id BIGSERIAL PRIMARY KEY,
  ho_so_id BIGINT REFERENCES ho_so(id) ON DELETE CASCADE,
  step_num INTEGER NOT NULL CHECK (step_num IN (1, 2, 3, 4)),
  step_label TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'Pending',
  date DATE,
  reason TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(ho_so_id, step_num)
);

-- ========== 3. BẢNG DANH SÁCH ADMIN ==========
CREATE TABLE IF NOT EXISTS admin_list (
  id BIGSERIAL PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  is_super_admin BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ========== 4. BẢNG AUDIT LOG (chỉ log thao tác quan trọng) ==========
CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_email TEXT NOT NULL,
  user_name TEXT NOT NULL,
  action TEXT NOT NULL,
  ho_so_id BIGINT,
  details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ========== 5. TRIGGER: TỰ CẬP NHẬT UPDATED_AT ==========
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_ho_so_updated_at
BEFORE UPDATE ON ho_so
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_steps_updated_at
BEFORE UPDATE ON ho_so_steps
FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ========== 6. TRIGGER: AUDIT LOG ==========
CREATE OR REPLACE FUNCTION log_audit()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO audit_logs (user_email, user_name, action, ho_so_id, details)
  VALUES (
    COALESCE(auth.jwt() ->> 'email', 'system'),
    COALESCE(auth.jwt() ->> 'full_name', COALESCE(auth.jwt() ->> 'name', 'system')),
    TG_OP,
    COALESCE(NEW.id, OLD.id),
    jsonb_build_object(
      'old', CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
      'new', CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END
    )
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Chỉ log khi: Hoàn thành khóa hồ sơ, Xóa hồ sơ, hoặc thêm/xóa admin
CREATE TRIGGER trg_log_ho_so_complete
AFTER UPDATE ON ho_so
FOR EACH ROW
WHEN (NEW.locked = TRUE AND OLD.locked = FALSE)
EXECUTE FUNCTION log_audit();

CREATE TRIGGER trg_log_ho_so_delete
AFTER DELETE ON ho_so
FOR EACH ROW
EXECUTE FUNCTION log_audit();

CREATE TRIGGER trg_log_admin_insert
AFTER INSERT ON admin_list
FOR EACH ROW
EXECUTE FUNCTION log_audit();

CREATE TRIGGER trg_log_admin_delete
AFTER DELETE ON admin_list
FOR EACH ROW
EXECUTE FUNCTION log_audit();

-- ========== 7. ROW LEVEL SECURITY (RLS) ==========

-- Bật RLS
ALTER TABLE ho_so ENABLE ROW LEVEL SECURITY;
ALTER TABLE ho_so_steps ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_list ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- POLICY: admin_list - chỉ cho phép đọc (frontend đọc để check role)
CREATE POLICY "doc_admin_list" ON admin_list
  FOR SELECT USING (true);

-- POLICY: admin_list - chỉ SUPERADMIN mới ghi
CREATE POLICY "superadmin_ghi_admin" ON admin_list
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_list 
      WHERE email = auth.jwt() ->> 'email' 
      AND is_super_admin = TRUE
    )
  );

CREATE POLICY "superadmin_sua_admin" ON admin_list
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM admin_list 
      WHERE email = auth.jwt() ->> 'email' 
      AND is_super_admin = TRUE
    )
  );

CREATE POLICY "superadmin_xoa_admin" ON admin_list
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM admin_list 
      WHERE email = auth.jwt() ->> 'email' 
      AND is_super_admin = TRUE
    )
  );

-- POLICY: ho_so - Admin xem tất cả, BP VH chỉ xem hồ sơ mình tạo
CREATE POLICY "admin_xem_tat_ca_ho_so" ON ho_so
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

CREATE POLICY "bpvh_xem_ho_so_cua_minh" ON ho_so
  FOR SELECT USING (
    nguoi_gui_email = auth.jwt() ->> 'email'
  );

-- POLICY: ho_so - Admin INSERT/UPDATE/DELETE
CREATE POLICY "admin_ghi_ho_so" ON ho_so
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

CREATE POLICY "admin_sua_ho_so" ON ho_so
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

CREATE POLICY "admin_xoa_ho_so" ON ho_so
  FOR DELETE USING (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

-- POLICY: ho_so - BP VH chỉ được tạo hồ sơ mới (không sửa/xóa)
CREATE POLICY "bpvh_tao_ho_so" ON ho_so
  FOR INSERT WITH CHECK (
    nguoi_gui_email = auth.jwt() ->> 'email'
  );

-- POLICY: ho_so_steps - Admin thao tác, BP VH đọc
CREATE POLICY "admin_ghi_steps" ON ho_so_steps
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

CREATE POLICY "doc_ho_so_steps" ON ho_so_steps
  FOR SELECT USING (true);

-- POLICY: ho_so_steps - BP VH được tạo steps cho hồ sơ của mình
CREATE POLICY "bpvh_tao_steps" ON ho_so_steps
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM ho_so 
      WHERE ho_so.id = ho_so_steps.ho_so_id
      AND ho_so.nguoi_gui_email = auth.jwt() ->> 'email'
    )
  );

-- POLICY: audit_logs - Admin mới đọc được
CREATE POLICY "admin_doc_audit" ON audit_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM admin_list WHERE email = auth.jwt() ->> 'email'
    )
  );

-- ========== 8. SEED: SUPERADMIN MẶC ĐỊNH ==========
-- Thay 'tamlh@ghn.vn' bằng email superadmin thật của công ty
INSERT INTO admin_list (email, name, is_super_admin)
VALUES ('tamlh@ghn.vn', 'Tâm LH (Quản trị viên)', TRUE)
ON CONFLICT (email) DO NOTHING;

-- ========== 9. REALTIME ==========
ALTER PUBLICATION supabase_realtime ADD TABLE ho_so;
ALTER PUBLICATION supabase_realtime ADD TABLE ho_so_steps;

-- ========== 10. CHẶN EMAIL KHÔNG PHẢI @GHN.VN ==========
-- Lưu ý: Toàn bộ logic auth sẽ handle ở frontend + RLS
-- Email domain check đã được đảm bảo bởi:
--   1. Supabase Auth sẽ lấy email từ Google OAuth
--   2. Frontend kiểm tra email endsWith('@ghn.vn') trước khi cho truy cập
--   3. RLS chỉ cho phép user có email trong admin_list làm admin

-- ========== 11. INDEX CHO HIỆU SUẤT (50K-100K records) ==========
CREATE INDEX IF NOT EXISTS idx_ho_so_nguoi_gui ON ho_so(nguoi_gui_email);
CREATE INDEX IF NOT EXISTS idx_ho_so_tinh ON ho_so(tinh);
CREATE INDEX IF NOT EXISTS idx_ho_so_vung ON ho_so(vung);
CREATE INDEX IF NOT EXISTS idx_ho_so_loai ON ho_so(loai_hs);
CREATE INDEX IF NOT EXISTS idx_ho_so_ngay_nhan ON ho_so(ngay_nhan);
CREATE INDEX IF NOT EXISTS idx_ho_so_locked ON ho_so(locked);
CREATE INDEX IF NOT EXISTS idx_steps_ho_so_id ON ho_so_steps(ho_so_id);
CREATE INDEX IF NOT EXISTS idx_steps_status ON ho_so_steps(status);
CREATE INDEX IF NOT EXISTS idx_audit_created_at ON audit_logs(created_at);

-- ========== 12. RPC FUNCTION: THÊM HỒ SƠ + STEPS (TRANSACTION) ==========
-- Giải quyết: Race condition STT + Dữ liệu mồ côi khi insert steps thất bại
CREATE OR REPLACE FUNCTION add_ho_so_with_steps(
  p_loai_hs TEXT,
  p_vung TEXT,
  p_tinh TEXT,
  p_nguoi_gui TEXT,
  p_nguoi_gui_email TEXT,
  p_ncc TEXT,
  p_noi_dung TEXT,
  p_ngay_nhan DATE,
  p_doc_code TEXT,
  p_trang_thai TEXT DEFAULT 'In Progress',
  p_admin_received BOOLEAN DEFAULT FALSE,
  p_admin_received_date DATE DEFAULT NULL,
  p_admin_received_time TEXT DEFAULT NULL,
  p_locked BOOLEAN DEFAULT FALSE,
  p_steps JSONB DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_ho_so_id BIGINT;
  v_stt INTEGER;
  v_step JSONB;
BEGIN
  -- Lấy STT từ sequence (atomic, không bị race condition)
  v_stt := nextval('ho_so_stt_seq');
  
  -- Insert hồ sơ
  INSERT INTO ho_so (
    stt, loai_hs, vung, tinh, nguoi_gui, nguoi_gui_email,
    ncc, noi_dung, ngay_nhan, doc_code, trang_thai, admin_received,
    admin_received_date, admin_received_time, locked
  ) VALUES (
    v_stt, p_loai_hs, p_vung, p_tinh, p_nguoi_gui, p_nguoi_gui_email,
    p_ncc, p_noi_dung, p_ngay_nhan, p_doc_code, p_trang_thai, p_admin_received,
    p_admin_received_date, p_admin_received_time, p_locked
  ) RETURNING id INTO v_ho_so_id;

  -- Nếu có steps data, dùng steps đó; ngược lại tạo steps mặc định
  IF p_steps IS NOT NULL AND jsonb_array_length(p_steps) > 0 THEN
    FOR v_step IN SELECT * FROM jsonb_array_elements(p_steps)
    LOOP
      INSERT INTO ho_so_steps (ho_so_id, step_num, step_label, status, date, reason)
      VALUES (
        v_ho_so_id,
        (v_step->>'step_num')::INTEGER,
        v_step->>'step_label',
        COALESCE(v_step->>'status', 'Pending'),
        (v_step->>'date')::DATE,
        v_step->>'reason'
      );
    END LOOP;
  ELSE
    INSERT INTO ho_so_steps (ho_so_id, step_num, step_label, status, date, reason) VALUES
      (v_ho_so_id, 1, 'BP Mặt bằng', 'Pending', NULL, NULL),
      (v_ho_so_id, 2, 'BP Kế toán', 'Pending', NULL, NULL),
      (v_ho_so_id, 3, 'BP Pháp lý', 'Pending', NULL, NULL),
      (v_ho_so_id, 4, 'COO', 'Pending', NULL, NULL);
  END IF;

  RETURN jsonb_build_object('success', TRUE, 'id', v_ho_so_id, 'stt', v_stt);
END;
$$;

-- ========== 13. RPC FUNCTION: CẬP NHẬT TIẾN ĐỘ + KHÓA HỒ SƠ (TRANSACTION) ==========
CREATE OR REPLACE FUNCTION update_ho_so_progress(
  p_ho_so_id BIGINT,
  p_steps JSONB,
  p_doc_code TEXT DEFAULT NULL,
  p_locked BOOLEAN DEFAULT FALSE,
  p_trang_thai TEXT DEFAULT 'In Progress'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_step JSONB;
BEGIN
  -- Kiểm tra hồ sơ tồn tại
  IF NOT EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Không tìm thấy hồ sơ');
  END IF;

  -- Kiểm tra hồ sơ không bị khóa
  IF EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id AND locked = TRUE) AND NOT p_locked THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Hồ sơ đã bị khóa, không thể sửa');
  END IF;

  -- Cập nhật từng step
  FOR v_step IN SELECT * FROM jsonb_array_elements(p_steps)
  LOOP
    UPDATE ho_so_steps
    SET status = COALESCE(v_step->>'status', 'Pending'),
        date = (v_step->>'date')::DATE,
        reason = v_step->>'reason',
        updated_at = NOW()
    WHERE ho_so_id = p_ho_so_id
      AND step_num = (v_step->>'step_num')::INTEGER;
  END LOOP;

  -- Cập nhật ho_so
  UPDATE ho_so
  SET doc_code = COALESCE(p_doc_code, doc_code),
      trang_thai = p_trang_thai,
      locked = p_locked,
      updated_at = NOW()
  WHERE id = p_ho_so_id;

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

-- ========== 14. RPC FUNCTION: XÓA HỒ SƠ VÀ SẮP XẾP LẠI STT (TRANSACTION) ==========
CREATE OR REPLACE FUNCTION delete_ho_so_and_reorder(
  p_ho_so_id BIGINT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_deleted_id BIGINT;
BEGIN
  -- Kiểm tra hồ sơ tồn tại
  IF NOT EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Không tìm thấy hồ sơ');
  END IF;

  -- Kiểm tra không xóa hồ sơ đã khóa
  IF EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id AND locked = TRUE) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Không thể xóa hồ sơ đã khóa');
  END IF;

  -- Xóa hồ sơ (steps tự xóa theo CASCADE)
  DELETE FROM ho_so WHERE id = p_ho_so_id RETURNING id INTO v_deleted_id;

  -- Sắp xếp lại STT
  WITH numbered AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY stt, id) AS new_stt
    FROM ho_so
  )
  UPDATE ho_so h SET stt = n.new_stt
  FROM numbered n WHERE h.id = n.id;

  -- Cập nhật sequence để không trùng với STT mới nhất
  PERFORM setval('ho_so_stt_seq', COALESCE((SELECT MAX(stt) FROM ho_so), 0) + 1, false);

  RETURN jsonb_build_object('success', TRUE, 'deleted_id', v_deleted_id);
END;
$$;

-- ========== 15. RPC FUNCTION: NHẬN HỒ SƠ (ADMIN RECEIVED) ==========
CREATE OR REPLACE FUNCTION mark_ho_so_received(
  p_ho_so_id BIGINT,
  p_receive_date DATE,
  p_receive_time TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  -- Kiểm tra hồ sơ tồn tại
  IF NOT EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Không tìm thấy hồ sơ');
  END IF;

  -- Kiểm tra không nhận hồ sơ đã khóa
  IF EXISTS (SELECT 1 FROM ho_so WHERE id = p_ho_so_id AND locked = TRUE) THEN
    RETURN jsonb_build_object('success', FALSE, 'error', 'Hồ sơ đã bị khóa');
  END IF;

  UPDATE ho_so
  SET admin_received = TRUE,
      admin_received_date = p_receive_date,
      admin_received_time = p_receive_time,
      updated_at = NOW()
  WHERE id = p_ho_so_id;

  RETURN jsonb_build_object('success', TRUE);
END;
$$;
