#!/usr/bin/env bats

setup() {
  load test-helper
  common_setup
}

teardown() {
  common_teardown
}

# ════════════════════════════════════════════════════════════
# ガードチェック（早期終了）
# ════════════════════════════════════════════════════════════

@test "stop_hook_active=true → 早期終了、rename 未呼出" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "default" "true")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "状態ファイル既存 → 早期終了、rename 未呼出" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  # 状態ファイルを先に作成
  touch "/tmp/auto-session-name-${TEST_SESSION_ID}"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "トランスクリプト不存在 → 終了" {
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "${TEST_TMPDIR}/nonexistent.jsonl")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "手動命名済み(custom-title) → 終了、STATE_FILE 作成" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript_with_custom_title "$transcript"
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ -f "/tmp/auto-session-name-${TEST_SESSION_ID}" ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "コンテキスト短すぎ → 終了" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" "short msg"
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "LLM出力が空 → 終了" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT=""

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "LLM出力が2文字以下 → 終了" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="ab"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

# ════════════════════════════════════════════════════════════
# コンテキスト抽出
# ════════════════════════════════════════════════════════════

@test "文字列型 content の正常抽出 → claude -p が呼ばれる" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
}

@test "配列型 content の正常抽出 → claude -p が呼ばれる" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "array" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
}

@test "ユーザーメッセージ5件超 → 先頭5件のみ使用" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  # 10件のメッセージを生成（各メッセージは十分な長さ）
  create_transcript "$transcript" "string" \
    "First message about authentication setup" \
    "Second message about database config" \
    "Third message about API endpoints" \
    "Fourth message about error handling" \
    "Fifth message about testing strategy" \
    "Sixth message should be ignored" \
    "Seventh message should be ignored" \
    "Eighth message should be ignored" \
    "Ninth message should be ignored" \
    "Tenth message should be ignored"
  MOCK_CLAUDE_OUTPUT="auth-setup"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  # rename が呼ばれることで正常処理を確認
  [[ -f "$MOCK_RENAME_LOG" ]]

  # トランスクリプトに10件のメッセージがあることを確認
  local line_count
  line_count=$(wc -l < "$transcript")
  [[ "$line_count" -eq 10 ]]
}

# ════════════════════════════════════════════════════════════
# Plan mode
# ════════════════════════════════════════════════════════════

@test "plan mode → prefix 付与: plan-topic" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me plan the implementation of authentication"
  MOCK_CLAUDE_OUTPUT="auth-design"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "plan")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "plan-auth-design" "$MOCK_RENAME_LOG"
}

@test "default mode → prefix なし: topic のみ" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "default")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "auth-impl" "$MOCK_RENAME_LOG"
  ! grep -q "plan-" "$MOCK_RENAME_LOG"
}

# ════════════════════════════════════════════════════════════
# 正常パス
# ════════════════════════════════════════════════════════════

@test "正常完了: rename に session_id と生成名が渡される" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me fix the authentication bug in my application"
  MOCK_CLAUDE_OUTPUT="auth-fix"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "session rename ${TEST_SESSION_ID} auth-fix" "$MOCK_RENAME_LOG"
}

@test "rename 失敗でも STATE_FILE 作成" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"
  MOCK_RENAME_FAIL="true"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  # rename 失敗でも STATE_FILE が作られる
  [[ -f "/tmp/auto-session-name-${TEST_SESSION_ID}" ]]
}

@test "TOPIC 正規化: スペース・大文字・記号を除去" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me fix the authentication system in my application"
  MOCK_CLAUDE_OUTPUT="  Auth-Fix! "

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "auth-fix" "$MOCK_RENAME_LOG"
  ! grep -q "Auth" "$MOCK_RENAME_LOG"
}
