use std::time::{Duration, Instant};

use sqlx::{Sqlite, SqlitePool, pool::PoolConnection};

#[derive(Debug, thiserror::Error)]
#[error(
    "database pool acquire failed for {operation} after {elapsed_ms} ms (size={size}, idle={idle}): {detail}"
)]
pub struct PoolAcquireError {
    operation: &'static str,
    elapsed_ms: u64,
    size: u32,
    idle: usize,
    detail: String,
}

pub async fn acquire_with_diagnostics(
    pool: &SqlitePool,
    operation: &'static str,
    timeout: Duration,
) -> Result<PoolConnection<Sqlite>, PoolAcquireError> {
    let started = Instant::now();
    let result = tokio::time::timeout(timeout, pool.acquire()).await;
    match result {
        Ok(Ok(connection)) => Ok(connection),
        Ok(Err(error)) => Err(report(pool, operation, started, error.to_string())),
        Err(_) => Err(report(
            pool,
            operation,
            started,
            "deadline exceeded".to_owned(),
        )),
    }
}

fn report(
    pool: &SqlitePool,
    operation: &'static str,
    started: Instant,
    detail: String,
) -> PoolAcquireError {
    let error = PoolAcquireError {
        operation,
        elapsed_ms: u64::try_from(started.elapsed().as_millis()).unwrap_or(u64::MAX),
        size: pool.size(),
        idle: pool.num_idle(),
        detail,
    };
    tracing::error!(
        operation,
        elapsed_ms = error.elapsed_ms,
        pool_size = error.size,
        pool_idle = error.idle,
        "database pool acquisition failed"
    );
    error
}
