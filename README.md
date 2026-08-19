# claude-plugin-platform

Medialine's Claude Code plugin marketplace + the `medialine-platform` plugin it publishes. Pinned by every Medialine repo so updates propagate from one place.

## What lives here

```
.claude-plugin/marketplace.json   ← marketplace catalog (lists medialine-platform)
medialine-platform/                ← the plugin
├── .claude-plugin/plugin.json     ← plugin manifest (name, version, author)
├── skills/                        ← Claude-invokable skills (model-discovered)
│   ├── ai-assistant/              ← + references/manifest-example.md
│   ├── auth-integration/SKILL.md
│   ├── cloud-workflow/SKILL.md
│   ├── jenkins-pipeline/SKILL.md
│   ├── medialine-dev-credentials/SKILL.md
│   ├── object-storage/SKILL.md
│   ├── platform-services/         ← index of shared services
│   │                                 + references/widget-build-wiring.md
│   ├── port-allocation/SKILL.md
│   ├── pulse-feedback/SKILL.md
│   ├── vector-search/SKILL.md
│   └── vibes-conventions/SKILL.md
├── rules/                         ← always-loaded conventions (Medialine extension)
│   ├── app-baseline.md
│   ├── branch-workflow.md
│   ├── cloud-only.md
│   ├── conventional-commits.md
│   ├── documentation.md
│   ├── feedback-loop.md
│   ├── medialine-stack.md
│   └── security.md
├── scripts/                       ← hook implementations (invoked via CLAUDE_PLUGIN_ROOT)
│   ├── block-host-installs.sh     ← PreToolUse: enforce cloud-only
│   ├── docs-review-gate.sh        ← PreToolUse: doc-review reminder on commit
│   └── platform-baseline-notice.sh ← SessionStart: flag unused platform services
├── agents/                        ← subagent definitions
│   ├── backend-developer.md
│   ├── frontend-developer.md
│   ├── integrator.md
│   └── reviewer.md
└── hooks/hooks.json               ← PreToolUse / PostToolUse handlers
```

Future additions: `medialine-platform/.mcp.json` (registers the Medialine MCP servers — Track B in the rollout plan).

## Use it from your repo

Each repo ships a committed `.claude/settings.json` that both registers the
marketplace and enables the plugin (Claude Code's native mechanism — there is
**no** `.claude/plugins.json`; that file is silently ignored):

```json
{
  "extraKnownMarketplaces": {
    "medialine": {
      "source": {
        "source": "git",
        "url": "https://gitea.medialine.com/medialine/claude-plugin-platform.git"
      },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "medialine-platform@medialine": true
  }
}
```

On a fresh clone, trust the folder; Claude Code prompts to install the
`medialine` marketplace, then auto-enables the plugin on session start —
skills/rules/agents/hooks all light up. No manual
`claude plugin marketplace add` needed.

> Prereq: the gitea CA cert must be trusted in git config (`http.<gitea>.sslcainfo`)
> so the git marketplace source can fetch — the same cert any gitea clone needs.
> No `http.sslVerify=false` required.

To pull a new version: `autoUpdate` refreshes the marketplace on startup; or run
`/plugin marketplace update medialine` then `/plugin update medialine-platform@medialine`.

## Governance

A single `claude-config-dri` in TaskTool (extension of `platform.users.role`) owns this repo. They:

- Approve every PR (default branch is `main`, protected — see [Branch Workflow](./medialine-platform/rules/branch-workflow.md))
- Bump the plugin's `version` in `medialine-platform/.claude-plugin/plugin.json` on release
- Run the quarterly convention review per Anthropic's [best-practices guidance](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) — retire rules that newer models no longer need, add skills that real session patterns prove worth promoting
- Triage proposals from the closed feedback loop (see Track D in the rollout plan: Claude proposes plugin updates when it spots reusable patterns; MCP-server telemetry surfaces repeated curl-fallbacks)

## Versioning

This plugin uses semver in `medialine-platform/.claude-plugin/plugin.json`. Repos pin major versions (e.g. `^1.0.0`) and auto-pick up minor/patch bumps. Major bumps require explicit per-repo updates.

When you change the plugin contents:
- **Patch** (`1.0.x`): typo fix, clarification, no behavior change
- **Minor** (`1.x.0`): new skill / new rule / new agent / new hook (additive)
- **Major** (`x.0.0`): removed or renamed convention, hook that may break existing repos

## Related

- The rollout plan: `tasktool/.claude/plans/logical-toasting-dolphin.md`
- Anthropic plugin docs: <https://code.claude.com/docs/en/plugins>
- Marketplace docs: <https://code.claude.com/docs/en/plugin-marketplaces>
