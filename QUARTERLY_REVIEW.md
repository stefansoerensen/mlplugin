# Quarterly Review

Anthropic recommends reviewing Claude Code configuration **every 3–6 months** because model improvements steadily make older skills, rules, and hooks obsolete. This document is the DRI's checklist for the Medialine quarterly review.

**Cadence**: every calendar quarter (Q1: March, Q2: June, Q3: September, Q4: December). Tracked as a recurring task in TaskTool admin.

**Time budget**: 60–90 minutes per review.

---

## 1. Skills

For every `medialine-platform/skills/<name>/SKILL.md`:

- [ ] **Still describes reality?** Container names, endpoints, file paths, CLI flags — anything stale gets a PR.
- [ ] **Still pulls its weight?** Run `mcp-diag.db_query` against Loki (when Flow 2 telemetry is live) to see how often the skill is invoked. A skill called 0 times in 90 days is a candidate for removal.
- [ ] **Could be replaced by an MCP tool?** Curl recipes inside a skill are tech debt; if the operation belongs in `mcp-gitea`/`mcp-jenkins`/`mcp-diag`, open an issue.

## 2. Rules

For every `medialine-platform/rules/<name>.md`:

- [ ] **Does the current Claude model still need this?** Re-read the rule. Did it exist because an older model struggled with the pattern? Test the model without the rule on a small task; if the model gets it right, the rule is overhead.
- [ ] **Has the underlying constraint changed?** `docker-first.md` is fine because Docker isn't going anywhere. `medialine-stack.md` may need quarterly tech-stack updates (new approved library, dropped one).
- [ ] **Can it be tightened?** Vague rules age worse than specific ones. "Always validate input" → "Use Pydantic models on every FastAPI endpoint."

## 3. Agents

For every `medialine-platform/agents/<name>.md`:

- [ ] **Does the role match how agents actually run today?** `backend-developer.md` from 2 quarters ago may predate FastMCP, Streamable HTTP, or the platform JWT flow we just shipped.
- [ ] **Tool list current?** If new MCP servers exist (`mcp-gitea`, etc.), they should be in the agent's allowed-tools list.

## 4. Hooks (`hooks/hooks.json`)

- [ ] **Each hook still load-bearing?** A hook blocking `pip install` is great; a hook blocking a command no one runs anymore is overhead.
- [ ] **No conflicts with user globals?** Confirm the plugin's hooks merge cleanly with users' `~/.claude/settings.json`.

## 5. MCP servers

For every `mcp-*` server in `medialine/mcp-servers`:

- [ ] **Telemetry sanity** (once Flow 2 is live): error rate, fallback-rate, top-N tools by call count.
- [ ] **Auth still tight?** Rotate the APIM subscription keys; confirm the rotation procedure in `mcp-servers/README.md` matches reality.
- [ ] **Healthchecks green?** `docker ps --filter name=mcp-` should show all five healthy.

## 6. Drift CI + proposal backlog

- [ ] **Drift CI noise level**: review the past 90 days of advisory PRs from `claude_drift_check_job`. If the same repos keep needing the advisory and no one accepts, escalate to repo owner.
- [ ] **Proposal backlog** at `/admin/claude-feedback`: triage every open proposal that's older than 30 days. Either accept, decline (with reason), or convert to a tracked task.
- [ ] **Counts by kind**: if 80% of proposals are `mcp-gap`, that's a signal we're under-tooled and should prioritize MCP-server expansion.

## 7. Plugin version bump + propagation check

After the above:

- [ ] If any change landed, bump `medialine-platform/.claude-plugin/plugin.json` `version` — patch / minor / major per the rules in [README.md](./README.md).
- [ ] **Audit for unbumped merges.** List everything merged to `main` since the last bump:
      `git log --oneline <last-version-tag>..main -- medialine-platform/`
      Any content change in that range without a version bump **never reached a single install**. Bump and re-release it.
- [ ] Tag the merge commit (`v1.x.y`).
- [ ] **Verify propagation, don't assume it.** A matching version does not prove matching content — the installer skips when the version is unchanged, so a stale install reports the current version number:
      ```bash
      diff -rq ~/.claude/plugins/marketplaces/medialine/medialine-platform \
               ~/.claude/plugins/cache/medialine/medialine-platform/<version>
      ```
      Anything other than the `.in_use` marker means the release did not land.
- [ ] Announce to platform users (Teams / email) so they update via `/plugin marketplace update medialine` (CLI) or the `/plugin` panel's Marketplaces tab (VS Code extension).

---

## DRI worksheet

Fill in per review, commit alongside any change PRs:

```
Reviewed: YYYY-Q[1-4]   By: <user>   Duration: __ min
Skills retired:         <list>
Rules retired/changed:  <list>
Agents updated:         <list>
MCP servers added:      <list>
Open proposals triaged: <count>
Plugin version bumped:  v__.__.__
Notes:                  <anything for next quarter>
```
