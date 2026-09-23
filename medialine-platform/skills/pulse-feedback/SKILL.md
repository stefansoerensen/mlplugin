---
name: pulse-feedback
description: Integrate the shared Pulse feedback widget into a Medialine app — the floating feedback button, screenshot capture, session recording, voice dictation, and app registration — and read back what users reported via the feedback API. Use when adding user feedback, a "report a bug" affordance, bootstrapping a new app's baseline, or querying an app's feedback queue, status and roadmap.
user-invocable: false
---

# Pulse — Shared Feedback Widget

**Pulse** (`medialine/pulse`) is the platform feedback service: an embeddable
React widget (`@pulse/widget`) that gives every app a floating feedback button,
plus a backend + admin frontend where the team triages what users report.

Every user-facing Medialine app ships it — see
[`rules/app-baseline.md`](../../rules/app-baseline.md). Never build a private
feedback form, and never write feedback into your own app's tables.

- **Prod API**: `https://pulse.tasktool.medialine.com/api`
- **Admin UI**: `https://pulse.tasktool.medialine.com`
- **Ports**: host 8001 (backend), 8003 (frontend) — see [`port-allocation`](../port-allocation/SKILL.md)

Pulse is two halves. The **write** half is the widget — how feedback gets in,
and most of this skill. The **read** half is the feedback API — the queue, the
status model and the roadmap fields, which is how an agent or a dashboard gets
feedback back out. That half is documented under
[Reading feedback back out](#reading-feedback-back-out).

## What a reporter can attach

| | What it captures | Notes |
|---|---|---|
| **Screenshot** | The visible viewport, with annotation tools | `html2canvas`; needs HTTPS |
| **Session recording** | Clicks, inputs, scrolls and DOM changes, replayable in the hub with a click timeline | rrweb DOM replay, **not** screen video — no permission prompt, and it can only ever see the app's own page, never another tab or the desktop |
| **Voice dictation** | Speech into the description field | Transcribed via CompanyAI; audio is discarded after transcription and never stored |

**These arrive automatically.** Widgets build from source off pulse `main` with
no version pinning (see
[`platform-services/references/widget-build-wiring.md`](../platform-services/references/widget-build-wiring.md)),
so an app picks up new widget features on its next build. You do not upgrade a
dependency, and there is nothing to bump.

## Integration in four steps

### 1. Wire the widget build

`@pulse/widget` is **built from source in the Docker build**, not installed from
npm. Add the `file:` dependency, the Dockerfile stage, and the Jenkinsfile
clone exactly as described in
[`platform-services/references/widget-build-wiring.md`](../platform-services/references/widget-build-wiring.md).

```json
// frontend/package.json
"@pulse/widget": "file:/pulse/widget"
```

### 2. Add a wrapper component

Keep the auth wiring in one place, and render nothing when signed out —
anonymous feedback is not supported.

```tsx
// frontend/src/components/PulseWidgetWrapper.tsx
import { PulseWidget } from '@pulse/widget';
import { useAuthStore } from '../contexts/authStore';

function getPulseApiUrl(): string {
  if (import.meta.env.DEV) return 'http://localhost:8001/api';
  if (window.location.hostname === 'localhost') return 'http://localhost:8001/api';
  return 'https://pulse.tasktool.medialine.com/api';
}

export default function PulseWidgetWrapper() {
  const { user, isAuthenticated } = useAuthStore();

  if (!isAuthenticated || !user) return null;

  return (
    <PulseWidget
      appSlug="your-app-slug"
      apiUrl={getPulseApiUrl()}
      user={{
        username: user.email,
        displayName: user.username || user.email,
        appRole: user.role === 'admin' ? 'admin' : 'user',
      }}
      appVersion="1.0.0"
    />
  );
}
```

Adapt the auth hook to whatever the app uses (`useAuthStore`, `useAuth`, …) —
the shape of `user` passed to `PulseWidget` is what matters.

### 3. Mount it at the app root

Outside the router, so it renders on every page:

```tsx
// frontend/src/App.tsx
<>
  <Routes>{/* … */}</Routes>
  <PulseWidgetWrapper />
</>
```

### 4. Register the app in Pulse

The widget loads its config (color, position, button text, and which capture
features are enabled) from Pulse by slug. **Until the app is registered, the
widget will not appear.** Register at `https://pulse.tasktool.medialine.com` →
Apps → Create App, with `slug` exactly matching the `appSlug` prop.

## Props

| Prop | Required | Notes |
|---|---|---|
| `appSlug` | yes | Must match the app registered in Pulse |
| `apiUrl` | yes | Pulse API base URL |
| `user.username` | yes | Unique identifier — use the email |
| `user.displayName` | yes | Shown in the feedback form |
| `user.appRole` | no | The user's role *in your app* |
| `appVersion` | no | Defaults `"1.0.0"` — context on the feedback record |
| `maskAllInputs` | no | Defaults `false`. Masks every input value in session recordings. See Privacy below |
| `onSubmit` / `onError` | no | Callbacks; wire `onError` to a console/log at minimum |

## Privacy — read this before shipping to an app with sensitive data

Session replay records what people type. Three controls, in order of bluntness:

1. **Passwords are always masked.** Hard-coded, not configurable.
2. **Mask specific elements** with a `data-pulse-mask` attribute or a
   `.pulse-mask` class. Use this for a field showing salary, health or customer
   PII. For everything at once, pass `maskAllInputs`.
3. **Turn recording off for the whole app** — `widget_recording_enabled` on the
   app's record in the Pulse admin UI. **It defaults to ON**, so this is an
   opt-out, not an opt-in.

`maskAllInputs` defaults to `false` on purpose: for internal tools, seeing the
value that broke something is most of the debugging value. That default is the
wrong one for an app handling personal data — change it, or use the per-app
switch.

Capture is always user-initiated (they press Record), a `● REC` bar stays
visible for the whole session, and rrweb can only observe the page it is
running in.

## Endpoints the widget calls

```
GET  /api/apps/{slug}                    → widget config + capability flags
POST /api/apps/{slug}/feedback           → submit feedback
POST /api/feedback/{id}/screenshots      → upload screenshot
POST /api/feedback/{id}/recordings       → upload session recording (gzipped rrweb events)
POST /api/transcribe                     → transcribe a dictated audio clip
```

The config response carries `widget_recording_enabled` and `dictation_enabled`;
the widget hides a control rather than offering one whose endpoint would fail.

## Reading feedback back out

The widget only writes. Everything below is the read side — the part an agent,
a dashboard or a status report needs, and the part this skill used to omit
entirely. For how to *work* this into a loop (claim an item, open a PR, record
what happened), see [`product-management`](../product-management/SKILL.md).

### Authentication for reads

Pulse identifies callers from `X-Pulse-*` headers (`get_current_user` in
`backend/app/auth/dependencies.py`). `X-Pulse-User` is required; without it the
read returns 401. A caller with only that header sees **public items only**.

Internal-visibility items unlock exclusively for a caller whose verified
TaskTool bearer token resolves to an app admin (`get_optional_verified_user` +
`is_app_admin`). The header alone never grants it — it is forgeable, and Pulse
treats it as such deliberately. If a query comes back thinner than expected,
suspect visibility before suspecting an empty queue.

```bash
curl -s "$PULSE_API/apps/$APP_SLUG/feedback?roadmap_status=now&sort=priority" \
  -H "X-Pulse-User: $PULSE_USER" \
  -H "X-Pulse-Display-Name: $PULSE_DISPLAY_NAME"
```

Never write a token or a service key into a file — see
[`security`](../../rules/security.md).

### `GET /api/apps/{slug}/feedback`

| Parameter | Accepts | Notes |
|---|---|---|
| `status` | comma-separated list | `new,under_review` matches either |
| `type` | comma-separated list | `bug`, `idea`, `uncategorized` |
| `roadmap_status` | single value | `none`, `now`, `next`, `later`, `parking_lot` |
| `category` | single value | free-text, set by admins |
| `author_role` | single value | `user`, `app_admin`, `super_admin` |
| `epic_id` | UUID | items grouped under an epic |
| `search` | text | `ILIKE` over title **and** description |
| `mine` | bool | items authored by the calling identity |
| `sort` | `newest`, `oldest`, `votes`, `priority` | default `newest` |
| `page` / `limit` | ints | `limit` max 100, default 20 |

Returns `{items, total, page, pages}`. `sort=priority` orders by
`impact_score / effort_score` descending, **nulls last** — unscored items sink
rather than float, so a thin-looking priority queue usually means nobody has
scored it.

`GET /api/feedback/{id}` returns a single item under the same visibility rule.

### The status model

```
new → under_review → planned → in_progress → done → released
```

plus `rejected` and `merged` — the latter alongside `merged_into_id`, pointing
at the item that absorbed it. This is the `feedback_status` PostgreSQL enum in
`backend/app/models/feedback.py`, and `status_reason` carries the free-text
explanation that belongs with a `rejected` or `merged`.

### Roadmap and prioritisation

| Field | Values |
|---|---|
| `roadmap_status` | `none`, `now`, `next`, `later`, `parking_lot` |
| `impact_score` | 1–5, nullable, set by admins |
| `effort_score` | 1–5, nullable, set by admins |
| `vote_count` | int, denormalised, maintained by a DB trigger on votes |

**`GET /api/apps/{slug}/roadmap/public` is not a substitute for these.** It
hydrates from Jira Product Discovery, and JPD is not configured in production —
the handler catches `JpdNotConfigured` and returns empty `now`/`next`/`later`
buckets rather than erroring. An empty response from it tells you nothing about
the roadmap. The `roadmap_status` field on the feedback list is the live one.

### The Claude Code fields

`FeedbackItem` carries three columns under a comment that reads
`# Claude Code Integration`:

| Field | Type | Means |
|---|---|---|
| `picked_up_by` | FK → `users.id` | who is working it |
| `picked_up_at` | timestamptz | since when |
| `branch_name` | varchar(200) | where the work lives |

All three are returned by `FeedbackResponse`, so a read shows whether an item is
already claimed. They exist so two agents cannot build the same thing.

### Writing status back — the gap, stated plainly

**An automated caller cannot currently set status or the claim fields.** Two
separate problems:

1. **Authorisation.** `PUT /api/feedback/{id}` (`update_feedback` in
   `backend/app/api/feedback.py`) depends on `get_verified_user` and then
   `is_app_admin`. `get_verified_user` accepts only a verified TaskTool bearer
   token and deliberately has no header fallback, so the only way through is a
   human app admin's token. `require_service_api_key` exists in
   `backend/app/auth/dependencies.py` and validates an `X-Service-Api-Key`
   header — already in the CORS allow-list in `backend/app/main.py` — but it is
   **not wired to this endpoint**.

2. **Schema.** `FeedbackUpdate` in `backend/app/schemas/feedback.py` accepts
   `title`, `description`, `type`, `visibility`, `status`, `status_reason`,
   `epic_id`, `category`, `roadmap_status`, `impact_score` and `effort_score` —
   and **not** `picked_up_by`, `picked_up_at` or `branch_name`. Those columns
   exist on the model and are returned in responses, but nothing in the API
   writes them. Fixing the authorisation alone would not be enough.

Both are Slice 3 of the product-management spine. **Do not work around this by
borrowing a human admin's token** — it makes the audit trail attribute an
agent's action to a person, which is the one property that makes autonomous
action acceptable in the first place. Until it lands, report what should change
and let a human change it.

Note that a human admin *can* set status and roadmap fields through the admin UI
today; the gap is specifically the service-to-service path and the claim fields.

## Troubleshooting

- **Widget doesn't render** — in order: is the user signed in (wrapper returns
  `null` otherwise), is the app registered in Pulse with that exact slug, is
  `apiUrl` reachable from the browser.
- **Screenshot capture fails** — `html2canvas` needs HTTPS in most browsers, and
  cannot capture iframes or `<canvas>` content.
- **No "Record Session" button** — recording is switched off for that app
  (`widget_recording_enabled`), or the backend predates the feature.
- **Recording submitted but not visible in the hub** — the upload is deliberately
  non-fatal so a failure never costs the user their written feedback. Check the
  Pulse backend log and wire `onError` if you have not.
- **Microphone: "blocked by this site's security policy"** — the platform nginx
  sets `Permissions-Policy`. It must read `microphone=(self)`; an empty
  allowlist `microphone=()` denies the mic to every origin *including self*, so
  the browser refuses without ever prompting. Fixed centrally — if you see this,
  something has regressed in `infrastructure/nginx/nginx.conf`.
- **Microphone: "No speech detected"** — audio reached the service but held no
  speech. Almost always the wrong input device selected in the browser.
- **No mic button at all** — `dictation_enabled` is false, meaning Pulse's
  `EXT_API_BASE_URL` is unset and it cannot reach the transcription service.
- **A read returns 401** — `X-Pulse-User` is missing. It is required on every
  feedback read, not just on writes.
- **A read returns fewer items than the admin UI shows** — you are seeing public
  items only. Internal ones need a verified bearer token belonging to an app
  admin.
- **`roadmap/public` returns three empty buckets** — expected. JPD is not
  configured; filter on `roadmap_status` instead.
- **CORS errors** — the app's origin must be allowed by the Pulse API.
- **Build fails on `file:/pulse/widget`** — the Dockerfile stage or the
  Jenkinsfile `--build-context` is missing. See the wiring reference.

## Upstream docs, and where they drift

`medialine/pulse` carries `WIDGET-INTEGRATION.md`, `HOW-TO-USE.md`, and
`TASKTOOL-INTEGRATION.md`. They are useful background but **this skill wins on
conflicts** — two known drifts as of this writing:

- They document `npm install @pulse/widget` from GitHub Packages. No app does
  that; every app uses the `file:` + build-context mechanism above.
- They give the API URL as `https://pulse.medialine.com/api`. The real host is
  `https://pulse.tasktool.medialine.com/api`.
