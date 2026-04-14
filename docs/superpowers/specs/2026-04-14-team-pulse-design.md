# Team Pulse — Design Spec

## Overview

A `/team-pulse` slash command that summarizes the Enterprise Ready team's current
work across GitHub and Jira. Produces a daily-usable snapshot with two tiers of
attention: "directly on your plate" and "might want eyes on." Stays conversational
after the summary for drill-down and action-taking.

## Architecture

Command + parallel subagents (hybrid per-member + synthesis).

```
/team-pulse [lookback]
       │
       ▼
┌─────────────────────┐
│  Orchestrator        │
│  (team-pulse.md)     │
│                      │
│  1. Resolve roster   │
│     via GH teams API │
│  2. Query Mat's own  │
│     PRs + Jira       │
│  3. Dispatch member  │
│     agents (parallel)│
│  4. Dispatch synth   │
│     agent            │
│  5. Present summary  │
└─────────────────────┘
       │
       ├──── member-pulse agent (x10, parallel)
       │     ├── gh: open PRs, merged PRs, review status, CI
       │     └── jira: assigned tickets, status changes, blocked
       │
       └──── team-pulse-synthesis agent (sequential, after members)
             ├── aggregate member reports
             ├── identify risk / cross-cutting via Sourcegraph
             └── build structured summary
```

## Components

### 1. `/team-pulse` Command

**File:** `claude-config/commands/team-pulse.md`

**Frontmatter:**
```yaml
---
id: team-pulse
aliases: [tp]
tags:
  - team
  - daily
permissions:
  - "Bash(gh:*)"
  - "Bash(jq:*)"
  - "Bash(acli:*)"
  - "Read"
  - "Glob"
  - "Grep"
  - "mcp__sourcegraph__diff_search"
  - "mcp__sourcegraph__read_file"
  - "mcp__sourcegraph__keyword_search"
  - "mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql"
  - "mcp__claude_ai_Atlassian_Rovo__getJiraIssue"
  - "mcp__claude_ai_Atlassian_Rovo__lookupJiraAccountId"
---
```

**Behavior:**
1. Parse optional lookback arg (default: `3d`). Accepts `Nd` format.
2. Resolve ER team roster: `gh api /orgs/agilebits-inc/teams/enterprise-ready/members -q '.[].login'`
3. Resolve Mat's GH username: `gh api /user -q '.login'`
4. Query Mat's direct items inline (small, fast):
   - PRs requesting Mat's review: `gh search prs --review-requested={mat_login} --owner=agilebits-inc --state=open`
   - Mat's assigned Jira tickets:
     `acli jira workitem search --jql "project = ER AND assignee = currentUser() AND statusCategory != Done" --json | jq '[.[] | {key, summary: .fields.summary, status: .fields.status.name}]'`
5. Dispatch one `member-pulse` agent per teammate (excluding Mat), all in a single
   parallel batch. Each receives: member GH login, display name (from GH profile),
   lookback window, ER project key.
6. After all member agents return, dispatch one `team-pulse-synthesis` agent with:
   all member reports, Mat's direct items, Mat's GH login, lookback window.
7. Present the synthesis agent's output directly to the user.
8. Remain conversational — ready for follow-up questions and actions.

### 2. `member-pulse` Agent

**File:** `claude-config/agents/member-pulse.md`

**Frontmatter:**
```yaml
---
name: member-pulse
description: Gather GitHub PR and Jira activity for a single ER team member. Dispatched by /team-pulse with member login, lookback window, and project key.
tools: Bash, mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian_Rovo__getJiraIssue, mcp__claude_ai_Atlassian_Rovo__lookupJiraAccountId
---
```

**Receives via prompt:** member GH login, display name, lookback window, ER project key.

**Data gathering:**

*GitHub (two-step — search then view for full details):*
- Search open PRs: `gh search prs --author={login} --owner=agilebits-inc --state=open --json number,title,repository,createdAt,url`
- For each PR, get review/CI details: `gh pr view {number} -R {repo} --json reviewDecision,statusCheckRollup,reviewRequests`
- Search recently merged (within lookback): `gh search prs --author={login} --owner=agilebits-inc --state=closed --merged --json number,title,repository,url,closedAt`
- Filter merged PRs by lookback window locally

*Jira (via `acli`):*
- Tickets with recent transitions:
  `acli jira workitem search --jql 'project = ER AND assignee = "{display_name}" AND status changed AFTER -{lookback}' --json | jq '[.[] | {key, summary: .fields.summary, status: .fields.status.name}]'`
- Currently in-progress:
  `acli jira workitem search --jql 'project = ER AND assignee = "{display_name}" AND status = "In Progress"' --json | jq '[.[] | {key, summary: .fields.summary}]'`
- Blocked/flagged:
  `acli jira workitem search --jql 'project = ER AND assignee = "{display_name}" AND flagged is not EMPTY' --json | jq '[.[] | {key, summary: .fields.summary, status: .fields.status.name}]'`

**Jira tooling:** Both `acli` CLI and Atlassian Rovo MCP tools are available.
Prefer `acli` for JQL search (simpler, pipes to jq). Use Rovo MCP for user lookup
(`lookupJiraAccountId`) and operations `acli` can't do. The orchestrator passes
the display name (from GH profile: `gh api /users/{login} -q .name`) for Jira
queries. If a display name doesn't match, try the GH login without the `_1pw`
suffix as a fallback.

**Output format:** Structured text summary for that member:
```
## {Display Name} (@{login})

### Open PRs
- repo#123 — title (age, review status, CI status)

### Recently Merged
- repo#456 — title (merged date)

### Jira — In Progress
- ER-789 — title (status)

### Jira — Status Changes
- ER-101 — title (from -> to, date)

### Blocked / Flagged
- ER-102 — title (reason if available)
```

### 3. `team-pulse-synthesis` Agent

**File:** `claude-config/agents/team-pulse-synthesis.md`

**Frontmatter:**
```yaml
---
name: team-pulse-synthesis
description: Aggregate member-pulse reports into a team dashboard. Identifies risk, cross-cutting changes, and blocked work. Dispatched by /team-pulse after all member agents complete.
tools: Bash, mcp__sourcegraph__diff_search, mcp__sourcegraph__read_file, mcp__sourcegraph__keyword_search
---
```

**Receives via prompt:** all member reports, Mat's direct items, Mat's GH login,
lookback window.

**Responsibilities:**

1. **Needs Your Attention** — PRs explicitly requesting Mat as reviewer. Mat's
   assigned Jira tickets with status context.
2. **Flagged for Review** — Scan member reports for PRs that look cross-cutting,
   risky, or span multiple domains. Use Sourcegraph (`diff_search`, `read_file`)
   to inspect diffs of interesting PRs. Flag with a reason (e.g., "touches CI
   pipeline", "modifies shared auth middleware", "large diff across 3 services").
3. **Team Activity** — What shipped (merged PRs), what's in flight (open PRs),
   Jira movement (status changes).
4. **Blocked / Stuck** — Aggregate blocked Jira tickets and stale PRs (no review
   activity in 3+ days, failing CI) across all members.

**Output format:**
```
# Team Pulse — Enterprise Ready

## Needs Your Attention
(Mat's review requests + assigned tickets)

## Flagged for Review
(Cross-cutting / risky changes with reasons)

## Team Activity
### What Shipped
### In Flight
### Jira Movement

## Blocked / Stuck
(Aggregated across members)
```

## Configuration

**Team:** Enterprise Ready
**GitHub org:** `agilebits-inc`
**GitHub team slug:** `enterprise-ready`
**Jira project:** `ER`
**Jira board:** 1339
**Default lookback:** 3 days

## Iteration Plan

**V1 (walking skeleton):**
- Command + member agents gathering GH PRs only (no Jira)
- Basic synthesis — aggregate and present, no Sourcegraph risk analysis
- Validate the parallel agent orchestration works

**V2:**
- Add Jira data to member agents
- Add "Needs Your Attention" section with Mat's direct items

**V3:**
- Synthesis agent uses Sourcegraph to analyze cross-cutting/risky PRs
- "Flagged for Review" section with reasons

**V4+:**
- Action-taking (review PRs, comment on tickets inline)
- Add Admin Workflow team when ready
- Configurable team selection via args
