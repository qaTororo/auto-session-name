#!/bin/bash
# test-helper.bash: auto-session-name テスト用共通ヘルパー

# プロジェクトルートディレクトリ
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/hooks/auto-name.sh"

# common_setup: 各テストの setup() から呼ぶ共通セットアップ
common_setup() {
  # テスト用一時ディレクトリ（BATS_TEST_TMPDIR が利用不可の場合は自前で作成）
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    TEST_TMPDIR=$(mktemp -d "${BATS_TMPDIR:-/tmp}/auto-name-test.XXXXXX")
  else
    TEST_TMPDIR="${BATS_TEST_TMPDIR}"
  fi
  export TEST_TMPDIR

  # PATH 先頭に mocks/ を追加（claude モック差し替え）
  export PATH="${PROJECT_ROOT}/test/mocks:${PATH}"

  # モック状態の初期化
  export MOCK_CLAUDE_OUTPUT=""
  export MOCK_RENAME_LOG="${TEST_TMPDIR}/rename.log"
  export MOCK_RENAME_FAIL=""

  # テスト用のユニーク session_id
  export TEST_SESSION_ID="test-session-${BATS_TEST_NUMBER}"

  # 状態ファイルのクリーンアップ
  rm -f "/tmp/auto-session-name-${TEST_SESSION_ID}"
}

# common_teardown: 各テストの teardown() から呼ぶ共通クリーンアップ
common_teardown() {
  # テスト用状態ファイルを削除
  rm -f "/tmp/auto-session-name-${TEST_SESSION_ID}"

  # 自前で作成した一時ディレクトリを削除
  if [[ -d "${TEST_TMPDIR:-}" && "$TEST_TMPDIR" == *auto-name-test* ]]; then
    rm -rf "$TEST_TMPDIR"
  fi
}

# ── ヘルパー関数 ──

# create_hook_input: Stop フック JSON を生成
# 引数: session_id, transcript_path, permission_mode, stop_hook_active
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

# create_transcript: 模擬トランスクリプトファイルを生成
# 引数:
#   $1 - 出力ファイルパス
#   $2 - content タイプ ("string" or "array")
#   $3+ - ユーザーメッセージ (可変長)
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

# create_transcript_with_custom_title: custom-title を含むトランスクリプトを生成
create_transcript_with_custom_title() {
  local output_path="$1"
  echo '{"type":"user","message":{"content":"hello world this is a test message"}}' > "$output_path"
  echo '{"type":"system","custom-title":"my-session"}' >> "$output_path"
}

# run_hook: stdin に JSON を渡して auto-name.sh を実行
run_hook() {
  local hook_input="$1"
  echo "$hook_input" | bash "$HOOK_SCRIPT"
}
