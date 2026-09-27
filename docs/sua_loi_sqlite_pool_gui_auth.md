# Báo cáo Chẩn đoán & Sửa lỗi SQLite Pool Cạn kiệt (gui_auth.password_hash) trong ChatCMD

## 1. Triệu chứng lỗi ghi nhận

Khi giao diện người dùng (Web UI) hoặc tiện ích mở rộng ChatGPT thực hiện kiểm tra tiến độ nén ngữ cảnh (compact progress) hoặc gửi tin nhắn, hệ thống trả về lỗi sau:

```text
Could not read compact progress. Retry before sending. local storage operation failed
database pool acquire failed for gui_auth.password_hash after 5002 ms (size=4, idle=0): pool timed out while waiting for an open connection
```

## 2. Nguyên nhân gốc rễ (Root Cause Analysis)

Sau khi điều tra mã nguồn theo quy trình chuẩn đoán lỗi (`diagnosing-bugs`):

1. **Kích thước Pool cố định và giới hạn (`max_connections = 4`)**:
   - Kho lưu trữ SQLite (`SqliteRepository`) giới hạn tối đa 4 kết nối đồng thời nhằm tối ưu hiệu năng và tránh tranh chấp tệp cơ sở dữ liệu trên Windows.
   - Khi có nhiều yêu cầu HTTP song song (ví dụ: vòng lặp polling `CompactSession` mỗi 2 giây, yêu cầu kiểm tra phiên `authStatus`, tải danh sách `tasks`, `sessions`, WebSocket ping), 4 kết nối này nhanh chóng bị các tác vụ chiếm giữ.

2. **Truy vấn tĩnh nhưng thực hiện liên tục không có bộ nhớ đệm (Cache Miss)**:
   - Trong `src/gui_auth.rs`, hàm `has_password()` và `password_hash()` được gọi liên tục bởi middleware `require_gui_auth` và endpoint `/api/local/auth/status`.
   - Mỗi lần gọi, hàm này lại thực hiện:
     ```rust
     let mut connection = chatcmd_storage::acquire_with_diagnostics(
         self.repository.pool(),
         "gui_auth.password_hash",
         Duration::from_secs(5),
     ).await?;
     ```
   - Mật khẩu GUI (`gui_password_hash_v1`) là dữ liệu cấu hình gần như bất biến (chỉ thay đổi khi khởi tạo hoặc đổi mật khẩu). Việc truy vấn SQLite liên tục trong mỗi chu kỳ kiểm tra làm lãng phí các kết nối và dẫn tới tình trạng cạn kiệt pool (`size=4, idle=0`).

3. **Hiện tượng nghẽn hàng đợi (Connection Starvation)**:
   - Khi 4 kết nối đều bận, lệnh gọi `acquire_with_diagnostics` cho `gui_auth.password_hash` bị chặn và chờ đúng 5.000 ms (5 giây) trước khi văng lỗi quá thời gian (`PoolAcquireError: deadline exceeded`).
   - Phía frontend bắt được lỗi 500 này và chặn người dùng gửi tiếp (`Could not read compact progress. Retry before sending.`).

---

## 3. Giải pháp khắc phục từng bước

### Bước 1: Thêm bộ nhớ đệm trong RAM (`cached_hash`) cho `GuiAuth`
Lưu trữ giá trị băm mật khẩu trong bộ nhớ RAM (`Arc<RwLock<Option<Option<String>>>>`).
- Lần đầu tiên hệ thống chạy, hàm sẽ đọc từ SQLite 1 lần duy nhất và ghi nhớ vào RAM.
- Các lần kiểm tra tiếp theo chỉ cần đọc thẳng từ RAM với tốc độ micro-giây mà **hoàn toàn không cần chạm vào SQLite pool**.
- Khi người dùng thiết lập mật khẩu (`setup_password`) hoặc đổi mật khẩu (`change_password`), giá trị trong cache sẽ được cập nhật đồng bộ.

### Bước 2: Giải phóng kết nối ngay tức thì (`drop(kn)`)
Trong trường hợp cache bị rỗng (lần đọc đầu tiên), sau khi truy vấn xong dữ liệu từ SQLite, kết nối được chủ động giải phóng (`drop(kn)`) ngay lập tức trước khi thực hiện parse JSON, trả kết nối về pool cho các tiến trình khác sử dụng.

---

## 4. Chi tiết mã nguồn đã sửa đổi (Giải thích từng dòng)

Dưới đây là đoạn mã nguồn trong `src/gui_auth.rs`:

```rust
// Dòng 1: Định nghĩa cấu trúc GuiAuth với trường bộ nhớ đệm cached_hash
#[derive(Clone)]
pub(crate) struct GuiAuth {
    // Dòng 2: Kho lưu trữ SQLite cơ sở dữ liệu
    repository: SqliteRepository,
    // Dòng 3: Danh sách các phiên đăng nhập đang hoạt động trong RAM
    sessions: Arc<RwLock<HashMap<String, SessionEntry>>>,
    // Dòng 4: Khóa chống ghi đè mật khẩu đồng thời
    password_write: Arc<Mutex<()>>,
    // Dòng 5: Bộ nhớ đệm lưu băm mật khẩu (None = chưa nạp, Some(None) = chưa đặt pass, Some(Some(xau)) = có pass)
    cached_hash: Arc<RwLock<Option<Option<String>>>>,
}

impl GuiAuth {
    // Dòng 6: Khởi tạo đối tượng GuiAuth mới
    pub(crate) fn new(repository: SqliteRepository) -> Self {
        Self {
            // Dòng 7: Gán kho lưu trữ
            repository,
            // Dòng 8: Khởi tạo bảng băm phiên làm việc
            sessions: Arc::new(RwLock::new(HashMap::new())),
            // Dòng 9: Khởi tạo khóa bảo vệ ghi mật khẩu
            password_write: Arc::new(Mutex::new(())),
            // Dòng 10: Ban đầu bộ nhớ đệm ở trạng thái chưa nạp (None)
            cached_hash: Arc::new(RwLock::new(None)),
        }
    }

    // Dòng 11: Hàm lấy băm mật khẩu với cơ chế cache thông minh
    async fn password_hash(&self) -> Result<Option<String>> {
        // Dòng 12: Mở khối đọc cache trong RAM
        {
            // Dòng 13: Lấy khóa đọc (read lock) từ bộ nhớ đệm
            let dem = self.cached_hash.read().await;
            // Dòng 14: Nếu đã có dữ liệu trong cache
            if let Some(xau) = &*dem {
                // Dòng 15: Trả về kết quả ngay lập tức mà không cần mở kết nối SQLite
                return Ok(xau.clone());
            }
        } // Dòng 16: Tự động giải phóng khóa đọc

        // Dòng 17: Khi cache miss, lấy 1 kết nối từ pool có chẩn đoán thời gian
        let mut kn = chatcmd_storage::acquire_with_diagnostics(
            self.repository.pool(),
            "gui_auth.password_hash",
            Duration::from_secs(5),
        )
        .await?;

        // Dòng 18: Thực hiện truy vấn đọc bản ghi cấu hình từ bảng settings
        let gia_tri: Option<String> =
            sqlx::query_scalar("SELECT value_json FROM settings WHERE key=?")
                .bind(PASSWORD_SETTING_KEY)
                .fetch_optional(&mut *kn)
                .await
                .context("load GUI password hash")?;

        // Dòng 19: Giải phóng kết nối trả về pool ngay lập tức
        drop(kn);

        // Dòng 20: Giải mã chuỗi JSON thành băm mật khẩu
        let ket_qua = gia_tri
            .map(|xau| serde_json::from_str::<String>(&xau).context("decode GUI password hash"))
            .transpose()?;

        // Dòng 21: Mở khóa ghi để lưu kết quả vào bộ nhớ đệm
        {
            let mut dem = self.cached_hash.write().await;
            *dem = Some(ket_qua.clone());
        } // Dòng 22: Giải phóng khóa ghi

        // Dòng 23: Trả về kết quả băm mật khẩu
        Ok(ket_qua)
    }

    // Dòng 24: Lưu băm mật khẩu mới vào cơ sở dữ liệu và đồng bộ cache
    async fn store_password_hash(&self, hash: &str) -> Result<()> {
        // Dòng 25: Mã hóa băm mật khẩu thành chuỗi JSON
        let xau_json = serde_json::to_string(hash).context("encode GUI password hash")?;
        // Dòng 26: Lấy mốc thời gian hiện tại
        let thoi_gian = crate::api::now_ms();
        // Dòng 27: Ghi bản ghi vào bảng settings
        sqlx::query("INSERT INTO settings(key,value_json,updated_at_ms) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json,updated_at_ms=excluded.updated_at_ms")
            .bind(PASSWORD_SETTING_KEY)
            .bind(xau_json)
            .bind(thoi_gian)
            .execute(self.repository.pool())
            .await
            .context("store GUI password hash")?;

        // Dòng 28: Cập nhật giá trị mới vào cache trong RAM
        {
            let mut dem = self.cached_hash.write().await;
            *dem = Some(Some(hash.to_owned()));
        }
        // Dòng 29: Hoàn tất thao tác ghi thành công
        Ok(())
    }
}
```

---

## 5. Kiểm thử hồi quy tự động (Regression Test)

Đã bổ sung bài kiểm tra `cached_password_hash_survives_exhausted_pool` trong `src/gui_auth.rs`:
- Khởi tạo `SqliteRepository` chỉ có đúng **1 kết nối duy nhất** (`max_connections = 1`).
- Thực hiện kiểm tra lần đầu để nạp cache.
- Chiếm dụng toàn bộ kết nối duy nhất đó (`pool.acquire()`).
- Gọi `has_password()` với thời gian chờ chỉ 50ms: Hàm thành công ngay lập tức từ bộ nhớ đệm RAM mà không bị timeout hay kẹt kết nối.

Kết quả kiểm thử đạt 100%:
```text
running 4 tests
test gui_auth::tests::parses_named_cookie ... ok
test gui_auth::tests::rejects_short_passwords ... ok
test gui_auth::tests::cached_password_hash_survives_exhausted_pool ... ok
test runtime_host::user_message_project_tests::gui_auth_remains_responsive_during_parallel_legacy_lists ... ok

test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 235 filtered out; finished in 0.24s
```
