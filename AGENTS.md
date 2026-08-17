# AGENTS.md — AIRA

Tool-agnostic conventions for any coding agent operating in this checkout. `CLAUDE.md` is the
Claude Code entry point and carries identity, layout and project history; this file is for
everyone else, and for the parts that apply regardless of which agent is reading them.

There is a third file, and it outranks both for runtime behavior: **`.github/copilot-instructions.md`
is the product's actual specification.** AIRA runs as a multi-agent orchestration framework inside
VS Code via GitHub Copilot Chat, and that file defines the personality, the operational rules and a
**strict intent-to-action map** that names scripts and their flags by hand. Changing a script's
name or signature without updating the map silently breaks the product while every file still
parses. Read it before touching `core/scripts/`, `core/prompts/` or `core/modules/`.

## Build / test / run

There is no build. The implementation is PowerShell modules, PowerShell scripts and Markdown
prompts; nothing compiles and nothing is packaged.

Tests are Pester, split by what they touch:

```powershell
Invoke-Pester .aira/tests/unit          # modules, policy, paths, templating, memory,
                                        # resource resolution, context validation, package safety
Invoke-Pester .aira/tests/integration   # Jira, Confluence, TestRail, GitHub, Bitbucket
```

The unit suite is the one to run on every change. The integration suite talks to **real delivery
systems** and needs live credentials — see the next section before running it.

Operator-facing entry points, all under `core/scripts/`: `aira.ps1` (`-BuildContext`, `-Rescan`),
`jira.ps1`, `confluence.ps1`, `testrail.ps1`, `excel.ps1`, `memory.ps1`, `session.ps1`,
`validate.ps1` (`-Promote`).

## The rule that matters most here: this repository reaches live systems

Jira, Confluence and TestRail integrations mean real tickets, real specification pages and real
test cases belonging to a real team.

- **Reads for analysis are ordinary work.** Fetching a story, pulling a Confluence page, checking
  existing coverage — these need no special ceremony.
- **Any write is an external state-changing action** and needs its own explicit confirmation, even
  under a broader approval. Creating, updating or deleting an issue, a page or a test case is not
  covered by "go ahead and fix the analysis pipeline".
- **The integration Pester suite is a write-capable surface.** Do not run it against a production
  instance to "check something quickly". If a test needs a live instance, say which instance and
  ask.
- **Credentials live in `.env`, and `.env.example` is the only version that belongs in git.** Never
  read a token into a report, a log, a commit message or a test fixture. The example file
  enumerates exactly which secrets exist: Jira, Confluence and TestRail tokens, optional GitHub and
  Bitbucket tokens.

## Correctness rules specific to this product

- **Duplicate-coverage prevention is the core promise, not a feature.** Cross-reference analysis
  against existing TestRail coverage is why the product exists. A change that makes it weaker, more
  permissive, or silently skippable is a product regression regardless of what the tests say.
- **The target is regulated environments.** Transparency and auditability are requirements. Keep
  policy-driven validation explicit and keep the trail of why an output was produced. A fallback
  that lets a validation *appear* to pass is a defect here, not resilience — if a check cannot run,
  it must say so.
- **Never invent requirement content.** The instructions are explicit that AIRA cites sources and
  does not hallucinate. An analysis output that fills a gap in a Jira story with a plausible
  invention is worse than one that names the gap.
- **Policy supplies defaults; do not hard-code around it.** Context scope and dependency depth come
  from `.aira/*.policy.json`, and the documented behavior is to let the policy value apply unless
  the user explicitly overrides it. Passing an explicit flag "to be safe" changes behavior for
  every team that tuned their policy.
- **`BUG-*` keys are blocked by design.** A bug is recorded as a concern and the related
  Feature/Story is requested. This is a decision about where requirements live, not a missing case.
- **Extend through `plugins/` and `overrides/`.** `plugins/aira-example` is the minimal shape
  (manifest, one skill, one validation check); `plugins/aira-prototyping` adds a module, a prompt
  and a script. New capability follows that shape rather than growing `core/`.

## Prompts are code here

`core/prompts/*.md` and `core/validation/*.ps1` are the behavior. A prompt edit ships immediately,
has no type checker behind it and no compile step to catch it. Consequences:

- Do not report a prompt change as "verified" on the basis of reading it. Verification means
  running the flow in Copilot Chat and looking at the artifact it produced.
- The eight validation checks (`content_safety`, `context_integrity`, `duplicate_detection`,
  `forbidden_values`, `prerequisite_exists`, `reference_integrity`, `schema_compliance`,
  `step_completeness`) are the mechanical half. Prefer adding a check over adding a paragraph of
  instruction: a check can fail, a paragraph can only be ignored.

## Git safety

- Remote `origin` is `github.com/xLZDx/AIRA`, default branch `main`. There is **no upstream** — it
  was deliberately removed in `00f50b7`. Nothing here syncs from another repository.
- The history is import-shaped: seven commits on 2026-03-27, one de-branding commit on 2026-05-31,
  nothing since. Do not expect git to explain a design decision; `docs/`, `core/prompts/` and the
  Copilot instructions are the design record.
- That de-branding commit removed a **hidden base64 author signature** from
  `.github/copilot-instructions.md`. When importing anything into `.github/` or `core/prompts/`,
  check for encoded content before committing it.
- A local commit never implies permission to push. Push is a separate, explicit authorization for a
  specific commit list.

## Where everything else lives

| Need | Go to |
|---|---|
| Identity, layout, project rules, history | `CLAUDE.md` |
| Runtime behavior, intent-to-action map, scope/dependency/attachment keywords | `.github/copilot-instructions.md` |
| The eight per-agent definitions | `core/prompts/*.md` (and `.github/agents/*.agent.md` for Copilot) |
| User-facing walkthrough | `docs/USER_GUIDE.md`, `README.md` |
| Which secrets exist and what they are named | `.env.example` |
| Team/admin/schema defaults | `.aira/*.policy.json` |
| Contribution and vulnerability-reporting process | `CONTRIBUTING.md`, `SECURITY.md` |
