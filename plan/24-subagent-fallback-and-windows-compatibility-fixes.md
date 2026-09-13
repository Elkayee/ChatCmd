# Plan 24 — Sửa lỗi Subagent Fallback HTTP 405 và Hoàn thiện Tương thích Windows

## 1. Mục đích

Khắc phục các lỗi thực tế được phát hiện qua audit runtime và adversarial harness của ChatCMD trên Windows:
1. Sửa lỗi HTTP 405 khiến tính năng Subagent bị fail khi giao tiếp giữa ChatGPT Extension và Server.
2. Sửa lỗi định dạng xuống dòng CRLF cho file SQL migration.
3. Tương thích hóa các bài kiểm thử đối kháng filesystem và Git trên Windows (mtime resolution, index lock, commit scope).

## 2. Các hạng mục công việc chi tiết

### Hạng mục 1: Subagent HTTP 405 Method Not Allowed (ĐÃ HOÀN THÀNH)
- Kiểm tra toàn bộ các lời gọi `postJson` / `getJson` trong `chatgpt-extension/background-io.js` và `chatgpt-extension/background.js`:
  - `/api/local/subagents/{id}/fallback/started` (POST)
  - `/api/local/subagents/{id}/fallback/heartbeat` (POST)
  - `/api/local/subagents/{id}/fallback/result` (POST)
  - `/api/local/subagents/fallback/pending` (GET)
- **Điểm nghẽn xác định**:
  1. Trong `src/api/auth.rs`: Hàm `extension_route_allowed` thiếu nhánh `(&Method::GET, ["subagents", "fallback", "pending"]) => true`.
  2. Rủi ro trượt tiền tố: Khi Axum Router lồng `.nest("/local", ...)` bóc tách path, URL có thể mất `/api/local` hoặc `OriginalUri` không đồng bộ, làm `parts` lệch cấu trúc.
- **Giải pháp kỹ thuật đã áp dụng**:
  1. Trong `src/api/auth.rs`: Chuẩn hóa `parts` bằng cách loại bỏ tiền tố `api/local` (hoặc `api`, `local`) trước khi pattern matching.
  2. Bổ sung matcher `(&Method::GET, ["subagents", "fallback", "pending"]) => true` và giữ nguyên matcher POST cho `["subagents", _, "fallback", action]`.
  3. Bổ sung test case trong `src/api/chatgpt_router_tests.rs` xác thực `GET /api/local/subagents/fallback/pending` trả về `StatusCode::OK` với client header `chatgpt-extension`.
  4. Xác thực test: `cargo test -p chat-cmd-client extension_approval_and_subagent_routes_survive_nesting` $\rightarrow$ `ok. 1 passed; 0 failed`.

### Hạng mục 2: SQL Migration LF Normalization (ĐÃ HOÀN THÀNH)
- Chuẩn hóa toàn bộ các file `crates/chatcmd-storage/migrations/*.sql` (từ 0001 đến 0014) thành thuần byte LF (`\n`).
- Cấu hình `.gitattributes`:
  ```gitattributes
  crates/chatcmd-storage/migrations/*.sql text eol=lf
  ```
- Xác thực test: `cargo test -p chatcmd-storage` $\rightarrow$ `ok. 30 passed; 0 failed`. Kiểm thử `checked_in_migrations_use_stable_lf_line_endings` đạt `ok`.

### Hạng mục 3: Windows Filesystem & Git Test Compatibility
- Điều chỉnh `crates/chatcmd-runtime/tests/adversarial_filesystem.rs`:
  - Với Windows NTFS, bổ sung cơ chế kiểm tra chống trùng lặp mtime hoặc dùng Content Hash version.
- Điều chỉnh `crates/chatcmd-runtime/tests/adversarial_filesystem/git_cases.rs`:
  - Cho phép pha lỗi là `"staging"` hoặc `"commitHooksIncluded"`.
- Điều chỉnh `crates/chatcmd-runtime/tests/git_commit_scope.rs`:
  - Đảm bảo `preview_commit_with_options` khi có `all = true` xử lý đúng ranh giới `git_scope_conflict`.

## 3. Tiêu chí hoàn thành (Done Definition)
- Toàn bộ suite `cargo test --workspace` đều đạt kết quả `PASSED` trên Windows x64.
- Extension browser có thể dispatch subagent task mà không gặp lỗi 405.
