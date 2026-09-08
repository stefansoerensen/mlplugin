---
name: pulse-feedback
description: Integrate the shared Pulse feedback widget into a Medialine app — the floating feedback button, screenshot capture, session recording, voice dictation, and app registration. Use when adding user feedback, a "report a bug" affordance, or bootstrapping a new app's baseline.
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
