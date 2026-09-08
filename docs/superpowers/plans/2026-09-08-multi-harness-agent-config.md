# Multi-Harness Agent Configuration Implementation Plan

> **Status (2026-09-08):** executed in reduced form. What landed, what was deferred, and the
> evidence are in `claude-config/docs/compatibility.md` and the `agent-config` skill.
> Deferred by decision: the `claude-config` → `agent-config` rename (Task 5) and the
> `shared/` + `harnesses/` restructure (Task 3) — both pure path churn with no behavior
> change; revisit if a third harness arrives. Dropped: the symlink fixture test suite
> (Task 4) in favor of an idempotent installer plus `agent/check_agent_config.sh`.

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. This document authorizes planning only; Mat will initiate execution separately. Do not infer permission to migrate, rename repositories, switch branches, commit, or push from this document.

**Goal:** Maintain Claude Code and Codex from one personally controlled configuration repository, sharing stable content and deliberately adapting harness-specific behavior.

**Architecture:** Evolve the existing `claude-config` submodule toward `agent-config`. Keep Mat's dotfiles installer as the installation mechanism. A maintenance skill owns adaptation decisions; small local scripts perform predictable installation and verification operations.

**Tech stack:** Existing shell setup scripts and `lib/helpers.sh`, Git, Markdown/Agent Skills, native Claude JSON and Codex TOML. Reuse existing runtimes and dependencies.

**Spec:** The design decisions and boundaries in this document are the consolidated specification from the planning conversation. No separate design document is required to understand or execute it.

## Constraints and decisions

- Preserve the existing dotfiles installation approach. Do not introduce Ruler, Vercel Skills, a configuration framework, a new package manager, or an automatic synchronization service.
- Borrow community patterns, not entire implementations. Add abstractions only where actual configuration requires them.
- Support both harnesses independently. Also verify Codex delegation from Claude; delegation must not be the only working Codex entry point.
- Share files only when meaning, dependencies, and lifecycle match. A common format does not establish equivalent invocation or enforcement.
- Native configuration remains native. Do not invent a universal schema for permissions, models, hooks, or subagent controls.
- Project knowledge remains in its project repository. The personal configuration repository owns personal defaults, reusable assets, and maintenance procedures.
- Keep work/personal machine separation. Preserve `.dotfiles-profile` behavior and work-only plugin/integration selection.
- Each installed artifact or configuration key has one owner: this repository, the harness/application, a plugin manager, or the local user.
- Preserve unmanaged files, application-written settings, credentials, trust decisions, and installed caches. Do not treat entire native configuration directories as disposable output.
- No automatic push, broad staging, destructive reset, or deletion of unexpected files. Use `trash` for approved deletes.
- Keep files under 500 lines. Do not rewrite unrelated installer helpers or unrelated skills as part of this migration.
- Instruction-content changes to `AGENTS.md`/`CLAUDE.md` require Mat's review. Do not silently resolve behavioral conflicts while moving files.

## Current baseline: recheck before execution

Observed September 8, 2026:

- `~/dotfiles/.gitmodules` declares the `claude-config` submodule at `git@github.com:mpataki/claude-config.git`.
- `install.sh` sources `claude/setup_claude.sh`; that script links instructions, skills, agents, commands, settings, and workflows, then configures MCPs/plugins and the work profile.
- `claude-config/CLAUDE.md` is newer than `~/.codex/AGENTS.md`. The Codex copy references a nonexistent `~/dotfiles/Codex-config` tree and contains different interaction/approval conventions.
- `~/.agents/skills` includes independent directories rather than being wholly linked to the current Claude source.
- `~/.codex/config.toml` mixes user configuration with app/plugin/runtime state. Replacing it wholesale would lose unrelated settings.
- `claude-config/skills/add-mcp/SKILL.md` targets Claude; a separate installed Codex copy targets Codex. These need semantic comparison, not hash-only deduplication.
- `claude-config/skills/skill-creator/SKILL.md` specifies Claude-oriented global and project locations.
- `lib/helpers.sh` contains destructive replacement branches in `check_and_link_file` and `git_clone`. Do not call those branches during migration. Reuse safe helpers and add a narrowly scoped, non-destructive installation operation where necessary.
- The dotfiles working tree had unrelated changes in `git/gitignore`, `ssh/config`, and the `claude-config` submodule. Preserve whatever work is present when execution begins.

## Boundaries

| Layer | Contents | Rule |
| --- | --- | --- |
| Shared intent | Engineering tactics, Git policy, verification expectations | One authoritative definition; adaptations cite it |
| Portable assets | Skill procedures, references, executable helpers | Same files when semantics and dependencies match |
| Native adaptations | Hooks, permissions, model routing, agent registration, MCP registration | Native implementation, explicit limitations |
| Local state | Authentication, trust, caches, app preferences, session history | Harness/machine-owned; excluded from synchronization |
| Delegation | Task brief, directory, authority, required skills, report contract | Explicit handoff; no assumed conversation inheritance |

Direct collaboration and delegated execution are separate modes. Conversational teaching/predict-first behavior belongs with the user-facing coordinator. Delegated builders share engineering requirements but receive bounded execution instructions and return evidence.

## Intended file ownership

Use the existing `claude-config` path while bootstrapping the maintenance skill. Perform the final path move only after inventory and explicit cutover authorization.

```text
dotfiles/
  install.sh
  .gitmodules
  claude/setup_claude.sh          # Claude-native setup, retained
  codex/setup_codex.sh            # Codex-native setup, added
  agent/setup_agent.sh            # shared installation selection/orchestration
  agent/lib/install_owned.sh     # narrow safe operations, only if needed
  agent/check_agent_config.sh     # structural/configuration checks
  agent/tests/                   # filesystem fixtures for new install operations
  agent-config/                  # existing configuration submodule, evolved
    README.md                    # source ownership, installation, maintenance
    shared/
      instructions/              # shared behavioral content
      skills/                    # portable skills, including maintenance skill
      code-tactics/              # existing catalog; preserve content
    harnesses/
      claude/                    # native settings, hooks, agents, plugins
      codex/                     # native settings source, rules, hooks, agents
    docs/
      compatibility.md           # intent -> implementations -> evidence
      migration-inventory.md     # temporary cutover record, no secrets
```

The diagram assigns ownership; it does not require empty directories. Keep platform-specific references inside the skills that use them. Keep existing skill names unless a real collision requires a reviewed rename.

For project repositories, use root `AGENTS.md` and canonical `.agents/skills/<name>/`. `CLAUDE.md` may be a relative symlink when content is identical, or a thin native wrapper importing shared instructions when differences exist. Link individual skills into native discovery locations. Arbitrary files under `.agents/` need explicit references; the directory is not a universal autoload mechanism.

For global instructions, install into each harness's documented entry point. Do not assume `~/.agents/AGENTS.md` is discovered. Prefer real native skill directories with individual owned links so local entries can coexist. Where global instructions need composition, render literal shared-plus-native text deterministically; do not rely on one harness understanding another's import syntax.

## Task 1: Inventory and classify without changing live configuration

**Files:** Create `claude-config/docs/migration-inventory.md` and `claude-config/docs/compatibility.md` when execution is authorized.

- [ ] Inspect both repositories with `git status --short`, `git diff --stat`, and `git submodule status`. Establish which in-flight changes must land before cutover; do not stash or absorb them.
- [ ] Inventory tracked sources and installed entry points for instructions, skills, hooks, agents, commands, MCPs, plugins, model settings, signing environment, and machine profiles. Search named directories; do not dump credentials or broad native state files.
- [ ] Record per item: source, installed destination, owner, scope, shared/native/local classification, conflict, and proposed action.
- [ ] Compare the installed Codex skills with current source skills. Preserve unique useful content; do not choose a winner by modification date or name alone.
- [ ] Record instruction differences for Mat: greeting/verbosity, predict-first, write/commit authority, push behavior, secret handling, and missing/new tactics. Present exact proposed behavioral resolutions before editing those instructions.
- [ ] Record current harness/plugin versions and effective discovery/configuration behavior using current official docs and local tool schemas. Do not freeze model identifiers or hook payload assumptions from this conversation.

**Acceptance:** Every migration candidate has an owner and action; secrets and local runtime state are excluded; unresolved instruction conflicts remain explicit.

## Task 2: Create the maintenance capability before using it to migrate

**Files:** Initially create `claude-config/skills/agent-config/SKILL.md` with `references/{boundaries,claude,codex,migration,verification}.md`. Later move the complete skill into `agent-config/shared/skills/agent-config/`.

**Interface:** Inputs are a requested configuration change, target scope, and intended harnesses. Output is a reviewable change set plus applicability and verification evidence.

- [ ] Define triggers: maintain multi-harness config, adapt a shared skill/policy, onboard a project, migrate existing configuration, and diagnose drift. Exclude ordinary application development.
- [ ] Encode the workflow: discover owner -> classify intent -> select relevant harness references -> inspect actual capabilities -> propose required semantic changes -> modify authoritative sources -> install through dotfiles -> verify.
- [ ] Separate routine maintenance from migration within the skill. Migration adds inventory, conflict resolution, backup/restore recording, and staged cutover; routine changes do not re-inventory everything.
- [ ] Require explicit handling for unavailable capabilities and lossy translations. Never silently drop a permission, tool restriction, model setting, or hook behavior.
- [ ] Route existing specialists through this boundary: `add-mcp`, personal `skill-creator`, `codify-tactic`, `session-review`, and the agent/skill manager definitions. Inspect each before editing; preserve their existing task-specific expertise.
- [ ] Add only relevant native references to each specialist. For example, `add-mcp` retains common connection intent but selects native registration and authentication handling per harness; no secrets belong in shared examples or catalogs.
- [ ] Check maintained skill names against installed/system/plugin names. Disambiguate the personal entry point where needed rather than assuming duplicate names merge.
- [ ] Exercise the new skill on three planning-only scenarios: add a portable verification skill; adapt a Git restriction; register a work-only MCP. Inspect whether it identifies the correct sources, native differences, and checks.

**Acceptance:** The skill is usable from both harnesses and produces actionable adaptations without inventing native capabilities or invoking migration on a routine request.

## Task 3: Prepare shared content and native adaptations

**Files:** Populate `claude-config/shared/` and `claude-config/harnesses/{claude,codex}/` before the path rename. Update inventoried internal references in small groups.

- [ ] Use the maintenance skill from Task 2 to classify and move portable skills and the tactics catalog. Preserve associated references/scripts/assets as complete units.
- [ ] Compose shared instructions only from reviewed decisions. Keep native tool names, configuration locations, and coordinator/worker interaction differences in native adaptations.
- [ ] Keep Claude agent metadata and Codex role configuration native. Share role responsibilities/report contracts only where meaningful; verify available tools and model routing independently.
- [ ] Preserve the Claude work plugin boundary and existing third-party plugin management. Do not copy plugin caches into owned skill directories.
- [ ] Prepare Codex-owned settings separately from live app-managed configuration. Merge only explicitly owned keys/tables; stop on conflicting unmanaged values instead of replacing the whole file. Use an existing TOML-capable runtime if available; propose any required dependency before adding it.
- [ ] Adapt hooks by event and purpose. Verify input fields, matching, output semantics, exit behavior, and registration. Audit compaction recovery, secret guarding, project-note commits, and signing environment individually.
- [ ] Put shared facts in the smallest useful source. Do not require a universal MCP/agent schema merely to eliminate two native declarations.

**Acceptance:** Shared assets have one source; every native behavior either has a verified adaptation or an explicit unsupported/deferred entry. Claude's existing behavior remains available during preparation.

## Task 4: Extend the existing installer and verify its filesystem behavior

**Files:** Add `agent/setup_agent.sh`, `codex/setup_codex.sh`, `agent/check_agent_config.sh`, and focused fixtures under `agent/tests/`. Modify `claude/setup_claude.sh` and `install.sh`. Add `agent/lib/install_owned.sh` only for operations unsafe through existing helpers.

**Interface:** Setup remains callable through the existing installer and tool-specific scripts. New filesystem operations accept explicit source/destination paths, preserve unmanaged destinations, and report conflicts. Fixture tests use an explicit temporary root, never a reassigned `HOME`.

- [ ] Follow the established prompt/setup structure and reuse safe helpers for platform detection and output. Keep native setup callable without running every tool installer.
- [ ] Implement only required operations: create an absent owned link; leave a correct link unchanged; report a wrong/unmanaged destination; restore a previously recorded owned destination during rollback.
- [ ] Add a preview path for migration operations before live writes. Convert whole-directory links to individual links only after recording their targets and resolving local contents.
- [ ] Build focused filesystem fixtures covering: absent destination, correct link, wrong link, real local entry, broken owned link, names with spaces, and interrupted/repeated setup. Confirm local content survives every case.
- [ ] Preserve `.dotfiles-profile`: work configuration only on work machines; switching away removes/disables only owned work configuration and preserves personal/app entries.
- [ ] Verify native settings remain parseable after applying owned configuration and that unrelated keys survive. Test applying twice produces no further changes.
- [ ] Run `bash -n` on changed shell files, ShellCheck if already available, and the fixture checks. Exercise new filesystem operations on macOS and Linux before claiming both verified; report an unavailable platform explicitly.

**Acceptance:** Installation is repeatable, inspectable, non-destructive to unmanaged state, and compatible with the existing workflow. Do not run the full `install.sh` as a test: it updates/installs unrelated tools.

## Task 5: Cut over the submodule path and installed configuration

**Files:** Update `.gitmodules`, affected paths in setup scripts, and inventoried references. Move the existing submodule checkout from `claude-config` to `agent-config` only during the authorized cutover.

- [ ] Recheck both working trees. Wait for Mat's in-flight changes to settle or obtain an explicit coexistence plan before moving the submodule.
- [ ] Record current installed links and owned native values outside version control, with restrictive permissions where needed. Do not export authentication state or secrets into the repository.
- [ ] Keep the existing Git remote URL initially. A local path/name change does not require renaming the GitHub repository; remote renaming is a separate optional action.
- [ ] Move the submodule using Git-aware operations and validate its gitdir/worktree relationship. The `.gitmodules` section identifier may remain unchanged; avoid unnecessary metadata churn.
- [ ] Update source paths and live hook/skill references from the inventory. Search for both `claude-config` and stale `Codex-config` references; classify historical documentation separately from executable paths.
- [ ] Preview then apply the targeted setup. Keep old owned entry points available until verification passes; any temporary compatibility link has a named removal condition.
- [ ] Record configuration-repo changes and the parent submodule pointer separately when committing is authorized. Stage explicit paths only; leave unrelated parent changes untouched. Do not push.

**Rollback:** Restore the recorded owned links/settings, restore the prior setup path, and reverse the local submodule move with Git-aware operations. Preserve edits made after cutover. Never use a hard reset or wholesale native-directory replacement.

**Acceptance:** Both configurations resolve to the intended sources; the installer works from the new path; rollback is documented against actual changed destinations.

## Task 6: Validate direct use, delegation, and one project

**Files:** Update `agent-config/docs/compatibility.md` and `agent-config/README.md`. Project files are touched only in a disposable fixture or a project explicitly selected by Mat.

- [ ] Run structural checks for broken links, duplicate skill exposure, absent references, settings syntax, and managed/unmanaged collisions.
- [ ] Start fresh Claude and Codex sessions in a disposable Git repository. Give its `AGENTS.md` a unique instruction marker; confirm each session can identify the correct global and project instruction sources without explicitly feeding the marker in the task.
- [ ] Add a fixture skill whose procedure produces a distinctive report field. Invoke it explicitly in each harness and confirm the procedure is used. Separately test a matching natural-language request; record automatic selection as observed behavior, not a guaranteed enforcement mechanism.
- [ ] Test native restrictions with harmless fixtures in an isolated repository. Verify attempted operations are blocked by native enforcement, not merely declined in prose. Never test destructive operations against real work or credentials.
- [ ] For each migrated hook, use synthetic payloads and a safe session event to verify actual behavior. The project-note commit hook must target an isolated fixture during testing, not the real vault.
- [ ] Verify the official Claude-to-Codex integration available at execution time. Delegate into an explicit fixture working directory with task scope, required skill path, verification command, and report contract. Confirm Codex discovers shared instructions and uses its native restrictions.
- [ ] Continue the same delegated thread with a correction; confirm retained context. Confirm relevant task decisions are present in the brief rather than assuming all Claude conversation state transfers.
- [ ] Start direct Codex in the same fixture and compare engineering outcomes. Interaction style may differ by design; record supported differences.
- [ ] Apply the project convention to one selected project after fixture validation: local knowledge stays in that repo, relative links survive a worktree, and setup does not require copying project knowledge into personal config.
- [ ] Record exact tested versions, mode, date, command/scenario, result, and limitations. A discoverable file is not evidence of skill invocation; invocation is not evidence of permission enforcement.

**Acceptance:** Direct Claude, direct Codex, and delegated Codex each pass their applicable scenarios. Unavailable integrations or platforms are stated as unverified, not silently treated as passing.

## Handoff and maintenance

- [ ] Document one normal entry point: ask the `agent-config` skill to make a configuration change; it uses the existing specialist skills and installer.
- [ ] Document where to edit owned sources, how local overrides coexist, how to preview/apply, and how to restore a failed cutover.
- [ ] Preserve evidence for intentional differences. Recheck affected behavior after harness upgrades or configuration changes; avoid a permanent background sync/audit service.
- [ ] Remove obsolete owned copies/compatibility links only after all consumers move and Mat authorizes removal. Use `trash` where deletion is necessary.
- [ ] Summarize changed sources, installation effects, validation, remaining limitations, and separate repository commits. No push unless requested.

## Research informing this plan

- [Adobe harness guide](https://github.com/adobe/ai-repo-harness-guide/blob/main/guide/07-Build-Your-Harness.md): canonical project skills, native links, thin instruction wrappers, harness-specific references.
- [Agent Skills specification](https://agentskills.io/specification): portable package structure and compatibility declarations; tool-control support varies.
- [agent-config-skills](https://github.com/LightShards02/agent-config-skills): migration versus routine maintenance, inventory, ownership-aware installation. Borrow procedures only; retain project knowledge in projects.
- [Community dotagents](https://github.com/anton-winter-arch/dotagents): individual owned links alongside local entries. Verify behavioral claims against official harness documentation.
- [Ruler](https://github.com/intellectronica/ruler): useful comparison for deterministic output and lossy adapters; not a dependency.
- [Vercel Skills](https://github.com/vercel-labs/skills): considered; not adopted. Existing dotfiles installation remains authoritative.
- [Official Codex plugin](https://github.com/openai/codex-plugin-cc): local runtime/configuration reuse; verify actual delegated behavior on the installed version.

## Completion definition

One logical configuration change has one clear maintenance workflow. Stable content has one source. Native differences are explicit and verified. The existing installer remains recognizable and under Mat's control. Both harnesses work independently, delegation has a tested contract, and unrelated/local configuration survives installation and rollback.
