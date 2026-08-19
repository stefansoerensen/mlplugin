---
paths:
  - "**/*"
---

# App Baseline (MANDATORY for new apps)

Medialine apps are thin clients on a platform that already solves the
cross-cutting problems. Before building any capability that smells
cross-cutting — feedback, AI chat, login, file storage, search, deployment —
check [`platform-services`](../skills/platform-services/SKILL.md). Building a
private version of a shared service is a convention violation.

Every new user-facing app ships all four of these before it is considered done:

1. **TaskTool SSO** — dual-mode auth via auth-service. → [`auth-integration`](../skills/auth-integration/SKILL.md)
2. **Pulse feedback widget** — mounted at app root, app registered in Pulse. → [`pulse-feedback`](../skills/pulse-feedback/SKILL.md)
3. **Platform AI assistant** — widget mounted plus an `/api/assistant-tools/manifest`
   carrying at minimum a real glossary. Ships gated off; tools and actions grow
   over time. → [`ai-assistant`](../skills/ai-assistant/SKILL.md)
4. **`docs/` in the repo** — what the app is for, its domain vocabulary, and its
   integration points. `CLAUDE.md` covers how to work on the app; `docs/` covers
   what the app *is*. → [`documentation`](./documentation.md)

## Existing apps

This rule does not authorize opportunistic retrofits. If you are working in an
app that is missing part of the baseline, **say so and offer** — do not widen
the current task to add a widget nobody asked for. Backfill is tracked
separately per app.

## Shared services document themselves in the plugin

A service repo's own `README`/`CLAUDE.md` is invisible from every other repo's
session, which is why capabilities go unused. If you build or change a shared
platform service, its **integration contract belongs in a plugin skill** —
propose it via `mcp-plugin.propose_update` per
[`feedback-loop`](./feedback-loop.md). The service repo keeps the deep
implementation docs; the skill carries what a consuming app needs.

## Why

Audited 2026-08: the Pulse widget was live in 5 of 12 apps and the assistant in
2 of 12 — not because teams rejected them, but because nothing in a consuming
app's session made them discoverable. Feedback that never reaches Pulse is
feedback the team never sees.
