use chatcmd_core::{
    AgentId, ExecutionMode, Setting, SettingsStore as _, TaskExecutionMode, TaskId, TaskStore as _,
    ToolCatalogStore as _,
};
use chatcmd_runtime::OperationContext;
use serde_json::json;

use super::{now_ms, user_message_tests};

#[cfg(windows)]
fn msys_path(path: &std::path::Path) -> String {
    let native = path.display().to_string().replace('\\', "/");
    format!(
        "/{}/{}",
        native[..1].to_ascii_lowercase(),
        native[3..].trim_start_matches('/')
    )
}

#[cfg(windows)]
async fn shell_context(
    host: &super::RuntimeHost,
    agent_id: &str,
    request_id: &str,
) -> OperationContext {
    let accepted = host
        .call_persisted(
            "agent_user_message",
            user_message_tests::turn_context(
                &format!("{request_id}-user"),
                agent_id,
                "agent_user_message",
                &format!("{request_id}-turn"),
                &format!("{request_id}-scope"),
            ),
            json!({"content":"open a terminal"}),
        )
        .await
        .expect("user message");
    let mut context = OperationContext::new(request_id, agent_id, "shell_create");
    context.task_id = accepted["taskId"].as_str().map(str::to_owned);
    context.turn_id = accepted["turnId"].as_str().map(str::to_owned);
    context.mcp_session_id = accepted["sessionId"].as_str().map(str::to_owned);
    context
}

#[cfg(windows)]
async fn close_test_shell(host: &super::RuntimeHost, session_id: &str) {
    host.shell
        .close(
            &OperationContext::new("close-test-shell", "test-agent", "shell_close"),
            session_id,
            true,
        )
        .await
        .expect("close test shell");
}

#[cfg(windows)]
#[tokio::test]
async fn shell_create_uses_persisted_terminal_executable() {
    let (host, agent_id, directory) = user_message_tests::test_host().await;
    let configured_shell = if std::path::Path::new(r"C:\Program Files\Git\bin\bash.exe").is_file() {
        r"C:\Program Files\Git\bin\bash.exe"
    } else {
        "cmd.exe"
    };
    host.repository
        .set_setting(&Setting {
            key: "ui_terminalExecutable".to_owned(),
            value_json: serde_json::to_string(configured_shell).expect("serialize shell"),
            updated_at_ms: now_ms(),
        })
        .await
        .expect("save terminal executable");
    let context = shell_context(&host, &agent_id, "default-shell").await;
    let result = host
        .dispatch(
            "shell_create",
            context,
            json!({"workingDirectory": directory.path()}),
        )
        .await
        .expect("create configured shell");
    let session_id = result["sessionId"].as_str().expect("session ID");
    close_test_shell(&host, session_id).await;
    assert_eq!(result["executable"], configured_shell);
}

#[cfg(windows)]
#[tokio::test]
async fn shell_create_accepts_git_bash_style_windows_working_directory() {
    let (host, agent_id, directory) = user_message_tests::test_host().await;
    let context = shell_context(&host, &agent_id, "msys-working-directory").await;
    let result = host
        .dispatch(
            "shell_create",
            context,
            json!({
                "workingDirectory": msys_path(directory.path()),
                "executable": "cmd.exe"
            }),
        )
        .await
        .expect("create shell from MSYS working directory");
    let session_id = result["sessionId"].as_str().expect("session ID");
    close_test_shell(&host, session_id).await;
    assert_eq!(
        std::path::PathBuf::from(result["initialWorkingDirectory"].as_str().expect("cwd")),
        directory
            .path()
            .canonicalize()
            .expect("canonical test directory")
    );
}

#[cfg(windows)]
#[tokio::test]
async fn startup_reconciles_tool_calls_without_terminal_results() {
    let (host, agent_id, _directory) = user_message_tests::test_host().await;
    let context = shell_context(&host, &agent_id, "orphaned-shell-wait").await;
    host.append_call_event(
        &context,
        "shell_wait",
        "started",
        Some(&json!({"sessionId":"lost-after-restart"})),
        None,
        None,
    )
    .await
    .expect("persist orphaned tool call");

    assert_eq!(
        host.reconcile_orphaned_tool_calls_after_restart()
            .await
            .expect("reconcile restart activities"),
        1
    );
    let status: String = sqlx::query_scalar(
        "SELECT json_extract(payload_json,'$.status') FROM timeline_events WHERE json_extract(payload_json,'$.activityId')='orphaned-shell-wait' AND kind='tool_result'",
    )
    .fetch_one(host.repository.pool())
    .await
    .expect("read reconciled result");
    assert_eq!(status, "interrupted");
}

#[tokio::test]
async fn command_run_wire_preserves_nonzero_exit_as_execution_result() {
    let (host, agent_id, directory) = user_message_tests::test_host().await;
    crate::catalog_seed::seed_catalog(&host.repository)
        .await
        .expect("seed current catalog");
    let command_tool = host
        .repository
        .list_tools()
        .await
        .expect("list tools")
        .into_iter()
        .find(|tool| tool.key == "command_run")
        .expect("command_run catalog entry");
    host.repository
        .set_agent_allowed_tools(
            &AgentId::new(&agent_id).expect("agent ID"),
            &[command_tool.id],
        )
        .await
        .expect("allow command_run");
    let accepted = host
        .call_persisted(
            "agent_user_message",
            user_message_tests::turn_context(
                "command-user",
                &agent_id,
                "agent_user_message",
                "command-turn",
                "command-scope",
            ),
            json!({"content":"run command boundary regression"}),
        )
        .await
        .expect("user message");
    let task_id = TaskId::new(accepted["taskId"].as_str().expect("task ID")).expect("task ID");
    host.repository
        .set_execution_mode(&TaskExecutionMode {
            task_id: task_id.clone(),
            mode: ExecutionMode::Allow,
            updated_at_ms: now_ms(),
        })
        .await
        .expect("allow task execution");
    let mut context = OperationContext::new("command-call", &agent_id, "command_run");
    context.task_id = Some(task_id.as_str().to_owned());
    context.turn_id = accepted["turnId"].as_str().map(str::to_owned);
    context.mcp_session_id = accepted["sessionId"].as_str().map(str::to_owned);

    #[cfg(windows)]
    let (executable, arguments) = (
        "powershell.exe",
        json!([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            "Write-Output PASS; exit 7"
        ]),
    );
    #[cfg(not(windows))]
    let (executable, arguments) = ("/bin/sh", json!(["-c", "printf PASS; exit 7"]));
    let result = host
        .call_persisted(
            "command_run",
            context,
            json!({
                "executable": executable,
                "arguments": arguments,
                "cwd": directory.path(),
                "timeoutMs": 5_000
            }),
        )
        .await
        .expect("execution result");
    assert_eq!(result["terminalState"], "exited");
    assert_eq!(result["exitCode"], 7);
    assert!(
        result["stdout"]
            .as_str()
            .is_some_and(|text| text.contains("PASS"))
    );
    assert!(
        result["executionId"]
            .as_str()
            .is_some_and(|id| !id.is_empty())
    );
}

#[tokio::test]
async fn command_run_cannot_spawn_when_c01_mode_denies_execution() {
    let (host, agent_id, directory) = user_message_tests::test_host().await;
    crate::catalog_seed::seed_catalog(&host.repository)
        .await
        .expect("seed current catalog");
    let command_tool = host
        .repository
        .list_tools()
        .await
        .expect("list tools")
        .into_iter()
        .find(|tool| tool.key == "command_run")
        .expect("command_run catalog entry");
    host.repository
        .set_agent_allowed_tools(
            &AgentId::new(&agent_id).expect("agent ID"),
            &[command_tool.id],
        )
        .await
        .expect("allow command_run tool");
    let accepted = host
        .call_persisted(
            "agent_user_message",
            user_message_tests::turn_context(
                "deny-command-user",
                &agent_id,
                "agent_user_message",
                "deny-command-turn",
                "deny-command-scope",
            ),
            json!({"content":"do not run the command"}),
        )
        .await
        .expect("user message");
    let task_id = TaskId::new(accepted["taskId"].as_str().expect("task ID")).expect("task ID");
    host.repository
        .set_execution_mode(&TaskExecutionMode {
            task_id: task_id.clone(),
            mode: ExecutionMode::Deny,
            updated_at_ms: now_ms(),
        })
        .await
        .expect("deny task execution");
    let sentinel = directory.path().join("must-not-run.txt");
    #[cfg(windows)]
    let (executable, arguments) = (
        "powershell.exe",
        json!([
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            format!(
                "Set-Content -LiteralPath '{}' -Value bad",
                sentinel.display()
            )
        ]),
    );
    #[cfg(not(windows))]
    let (executable, arguments) = (
        "/bin/sh",
        json!(["-c", format!("touch '{}'", sentinel.display())]),
    );
    let mut context = OperationContext::new("deny-command-call", &agent_id, "command_run");
    context.task_id = Some(task_id.as_str().to_owned());
    context.turn_id = accepted["turnId"].as_str().map(str::to_owned);
    context.mcp_session_id = accepted["sessionId"].as_str().map(str::to_owned);
    let error = host
        .call_persisted(
            "command_run",
            context,
            json!({"executable": executable, "arguments": arguments, "cwd": directory.path()}),
        )
        .await
        .expect_err("C01 denial must happen before spawn");
    assert_eq!(error.code, "policy_denied");
    assert!(!sentinel.exists());
}
