# Feedback Loop (mandatory)

This plugin compounds in value when sessions push insights back into it. The mechanism is the `mcp-plugin.propose_update` tool. Use it whenever you notice any of these patterns.

## When to call `propose_update`

- **Re-discovered curl**: the same curl recipe (or any pattern) appears in the session more than once. The right place is a tool on an MCP server or a step in a SKILL.md — not a paste from memory.
- **SKILL doesn't match reality**: a skill says "the container is X" but the actual container is Y; a skill references an old endpoint path; the rule contradicts what the model just had to do.
- **Plugin gap**: you had to invent a workaround because no skill / tool / rule covered the case. The workaround is the proposal.
- **Obsolete rule**: a rule made you take a slower path than the model can now handle (per Anthropic's [best-practices guidance](https://claude.com/blog/how-claude-code-works-in-large-codebases-best-practices-and-where-to-start), rules age out with model upgrades). Propose removing it.
- **MCP tool missing**: you needed a Gitea / Jenkins / diag operation that no `mcp-*` server exposes. Propose adding the tool.

## How to call it

```
mcp-plugin.propose_update(
  kind="new-skill" | "skill-fix" | "rule-update" | "agent-fix" | "mcp-gap" | "hook-update",
  title="<one-line summary>",
  rationale="<why this matters; the trigger pattern; consequence of leaving it>",
  proposed_change="<plain-English description of what should change>",
  target_path="<file in claude-plugin-platform that would change, optional>",
  new_file_content="<full new content of target_path, optional — turns the stub PR into a real diff>",
  originating_repo="<medialine/...>",
  originating_user="<username from the session>",
)
```

The server opens a **draft PR** against `medialine/claude-plugin-platform` with the full context. The DRI triages from `mcp-plugin.list_recent_proposals` or the `/admin/claude-feedback` page in TaskTool.

## Confirm with the dev first

You're a guest in the dev's session. **Always** ask "Want me to open a draft PR against `medialine/claude-plugin-platform` with this?" — never call `propose_update` silently. If they say no, drop it.

## What `propose_update` is not

- Not a place to dump session learnings about the specific repo — that's [auto-memory](https://docs.claude.com/en/docs/claude-code/memory).
- Not a fix-it-yourself button — the DRI reviews + adapts every proposal.
- Not a confession of failure — every proposal makes the next dev's session faster.
