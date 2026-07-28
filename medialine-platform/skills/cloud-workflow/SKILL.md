---
name: cloud-workflow
description: Cloud-only Medialine dev loop -- push to Gitea, let Jenkins deploy to prod, verify via the diag MCP. No local docker-compose.
user-invocable: false
---

# Cloud Workflow

The Medialine dev loop. Same for every repo.

## The loop

```
edit  ->  commit  ->  push branch (or PR via mcp-gitea)
                              |
                         Jenkins builds
                              |
                       deploys to prod*
                              |
                 verify via diag-api skill
```

`*` "prod" = the production server on `medialine_network`. There is no
"staging" or "local" environment in this loop -- see the cloud-only rule.

## Push patterns

- **Direct push to your branch** if branch protection doesn't gate it. Jenkins
  builds it automatically (multibranch + GiteaSCMSource).
- **PR-based merge to main** for protected branches. Use mcp-gitea
  `open_pull` + `merge_pull` to avoid manual API calls.
- Never push to `main` directly -- the global PreToolUse hook blocks it.

### One branch = one PR = one merge

Two failure modes to avoid: commits **stranded** on a branch whose PR already
merged (they never reach prod), and PRs that merge into the **wrong branch**
(stacking).

- Cut every new branch from a freshly fetched `main`
  (`git fetch origin && git switch -c <name> origin/main`). Never start new work
  on an existing feature branch.
- Always open PRs with **base = `main`**. Never base a PR on another feature
  branch -- do not stack PRs.
- A branch is **frozen once its PR is open**: do not push more commits to it and
  do not reuse it for new work. Start a new branch from `main` instead.
- Before pushing to an existing branch, confirm its PR is still **open**
  (`get_pull` / `list_pulls`). If it is merged or closed, the commit would be
  stranded -- branch anew from the latest `main`.
- If new work depends on an unmerged PR, wait for that PR to merge, then branch
  from the updated `main` -- rather than stacking a second branch on the first.

## Verify patterns

After deploy, the diag-api skill gives:

- `/apps/<slug>/logs?tail=200` -- container logs
- `/apps/<slug>/stats` -- cpu/mem/network
- `/apps/<slug>/inspect` -- docker inspect, secrets redacted
- `/proxy/<slug>/<path>` -- forward a request to the prod backend (allowlist)
- `/db/<slug>/query` -- read-only SELECT against the prod DB (allowlist)

These collapse a "is it deployed and working?" check from minutes of SSH +
log paging to one HTTP call.

## What this skill does NOT cover

- **Building**: handled by the Jenkinsfile in each repo. See `jenkins-pipeline`
  skill if you need to add or modify a pipeline.
- **Local-host runtime**: no longer supported. The cloud-only rule explains why.
- **Container orchestration on prod**: handled by docker-compose.prod.yml +
  the cicd-service redeploy hook.

## Why we work this way

A single deploy path -> no drift between "works on my machine" and prod. The
diag-api makes prod observable enough that the local loop stops paying off.
