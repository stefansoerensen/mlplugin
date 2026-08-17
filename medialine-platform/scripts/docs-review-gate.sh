#!/usr/bin/env bash
# PreToolUse(Bash) — documentation review reminder.
#
# When a `git commit` stages code changes but no documentation changes, inject
# a reminder to decide whether docs need updating. Deliberately NON-BLOCKING:
# it adds context and lets the commit proceed under the normal permission flow.
#
# Rationale: rules/documentation.md. Reviewing whether docs need updating is a
# step in committing, not a follow-up task — follow-up doc tasks don't happen.

set -uo pipefail

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Only `git commit` (including --amend). Not `git commit-tree`, and not
# commands that merely mention the word.
printf '%s' "$CMD" | grep -qE '(^|[;&|]|[[:space:]])git([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || exit 0

# Already considered — say nothing.
printf '%s' "$CMD" | grep -qiE 'Docs-Reviewed:' && exit 0

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

STAGED=$(git diff --cached --name-only 2>/dev/null) || exit 0
[ -n "$STAGED" ] || exit 0

# Anything that could change how the product behaves?
CODE=$(printf '%s\n' "$STAGED" | grep -E '\.(py|ts|tsx|js|jsx|sql)$|^backend/|^frontend/src/' | head -1)
[ -n "$CODE" ] || exit 0

# Documentation touched too?
DOCS=$(printf '%s\n' "$STAGED" | grep -iE '^docs/|\.md$' | head -1)
[ -n "$DOCS" ] && exit 0

CTX='Documentation check (rules/documentation.md): this commit stages code but no documentation.

Before completing it, decide which applies:

1. Does this change what a user sees, how they use the app, its API surface,
   its configuration, or its domain vocabulary?
   -> Update `docs/` and stage it as part of THIS commit. A doc update deferred
      to a later commit is one that gets lost when the branch is squashed.

2. Genuinely internal (refactor, test, dependency bump, formatting)?
   -> Proceed, and add a trailer line to the commit message so the decision is
      on record:  Docs-Reviewed: none-needed

This is a reminder, not a block -- the commit will go through either way. If you
are unsure which case applies, ask the user rather than defaulting to the trailer.'

jq -n --arg ctx "$CTX" '{additionalContext: $ctx}'
exit 0
