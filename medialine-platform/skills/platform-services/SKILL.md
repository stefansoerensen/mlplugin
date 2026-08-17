---
name: platform-services
description: Index of every shared Medialine platform service (feedback widget, AI assistant, SSO, object storage, vector search, CI/CD, diagnostics) — read this when starting a new app, adding a feature, or wondering whether a capability already exists platform-wide
user-invocable: false
---

# Shared Platform Services

Medialine apps are **thin**. Almost every cross-cutting capability already
exists as a shared service on `medialine_network` behind
`*.tasktool.medialine.com`. Building a private version of one of these is a
convention violation, not a shortcut.

Read this index before you build anything that smells cross-cutting:
feedback, chat/AI, login, file upload, search, notifications, deployment.

## The services

| Service | Repo | What it gives you | Skill |
|---|---|---|---|
| **Pulse** | `medialine/pulse` | In-app feedback widget (floating button, form, screenshot capture) + admin backend to triage what users report | [`pulse-feedback`](../pulse-feedback/SKILL.md) |
| **Assistant** | `medialine/assistant-service` | Platform AI assistant — one brain, every app. Floating ✨ launcher + ⌘-K spotlight that answers questions, looks up your app's records, and proposes actions the user confirms | [`ai-assistant`](../ai-assistant/SKILL.md) |
| **Auth** | `medialine/auth-service` | TaskTool SSO, JWT issuance, dual-mode standalone login | [`auth-integration`](../auth-integration/SKILL.md) |
| **MinIO** | `medialine/infrastructure` | Shared S3-compatible object storage, per-app users + bucket policies | [`object-storage`](../object-storage/SKILL.md) |
| **Vector service** | `medialine/vector-service` | Shared Milvus collections for RAG / semantic search | [`vector-search`](../vector-search/SKILL.md) |
| **ext-api-service** | `medialine/ext-api-service` | Gateway to external APIs (companyai/Claude, Lusha, Handelsregister, …). Never call a vendor API directly from an app | — |
| **cicd-service** | `medialine/cicd-service` | Jenkins job + Gitea webhook provisioning | [`jenkins-pipeline`](../jenkins-pipeline/SKILL.md) |
| **Diag API** | `medialine/tasktool` | Read-only prod introspection: container logs, stats, proxied requests, SELECTs | `diag-api` |

## The two widget services

Pulse and Assistant are the two that apps embed as **React widgets**, and they
are the two most often forgotten. They share one build mechanism — the widget
source is cloned by Jenkins and built as a Docker build-context stage, *not*
installed from an npm registry. That wiring is identical for both and is
documented once in
[`references/widget-build-wiring.md`](./references/widget-build-wiring.md).

`medialine/aboabrechnung` is the reference implementation: it has both widgets
wired end to end (Dockerfile stages, Jenkinsfile clone, wrapper components).

## Baseline expectation

Every user-facing app is expected to ship SSO, the Pulse widget, and the
Assistant widget. That is a rule, not a suggestion — see
[`rules/app-baseline.md`](../../rules/app-baseline.md).

## If the capability you need isn't here

Don't build it privately. Two options, in order:

1. Check whether an existing service should grow the feature (open an issue on
   that repo).
2. If it's genuinely new and cross-cutting, it's a new platform service — raise
   it with the platform DRI before writing code in an app repo.

If you hit a gap in *this* plugin while doing that, use
`mcp-plugin.propose_update` per [`rules/feedback-loop.md`](../../rules/feedback-loop.md).
