---
name: product-management
description: Work an app's product loop — read `product-management/` to learn what the product is for, query Pulse for what users asked for, claim an item, open a PR that cites it, and record what happened. Use when picking up the next piece of work in an app, triaging user feedback into changes, or acting as the PM agent for a repo.
user-invocable: false
---

# Working the Product Loop

An app born in Draft Punk arrives with its product definition in the repo and
its user feedback in Pulse. This skill is how an agent turns those two into a
pull request.

```
product-management/  ──┐
  what this is for     │
                       ├──►  decide ──► claim ──► branch ──► PR ──► worklog
Pulse                ──┘
  what users said,
  what is next
```

The scope of what an agent may do with this loop is set in
[`pm-agent`](../../agents/pm-agent.md). The folder it reads is defined in
[`product-management-folder`](../../rules/product-management-folder.md). Read
both before acting.

## 1. Read the folder first, every time

Start by reading `product-management/` — at minimum `product.md`, and
`decisions.md` from the bottom up.

This is not ceremony. Without it an agent can only ask *"can I build what was
asked?"*, and the answer is almost always yes. With it, the agent can ask the
question that actually matters: **does this belong in this product?** A user who
asks for a spreadsheet export from a tool whose whole point is to stop people
working in spreadsheets has made a real request that should probably still be
declined — and `product.md` is the only thing in the repo that tells you so.

Three specific uses:

- **`product.md`** — the problem and the target user. A request from outside the
  target user is a signal, not an instruction.
- **`decisions.md`** — a request that re-opens a settled decision is not a new
  idea. Say which entry settled it, and do not quietly build the other way.
- **`mockup.html`** — what "done" was agreed to look like. Useful when a bug
  report is really a mismatch between the build and the approved design.

If the folder does not exist, this app did not come through Draft Punk. Say so;
do not invent one.

## 2. Query Pulse for the work

**Prod API base:** `https://pulse.tasktool.medialine.com/api`

Pulse identifies callers from `X-Pulse-*` headers (`get_current_user` in
`backend/app/auth/dependencies.py`). Reads need at least `X-Pulse-User`; without
it the request comes back 401.

```bash
curl -s "$PULSE_API/apps/$APP_SLUG/feedback?status=planned&sort=priority&limit=20" \
  -H "X-Pulse-User: $PULSE_USER" \
  -H "X-Pulse-Display-Name: $PULSE_DISPLAY_NAME"
```

`$PULSE_USER` is the identity the session already has. Never write a token or a
service key into a file — see [`security`](../../rules/security.md).

### `GET /api/apps/{slug}/feedback`

| Parameter | Accepts | Notes |
|---|---|---|
| `status` | comma-separated list | `new,under_review` matches either |
| `type` | comma-separated list | `bug`, `idea`, `uncategorized` |
| `roadmap_status` | single value | `none`, `now`, `next`, `later`, `parking_lot` |
| `category` | single value | free-text field, set by admins |
| `author_role` | single value | `user`, `app_admin`, `super_admin` |
| `epic_id` | UUID | items grouped under an epic |
| `search` | text | `ILIKE` over title **and** description |
| `mine` | bool | items authored by the calling identity |
| `sort` | `newest`, `oldest`, `votes`, `priority` | default `newest` |
| `page` / `limit` | ints | `limit` max 100, default 20 |

Returns `{items, total, page, pages}`.

`sort=priority` orders by `impact_score / effort_score` descending, **nulls
last** — so an unscored item sorts to the bottom, not the top. If the queue
looks empty of good candidates, check whether anyone has scored it.

**Visibility.** Without a verified TaskTool bearer token, only
`visibility: public` items come back. Internal items unlock solely for a caller
whose *token* resolves to an app admin — the `X-Pulse-User` header alone never
does it, by design, because that header is forgeable. An agent running on header
identity only will not see internal items and must not conclude there are none.

`GET /api/feedback/{id}` returns a single item, under the same visibility rule.

### The status model

```
new → under_review → planned → in_progress → done → released
```

plus `rejected` and `merged` — the latter alongside `merged_into_id`, which
points at the item that absorbed it. This is the `feedback_status` PostgreSQL
enum in `backend/app/models/feedback.py`.

For an agent the meaningful transitions are `planned → in_progress` when work
starts and `in_progress → done` when the PR is open. **`released` is not the
agent's to set** — the agent does not deploy, so it cannot know when something
reached users.

### Roadmap and priority

| Field | Values | Notes |
|---|---|---|
| `roadmap_status` | `none`, `now`, `next`, `later`, `parking_lot` | `roadmap_status` enum |
| `impact_score` | 1–5, nullable | set by admins |
| `effort_score` | 1–5, nullable | set by admins |
| `vote_count` | int | denormalised; maintained by a DB trigger on votes |

`roadmap_status=now` combined with `sort=priority` is the default answer to
*"what should I pick up?"*.

**Do not read `GET /api/apps/{slug}/roadmap/public` for this.** That endpoint
hydrates from Jira Product Discovery, and JPD is not configured — the handler
catches `JpdNotConfigured` and returns empty `now`/`next`/`later` buckets rather
than failing. An empty answer from it means nothing at all. The `roadmap_status`
field on the feedback list is the live one.

### The Claude Code fields

`FeedbackItem` carries three columns under a comment that reads
`# Claude Code Integration`. Pulse was built expecting this agent:

| Field | Type | Means |
|---|---|---|
| `picked_up_by` | FK → `users.id` | who is working it |
| `picked_up_at` | timestamptz | since when |
| `branch_name` | varchar(200) | where the work lives |

All three are returned by `FeedbackResponse`, so a read tells you whether an item
is already claimed. **Writing them is where the gap is** — see the last section.

## 3. Claim before you work

Read the item, confirm `picked_up_by` is null, then set `picked_up_by`,
`picked_up_at` and `branch_name` **before** creating the branch.

This is not bookkeeping. Two agents given the same app and the same "take the
highest-priority open bug" instruction will choose the same item, and the first
anyone notices is a conflict between two PRs fixing the same thing differently.
The claim is the only thing standing between this loop and that outcome.

If `picked_up_by` is already set, take the next item. If it is set and
`picked_up_at` is old enough that the claim looks stale, **ask a human**. Do not
steal a claim on your own judgement.

## 4. Branch, build, open the PR

Follow [`branch-workflow`](../../rules/branch-workflow.md) exactly: cut from
freshly-fetched `origin/main`, name the branch `claude/<task-slug>`, and put that
same name in `branch_name` on the Pulse item so the two agree.

**Every PR names the Pulse item that motivated it** — id and title, in the
description:

```markdown
Fixes Pulse item `a3f1b2c4-5d6e-7f80-9123-456789abcdef`
— "CSV export is missing the last row"
https://pulse.tasktool.medialine.com/apps/draft-punk/feedback/a3f1b2c4-…

Reported by a Fachbereich user on 2026-09-18. 7 votes, impact 4 / effort 1.
```

The first question a reviewer asks about an agent-authored PR is *"why does this
exist?"*. If the answer is not in the PR body, the reviewer has to go hunting,
and the cheapest correct decision becomes closing it unread.

Then apply the rest of the house rules:
[`conventional-commits`](../../rules/conventional-commits.md),
[`documentation`](../../rules/documentation.md) — the doc review is part of the
commit, not a follow-up — and [`cloud-only`](../../rules/cloud-only.md) for how
verification works.

**Open the PR. Do not merge it, and do not deploy it.**
[`pm-agent`](../../agents/pm-agent.md) explains why that line sits where it does.

## 5. Move the status, then write the worklog

On opening the PR, move the item to `in_progress` (or `done`, if the team treats
an open PR as done), and append to `product-management/worklog.md` **in the same
commit as the change**:

```markdown
## 2026-09-23 — Fix: CSV export drops the last row

**Pulse item:** `a3f1b2c4-…` — "Export is missing one line"
**Branch:** `claude/fix-csv-last-row`
**PR:** #42
**What changed:** Off-by-one in the row iterator in `export_service.py`.
**Status moved:** `planned` → `in_progress`
```

If the change embodies a judgement a future reader would otherwise have to
reverse-engineer from the diff, append to `decisions.md` as well. Both files are
append-only — see
[`product-management-folder`](../../rules/product-management-folder.md).

## The write gap — read this before planning around it

**An agent cannot set Pulse status or claim fields today.** Slice 3 of the
product-management spine closes this. There are two separate problems, both
confirmed in the Pulse source, and both need fixing:

1. **Authorisation.** `PUT /api/feedback/{id}` (`update_feedback` in
   `backend/app/api/feedback.py`) depends on `get_verified_user`, then checks
   `is_app_admin`. `get_verified_user` accepts **only** a verified TaskTool
   bearer token — it has a deliberate, documented absence of any header
   fallback. So the sole route through today is a human app admin's token.
   `require_service_api_key` does exist in `backend/app/auth/dependencies.py`
   and validates an `X-Service-Api-Key` header (already present in the CORS
   allow-list in `backend/app/main.py`) — but it is **not wired to this
   endpoint**.

2. **Schema.** Even with admin authority the claim fields are not writable.
   `FeedbackUpdate` in `backend/app/schemas/feedback.py` declares `title`,
   `description`, `type`, `visibility`, `status`, `status_reason`, `epic_id`,
   `category`, `roadmap_status`, `impact_score` and `effort_score` — and **not**
   `picked_up_by`, `picked_up_at` or `branch_name`. The columns exist on the
   model and are returned in responses, but no endpoint sets them. A service key
   alone would therefore still not let an agent claim an item.

**What to do in the meantime:**

- **Do not borrow a human admin's token to force a status write through.** It
  makes the audit trail say a person did what an agent did, and that audit trail
  is the entire reason the agent is trusted to act at all. Trading it for
  convenience is the one thing this loop cannot afford.
- Until Slice 3 lands, run the Pulse side read-only: read the queue, open the PR
  citing the item, write the worklog entry, and **tell the human which item to
  move and to what**. The claim then happens by hand or by team agreement —
  which does not scale, and is precisely why Slice 3 exists.
- Write your prompts and tooling against the end state described above. When the
  service-key path and the schema fields land, the loop closes with no rewrite.

Everything else in this skill — the entire read path, the status model, the
roadmap and priority fields, the claim fields as *readable* state — exists and
works today.

## Related

- [`product-management-folder`](../../rules/product-management-folder.md) — the folder and its five files
- [`pm-agent`](../../agents/pm-agent.md) — what the agent may and may not do
- [`pulse-feedback`](../pulse-feedback/SKILL.md) — the widget, and the full API surface
- [`branch-workflow`](../../rules/branch-workflow.md) — branching and PRs
- [`cloud-workflow`](../cloud-workflow/SKILL.md) — verifying on prod after deploy
