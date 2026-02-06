#!/usr/bin/env bats

setup() {
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

# ════════════════════════════════════════════════════════════
# plugin.json 検証
# ════════════════════════════════════════════════════════════

@test "plugin.json が有効な JSON" {
  jq . "${PROJECT_ROOT}/.claude-plugin/plugin.json" > /dev/null
}

@test "plugin.json の必須フィールド (name, version, description) が存在" {
  local plugin="${PROJECT_ROOT}/.claude-plugin/plugin.json"

  local name
  name=$(jq -r '.name' "$plugin")
  [[ -n "$name" && "$name" != "null" ]]

  local version
  version=$(jq -r '.version' "$plugin")
  [[ -n "$version" && "$version" != "null" ]]

  local description
  description=$(jq -r '.description' "$plugin")
  [[ -n "$description" && "$description" != "null" ]]
}

# ════════════════════════════════════════════════════════════
# hooks.json 検証
# ════════════════════════════════════════════════════════════

@test "hooks.json が有効な JSON" {
  jq . "${PROJECT_ROOT}/hooks/hooks.json" > /dev/null
}

@test "hooks.json に Stop フック定義が存在" {
  local result
  result=$(jq '.hooks.Stop' "${PROJECT_ROOT}/hooks/hooks.json")
  [[ "$result" != "null" ]]
}

# ════════════════════════════════════════════════════════════
# auto-name.sh 検証
# ════════════════════════════════════════════════════════════

@test "auto-name.sh が実行可能パーミッションを持つ" {
  [[ -x "${PROJECT_ROOT}/hooks/auto-name.sh" ]]
}
