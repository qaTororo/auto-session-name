#!/bin/bash
# test-helper.bash: common helper for auto-session-name tests

# Project root directory
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/hooks/auto-name.sh"

# common_setup: call from each test's setup()
common_setup() {
  # Test temporary directory (fallback if BATS_TEST_TMPDIR unavailable)
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    TEST_TMPDIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/auto-name-test.XXXXXX")
  else
    TEST_TMPDIR="${BATS_TEST_TMPDIR}"
  fi
  export TEST_TMPDIR

  # Use CLAUDE_CMD env var for mock injection (instead of PATH manipulation)
  export CLAUDE_CMD="${PROJECT_ROOT}/test/mocks/claude"

  # Mock state initialization
  export MOCK_CLAUDE_OUTPUT=""
  export MOCK_RENAME_LOG="${TEST_TMPDIR}/rename.log"
  export MOCK_RENAME_FAIL=""

  # Unique session_id for each test
  export TEST_SESSION_ID="test-session-${BATS_TEST_NUMBER}"

  # State file path (matches script's TMPDIR logic)
  export TEST_STATE_FILE="${TMPDIR:-/tmp}/auto-session-name-${TEST_SESSION_ID}"

  # Clean up state file before test
  rm -f "$TEST_STATE_FILE"
}

# common_teardown: call from each test's teardown()
common_teardown() {
  # Remove test state file
  rm -f "$TEST_STATE_FILE"

  # Remove self-created temporary directory
  if [[ -d "${TEST_TMPDIR:-}" && "$TEST_TMPDIR" == *auto-name-test* ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ── Helper functions ──

# create_hook_input: generate Stop hook JSON
# args: session_id, transcript_path, permission_mode, stop_hook_active
create_hook_input() {
  local session_id="${1:-${TEST_SESSION_ID}}"
  local transcript_path="${2:-${TEST_TMPDIR}/transcript.jsonl}"
  local permission_mode="${3:-default}"
  local stop_hook_active="${4:-false}"

  cat <<EOF
{
  "session_id": "${session_id}",
  "transcript_path": "${transcript_path}",
  "permission_mode": "${permission_mode}",
  "stop_hook_active": ${stop_hook_active}
}
EOF
}

# create_transcript: generate mock transcript file
# args:
#   $1 - output file path
#   $2 - content type ("string" or "array")
#   $3+ - user messages (variadic)
create_transcript() {
  local output_path="$1"
  local content_type="${2:-string}"
  shift 2

  > "$output_path"

  for msg in "$@"; do
    if [[ "$content_type" == "string" ]]; then
      echo "{\"type\":\"user\",\"message\":{\"content\":\"${msg}\"}}" >> "$output_path"
    elif [[ "$content_type" == "array" ]]; then
      echo "{\"type\":\"user\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"${msg}\"}]}}" >> "$output_path"
    fi
  done
}

# create_transcript_with_custom_title: generate transcript with custom-title marker
create_transcript_with_custom_title() {
  local output_path="$1"
  echo '{"type":"user","message":{"content":"hello world this is a test message"}}' > "$output_path"
  echo '{"type":"system","custom-title":"my-session"}' >> "$output_path"
}

# run_hook: execute auto-name.sh with JSON on stdin
run_hook() {
  local hook_input="$1"
  echo "$hook_input" | bash "$HOOK_SCRIPT"
}
