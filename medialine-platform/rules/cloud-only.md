---
paths:
  - "**/*"
---

# Cloud-Only Workflow (NON-NEGOTIABLE)

Medialine projects deploy through CI, not local docker-compose. Treat your
laptop as a code editor and a git client -- nothing else.

## What you do

1. Edit code, commit, push the branch (or open a PR via mcp-gitea).
2. Jenkins picks it up (multibranch + GiteaSCMSource, 2-min poll fallback) and
   runs the pipeline against the prod-shaped containers on `medialine_network`.
3. After deploy, **verify on prod** via the Platform Diag API skill (`diag-api`):
   container logs, stats, proxied requests, read-only SELECTs.

## What you DO NOT do

- `docker compose up`, `docker compose -f docker-compose.dev.yml up --build`,
  `docker compose exec backend pytest` -- none of this runs.
- `pip install`, `npm install`, `yarn`, `pnpm` on the host. There is no host
  runtime to install into.
- "Restart backend after .env change" -- there is no local backend. Change the
  env at the production source (infrastructure repo / cicd-service config),
  push, and let the pipeline pick it up.
- Pointing the frontend at `http://localhost:8000`. The deployed frontend uses
  relative paths proxied by nginx.

## When something goes wrong

1. Read the prod container logs via diag-api (`/apps/<slug>/logs?tail=200`).
2. If the bug is in code: edit, commit, push, watch Jenkins, re-verify on prod.
3. If the bug is config: change at source-of-truth (infra repo or cicd-service
   secrets), redeploy.
4. Never paper over a prod problem by fiddling locally -- the loop only works
   if every change goes through the same path.

## Exception: editor tooling

Running `tsc`, `pyright`, `ruff`, `black` against the source for editor
feedback is fine -- you're not creating a process or shipping anything. But
once you need to run the *app*, push.

## Background

This rule replaces the old "docker-first" rule which assumed a local
docker-compose dev loop. The platform moved to PR-only branch workflow +
Jenkins multibranch + the Platform Diag API in early 2026, which makes a
local stack redundant and a source of "works on my machine" drift.
