---
paths:
  - "**/*"
---

# The `product-management/` Folder (MANDATORY for apps born in Draft Punk)

Every app that comes out of Draft Punk carries a `product-management/` folder at
its repo root. It is the handover: the product definition travels with the code
instead of staying in a chat log, a Confluence page, or somebody's head.

**It sits at the root, not under `docs/`.** That is deliberate.
[`documentation`](./documentation.md) reserves `docs/` for humans — user guide,
developer guide, admin guide, each written for a person. This folder is written
for and largely by the machine: an agent reads it to decide what to build next,
and appends to it as it works. Mixing the two would make `docs/` half
human-authored prose and half agent scratch, and the coverage matrix TaskTool
runs over `docs/` would start counting files no human ever needs to read.

## The five files

| File | Written by | Holds |
|---|---|---|
| `product.md` | Draft Punk, **once** | The problem, the target user, the value proposition, and a link back to the Spark it came from |
| `mockup.html` | Draft Punk, **once** | The accepted mockup, exactly as it was approved |
| `team.md` | Draft Punk, **once** | Innovator/PO, developers, Fachbereich, and who released the capacity |
| `decisions.md` | agent **and** humans | Append-only: what was decided and why |
| `worklog.md` | agent | What the agent did, and which Pulse item drove it |

**The first three are the handover and are then left alone.** They record what
was agreed at the moment the idea became a project. Editing them later to match
what got built destroys the only record of what was originally promised —
if reality diverged, that belongs in `decisions.md` as a decision, not as a
quiet rewrite of `product.md`.

**The last two are the agent's working memory**, versioned in Git so every
decision is reviewable as a diff instead of evaporating in a chat history.

## There is no `backlog.md`

Pulse already holds the queue — `status`, `roadmap_status`, `impact_score`,
`effort_score`, `vote_count`, and who picked an item up. A `backlog.md` in the
repo would be a second answer to a question that already has one, and the two
would disagree within a week. The repo answers *what is this product for* and
*why did we decide that*; Pulse answers *what is next* and *who is on it*.

| Question | Answered by |
|---|---|
| What is this product for? | `product-management/product.md` |
| What do users say? | Pulse |
| What is next? | Pulse (`roadmap_status`, `impact_score`, `effort_score`, `vote_count`) |
| Who is working on what? | Pulse (`picked_up_by`, `picked_up_at`, `branch_name`) |
| Why was it decided this way? | `product-management/decisions.md` |

The same logic rules out a second roadmap model in the repo. Read the roadmap
from Pulse — see [`product-management`](../skills/product-management/SKILL.md).

## Append-only means append-only

`decisions.md` is a ledger. New entries go at the bottom; existing entries are
never edited or deleted. A decision that was later reversed gets a **new** entry
saying so and pointing at the old one. The value of the file is that you can
read it top to bottom and understand how the product got to where it is — that
survives exactly as long as nobody rewrites history in it.

```markdown
## 2026-09-23 — Voting stays anonymous

**Decided by:** S. Sörensen (PO), confirmed in Pulse item `a3f1…`
**Context:** Two users asked to see who voted for what.
**Decision:** Vote authorship stays hidden.
**Why:** The point of the vote is honest signal from people who report to each
other. Attribution would turn it into a political act.
**Supersedes:** —
```

`worklog.md` is the same shape, one entry per unit of agent work, and **every
entry names the Pulse item that caused it**:

```markdown
## 2026-09-23 — Fix: CSV export drops the last row

**Pulse item:** `a3f1b2c4-…` — "Export is missing one line"
**Branch:** `claude/fix-csv-last-row`
**PR:** #42
**What changed:** Off-by-one in the row iterator in `export_service.py`.
**Status moved:** `planned` → `in_progress`
```

If you cannot name the Pulse item, the work does not belong to the agent. See
[`pm-agent`](../agents/pm-agent.md) for the scope.

## Who may write what

- **Draft Punk** writes the three handover files at handover, and nothing after.
- **The PM agent** appends to `worklog.md` on every PR it opens, and to
  `decisions.md` when it makes a call that a future reader would otherwise have
  to reverse-engineer from a diff.
- **Humans** append to `decisions.md` freely. That is the file the product owner
  owns.
- **Nobody** deletes from either.

Changes to this folder ride in the same PR as the code they explain. A worklog
entry landed separately from its change is a worklog entry that gets forgotten
when the branch is abandoned — the same failure mode
[`documentation`](./documentation.md) exists to prevent.

## Apps not born in Draft Punk

This rule does not authorize a retrofit campaign. An existing app without a
`product-management/` folder is fine. If you are working in one and the folder
would help, **say so and offer** — do not widen the current task to write a
product definition nobody asked for.
