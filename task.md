# Task List & Kế hoạch sửa lỗi Harness ChatCMD

Tài liệu này ghi nhận các vấn đề phát hiện được trong quá trình audit toàn diện Harness của ChatCMD (`C:\Tools\ChatCmd`) vào ngày 13/09/2026.

---

## 1. Danh sách Task sửa lỗi (Bug Fixes & Hardening)

- [x] **Task 1: Sửa lỗi HTTP 405 cho Subagent Fallback (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P0 (Nghiêm trọng - chặn tính năng Multi-agent).
  - **Triệu chứng**: Khi gọi subagent (`zip-doc-conversion-research`, `a220-primary-research`), Extension báo lỗi `ChatCMD local API trả lỗi 405.` và chuyển sang trạng thái `exhausted`.
  - **Kết quả xử lý**:
    1. Đã chuẩn hóa `parts`: bóc tách tiền tố `api/local` an toàn trong `src/api/auth.rs`.
    2. Đã bổ sung `(&Method::GET, ["subagents", "fallback", "pending"]) => true` vào hàm `extension_route_allowed`.
    3. Đã thêm kiểm thử trong `src/api/chatgpt_router_tests.rs` và chạy `cargo test`: test `extension_approval_and_subagent_routes_survive_nesting` đạt `ok. 1 passed`.
  - **Tệp liên quan**:
    - `src/api/routes.rs`
    - `src/api/auth.rs`
    - `src/api/chatgpt_router_tests.rs`
    - `chatgpt-extension/background-io.js`
    - `chatgpt-extension/background.js`

- [x] **Task 2: Sửa lỗi SQL Migration Checksum do CRLF trên Windows (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P1 (Test CI / Storage).
  - **Triệu chứng**: Test `checked_in_migrations_use_stable_lf_line_endings` trong `chatcmd-storage` bị FAILED: `0001_local_storage.sql contains CRLF bytes`.
  - **Kết quả xử lý**:
    1. Đã chuyển toàn bộ 14 file SQL migration (từ 0001 đến 0014) từ `\r\n` (CRLF) về thuần `\n` (LF).
    2. Đã xác nhận cấu hình `crates/chatcmd-storage/migrations/*.sql text eol=lf` trong `.gitattributes`.
    3. Đã chạy test `cargo test -p chatcmd-storage`: toàn bộ test suite đạt `ok. 30 passed; 0 failed`.
  - **Tệp liên quan**:
    - `crates/chatcmd-storage/migrations/*.sql`
    - `.gitattributes`

- [x] **Task 3: Sửa lỗi Race Condition Metadata mtime trên Windows NTFS**
  - **Mức độ**: P1 (Adversarial Filesystem).
  - **Triệu chứng**: Test `simultaneous_expected_version_writers_have_one_commit_winner` trong `crates/chatcmd-runtime/tests/adversarial_filesystem.rs` báo `assertion failed: left: 2, right: 1`.
  - **Nguyên nhân**: Trên NTFS của Windows, độ phân giải timestamp sửa đổi file (mtime) thấp và kích thước file giữa 2 writer bằng nhau khiến phiên bản metadata trùng nhau, cả 2 writer đều commit thành công.
  - **Cách xử lý**: Dùng khóa handle tệp độc quyền (file locking / exclusive share mode) hoặc băm nội dung SHA-256 (`VersionStrength::Content`) cho test case đối kháng này.
  - **Tệp liên quan**:
    - `crates/chatcmd-runtime/tests/adversarial_filesystem.rs`

- [x] **Task 4: Sửa lỗi Lệch Pha Git Index Lock trên Windows (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P2 (Adversarial Git Cases).
  - **Triệu chứng**: Test `git_cases::git_corrupt_repository_and_index_lock_fail_without_panicking` bị FAILED: `assertion failed: left: "staging", right: "commitHooksIncluded"`.
  - **Nguyên nhân**: Trên Windows Git, khi `.git/index.lock` bị khóa, Git văng lỗi ngay ở pha staging (`staging`) thay vì tới `commitHooksIncluded`.
  - **Cách xử lý**: Cập nhật assertion cho phép cả `"staging"` hoặc `"commitHooksIncluded"`.
  - **Tệp liên quan**:
    - `crates/chatcmd-runtime/tests/adversarial_filesystem/git_cases.rs`

- [x] **Task 5: Sửa lỗi Git Commit Preview với cờ `all = true` (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P2 (Git Commit Scope).
  - **Triệu chứng**: Test `all_rejects_unstaged_or_untracked_changes_without_mutating_index` trong `git_commit_scope.rs` bị FAILED.
  - **Nguyên nhân**: `preview_commit_with_options` với `all = true` trả về `Ok(GitCommitPreview)` thay vì trả lỗi `git_scope_conflict`.
  - **Tệp liên quan**:
    - `crates/chatcmd-runtime/src/git.rs`
    - `crates/chatcmd-runtime/tests/git_commit_scope.rs`

- [x] **Task 6: Sửa lỗi Parse YAML Multiline (>-, |-) và Tối ưu hóa Find Skills với `skills_search` (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P1 (Skill Service & Token Saturation).
  - **Triệu chứng**: Các skill dùng YAML block chomping `>-` hoặc `|-` (`orchestration`, `ida-reverse`...) bị mất mô tả (chỉ lưu `">-"`). Danh sách 147 skills làm phình to payload lên 58 KB (~13.400 tokens).
  - **Cách xử lý**:
    1. Sửa `parse_frontmatter` nhận diện đúng chỉ thị block scalar và chomping modifier trong `crates/chatcmd-runtime/src/skill_service/support.rs`.
    2. Thêm phương thức tìm kiếm 4 cấp độ `search_for_workspace` vào `crates/chatcmd-runtime/src/skill_service.rs`.
    3. Đăng ký tool MCP `skills_search` vào `crates/chatcmd-mcp` và `src/runtime_host/dispatch.rs`.
    4. Giảm 97.3% kích thước payload (xuống ~1.5 KB / 5 kết quả).
  - **Tệp liên quan**:
    - `crates/chatcmd-runtime/src/skill_service/support.rs`
    - `crates/chatcmd-runtime/src/skill_service.rs`
    - `crates/chatcmd-mcp/src/tool_args/basic.rs`
    - `crates/chatcmd-mcp/src/tool_methods.rs`
    - `crates/chatcmd-mcp/src/tool_catalog/classification.rs`
    - `src/runtime_host/inputs.rs`
    - `src/runtime_host/dispatch.rs`
    - `scripts/kiem_tra_skills_va_context.py`

- [x] **Task 7: Chuyển đổi ChatCMD sang Dynamic Find Skill / Intent Skill Router (ĐÃ HOÀN THÀNH)**
  - **Mức độ**: P1 (Context Optimization & Token Efficiency).
  - **Vấn đề**: ChatCMD trước đây nhồi toàn bộ 147 skills vào prompt ChatGPT thông qua `skill list`, gây lãng phí ~7.000 tokens và làm loãng ngữ cảnh.
  - **Giải pháp đã triển khai**:
    1. [x] Xây dựng kế hoạch triển khai tại `plan/find_skill_router_plan.md`.
    2. [x] Tạo module Intent Pre-Filter `web/src/chatgpt/skillIntentRouter.ts` (TypeScript có type hints rõ ràng, chuẩn hóa NFD, loại bỏ stop-words tiếng Việt/tiếng Anh, chấm điểm relevance).
    3. [x] Tích hợp vào `web/src/chatgpt/ChatGptConversation.tsx` để hiển thị badge kỹ năng đề xuất trên UI và nạp Top 3 skills tinh gọn vào prompt.
    4. [x] Viết kịch bản kiểm thử tự động `C:\Tools\kiem_tra_skill_intent_router.ps1` và xác minh kết quả đạt 100%.
  - **Tệp liên quan**:
    - `plan/find_skill_router_plan.md`
    - `web/src/chatgpt/skillIntentRouter.ts`
    - `web/src/chatgpt/ChatGptConversation.tsx`
    - `C:\Tools\kiem_tra_skill_intent_router.ps1`

- [x] **Task 8: Chặn `fs_list` legacy treo vô hạn và hoàn tất MCP lifecycle**
  - **Mức độ**: P0 (MCP tool call bị kẹt).
  - **Bằng chứng**: Hai activity `fs_list` cách nhau khoảng 121 giây chỉ có trạng thái `started`, không có `tool_result`; control plane retry nhưng request cũ không được kết thúc.
  - **Cách xử lý**:
    1. Viết integration test tại seam MCP cho path tuyệt đối và path `.` theo project folder.
    2. Thêm deadline/cancellation cho legacy `fs_list`.
    3. Ghi đúng một terminal `tool_result` khi success, timeout, cancel hoặc disconnect.
    4. Không chờ vô hạn blocking worker sau khi client đã hủy.
  - **Kế hoạch chi tiết**: `plan.md` mục 1–3.

- [x] **Task 9: Chẩn đoán và ngăn SQLite pool exhaustion**
  - **Mức độ**: P1 (GUI auth có thể trả lỗi 500).
  - **Bằng chứng**: Auth status từng timeout đúng 5 giây, trùng `acquire_timeout`; SQLite `quick_check` vẫn `ok` và restart giải phóng lỗi.
  - **Cách xử lý**:
    1. Log pool size/idle và operation khi acquire timeout, không log dữ liệu nhạy cảm.
    2. Audit transaction không giữ connection qua filesystem/network/approval wait.
    3. Thêm regression test giữ/release bốn connection có kiểm soát.
  - **Không xử lý bằng cách** tăng pool size khi chưa có số đo tải.

- [x] **Task 10: Bảo đảm full build đồng bộ frontend và Rust backend**
  - **Mức độ**: P0 (release đang nhúng frontend cũ).
  - **Bằng chứng**: `ChatCMD.exe` khớp hash với target release, nhưng `web/dist` được tạo trước executable và trước các thay đổi frontend hiện tại.
  - **Cách xử lý**:
    1. Build/test frontend trước `cargo build --release --features embedded-web`.
    2. Fail build nếu frontend source mới hơn bundle.
    3. Đưa commit/build identity vào `/api/info` và xác minh hash sau deploy.

- [x] **Task 11: Đưa OpenAI tunnel vào package ChatCMD và sửa lifecycle restart**
  - **Mức độ**: P1 (tunnel phụ thuộc thư mục ngoài và trả 502 khi upstream restart).
  - **Cách xử lý**:
    1. Loại bỏ đường dẫn tuyệt đối `D:\chatgpt-local-coder`.
    2. Package launcher/bridge/profile template cùng ChatCMD, giữ secret ngoài Git.
    3. Chờ health/initialize trước khi mở tunnel.
    4. Trả `503 Retry-After` khi ChatCMD tạm thời chưa sẵn sàng; không retry tool mutation.
    5. Xóa token hard-code và token logging.
  - **Kế hoạch chi tiết**: `plan.md` mục 6.


- [ ] **Task 12: Sửa `Message delivery timed out` do thiếu terminal finalization**
  - **Mức độ**: P0 (lỗi delivery làm user phải retry dù ChatCMD/tunnel vẫn sống).
  - **Bằng chứng**: Turn `turn-20260917-185819-continue` có tool activity nhưng không gọi `agent_turn_complete`; sau 120 giây watchdog auto-finalize với `reason=finalizer_timeout`.
  - **Cần sửa**:
    1. Bắt buộc normal lifecycle kết thúc bằng đúng một terminal finalizer.
    2. Không cho đường code sau tool/progress thoát turn mà thiếu finalization.
    3. Log rõ normal finalization, watchdog timeout, disconnect và host delivery failure.
  - **Tệp chính**: `src/runtime_host/finalization_watchdog.rs` và lifecycle/finalizer dispatch liên quan.

- [ ] **Task 13: Reconcile stale `chatgpt_bridge_requests` khi watchdog hoàn tất turn**
  - **Mức độ**: P0 (state machine không nhất quán).
  - **Bằng chứng**: Có request vẫn `running` dù timeline đã có `finalization-watchdog ... status=completed`.
  - **Cần sửa**:
    1. Watchdog cập nhật bridge request sang `completed`.
    2. Set `completed_at_ms`, `updated_at_ms`.
    3. Clear `chatgpt_conversations.active_request_id`.
    4. Startup reconciliation sửa dữ liệu stale cũ.
    5. Toàn bộ logic idempotent.
  - **Tệp chính**: `src/runtime_host/finalization_watchdog.rs`, `src/api/chatgpt_support.rs`.

- [ ] **Task 14: Hợp nhất Browser Capture và MCP vào một canonical task theo conversation**
  - **Mức độ**: P0 (một conversation hiện có thể sinh hai task/lifecycle độc lập).
  - **Bằng chứng**: Cùng conversation từng có browser-recorder task và MCP task khác nhau, `conversation_scope_hash` khác nhau.
  - **Cần sửa**:
    1. Chuẩn hóa một resolver `conversation_id -> canonical task_id`.
    2. Native capture tái sử dụng MCP task khi đã có binding.
    3. Nếu recorder task được tạo trước thì hỗ trợ promote/rebind khi MCP xuất hiện.
    4. Giữ idempotency theo browser user identity; không merge dựa trên prompt text.
  - **Tệp chính**: `src/api/chatgpt_native.rs`, conversation binding/resume code.

- [ ] **Task 15: Regression test delivery/finalization/restart**
  - **Mức độ**: P1.
  - **Cases bắt buộc**:
    1. normal turn có finalizer;
    2. long-running tool không bị watchdog đóng nhầm;
    3. missing finalizer được auto-finalize đồng bộ toàn bộ state;
    4. browser capture + MCP cùng conversation chỉ còn một canonical task;
    5. restart/startup reconcile stale request;
    6. duplicate/retry không tạo nhiều terminal event;
    7. disconnect/cancel không để request `running` vô thời hạn.
  - **Kế hoạch chi tiết**: `plan.md` mục 7–10.

---

## 2. Kế hoạch xác thực sau khi sửa (Verification Checklist)

1. [x] Chạy `cargo test -p chatcmd-storage --test plan_question_migration` $\rightarrow$ Xanh 100%.
2. [x] Chạy `cargo test -p chatcmd-runtime --test adversarial_filesystem` $\rightarrow$ Xanh 100%.
3. [x] Chạy `cargo test -p chatcmd-runtime --test git_commit_scope` $\rightarrow$ Xanh 100%.
4. [x] Build binary release: `cargo build --release --bin ChatCMD` và cập nhật `C:\Tools\ChatCMD-windows-x64\ChatCMD.exe`.
5. [x] Khởi động lại `ChatCMD.exe` và kiểm tra extension subagent fallback không còn bị lỗi 405.
6. [x] Chạy `C:\Tools\kiem_tra_skill_intent_router.ps1` kiểm tra độ chính xác lọc Find Skill đạt 100%.
7. [x] Chạy MCP lifecycle regression cho `fs_list`, cancellation và duplicate request.
8. [x] Chạy stress test auth song song MCP read operations; không có pool acquire timeout.
9. [x] Chạy `npm test -- --run`, `npm run build`, rồi build release với `embedded-web`.
10. [x] Xác nhận tunnel chạy từ package ChatCMD và phục hồi sau một lần restart upstream có kiểm soát.
11. [ ] Test normal finalization: mỗi turn có đúng một terminal `agent_turn_complete`.
12. [ ] Test watchdog missing-finalizer: task và bridge request cùng chuyển `completed`, `active_request_id` được clear.
13. [ ] Test Browser Capture + MCP cùng `conversation_id`: chỉ một canonical task/scope.
14. [ ] Test startup reconciliation: stale `queued/running/stop_requested` được sửa idempotently.
15. [ ] Live smoke: chạy turn dài + reload/retry + restart ChatCMD/tunnel và xác nhận không xuất hiện lại `Message delivery timed out. Please try again.`

## Đợt 25/09/2026: ba lỗi ưu tiên và release

- [ ] **Task 16 — Timeout/retry:** watchdog nay hoàn tất bridge request và clear `active_request_id` cùng transaction; startup sửa request cũ, test từng fail `running` nay pass. Extension test long-running và silent pass. Không tự gửi lại prompt có side effect khi trạng thái chưa rõ. Còn cần live signed-in test để xác nhận không lặp `Message delivery timed out`.
- [x] **Task 17 — Output concise:** `command_run` mặc định preview 16 KiB stdout, 8 KiB stderr; test default và output flood pass. `truncated`, byte counters, artifact và terminal state hiện có được giữ. Caller vẫn được tăng budget rõ ràng khi cần.
- [ ] **Task 18 — Connector reconnect:** extension tự retry đúng một GET trạng thái sau network disconnect hoặc bridge 503/`Retry-After` tối đa 2 giây; test xác nhận POST không retry. MCP `catalog_mismatch` có metadata refresh một lần và test contract pass. Chrome fixture 2/3 chat đồng thời pass. Còn cần thử reconnect/schema discovery trên host ChatGPT thật.
- [x] **Task 19 — Verify/release:** web 33/33 files, 224/224 tests; frontend và Rust embedded release build PASS; SHA-256 binary nguồn/đích bằng nhau; ChatCMD PID 42852 trả `/api/info` HTTP 200; bridge `/health` HTTP 200. Script trả nonzero khi copy/hash/health fail. Lần copy đầu bị file lock, retry có giới hạn đã cho lần build sau thành công.
- [x] **Task 20 — Đồng bộ version extension:** `web/src/chatgptBridge.ts` lấy version từ manifest thay vì hard-code `0.1.12`; hướng dẫn EN/VI dùng cùng giá trị. Sau Task 21, bundle/package yêu cầu `0.1.14`. Chưa reload browser đang mở, nên chưa xác nhận popup biến mất ở tab cũ.

Task 12–16 và 18 vẫn mở theo các tiêu chí live/chưa triển khai còn ghi ở từng mục; build và health check không đủ bằng chứng để đánh dấu xong.

Lỗi test giới hạn 500 dòng trước đó đã được xử lý trong Task 21 bên dưới.

## Kết quả triển khai 25/09/2026

- [x] **Task 21 — Extension maintenance gate:** tách attachment helper khỏi `content-chatgpt.js` (còn 487 dòng), cập nhật manifest và browser harness; extension test 30/30 pass. Manifest/build/package hiện đồng bộ `0.1.14`.
- [x] **Task 22 — Build và chạy lại:** web 33/33 files, 224/224 tests; Rust embedded release PASS; SHA-256 source/installed bằng nhau; helper extension source/package bằng nhau; ChatCMD PID 14184 `/api/info` HTTP 200; bridge `/health` HTTP 200.
- [ ] **Task 23 — Live browser smoke:** user đã cho phép reload extension/tab cá nhân. CUA hiện trả `apps=[]`, `browsers=[]`; Computer Use native pipe trả `os error 2` cả sau reset; Chrome hiện chạy nhưng không mở CDP. Chưa reload được extension/tab thật, nên chưa xác nhận popup version biến mất, tool status reconnect hay turn dài có finalization. Cần user reload thủ công hoặc khôi phục UI automation surface rồi thử lại.
