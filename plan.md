# Kế hoạch sửa lỗi MCP/tunnel, delivery/finalization và đồng bộ build ChatCMD

> Không tăng kích thước SQLite pool để che lỗi, không tự động retry `tools/call` có thể thay đổi dữ liệu, và không đưa token/tunnel API key vào source hoặc log.

## Mục tiêu

Loại bỏ tình trạng MCP tool đứng ở `Waiting for output`, bảo đảm mọi tool call có kết quả cuối hoặc timeout hữu hạn, đồng bộ frontend với executable release, và đưa launcher OpenAI tunnel về cùng ChatCMD thay vì phụ thuộc đường dẫn tuyệt đối ngoài dự án.

## Hiện trạng đã xác minh

| Bằng chứng | Phát hiện | Đường xử lý |
| --- | --- | --- |
| Hai `fs_list` lúc 21:50:23 và 21:52:24 có `tool_call: started` nhưng không có `tool_result` | Tool call live bị treo và control plane retry sau khoảng 121 giây | Thêm repro ở seam MCP, deadline cho legacy `fs_list`, và kết quả terminal khi timeout/cancel |
| Windows liệt kê `C:\Tools\codex` trong khoảng 193 ms; `WorkspaceService::list` trực tiếp hoàn tất dưới 1 ms | Không phải thư mục lớn, reparse point hoặc lỗi filesystem ổn định | Tập trung vào runtime wrapper, cancellation và MCP transport |
| Full MCP cô lập `agent_user_message → fs_list` hoàn tất khoảng 31 ms | Backend không hỏng ở mọi session; lỗi phụ thuộc trạng thái live/session | Replay cancellation, retry và disconnect trên cùng MCP session |
| Auth status từng trả `500` sau khoảng 5 giây; SQLite `quick_check=ok`; restart giải phóng lỗi | Pool 4 connection từng bị chiếm hết, nhưng database không hỏng | Thêm pool diagnostics và tìm operation giữ connection; không tăng pool trước khi có bằng chứng |
| `ChatCMD.exe` và `target\release\chat-cmd-client.exe` có cùng SHA-256; `web/dist` cũ hơn executable và source frontend | Rust backend là build release hiện tại, nhưng executable nhúng frontend cũ | Bắt buộc build frontend trước Rust release và kiểm tra freshness |
| `502` xuất hiện đúng lúc ChatCMD restart, bridge vẫn chạy trên `8082` | Bridge không kết nối được upstream `8080` trong cửa sổ restart | Readiness gate, log lỗi proxy, và phản hồi `503 Retry-After` cho downtime tạm thời |

## Phạm vi sửa

### 1. Tạo regression loop cho MCP `fs_list`

- Thêm integration test/harness chạy đủ chuỗi:
  `initialize → notifications/initialized → agent_user_message → fs_list`.
- Có hai trường hợp:
  - path tuyệt đối;
  - path `.` được resolve từ `task.project_folder`.
- Mô phỏng client disconnect/cancel khi `fs_list` đang chạy.
- Test phải thất bại nếu sau deadline không có JSON-RPC response hoặc timeline thiếu `tool_result`.
- Không dùng database người dùng; tạo database và workspace tạm.

**Verify**

```powershell
cargo test -p chatcmd-mcp --test mcp_fs_list_lifecycle
```

### 2. Chặn legacy `fs_list` chờ vô hạn

- Bổ sung `timeoutMs` tùy chọn vào schema legacy `fs_list`, với default hữu hạn và giới hạn trên.
- Bao `WorkspaceService::list` bằng deadline tại runtime dispatch.
- Khi timeout/cancel:
  - trả structured error ổn định;
  - ghi đúng một `tool_result` terminal;
  - gỡ activity khỏi registry;
  - không giữ SQLite connection trong lúc chờ blocking filesystem worker.
- Không tự động retry tool ở server hoặc bridge.
- Giữ `fs_list_v2` là đường ưu tiên vì đã có budget/cancellation.

**Tệp dự kiến**

- `crates/chatcmd-mcp/src/tool_args/basic.rs`
- `src/runtime_host/inputs.rs`
- `src/runtime_host/dispatch/filesystem_tools.rs`
- `src/runtime_host/persistence.rs`
- test MCP lifecycle mới

**Verify**

```powershell
cargo test -p chatcmd-runtime legacy_list
cargo test relative_filesystem_path_uses_task_project_folder_outside_configured_roots
cargo test -p chatcmd-mcp --test mcp_fs_list_lifecycle
```

### 3. Sửa cancellation và orphaned tool activity

- Không chờ vô hạn `dispatch.await` sau khi client đã cancel.
- Phân biệt operation cooperative với `spawn_blocking` không thể hủy ngay.
- Với read-only operation, kết thúc request bằng timeout/cancel và để worker được thu hồi độc lập.
- Bảo đảm retry cùng request ID không tạo nhiều activity `started` không có terminal result.
- Reconcile activity cũ khi session đóng hoặc bị thay thế, không chỉ khi turn hoàn tất.

**Verify**

```powershell
cargo test -p chatcmd-mcp --test mcp_fs_list_lifecycle cancellation
cargo test -p chatcmd-mcp --test mcp_fs_list_lifecycle duplicate_request
```

### 4. Thêm chẩn đoán SQLite pool

- Khi acquire/query timeout, log operation name, elapsed time, `pool.size()` và `pool.num_idle()`; không log SQL parameter nhạy cảm.
- Thêm test giữ bốn connection có kiểm soát rồi xác nhận auth trả lỗi chẩn đoán hữu ích và phục hồi sau khi release.
- Audit transaction để không giữ connection qua filesystem, shell, network hoặc approval wait.
- Chỉ cân nhắc đổi pool size sau khi đo tải thực tế chứng minh cần thiết.

**Verify**

```powershell
cargo test -p chatcmd-storage pool
cargo test gui_auth
```

### 5. Đồng bộ frontend và release binary

- Build `web/dist` trước mọi release có feature `embedded-web`.
- Build script phải fail nếu source frontend mới hơn bundle hoặc bundle thiếu `index.html`.
- Ghi build version/commit vào `/api/info` để phân biệt source, frontend bundle và executable đang chạy.
- Không ghi đè các thay đổi frontend hiện có trước khi chúng được test.

**Verify**

```powershell
Push-Location web
npm test -- --run
npm run build
Pop-Location
cargo build --release --features embedded-web --bin chat-cmd-client
```

Sau khi deploy, xác nhận SHA-256 của hai binary bằng nhau và `/api/info` trả đúng build mới.

### 6. Đưa OpenAI tunnel về cùng ChatCMD

- Đặt launcher, bridge và profile template trong repo/package ChatCMD; không phụ thuộc `D:\chatgpt-local-coder`.
- Dùng đường dẫn tương đối từ thư mục release.
- Giữ `.env`, generated profile, binary tunnel và log ngoài Git.
- Xóa token fallback hard-code và không in token ra console.
- Launcher phải:
  1. chờ `/api/health` của ChatCMD;
  2. khởi động bridge;
  3. xác nhận `/mcp` initialize thành công;
  4. mới khởi động tunnel client.
- Khi upstream restart, bridge trả `503` cùng `Retry-After` và ghi `ECONNREFUSED`/`ECONNRESET` đã redacted.

**Verify**

```powershell
.\openai-tunnel.bat -Doctor
```

Sau đó restart ChatCMD có kiểm soát và xác nhận tunnel phục hồi, không để activity treo.


### 7. Sửa `Message delivery timed out` do turn không finalization đúng lifecycle

**Bằng chứng đã xác minh ngày 17/09/2026**

- Turn `turn-20260917-185819-continue` có nhiều tool event nhưng không gọi `agent_turn_complete`.
- Sau 120 giây không có activity mới, `finalization_watchdog` tự ghi `reason=finalizer_timeout`.
- Chuỗi `Message delivery timed out. Please try again.` không tồn tại trong source ChatCMD; đây là lỗi delivery ở lớp ChatGPT/host khi turn không kết thúc đúng protocol.
- `ChatCMD.exe`, local API `127.0.0.1:8080`, `tunnel-client.exe` và `openai-tunnel/bridge.mjs` vẫn hoạt động, nên không phải outage của process/tunnel.

**Cách xử lý**

- Mọi turn có `agent_user_message` phải đi tới đúng một terminal lifecycle: `agent_turn_complete` hoặc terminal error/cancel tương đương.
- Không để assistant kết thúc sau tool call/progress mà thiếu finalizer.
- Nếu watchdog buộc phải auto-finalize, phải reconcile toàn bộ state phụ trong cùng transaction hoặc cùng recovery flow.
- Thêm telemetry phân biệt: `normal_finalization`, `finalizer_timeout`, `client_disconnect`, `host_delivery_failure`.

**Verify**

- Turn chạy nhiều tool > 2 phút nhưng còn activity không bị watchdog đóng nhầm.
- Turn hoàn tất bình thường có đúng một `agent_turn_complete`.
- Turn cố ý bỏ finalizer được watchdog thu hồi nhưng không để state `running` sót lại.

### 8. Reconcile `chatgpt_bridge_requests` khi watchdog auto-finalize

- Khi `auto_finalize_turn()` chuyển task sang `completed`, đồng thời xử lý bridge request liên quan:
  - `status='completed'`;
  - cập nhật `updated_at_ms` và `completed_at_ms`;
  - xóa `chatgpt_conversations.active_request_id` nếu đang trỏ tới request đó;
  - reconcile orphaned tool calls như hiện tại.
- Không phụ thuộc vào việc client phải gọi lại `request_json()` mới sửa state.
- Bổ sung startup reconciliation cho dữ liệu cũ: request còn `queued/running/stop_requested` nhưng timeline của turn đã có terminal `status=completed`.
- Reconciliation phải idempotent, chạy lặp không tạo event hoặc state sai.

**Bằng chứng cần giữ làm regression fixture**

- Request `chatgpt-native-67b099dd-...` và `chatgpt-native-178a4126-...` từng còn `running` dù timeline đã có `finalization-watchdog ... status=completed`.

### 9. Hợp nhất task binding giữa Browser Capture và MCP

- Cùng một ChatGPT `conversation_id` phải resolve về cùng canonical task/scope khi đã có MCP task hợp lệ.
- Không để browser recorder tạo task `chatgpt-browser-recorder` song song với MCP task cho cùng conversation rồi duy trì hai lifecycle độc lập.
- Xác định một hàm duy nhất resolve `conversation_id -> task_id` và tái sử dụng ở native capture, MCP binding và resume.
- Nếu chưa có MCP binding thì recorder task vẫn được phép tạo, nhưng phải promote/rebind rõ ràng khi MCP task xuất hiện.
- Không merge nhầm hai conversation khác nhau chỉ vì prompt giống nhau.

**Verify**

- Native capture trước, MCP sau -> cuối cùng còn một canonical task.
- MCP trước, native capture sau -> native capture gắn đúng task hiện hữu.
- Reload tab/retry cùng `browserUserId` giữ idempotency.

### 10. Regression suite cho delivery/finalization

Thêm test cho tối thiểu các case:

1. normal turn: `agent_user_message -> tools -> agent_turn_complete`;
2. long-running tool có heartbeat/activity: watchdog không đóng nhầm;
3. missing finalizer: watchdog hoàn tất task và bridge request đồng bộ;
4. browser capture + MCP cùng conversation: không sinh hai canonical task;
5. restart/startup reconciliation: stale `running` được sửa;
6. duplicate/retry: không tạo nhiều terminal events hoặc nhiều active request;
7. disconnect/cancel: state cuối hữu hạn, không để `running` vô thời hạn.

**Tệp dự kiến**

- `src/runtime_host/finalization_watchdog.rs`
- `src/api/chatgpt_native.rs`
- `src/api/chatgpt_support.rs`
- module conversation/task binding liên quan
- integration tests cho lifecycle Browser Capture + MCP

## Thứ tự triển khai

1. Regression MCP lifecycle.
2. Timeout/cancellation cho `fs_list`.
3. Delivery/finalization regression để tái hiện `Message delivery timed out`.
4. Reconcile watchdog + `chatgpt_bridge_requests` + `active_request_id`.
5. Hợp nhất Browser Capture/MCP task binding theo `conversation_id`.
6. Pool observability.
7. Full frontend + release build.
8. Tunnel relocation và readiness.
9. Smoke test live trên chat mới, gồm turn dài, missing-finalizer, reload/retry và restart recovery.

## Tiêu chí hoàn thành

- `fs_list` path `.` trả kết quả hoặc structured timeout trong thời gian hữu hạn.
- Mỗi `tool_call` có đúng một `tool_result` terminal, kể cả cancel/disconnect.
- Không còn retry tạo nhiều orphaned `fs_list` activity.
- Auth status vẫn phản hồi khi chạy đồng thời các MCP read operations.
- Release binary chứa frontend bundle mới nhất và `/api/info` nhận diện được build.
- Tunnel chạy hoàn toàn từ package ChatCMD, không chứa secret trong source/log và tự phục hồi sau restart upstream.
- Không còn turn kết thúc thiếu terminal finalizer trong normal flow.
- Watchdog auto-finalize không để `chatgpt_bridge_requests` hoặc `active_request_id` ở trạng thái stale.
- Một ChatGPT conversation chỉ có một canonical task lifecycle giữa Browser Capture và MCP.
- Restart/reload/retry không để request `running` vô thời hạn và không tái tạo lỗi `Message delivery timed out`.

## Đợt 25/09/2026: timeout, output và connector

Giả định: ưu tiên ba lỗi người dùng nêu. Không tự gửi lại prompt hay `tools/call` khi outcome chưa rõ vì lệnh trước có thể đã ghi dữ liệu. Giữ nguyên các thay đổi không liên quan trong worktree.

1. **Timeout và retry có kiểm soát.** Tái hiện turn dài, turn im lặng và disconnect tại extension/MCP. Giữ deadline theo activity cho turn đang chạy; chỉ retry sau khi đọc trạng thái request, xác nhận operation chưa bắt đầu hoặc không thay đổi, và dùng cùng request ID/idempotency key. Với outcome `unknown`, đọc lại state/file/process trước khi quyết định. Verify: test monitor, MCP lifecycle và đúng một terminal result; live test turn dài không báo delivery timeout.
2. **Output concise.** Dùng budget hiện có (`maxStdoutBytes`, `maxStderrBytes`, artifact/continuation); output phải có `truncated`, lý do và artifact reference hoặc cursor. Thêm regression cho stdout/stderr và tool result lớn. Verify: bounded response, terminal state và exit code vẫn hiện, artifact/cursor đọc tiếp được.
3. **Connector reconnect.** Khi schema thiếu hoặc `catalog_mismatch`, discover/initialize/list_tools lại tối đa một lần, rồi retry chỉ khi outcome an toàn. Khi bridge nhận `503 Retry-After`, kiểm tra health và trạng thái request trước khi tiếp tục. Verify: restart upstream/bridge trong turn; không nhân đôi mutating tool call hoặc để request `running` sót.
4. **Verify sau action và release.** Sau write kiểm tra file/version, sau command kiểm tra terminal state/exit code, sau build so SHA-256 nguồn/installed, sau restart kiểm tra `/api/info` HTTP 200. Script release/startup trả nonzero nếu gate fail. Verify: PowerShell syntax, frontend tests/build, Rust release build, installed hash và HTTP health.

Các mục 1–3 cần fixture lỗi tương ứng trước khi đánh dấu hoàn thành. Source hiện đã có timeout theo activity, output budgets và realtime reconnect; chúng chưa chứng minh phục hồi live của connector hoặc ngăn delivery timeout trong mọi turn.

### Kết quả triển khai 25/09/2026

- Watchdog finalization nay đóng bridge request và clear `active_request_id` trong cùng transaction. Một lần reconciliation lúc startup sửa request cũ đã có completed timeline event. Regression tái hiện `running` sau auto-finalize trước khi sửa và pass sau khi sửa.
- `command_run` mặc định preview 16 KiB stdout và 8 KiB stderr; process vẫn trả terminal state, exit code, truncation metadata và stdout artifact. Retry GET trạng thái của extension có tối đa hai lần gọi tổng cộng, xử lý network disconnect và 503 với `Retry-After` tối đa 2 giây; POST không tự retry.
- Tách attachment helper để extension suite đạt 30/30; Chrome disposable-profile smoke với hai/ba conversation và 503 fixture pass. Release đã build/test, hash binary nguồn/đích và helper extension nguồn/package khớp; app/bridge HTTP 200; manifest/bundle yêu cầu `0.1.14`.
- Còn kiểm chứng trên host ChatGPT thật: schema lazy-load/reconnect và turn dài không tái hiện `Message delivery timed out`. Chrome cá nhân cần reload extension/tab để nhận code mới; chỉ làm sau khi người dùng cho phép theo preference phiên làm việc.

