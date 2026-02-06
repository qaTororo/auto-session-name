#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)

# ── 1. 無限ループ防止: stop_hook_active チェック ──
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then exit 0; fi

# ── 2. セッション情報抽出 ──
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
PERMISSION_MODE=$(echo "$HOOK_INPUT" | jq -r '.permission_mode // "default"')

# ── 3. 状態ファイルチェック（1セッション1回のみ実行） ──
STATE_FILE="/tmp/auto-session-name-${SESSION_ID}"
if [[ -f "$STATE_FILE" ]]; then exit 0; fi

# ── 4. トランスクリプト存在チェック ──
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then exit 0; fi

# ── 5. 手動命名済みチェック（/rename で付けた名前を尊重） ──
if grep -q '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null; then
  touch "$STATE_FILE"
  exit 0
fi

# ── 6. ユーザーメッセージからコンテキスト抽出 ──
CONTEXT=$(grep '"type":"user"' "$TRANSCRIPT_PATH" 2>/dev/null \
  | head -5 \
  | jq -r '.message.content
    | if type == "string" then .
      elif type == "array" then
        map(select(.type == "text") | .text) | join(" ")
      else "" end' 2>/dev/null \
  | head -c 800)

# コンテキストが短すぎる場合はスキップ（次のStopで再試行）
if [[ ${#CONTEXT} -lt 20 ]]; then exit 0; fi

# ── 7. Plan mode判定 → prefix決定 ──
PREFIX=""
MODE_HINT=""
if [[ "$PERMISSION_MODE" == "plan" ]]; then
  PREFIX="plan-"
  MODE_HINT="This is a PLANNING session. The name will be prefixed with 'plan-' automatically, so generate only the topic part."
fi

# ── 8. LLMでセッション名生成 ──
TOPIC=$(printf '%s' "$CONTEXT" \
  | claude -p --model claude-haiku-4-5-20251001 \
    "Generate a concise session topic name from this conversation context.
${MODE_HINT}
Rules:
- Use only lowercase alphabetic characters and hyphens (a-z, -)
- Keep it short and descriptive (ideally 5-15 characters)
- Capture the main topic or purpose
- Use common abbreviations: auth, config, db, api, fix, refact, test, etc.
- Examples: auth-fix, plugin-dev, add-test-api, setup-cicd, debug-query
Output ONLY the topic name, nothing else." 2>/dev/null \
  | tr -d '[:space:]' \
  | tr '[:upper:]' '[:lower:]' \
  | sed 's/[^a-z-]//g; s/^-//; s/-$//')

# バリデーション（3文字未満は無効）
if [[ -z "$TOPIC" || ${#TOPIC} -lt 3 ]]; then exit 0; fi

# ── 9. prefix付きセッション名を組み立て ──
SESSION_NAME="${PREFIX}${TOPIC}"

# ── 10. セッション名を適用 ──
claude session rename "$SESSION_ID" "$SESSION_NAME" 2>/dev/null || true

# ── 11. 状態ファイル作成（成功後のみ） ──
echo "$SESSION_NAME" > "$STATE_FILE"

exit 0
