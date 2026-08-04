# TODO: Tính năng KHÓA HỒ SƠ (Read-Only)

## Các bước thực hiện:

- [x] 1. Thêm field `locked` vào data model trong `normalizeHoSoRecords()`
- [x] 2. Cập nhật `handleProgressSubmit()`: gán `locked = true` khi hoàn thành
- [x] 3. Cập nhật Progress Modal HTML: thêm banner khóa, đổi nút
- [x] 4. Cập nhật `openProgressModal()`: xử lý locked state
- [x] 5. Cập nhật `setupStepInput()`: thêm tham số locked
- [x] 6. Cập nhật `enforcePipelineConstraints()`: xử lý locked
- [x] 7. Cập nhật `renderTableRows()`: badge, docCode, actions
- [x] 8. Cập nhật `markAsReceivedFromModal()`: từ chối nếu locked
- [x] 9. Cập nhật `markAsReceived()`: từ chối nếu locked
- [x] 10. Cập nhật `deleteHoSo()`: từ chối nếu locked

