---
paths:
  - "**/*"
---

# Documentation (MANDATORY)

**Reviewing whether documentation needs updating is part of committing, not a
follow-up task.** Follow-up doc tasks do not happen; the docs drift, and the
next person — or the next Claude session — works from something false.

Every Medialine repo carries user documentation in `docs/`. The split:

| Where | Audience | Contains |
|---|---|---|
| `docs/` | humans using or operating the app | what it's for, how to use it, domain vocabulary, configuration, integration points |
| `CLAUDE.md` | Claude working on the repo | stack, structure, conventions, how to run and deploy |
| plugin skills | Claude working on *another* repo | how to consume this app's shared services — see [`app-baseline`](./app-baseline.md) |

## Before every commit

Ask: **does this change what a user sees, how they use the app, its API
surface, its configuration, or its domain vocabulary?**

- **Yes** → update `docs/` in the *same commit*. A doc change in a later commit
  is a doc change that gets forgotten when the branch is squashed or abandoned.
- **No** (refactor, test, dependency bump, formatting) → record the decision in
  the commit message:

  ```
  Docs-Reviewed: none-needed
  ```

A `PreToolUse` hook reminds you: when a commit stages code but no documentation,
it injects this check as context. **It does not block** — the commit proceeds
either way, which means the rule holds only if you actually act on it. Treat the
reminder as the decision point it is, and if you are unsure which case applies,
ask the user rather than defaulting to the trailer.

## The audiences (required)

Documentation is written per audience, each in its own file under `docs/`.
TaskTool shows a coverage matrix of these across the platform and notifies the
owner when a required one is missing — treat a gap as a task, not an option.

| Persona | File | Covers |
|---|---|---|
| **User** | `docs/user-guide.md` | what the app is for, the main jobs, domain vocabulary — for someone using it |
| **Developer** | `docs/developer-guide.md` | architecture, integration points, how to extend it, which platform services it consumes — for someone building on or maintaining it |
| **Admin** | `docs/admin-guide.md` | configuration (every setting + default), operating/runbook, access & alerting — for someone operating it |

**What is required depends on the kind:**

- **Apps** — all three (User, Developer, Admin). An app is an end-user product,
  so it owes a user guide as much as developer and admin docs.
- **Services** — Developer and Admin only. A service has no end users; it is
  consumed by developers and operated by admins, so a user guide does not apply.

`CLAUDE.md` is separate — it is for Claude working *in* the repo (stack, structure,
how to run and deploy), not one of the human audiences.

An empty file does not count as coverage — write the real content, or leave the
gap visible so it gets filled.

## What good documentation covers

Write for someone who has never seen the app:

- **What it is for** — the business problem, in one paragraph, before any UI detail.
- **Domain vocabulary** — every internal term, abbreviation, status value, and
  threshold. This is the highest-value section and the one most often skipped.
  It also feeds directly into the app's assistant manifest glossary
  ([`ai-assistant`](../skills/ai-assistant/SKILL.md)) — write it once, use it twice.
- **How to do the main jobs** — the two or three workflows the app exists for.
- **Configuration** — every admin setting, what it changes, and its default.
- **Integration points** — what this app reads from and writes to, and which
  platform services it uses.

Screenshots go stale faster than prose; prefer describing what the user is
trying to achieve over narrating which button is where.

## New apps

A `docs/` directory is part of the app baseline — see
[`app-baseline`](./app-baseline.md). An app with no `docs/` is not finished.
