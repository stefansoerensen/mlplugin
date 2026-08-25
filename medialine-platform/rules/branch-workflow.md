# Branch Workflow (MANDATORY)

This project lives on Gitea (`gitea.medialine.com`) with server-side branch protection on `main`. Multibranch Jenkins is wired to the repo via the Gitea SCM source — every branch (including PR branches) gets its own CI build that posts back as `<repo>/pipeline/pr-main`.

## Rules

- **Default branch is `main`.** There is no `master`. Direct push to `main` is server-blocked.
- **Cut every branch from freshly-fetched `origin/main`.** Run `git fetch origin main` first, then `git checkout -b <name> origin/main`. Never branch off a stale local `main` or another feature branch.
- **One change = one fresh branch.** Name it `claude/<task-slug>` (e.g. `claude/fix-sso-callback`) or `feat/<slug>` / `fix/<slug>` for human work.
- **Never reuse a branch whose PR already merged.** A merged branch is dead — its commits are already in `main` and new commits pushed to it do NOT reach `main`. For any follow-up (a fix, a review comment, "one more thing"), start a brand-new branch off `origin/main`.
- **Verify PR state before pushing a follow-up.** If you're about to push to an existing branch, confirm its PR is still open (`get_pull` / `gh pr view`) — if it's merged or closed, cut a new branch instead.
- **Open a PR against `main`.** Wait for the Jenkins PR build to go green (`<repo>/pipeline/pr-main: success`).
- **Squash-merge via the Gitea UI** (or `gh`/API). PR branches are auto-deleted after merge.
- **Never push directly to `main`.** Gitea rejects it; a global PreToolUse hook in `~/.claude/settings.json` also blocks `git push origin main|master` from any Claude Code session.

## Why

Parallel Claude Code sessions used to collide on `main` and produce Frankenstein commits — including a real auth-service SSO incident where a deploy picked up the wrong branch. PR-before-merge with server enforcement and Jenkins PR builds is the fix.

## Quick reference

```bash
# Start a task — ALWAYS cut from freshly-fetched origin/main
git fetch origin main
git checkout -b claude/my-task origin/main

# ... make changes, commit ...
git -c http.sslVerify=false push -u origin claude/my-task

# Open PR via gh (or the Gitea UI)
gh pr create --base main --title "feat: ..." --body "..."

# Wait for Jenkins green, then squash-merge in Gitea UI

# Follow-up after merge? The old branch is dead — start a NEW one:
git fetch origin main
git checkout -b claude/my-followup origin/main
```
