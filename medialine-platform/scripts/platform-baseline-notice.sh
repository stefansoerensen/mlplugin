#!/usr/bin/env bash
# SessionStart — platform baseline notice.
#
# Existing apps predate the platform services, and nothing in a normal session
# surfaces what they're missing. Once per session, check the app's frontend
# package.json and its docs/ directory, and tell Claude what isn't wired up.
#
# This is a nudge, not a gate: it never blocks and never authorizes Claude to
# go install anything on its own. See rules/app-baseline.md.

set -uo pipefail

INPUT=$(cat)

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

# Only consuming apps. No frontend, nothing to embed a widget into.
PKG="frontend/package.json"
[ -f "$PKG" ] || exit 0

# Skip the widget-publishing services themselves (pulse, assistant-service):
# they carry a widget/ directory at the repo root.
[ -d "widget" ] && exit 0

MISSING=""
grep -q '@pulse/widget' "$PKG" 2>/dev/null || \
  MISSING="${MISSING}- Pulse feedback widget is not integrated. Skill: \`pulse-feedback\`.\n"
grep -q '@medialine/assistant' "$PKG" 2>/dev/null || \
  MISSING="${MISSING}- Platform AI assistant is not integrated. Skill: \`ai-assistant\`.\n"
if [ ! -d "docs" ]; then
  MISSING="${MISSING}- No \`docs/\` directory. Rule: \`documentation\`.\n"
fi

[ -n "$MISSING" ] || exit 0

CONTEXT=$(printf 'Platform baseline check for this repo:\n\n%b\nThese are shared platform capabilities this app is not using yet (see rules/app-baseline.md).\n\nHow to handle this:\n- Do NOT start integrating any of it now, and do not widen the task you were given.\n- At a natural pause -- once the current task is done, or if the user asks what else\n  this app could use -- mention it once, briefly, and offer to do it as separate work.\n- If the user declines or ignores it, drop the subject for the rest of the session.\n' "$MISSING")

jq -n --arg ctx "$CONTEXT" '{additionalContext: $ctx}'
exit 0
