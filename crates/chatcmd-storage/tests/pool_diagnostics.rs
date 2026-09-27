use std::time::Duration;

use chatcmd_storage::{SqliteRepository, acquire_with_diagnostics};

#[tokio::test]
async fn pool_timeout_reports_operation_and_recovers_after_release() {
    let directory = tempfile::tempdir().expect("temporary directory");
    let repository = SqliteRepository::open(&directory.path().join("chatcmd.db"), 1)
        .await
        .expect("open repository")
        .0;
    let held = repository.pool().acquire().await.expect("hold connection");

    let error = acquire_with_diagnostics(
        repository.pool(),
        "gui_auth.password_hash",
        Duration::from_millis(20),
    )
    .await
    .expect_err("exhausted pool must time out");
    let message = error.to_string();
    assert!(message.contains("gui_auth.password_hash"));
    assert!(message.contains("size=1, idle=0"));

    drop(held);
    acquire_with_diagnostics(
        repository.pool(),
        "gui_auth.password_hash",
        Duration::from_millis(100),
    )
    .await
    .expect("pool must recover after release");
}
