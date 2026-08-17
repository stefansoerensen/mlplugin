---
name: ai-assistant
description: Add the platform AI assistant to a Medialine app — the @medialine/assistant widget plus the app-side manifest, read-only tool callbacks, and confirmable actions. Use when adding AI chat, an in-app assistant, natural-language lookup, or "ask about my data" to any app.
user-invocable: false
---

# Platform AI Assistant

**assistant-service** (`medialine/assistant-service`) is the platform AI
assistant: *one brain serving every app*. Apps do not build their own chatbot,
do not hold an Anthropic key, and do not call an LLM directly.

The app's entire job is to (a) mount a widget and (b) describe itself in a
**manifest**. The assistant-service handles conversation, prompting, tool
orchestration, and the Claude calls (routed via `ext-api-service/companyai`).

- **Prod**: `https://assistant.tasktool.medialine.com` (env `VITE_ASSISTANT_API_URL`)
- **Widget**: `@medialine/assistant` — floating ✨ launcher + ⌘-K spotlight
- **Reference implementation**: `medialine/leads-united` (first consumer),
  `medialine/aboabrechnung` (second)

## How it works

```
User types in widget
   → assistant-service builds a prompt from YOUR manifest
   → Claude picks a tool
      ├─ read tool   → GET {your-app}/api/assistant-tools/tools/<name>?<params>
      │                 with the USER's JWT → result feeds the next turn
      └─ propose_action → an action card returned to the widget
                          → user clicks [Confirm]
                          → widget calls {appBaseUrl}{action.path} with the user's JWT
                          → your normal endpoint runs, audit-logged like a manual click
```

Two properties fall out of this design, and both are the point:

- **The assistant can only read what you expose, as the user who asked.** Tool
  callbacks take the user's JWT and must apply the same ownership/role checks as
  any other endpoint. There is no service-account backdoor.
- **The assistant never mutates anything on its own.** Writes go through
  *existing* app endpoints, only after an explicit user confirmation, so
  permissions and audit trails work unchanged.

## Integration

### 1. Wire the widget build

Built from source in the Docker build, not installed from npm. Add the `file:`
dependency, Dockerfile stage, Jenkinsfile clone, and the
`VITE_ASSISTANT_API_URL` build arg per
[`platform-services/references/widget-build-wiring.md`](../platform-services/references/widget-build-wiring.md).

```json
// frontend/package.json
"@medialine/assistant": "file:/medialine-assistant/widget"
```

### 2. Mount the widget

In `Layout.tsx` (or wherever the app's persistent chrome lives), rendered only
when there's both a user and a token:

```tsx
import { AssistantWrapper } from '@medialine/assistant';

const ASSISTANT_API_URL =
  (import.meta.env.VITE_ASSISTANT_API_URL as string | undefined) ||
  'https://assistant.tasktool.medialine.com';

// inside the layout component
const token = typeof window !== 'undefined' ? localStorage.getItem('auth_token') : null;

{user && token && (
  <AssistantWrapper
    appSlug="your-app-slug"
    apiUrl={ASSISTANT_API_URL}
    user={{
      id: user.id,
      email: user.email,
      display_name: user.display_name,
      is_admin: user.is_admin,
    }}
    token={token}
    locale={lang === 'de' ? 'de' : 'en'}
    appBaseUrl={typeof window !== 'undefined' ? window.location.origin : ''}
  />
)}
```

`token` is **required** — the widget needs it both to call assistant-service and
to execute confirmed actions against your backend. `appBaseUrl` defaults to
`window.location.origin`; pass it explicitly when the frontend is served from a
different origin than the API.

### 3. Build the app-side manifest + tool router

This is the real work, and the part worth thinking about. Create
`backend/app/api/assistant_tools.py` exposing:

- `GET /api/assistant-tools/manifest` — who this app is, its vocabulary, its tools and actions
- `GET /api/assistant-tools/tools/<name>` — one read-only callback per declared tool

Full worked example, extracted from `leads-united`:
[`references/manifest-example.md`](./references/manifest-example.md).

The manifest has five parts:

| Key | What good looks like |
|---|---|
| `app_slug` / `app_name` / `app_description` | One or two sentences on what the app is *for* — the assistant's whole framing |
| `version` | Bump when tools/actions change; the cache keys on it |
| `glossary` | **The highest-value field.** Every domain term, abbreviation, and status value a new colleague would have to ask about |
| `tools` | Read-only lookups. `name`, `description`, JSON-Schema `params_schema` |
| `actions` | Mutations, each mapped to an **existing** endpoint via `http_method` + `path` |

Register the router in `main.py`:

```python
from app.api import assistant_tools
app.include_router(assistant_tools.router)
```

### 4. Gate it behind admin settings

Ship the assistant off by default, and let admins turn it on once they trust the
answers. Two settings, checked at the top of *every* manifest and tool endpoint:

- `assistant_enabled` — master switch for the app
- `assistant_visible_to_all` — when off, only admins see it

```python
async def _check_assistant_enabled(user: dict, db: AsyncSession) -> None:
    enabled = await settings_service.get_value(db, "assistant_enabled")
    if not enabled:
        raise HTTPException(status_code=403, detail="Assistant disabled for this app")
    visible_to_all = await settings_service.get_value(db, "assistant_visible_to_all")
    if not user.get("is_admin") and not visible_to_all:
        raise HTTPException(status_code=403, detail="Assistant not visible to non-admin users in this app")
```

Surface both as toggles in the app's admin page.

### 5. Onboard the app

assistant-service caches each app's manifest. TaskTool calls the S2S endpoint
when an app is registered; trigger it manually after a manifest change:

```
POST https://assistant.tasktool.medialine.com/api/assistant/onboard
  headers: X-Service-Api-Key: <SERVICE_API_KEY>
  body:    { "app_slug": "your-app-slug", "jwt": "<a tasktool service token>" }
```

It fetches your `/manifest`, persists it, and returns `tools_count` /
`actions_count` — a quick way to confirm the manifest parsed as you intended.

## Writing a good manifest

The manifest is a prompt, not a schema dump. What separates a useful assistant
from a frustrating one:

- **Invest in the glossary.** An assistant that doesn't know "Mandant" means a
  business unit will confidently produce nonsense. Define every internal term,
  including status values and scoring thresholds.
- **Descriptions say when to use a tool**, not just what it returns.
- **Tools stay read-only. Always.** Anything that mutates belongs in `actions`,
  even when it feels harmless.
- **Actions point at endpoints that already exist.** Never add an endpoint
  purely for the assistant — if the user can't do it by clicking, the assistant
  shouldn't do it either.
- **Enforce ownership in the callback.** The user's JWT arrives, but the checks
  are yours to write: `if not user["is_admin"] and upload.uploaded_by != user["email"]: 403`.
- **Start with 3–5 tools.** Grow from real questions users ask, not from a
  survey of your models.

## Troubleshooting

- **Launcher doesn't appear** — `user`/`token` falsy, or `assistant_enabled` is
  off, or the user isn't an admin while `assistant_visible_to_all` is off.
- **"Tool is not in this app's manifest"** — the manifest cache is stale; re-run
  onboard.
- **Tool returns 403** — expected when ownership checks reject; the assistant
  reports it rather than escalating.
- **Confirmed action 404s** — the action's `path` template didn't resolve. Every
  `{placeholder}` must match a key in `params_schema`; leftovers go in the body.

## Known drift in assistant-service

- `tool_dispatcher.py`'s module docstring says read tools are dispatched with
  POST. The code does `client.get(url, params=…)` — **tool callbacks are GET**
  with query params, as `leads-united` implements them.
- The `frontend_snippet` returned by `/api/assistant/onboard` omits the required
  `token` and `appBaseUrl` props. Use the snippet in step 2 instead.
