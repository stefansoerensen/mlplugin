#!/usr/bin/env bash
# PreToolUse(Bash) — block direct pushes to main/master.
#
# rules/branch-workflow.md already forbids this and states that "a global
# PreToolUse hook in ~/.claude/settings.json also blocks git push origin
# main|master". No such hook exists — not in the plugin, not in any developer's
# settings.json — so the rule has been documentation only. A Klar session put
# 17 commits onto main this way, several of them touching production data,
# before anyone noticed.
#
# Server-side branch protection is the real enforcement and has to be set per
# repo. This closes the Claude Code side, where the mistake is easy to make:
# after a local merge the session is already standing on main and a bare
# `git push` is enough to bypass review and the Jenkins PR build.
#
# See rules/branch-workflow.md.

set -uo pipefail

INPUT=$(cat)

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Each chained command is judged on its own. A commit message that happens to
# contain the word "main" must not block an unrelated push in the same line.
SEGMENTS=$(printf '%s' "$CMD" | sed -e 's/&&/\n/g' -e 's/||/\n/g' -e 's/;/\n/g')

blocked=""
reason=""

while IFS= read -r seg; do
  [ -n "$seg" ] || continue
  printf '%s' "$seg" | grep -qE '(^|[[:space:]])git([[:space:]]|$)' || continue
  printf '%s' "$seg" | grep -qE '[[:space:]]push([[:space:]]|$)' || continue

  # Everything after the `push` verb: the remote and the refspecs.
  after=$(printf '%s' "$seg" | sed -E 's/.*[[:space:]]push([[:space:]]|$)/ /')
  args=$(printf '%s' "$after" | tr ' \t' '\n\n' | grep -v '^-' | grep -v '^$' || true)

  if [ -z "$args" ]; then
    # A bare `git push` follows the current branch. Standing on main after a
    # local merge is exactly how this goes wrong.
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
      blocked="yes"
      reason="'git push' auf dem aktuellen Branch '$branch'"
    fi
    continue
  fi

  # Compared token by token rather than by regex, so that a branch named
  # fix/main-rewrite or a remote named mainline is not caught.
  for tok in $args; do
    case "$tok" in
      main|master|+main|+master|:main|:master|*:main|*:master|*:+main|*:+master)
        blocked="yes"
        reason="Refspec '$tok'"
        ;;
    esac
  done
done <<EOF
$SEGMENTS
EOF

[ -n "$blocked" ] || exit 0

cat >&2 <<MSG
BLOCKED: branch-workflow policy (rules/branch-workflow.md) — $reason

Direkte Pushes auf main/master sind nicht erlaubt. Der Weg ist ein PR:

  git checkout -b claude/<task-slug>
  git -c http.sslVerify=false push -u origin claude/<task-slug>
  # PR öffnen: medialine-gitea MCP (open_pull) oder die Gitea-UI
  # auf <repo>/pipeline/pr-main warten, dann in der UI squash-mergen

Auch nicht: lokal nach main mergen und das Ergebnis pushen. Das umgeht den
Jenkins-PR-Build und jede Review-Möglichkeit gleichermaßen.

Wenn dieser Push wirklich beabsichtigt ist, lass ihn den Menschen ausführen.
MSG
exit 2
