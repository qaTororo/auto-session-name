#!/bin/bash
set -euo pipefail

# ── Configuration (overridable via environment variables) ──
MAX_USER_MESSAGES="${AUTO_SESSION_NAME_MAX_MESSAGES:-5}"
MAX_CONTEXT_CHARS="${AUTO_SESSION_NAME_MAX_CONTEXT:-800}"
MIN_CONTEXT_LENGTH="${AUTO_SESSION_NAME_MIN_CONTEXT:-20}"
MIN_TOPIC_LENGTH="${AUTO_SESSION_NAME_MIN_TOPIC:-3}"
LLM_TIMEOUT="${AUTO_SESSION_NAME_LLM_TIMEOUT:-25}"
CLAUDE_CMD="${CLAUDE_CMD:-claude}"

# ── Dependency check ──
for cmd in jq grep "$CLAUDE_CMD"; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "[auto-session-name] Required command not found: $cmd" >&2
    exit 0
  fi
done

# ── Helper: run command with timeout if available ──
run_with_timeout() {
  if command -v timeout &>/dev/null; then
    timeout "$LLM_TIMEOUT" "$@"
  else
    "$@"
  fi
}

HOOK_INPUT=$(cat)

# ── 1. Prevent infinite loop: check stop_hook_active ──
STOP_HOOK_ACTIVE=$(echo "$HOOK_INPUT" | jq -r '.stop_hook_active // false')
if [[ "$STOP_HOOK_ACTIVE" == "true" ]]; then exit 0; fi

# ── 2. Extract session info ──
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
PERMISSION_MODE=$(echo "$HOOK_INPUT" | jq -r '.permission_mode // "default"')

# Sanitize SESSION_ID (allow only alphanumeric characters and hyphens)
SESSION_ID=$(printf '%s' "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [[ -z "$SESSION_ID" ]]; then exit 0; fi

# ── 3. State file check (run only once per session) ──
STATE_DIR="${TMPDIR:-/tmp}"
STATE_FILE="${STATE_DIR}/auto-session-name-${SESSION_ID}"

# Clean up stale state files (older than 7 days)
find "$STATE_DIR" -maxdepth 1 -name "auto-session-name-*" -mtime +7 -delete 2>/dev/null || true

if [[ -f "$STATE_FILE" ]]; then exit 0; fi

# ── 4. Transcript existence check ──
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then exit 0; fi

# ── 5. Manual rename check (respect names set via /rename) ──
# grep -q short-circuits on first match, so full-file scan only occurs when absent
if grep -q '"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null; then
  touch "$STATE_FILE"
  exit 0
fi

# ── 6. Extract context from user messages ──
# Single jq invocation replaces grep + jq pipeline for fewer subprocesses
CONTEXT=$(jq -r '
  select(.type == "user") |
  .message.content |
  if type == "string" then .
  elif type == "array" then
    map(select(.type == "text") | .text) | join(" ")
  else "" end
' "$TRANSCRIPT_PATH" 2>/dev/null \
  | head -"$MAX_USER_MESSAGES" \
  | head -c "$MAX_CONTEXT_CHARS") || true

# Skip if context is too short (will retry on next Stop)
if [[ ${#CONTEXT} -lt $MIN_CONTEXT_LENGTH ]]; then exit 0; fi

# ── 7. Determine plan mode prefix ──
PREFIX=""
MODE_HINT=""
if [[ "$PERMISSION_MODE" == "plan" ]]; then
  PREFIX="plan-"
  MODE_HINT="This is a PLANNING session. The name will be prefixed with 'plan-' automatically, so generate only the topic part."
fi

# ── 8. Generate session name via LLM ──
LLM_ERROR=""
TOPIC_RAW=$(printf '%s' "$CONTEXT" \
  | run_with_timeout "$CLAUDE_CMD" -p --model claude-haiku-4-5-20251001 \
    "Generate a concise session topic name from this conversation context.
${MODE_HINT}
Rules:
- Use only lowercase alphabetic characters and hyphens (a-z, -)
- Keep it short and descriptive (ideally 5-15 characters)
- Capture the main topic or purpose
- Use common abbreviations: auth, config, db, api, fix, refact, test, etc.
- Examples: auth-fix, plugin-dev, add-test-api, setup-cicd, debug-query
Output ONLY the topic name, nothing else." 2>&1) || LLM_ERROR="$?"

if [[ -n "$LLM_ERROR" ]]; then
  echo "[auto-session-name] LLM call failed (exit code: $LLM_ERROR)" >&2
  exit 0
fi

TOPIC=$(printf '%s' "$TOPIC_RAW" \
  | tr -d ' \t\n\r' \
  | tr 'A-Z' 'a-z' \
  | sed 's/[^a-z-]//g; s/^-//; s/-$//')

# Validation (reject topics shorter than minimum length)
if [[ -z "$TOPIC" || ${#TOPIC} -lt $MIN_TOPIC_LENGTH ]]; then exit 0; fi

# ── 9. Build session name with prefix ──
SESSION_NAME="${PREFIX}${TOPIC}"

# ── 10. Apply session name ──
"$CLAUDE_CMD" session rename "$SESSION_ID" "$SESSION_NAME" 2>/dev/null || true

# ── 11. Create state file (only after attempted rename) ──
echo "$SESSION_NAME" > "$STATE_FILE"

exit 0
