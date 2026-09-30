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

| Service | What it gives you | Skill |
|---|---|---|
| **Pulse** | In-app feedback widget (floating button, form, screenshot capture) + admin backend to triage what users report | [`pulse-feedback`](../pulse-feedback/SKILL.md) |
| **Assistant** | Platform AI assistant — one brain, every app. Floating ✨ launcher + ⌘-K spotlight that answers questions, looks up your app's records, and proposes actions the user confirms | [`ai-assistant`](../ai-assistant/SKILL.md) |
| **Auth** | TaskTool SSO: Entra login + RS256 platform JWT issuance. Apps only verify with the mounted public key — no app-side login | [`auth-integration`](../auth-integration/SKILL.md) |
| **MinIO** | Shared S3-compatible object storage, per-app users + bucket policies | [`object-storage`](../object-storage/SKILL.md) |
| **Vector service** | Shared Milvus collections for RAG / semantic search | [`vector-search`](../vector-search/SKILL.md) |
| **ext-api-service** | Gateway to external APIs. Never call a vendor API directly from an app — ask the gateway which APIs this installation offers (`list_apis`, `get_api`) | — |
| **cicd-service** | Jenkins job + webhook provisioning | [`jenkins-pipeline`](../jenkins-pipeline/SKILL.md) |
| **Diag API** | Read-only prod introspection: container logs, stats, proxied requests, SELECTs | `diag-api` |

> The repository behind each service is deliberately not listed. You do not need
> it to consume a service, and the platform repositories are not readable from an
> app developer's account. Everything you need is in the linked skill.

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
