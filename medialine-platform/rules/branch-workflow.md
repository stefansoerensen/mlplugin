# Branch Workflow (MANDATORY)

This project lives on Gitea (`gitea.medialine.com`) with server-side branch protection on `main`. Multibranch Jenkins is wired to the repo via the Gitea SCM source — every branch (including PR branches) gets its own CI build that posts back as `<repo>/pipeline/pr-main`.

## Rules

- **Default branch is `main`.** There is no `master`. Direct push to `main` is server-blocked.
- **Always work on a feature branch.** Name it `claude/<task-slug>` (e.g. `claude/fix-sso-callback`) or `feat/<slug>` / `fix/<slug>` for human work.
- **Open a PR against `main`.** Wait for the Jenkins PR build to go green (`<repo>/pipeline/pr-main: success`).
- **Squash-merge via the Gitea UI** (or `gh`/API). PR branches are auto-deleted after merge.
- **Never push directly to `main`.** Gitea rejects it; a global PreToolUse hook in `~/.claude/settings.json` also blocks `git push origin main|master` from any Claude Code session.

## Why

Parallel Claude Code sessions used to collide on `main` and produce Frankenstein commits — including a real auth-service SSO incident where a deploy picked up the wrong branch. PR-before-merge with server enforcement and Jenkins PR builds is the fix.

## Quick reference

```bash
# Start a task
git checkout -b claude/my-task

# ... make changes, commit ...
git -c http.sslVerify=false push -u origin claude/my-task

# Open PR via gh (or the Gitea UI)
gh pr create --base main --title "feat: ..." --body "..."

# Wait for Jenkins green, then squash-merge in Gitea UI
```
