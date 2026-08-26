# claude-plugin-platform

Medialine's Claude Code plugin marketplace + the `medialine-platform` plugin it publishes. Pinned by every Medialine repo so updates propagate from one place.

## What lives here

```
.claude-plugin/marketplace.json   ← marketplace catalog (lists medialine-platform)
docs/developer-guide.md           ← Entwickler (DE): Installation, Update, Nutzung
docs/admin-guide.md               ← Betrieb (DE): Onboarding, Release, Bereitstellung
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

To pull a new version: `autoUpdate` refreshes the **marketplace clone**, which is
not the same as updating your **installed** copy — the clone can be current while
the install is stale. In the Claude Code CLI, run `/plugin marketplace update
medialine` then `/plugin update medialine-platform@medialine`. The VS Code
extension has no command line for these: use the `/plugin` panel's
**Marketplaces** tab instead. Either way, reload the window afterwards — plugins
load at session start, so a running session keeps the copy it began with.

## Governance

A single `claude-config-dri` in TaskTool (extension of `platform.users.role`) owns this repo. They:

- Approve every PR (default branch is `main`, protected — see [Branch Workflow](./medialine-platform/rules/branch-workflow.md))
- Bump the plugin's `version` in `medialine-platform/.claude-plugin/plugin.json` on **every** merged change, docs included — an unbumped change never reaches installs (see [Versioning](#versioning))
- Run the quarterly convention review per Anthropic's [best-practices guidance](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start) — retire rules that newer models no longer need, add skills that real session patterns prove worth promoting
- Triage proposals from the closed feedback loop (see Track D in the rollout plan: Claude proposes plugin updates when it spots reusable patterns; MCP-server telemetry surfaces repeated curl-fallbacks)

## Versioning

This plugin uses semver in `medialine-platform/.claude-plugin/plugin.json`. Repos pin major versions (e.g. `^1.0.0`) and auto-pick up minor/patch bumps. Major bumps require explicit per-repo updates.

**Every merged change under `medialine-platform/` MUST bump the version — docs-only changes included.** Installs are keyed on the version string. If the version is unchanged, the installer sees the plugin as already up to date and never copies the new content, so the change reaches nobody: it sits in the marketplace clone looking merged while every session keeps loading the old copy. Re-adding the marketplace does not fix it, because the install step still sees a matching version.

Repo-level files are **not** part of the installed payload — only `medialine-platform/**` is copied into an install. Changes limited to `README.md`, `QUARTERLY_REVIEW.md` or `docs/` therefore need no bump.

This plugin is almost entirely rules and skills, so a docs change *is* the behaviour change. There is no content edit here that does not warrant a bump.

When you change the plugin contents:
- **Patch** (`1.0.x`): typo fix, clarification, reworded rule — anything that neither adds nor removes a component
- **Minor** (`1.x.0`): new skill / new rule / new agent / new hook (additive)
- **Major** (`x.0.0`): removed or renamed convention, hook that may break existing repos

A version number alone does not prove a release landed — two installs can share a version and differ in content. To verify:

```bash
diff -rq ~/.claude/plugins/marketplaces/medialine/medialine-platform \
         ~/.claude/plugins/cache/medialine/medialine-platform/<version>
```

## Related

- Entwickler-Handbuch (DE): [docs/developer-guide.md](./docs/developer-guide.md)
- Admin-Handbuch (DE): [docs/admin-guide.md](./docs/admin-guide.md)
- The rollout plan: `tasktool/.claude/plans/logical-toasting-dolphin.md`
- Anthropic plugin docs: <https://code.claude.com/docs/en/plugins>
- Marketplace docs: <https://code.claude.com/docs/en/plugin-marketplaces>
