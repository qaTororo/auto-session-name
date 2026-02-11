#!/usr/bin/env bats

setup() {
  load test-helper
  common_setup
}

teardown() {
  common_teardown
}

# ════════════════════════════════════════════════════════════
# Guard checks (early exit)
# ════════════════════════════════════════════════════════════

@test "stop_hook_active=true → early exit, rename not called" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "default" "true")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "state file exists → early exit, rename not called" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  # Create state file beforehand
  touch "$TEST_STATE_FILE"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "transcript missing → exit" {
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "${TEST_TMPDIR}/nonexistent.jsonl")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "manual rename (custom-title) → exit, STATE_FILE created" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript_with_custom_title "$transcript"
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$TEST_STATE_FILE" ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "context too short → exit" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" "short msg"
  MOCK_CLAUDE_OUTPUT="some-topic"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "LLM output empty → exit" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT=""

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

@test "LLM output 2 chars or less → exit" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="ab"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ ! -f "$MOCK_RENAME_LOG" ]]
}

# ════════════════════════════════════════════════════════════
# Context extraction
# ════════════════════════════════════════════════════════════

@test "string content extraction → claude -p is called" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
}

@test "array content extraction → claude -p is called" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "array" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
}

@test "more than 5 user messages → only first 5 used" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  # Generate 10 messages (each sufficiently long)
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

  [[ "$status" -eq 0 ]]
  # Confirm normal processing by verifying rename was called
  [[ -f "$MOCK_RENAME_LOG" ]]

  # Verify transcript has all 10 messages
  local line_count
  line_count=$(wc -l < "$transcript")
  [[ "$line_count" -eq 10 ]]

  # Verify LLM stdin contains first 5 messages but not 6th+
  [[ -f "$MOCK_STDIN_LOG" ]]
  grep -q "First message" "$MOCK_STDIN_LOG"
  grep -q "Fifth message" "$MOCK_STDIN_LOG"
  ! grep -q "Sixth message" "$MOCK_STDIN_LOG"
}

@test "LLM receives correct context from transcript" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Help me set up a REST API with Express"
  MOCK_CLAUDE_OUTPUT="rest-api-setup"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_STDIN_LOG" ]]
  grep -q "Help me set up a REST API with Express" "$MOCK_STDIN_LOG"
}

@test "context exceeding MAX_CONTEXT_CHARS is truncated" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  # Create a message with 100 chars (well above limit of 50)
  local long_msg
  long_msg=$(printf 'A%.0s' {1..100})
  create_transcript "$transcript" "string" "$long_msg"
  MOCK_CLAUDE_OUTPUT="long-topic"

  # Set max context to 50 chars
  export AUTO_SESSION_NAME_MAX_CONTEXT=50

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_STDIN_LOG" ]]
  # stdin to LLM should be truncated to 50 chars
  local stdin_len
  stdin_len=$(wc -c < "$MOCK_STDIN_LOG")
  [[ "$stdin_len" -le 51 ]]  # 50 chars + possible trailing newline
}

# ════════════════════════════════════════════════════════════
# Plan mode
# ════════════════════════════════════════════════════════════

@test "plan mode → prefix applied: plan-topic" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me plan the implementation of authentication"
  MOCK_CLAUDE_OUTPUT="auth-design"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "plan")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "plan-auth-design" "$MOCK_RENAME_LOG"
}

@test "default mode → no prefix: topic only" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript" "default")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "auth-impl" "$MOCK_RENAME_LOG"
  ! grep -q "plan-" "$MOCK_RENAME_LOG"
}

# ════════════════════════════════════════════════════════════
# Happy path
# ════════════════════════════════════════════════════════════

@test "success: rename receives session_id and generated name" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me fix the authentication bug in my application"
  MOCK_CLAUDE_OUTPUT="auth-fix"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "session rename -- ${TEST_SESSION_ID} auth-fix" "$MOCK_RENAME_LOG"
}

@test "rename failure still creates STATE_FILE" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me implement authentication for my application"
  MOCK_CLAUDE_OUTPUT="auth-impl"
  MOCK_RENAME_FAIL="true"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  # STATE_FILE is created even on rename failure
  [[ -f "$TEST_STATE_FILE" ]]
}

@test "TOPIC normalization: spaces, uppercase, symbols removed" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me fix the authentication system in my application"
  MOCK_CLAUDE_OUTPUT="  Auth-Fix! "

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "auth-fix" "$MOCK_RENAME_LOG"
  ! grep -q "Auth" "$MOCK_RENAME_LOG"
}

@test "TOPIC normalization: consecutive hyphens collapsed" {
  local transcript="${TEST_TMPDIR}/transcript.jsonl"
  create_transcript "$transcript" "string" \
    "Please help me fix the authentication system in my application"
  MOCK_CLAUDE_OUTPUT="auth---fix"

  local input
  input=$(create_hook_input "$TEST_SESSION_ID" "$transcript")
  run_hook "$input"

  [[ "$status" -eq 0 ]]
  [[ -f "$MOCK_RENAME_LOG" ]]
  grep -q "auth-fix" "$MOCK_RENAME_LOG"
  ! grep -q "auth---fix" "$MOCK_RENAME_LOG"
}
