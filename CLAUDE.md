# AIRA — project instructions

## Identity

**AIRA — AI Requirements & Test Case Assistant.** It turns Jira requirements into structured BA/QE
specifications and TestRail-ready test cases, and cross-references existing coverage to avoid
duplicate tests. It also acts as a context gateway so built-in and custom agents can reuse delivery
knowledge across Jira, Confluence and TestRail. Remote `origin` is
`https://github.com/xLZDx/AIRA.git`, default branch `main`.

AIRA runs as a multi-agent orchestration framework **inside VS Code via GitHub Copilot Chat** — that
is its runtime, and it is what distinguishes this repository from every other agent-related folder on
this machine. `D:\Repo\agents-skills-repo` is a separate repository of Claude Code agent and skill
specs; the two are unrelated and must not borrow structure or terminology from each other.

## Layout

`core`, `context`, `plugins`, `overrides`, `docs`, `.aira`, `.github`. Governance files at the root:
`CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`, `.env.example`.

**The implementation language is PowerShell, not Python or Node.** There is no `pyproject.toml`,
no `package.json` and no compiled artifact — which is why a search for a build command comes back
empty and should not be read as "nothing runs here". What actually exists:

- `core/modules/*.psm1` — nine modules (`Aira.Common`, `Aira.Config`, `Aira.Cache`, `Aira.Memory`,
  `Aira.Session`, `Aira.Telemetry`, `Aira.Templating`, `Aira.Validation`, `Aira.JiraText`).
- `core/scripts/*.ps1` — the operator-facing entry points: `aira.ps1` (context build / rescan),
  `jira.ps1`, `confluence.ps1`, `testrail.ps1`, `excel.ps1`, `memory.ps1`, `session.ps1`,
  `validate.ps1`.
- `core/prompts/*.md` — the agent definitions themselves (`aira_master`, `context_agent`,
  `context_validation_agent`, `context_processing_agent`, `analysis_agent`, `design_agent`,
  `validation_agent`, `testrail_specialist`). These are prompts, so a change here changes behavior
  with nothing to compile and nothing to type-check.
- `core/validation/*.ps1` — eight discrete checks (`content_safety`, `context_integrity`,
  `duplicate_detection`, `forbidden_values`, `prerequisite_exists`, `reference_integrity`,
  `schema_compliance`, `step_completeness`).
- `.aira/*.policy.json` — admin, schema and team policy. Policy supplies defaults (context scope,
  dependency depth); the documented rule is to let the policy value apply rather than passing an
  explicit override.
- `.aira/tests/unit/` and `.aira/tests/integration/` — Pester suites. Unit covers modules, policy,
  paths, templating, memory, resource resolution, context validation and package safety;
  integration covers Jira, Confluence, TestRail, GitHub and Bitbucket and therefore needs live
  credentials. Run the unit suite before claiming a change is safe; do not run the integration
  suite against a real instance casually — see the rule below.
- `.github/copilot-instructions.md` — the actual runtime specification, including the strict
  intent-to-action map. It is long and load-bearing: read it before changing any agent prompt or
  script signature, because the map names scripts and flags by hand.

## Rules specific to this project

- **It touches real delivery systems.** Jira, Confluence and TestRail integrations mean live tickets,
  live specifications and live test cases. Reads for analysis are ordinary work; anything that
  creates, updates or deletes an issue, page or test case in a real instance is an external
  state-changing action and needs its own explicit confirmation, even under a broader GO.
- **Credentials come from `.env`, and `.env.example` is the only version of it that belongs in git.**
  Never read secrets into a report or paste integration tokens into output.
- **The target is regulated environments.** Transparency and auditability are requirements, not
  polish: keep policy-driven validation explicit and keep the trail of why an output was produced.
  Silent fallbacks that make a validation appear to pass are defects here.
- Duplicate-coverage prevention is a core promise. A change that makes cross-reference analysis
  weaker or more permissive is a product regression, not an optimization.
- Custom agents and plugins extend the framework — put new capability in `plugins`/`overrides` as the
  existing structure intends rather than expanding `core` by default. `plugins/aira-example` is the
  minimal shape (manifest + one skill + one validation check); `plugins/aira-prototyping` is the
  worked example that also ships a module, a prompt and a script. Copy the shape rather than
  inventing a new extension mechanism.
- **`BUG-*` keys are deliberately not analyzable.** The intent map blocks them: a bug is recorded as
  a concern and the user is asked for the related Feature/Story. This is a product decision about
  where requirements live, not an unimplemented case to fill in.

## History — one import, one de-branding, and a long quiet period

Eight commits, and the shape of them matters more than the count.

**2026-03-27 — everything, in one day.** Seven of the eight commits land here: an initial commit, a
README rewrite, `README.md` renamed to `docs/USER_GUIDE.md` and a new README written in its place,
two `Add files via upload` commits, and finally `df0e6dd` — "Initial commit: add AIRA core, modules,
plugins, and tests". The upload-shaped messages tell you this arrived as a finished body of work
imported into git rather than grown in it, so **git history is not a design record here.** The
design record is `docs/`, `core/prompts/` and `.github/copilot-instructions.md`. Do not go looking
for the commit that explains a decision; it does not exist.

**2026-05-31 — de-branding (`00f50b7`).** The only substantive change since the import, and it is
worth knowing about because it defines what this repository is *not*: every mention of "the AIRA
project" as an organisation, the author attribution in `docs/USER_GUIDE.md`, an `example.com`
security contact in `SECURITY.md`, and a **hidden base64 author signature** inside
`.github/copilot-instructions.md` were all removed, and the upstream remote was dropped in favour
of `xLZDx/AIRA`. Two consequences to carry forward: this is a single-owner repository with no
upstream to sync from, and there is a precedent for third-party attribution being smuggled into an
instructions file in encoded form — worth a glance when importing anything into `.github/` or
`core/prompts/`.

**Since then — nothing.** No commits between 2026-05-31 and now. Treat any claim about "recent
work" on AIRA with suspicion, and check `git log` before repeating one. The repository being quiet
is not the same as the repository being finished: `docs/` describes capabilities whose runtime is
Copilot Chat, so verifying that something works means running it there, not reading the prompt that
describes it.

**The neighbourhood.** RQDO (`D:\Repo\Remote_Quality_Delivery_Office_Platform_rqdo`) names AIRA in
its architecture rules — rule 10: *"AIRA stays a separate repo, wired later as a feature-flagged
accelerator."* That integration does not exist yet in either repository. If work starts on it, it
starts as a decision recorded on both sides, not as an import.
