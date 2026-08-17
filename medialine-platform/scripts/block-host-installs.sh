#!/usr/bin/env bash
# PreToolUse(Bash) — block host package installs.
#
# There is no host runtime to install into. Dependencies belong in
# requirements.txt / package.json and arrive via the Jenkins build.
# See rules/cloud-only.md.

set -uo pipefail

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

if printf '%s' "$CMD" | grep -qE '(^|[;&|]|[[:space:]])(pip3?[[:space:]]+install|npm[[:space:]]+(install|i)([[:space:]]|$)|yarn[[:space:]]+add|pnpm[[:space:]]+(add|install))'; then
  cat >&2 <<'MSG'
BLOCKED: cloud-only policy (rules/cloud-only.md).

There is no host runtime to install into. Instead:
  - Python: add the pinned dependency to backend/requirements.txt
  - Node:   add it to frontend/package.json
Then commit and push -- Jenkins builds the image and deploys it.

Verify on prod afterwards via the diag-api skill, not locally.
MSG
  exit 2
fi

exit 0
