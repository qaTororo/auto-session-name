# auto-session-name

> **Archived**: This plugin is no longer maintained. As of Claude Code v2.1.41, the built-in `/rename` command auto-generates session names from conversation context when called without arguments, making this plugin unnecessary.
>
> To uninstall: `claude plugin remove qaTororo/auto-session-name`

Automatically name Claude Code sessions based on conversation context.

When a session stops, this plugin analyzes the conversation and generates a concise, descriptive session name using an LLM. This makes it much easier to find and resume past sessions with `/resume`.

## Features

- **Automatic naming** — Sessions are named based on conversation content (e.g., `auth-fix`, `plugin-dev`, `setup-cicd`)
- **Plan mode prefix** — Planning sessions are prefixed with `plan-` (e.g., `plan-auth-fix`) for easy identification
- **Plan-to-implementation linking** — A planning session `plan-auth-fix` and its implementation session `auth-fix` share the same topic name
- **Manual rename respected** — If you use `/rename`, the plugin won't overwrite your custom name
- **Silent operation** — Runs in the background without interrupting your workflow
- **One-shot per session** — Names each session only once to avoid unnecessary API calls

## Installation

```bash
claude plugin add qaTororo/auto-session-name
```

Or for local development:

```bash
claude --plugin-dir /path/to/auto-session-name
```

## How It Works

1. **Stop hook fires** when Claude Code finishes responding
2. **Guard checks** prevent duplicate runs, respect manual renames, and skip short conversations
3. **Context extraction** pulls the first 5 user messages (up to 800 chars)
4. **LLM generation** uses `claude -p --model claude-haiku-4-5-20251001` to generate a topic name
5. **Plan mode detection** checks `permission_mode` and adds `plan-` prefix if in plan mode
6. **Session rename** applies the name via `claude session rename`

## Naming Examples

| Session Type | permission_mode | Generated Name |
|---|---|---|
| Bug fix discussion | `default` | `auth-fix` |
| Planning session | `plan` | `plan-auth-fix` |
| API development | `default` | `add-test-api` |
| CI/CD setup planning | `plan` | `plan-setup-cicd` |

## Naming Rules

- Lowercase alphabetic characters and hyphens only (`a-z`, `-`)
- Short and descriptive (typically 5-15 characters)
- Common abbreviations used: `auth`, `config`, `db`, `api`, `fix`, `refact`, `test`, etc.
- Minimum 3 characters required for validation

## Configuration

Customize behavior with environment variables:

| Variable | Default | Description |
|---|---|---|
| `AUTO_SESSION_NAME_MAX_MESSAGES` | `5` | Number of user messages to analyze |
| `AUTO_SESSION_NAME_MAX_CONTEXT` | `800` | Maximum context characters sent to LLM |
| `AUTO_SESSION_NAME_MIN_CONTEXT` | `20` | Minimum context length to proceed |
| `AUTO_SESSION_NAME_MIN_TOPIC` | `3` | Minimum topic name length |
| `AUTO_SESSION_NAME_LLM_TIMEOUT` | `25` | LLM call timeout in seconds |

## Dependencies

- `jq` — JSON parsing
- `claude` CLI — Used for LLM generation (`claude -p`) and renaming (`claude session rename`)
- `timeout` (optional) — GNU coreutils; used to enforce LLM call timeout. Falls back gracefully if unavailable.
- Anthropic API key — Used internally by `claude -p`

## Cleanup

State files in `$TMPDIR` (or `/tmp`) are automatically cleaned up after 7 days. To manually remove them:

```bash
find "${TMPDIR:-/tmp}" -name "auto-session-name-*" -delete
```

## License

MIT
