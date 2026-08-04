-- ============================================================
-- DATS - DATABASE MIGRATION (CHO DATABASE ĐÃ TỒN TẠI)
-- ============================================================
-- Chạy script này trong: Supabase Dashboard → SQL Editor → New Query
-- Script này SỬA các rủi ro đã xác định trong đánh giá
-- ============================================================

-- ========== 1. THÊM UNIQUE CONSTRAINT CHO STT ==========
-- Chống trùng số thứ tự khi nhiều người cùng thêm hồ sơ
DO $$
BEGIN
  -- Xóa constraint cũ nếu tồn tại để tránh lỗi duplicate
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'unique_stt') THEN
    ALTER TABLE ho_so DROP CONSTRAINT unique_stt;
  END IF;
  -- Kiểm tra dữ liệu trùng trước
  IF EXISTS (
    SELECT stt FROM ho_so 
    GROUP BY stt HAVING COUNT(*) > 1
  ) THEN
    RAISE NOTICE 'Có dữ liệu STT trùng. Sẽ tự sửa trước khi thêm constraint...';
    -- Sửa trùng bằng cách gán lại STT theo thứ tự ngày tạo
    WITH numbered AS (
      SELECT id, ROW_NUMBER() OVER (ORDER BY created_at, id) AS new_stt
      FROM ho_so
    )
    UPDATE ho_so h SET stt = n.new_stt
    FROM numbered n WHERE h.id = n.id;
  END IF;
END $$;

ALTER TABLE ho_so ADD CONSTRAINT unique_stt UNIQUE (stt);

-- ========== 2. TẠO SEQUENCE CHO STT ==========
-- Đảm bảo STT tăng tự động, không bị trùng
CREATE SEQUENCE IF NOT EXISTS ho_so_stt_seq;

-- Đồng bộ sequence với dữ liệu hiện tại
SELECT setval('ho_so_stt_seq', COALESCE(MAX(stt), 0) + 1, false) FROM ho_so;

-- Gán DEFAULT cho cột stt dùng sequence
ALTER TABLE ho_so ALTER COLUMN stt SET DEFAULT nextval('ho_so_stt_seq');

-- ========== 3. THÊM CHECK CONSTRAINT: ADMIN_RECEIVED CONSISTENCY ==========
-- Đảm bảo nếu admin_received = TRUE thì phải có ngày nhận
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_admin_received') THEN
    ALTER TABLE ho_so ADD CONSTRAINT chk_admin_received 
      CHECK ((admin_received = FALSE) OR (admin_received_date IS NOT NULL));
  END IF;
END $$;

-- ========== 4. THÊM CHECK CONSTRAINT: LOCKED ⇒ DONE ==========
-- Đảm bảo nếu hồ sơ locked thì trạng thái phải là Done
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_locked_done') THEN
    -- Sửa dữ liệu cũ không hợp lệ trước
    UPDATE ho_so SET trang_thai = 'Done - Khóa tự động' 
    WHERE locked = TRUE AND trang_thai NOT LIKE 'Done%';
    
    ALTER TABLE ho_so ADD CONSTRAINT chk_locked_done 
      CHECK ((locked = FALSE) OR (trang_thai LIKE 'Done%'));
  END IF;
END $$;

-- ========== 5. THÊM UPDATE POLICY CHO ADMIN_LIST ==========
-- Cho phép Superadmin sửa thông tin admin (tên, quyền)
DROP POLICY IF EXISTS "superadmin_sua_admin" ON admin_list;
CREATE POLICY "superadmin_sua_admin" ON admin_list
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM admin_list 
      WHERE email = auth.jwt() ->> 'email' 
      AND is_super_admin = TRUE
    )
  );

-- ========== 6. THÊM POLICY: BP VH TẠO STEPS CHO HỒ SƠ CỦA MÌNH ==========
-- Cho phép BP VH tạo 4 steps mặc định khi tạo hồ sơ mới
DROP POLICY IF EXISTS "bpvh_tao_steps" ON ho_so_steps;
CREATE POLICY "bpvh_tao_steps" ON ho_so_steps
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM ho_so 
      WHERE ho_so.id = ho_so_steps.ho_so_id
      AND ho_so.nguoi_gui_email = auth.jwt() ->> 'email'
    )
  );

-- ========== 7. THÊM INDEX CHO HO_SO_STEPS.STATUS ==========
-- Tăng tốc query lọc theo trạng thái
CREATE INDEX IF NOT EXISTS idx_steps_status ON ho_so_steps(status);

-- ========== 8. TẠO RPC FUNCTION: THÊM HỒ SƠ + STEPS (TRANSACTION) ==========
-- Giải quyết:
--   - Race condition STT (dùng sequence atomic)
--   - Dữ liệu mồ côi khi insert steps thất bại (transaction đảm bảo atomic)
--   - Toàn bộ thao tác chạy trong 1 transaction
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

-- ========== 9. TẠO RPC FUNCTION: CẬP NHẬT TIẾN ĐỘ + KHÓA HỒ SƠ (TRANSACTION) ==========
-- Giải quyết: Cập nhật steps + ho_so trong 1 transaction để tránh dữ liệu không nhất quán
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

-- ========== 10. TẠO RPC FUNCTION: XÓA HỒ SƠ VÀ SẮP XẾP LẠI STT (TRANSACTION) ==========
-- Giải quyết: Xóa hồ sơ + cập nhật STT trong 1 transaction
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

-- ========== 11. TẠO RPC FUNCTION: NHẬN HỒ SƠ (ADMIN RECEIVED) ==========
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

-- ========== 12. XÓA RPC CŨ (NẾU CÓ) VÀ DROP CÁC POLICY TRÙNG ==========
-- Đảm bảo không có policy trùng lặp gây lỗi
-- LƯU Ý: KHÔNG drop policy "bpvh_tao_ho_so" - policy này cần thiết để BP VH tạo hồ sơ mới

-- ========== XONG ==========
-- Sau khi chạy script này, hãy cập nhật index.html theo hướng dẫn trong README.