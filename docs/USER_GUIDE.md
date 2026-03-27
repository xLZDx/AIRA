# AIRA — AI Requirements & Test Case Assistant

## Ownership

Maintained by the AIRA project.

Originally developed for internal QA automation use cases across regulated industries.

This repository contains generic framework components and does not include any client-specific implementations.

## Support & Disclaimer

This project is provided "as is", without warranties or guarantees of any kind.

It is intended as a reusable engineering accelerator and reference implementation, not as a substitute for enterprise-supported solutions.

Production support, SLAs, and customizations may be provided separately under commercial agreement.


> **Version 2.0** | Created and developed by the AIRA project for the AIRA project

AIRA is an AI-powered Business Analyst and Quality Engineer assistant that transforms Jira requirements into structured, testable specifications and TestRail-ready test cases — while preventing duplication with existing test coverage.

AIRA operates inside VS Code via GitHub Copilot Chat, coordinating a team of specialist AI agents backed by PowerShell automation scripts that integrate with Jira, TestRail, and Confluence APIs.

---

## Table of Contents

- [Key Features](#key-features)
- [Architecture Overview](#architecture-overview)
  - [Directory Structure](#directory-structure)
  - [Agent System](#agent-system)
  - [Script & Module Layer](#script--module-layer)
  - [Policy & Configuration](#policy--configuration)
    - [Policy Files](#policy-files)
    - [Key Policy Settings Reference](#key-policy-settings-reference)
- [Setup & Installation](#setup--installation)
  - [Prerequisites](#prerequisites)
  - [Step 1: Clone & Open Workspace](#step-1-clone--open-workspace)
  - [Step 2: Configure Environment Variables](#step-2-configure-environment-variables)
  - [Step 3: Configure Policies](#step-3-configure-policies)
  - [Step 4: Install Dependencies](#step-4-install-dependencies)
  - [Step 5: Run Readiness Check](#step-5-run-readiness-check)
- [Agent Reference](#agent-reference)
  - [AIRA Master (Orchestrator)](#aira-master-orchestrator)
  - [Context Agent](#context-agent)
  - [Analysis Agent](#analysis-agent)
  - [Design Agent](#design-agent)
  - [Validation Agent](#validation-agent)
  - [TestRail Specialist](#testrail-specialist)
- [Usage Guide](#usage-guide)
  - [Getting Started](#getting-started)
  - [Natural Language Interface](#natural-language-interface)
  - [Intent-to-Action Map](#intent-to-action-map)
- [Prompt Examples & Use Cases](#prompt-examples--use-cases)
  - [Context Building](#context-building)
  - [Requirement Analysis](#requirement-analysis)
  - [Test Case Generation (Full Pipeline)](#test-case-generation-full-pipeline)
  - [TestRail Coverage Analysis](#testrail-coverage-analysis)
  - [Gap Analysis](#gap-analysis)
  - [Systems & Dependency Analysis](#systems--dependency-analysis)
  - [Batch Context Operations](#batch-context-operations)
  - [Context Rescan & Diff](#context-rescan--diff)
  - [Session Management](#session-management)
  - [Memory & Preferences](#memory--preferences)
  - [Export & Reporting](#export--reporting)
  - [Combined / Advanced Workflows](#combined--advanced-workflows)
- [Output Structure & Reporting](#output-structure--reporting)
  - [Context Outputs](#context-outputs)
  - [Analysis Outputs (Requirements Spec)](#analysis-outputs-requirements-spec)
  - [Design Outputs (Test Cases)](#design-outputs-test-cases)
  - [Validation Reports](#validation-reports)
  - [Excel & CSV Exports](#excel--csv-exports)
  - [Coverage Reports](#coverage-reports)
  - [Session & Memory Data](#session--memory-data)
- [Script Reference](#script-reference)
- [Validation System](#validation-system)
- [Plugin System](#plugin-system)
- [Override System](#override-system)
- [Testing](#testing)
- [Future Enhancements](#future-enhancements)

---

## Key Features

| Capability | Description |
|---|---|
| **Requirement Analysis** | Transforms Jira Features/Stories into structured BA/QE requirement specifications with gap analysis |
| **Test Case Design** | Generates TestRail-ready test cases categorized as NEW, ENHANCE, or PREREQUISITE |
| **Duplication Prevention** | Cross-references TestRail coverage before proposing new cases |
| **Dependency Traversal** | Follows Jira issue links to configurable depth, analyzing the full dependency graph |
| **Attachment Analysis** | Downloads and analyzes Jira attachments (images, documents, spreadsheets) |
| **Coverage Traceability** | Maps requirement scenarios to TestRail cases with calculated coverage percentages |
| **Bidirectional TestRail** | Reads existing coverage and writes new/enhanced cases (with approval gates) |
| **Adaptive Learning** | Logs user corrections and promotes repeated patterns to preferences |
| **Multi-Team Policies** | Layered policy system (admin → team → team-specific) with locked fields |
| **Plugin Extensibility** | Custom validation checks, skills, prompts, and templates via plugins |
| **Session Continuity** | Auto-saves checkpoints; resume interrupted workflows seamlessly |
| **Excel/CSV Export** | Generates formatted spreadsheets for offline review and TestRail import |

---

## Architecture Overview

### Directory Structure

```
aira/
├── .aira/                          # Workspace state & configuration
│   ├── admin.policy.json           # Organization-wide policy (highest priority)
│   ├── team.policy.json            # Generic team defaults
│   ├── schema.policy.json          # Policy schema definition
│   ├── teams/                      # Team-specific policy overrides
│   │   └── teamname.policy.json
│   ├── memory/                     # Adaptive learning store
│   │   ├── corrections.jsonl       # Logged user corrections
│   │   └── user_preferences.json   # Promoted preferences
│   ├── sessions/                   # Session state files
│   │   └── session_*.json
│   └── tests/                      # Readiness tests
│       ├── startup.state.json      # Readiness gate state
│       ├── unit/                   # Pester unit tests
│       ├── integration/            # Pester integration tests
│       └── results/                # Test output (XML, JSON, logs)
│
├── .github/agents/                 # VS Code Copilot agent definitions
│   ├── aira-master.agent.md
│   ├── aira-analysis.agent.md
│   ├── aira-context-builder.agent.md
│   ├── aira-design.agent.md
│   ├── aira-testrail-specialist.agent.md
│   └── aira-validation.agent.md
│
├── core/                           # Core system (do not modify casually)
│   ├── modules/                    # PowerShell modules (.psm1)
│   │   ├── Aira.Common.psm1        # Shared helpers (repo root, path resolution)
│   │   ├── Aira.Config.psm1        # Policy loading, credentials, resource resolution
│   │   ├── Aira.Validation.psm1    # Validation orchestration engine
│   │   ├── Aira.JiraText.psm1      # Jira markup → plain text converter
│   │   ├── Aira.Memory.psm1        # Correction logging & preference promotion
│   │   ├── Aira.Session.psm1       # Session lifecycle management
│   │   ├── Aira.Cache.psm1         # API response caching
│   │   ├── Aira.Telemetry.psm1     # Optional telemetry (opt-in)
│   │   └── Aira.Templating.psm1    # Template rendering engine
│   ├── prompts/                    # Agent persona definitions
│   │   ├── aira_master.md          # Master orchestrator persona
│   │   ├── analysis_agent.md       # BA/QE analysis persona
│   │   ├── context_agent.md        # Context building persona
│   │   ├── design_agent.md         # Test design persona
│   │   ├── validation_agent.md     # Quality gatekeeper persona
│   │   └── testrail_specialist.md  # TestRail operations persona
│   ├── scripts/                    # PowerShell automation scripts
│   │   ├── aira.ps1                # Central CLI entry point
│   │   ├── jira.ps1                # Jira API operations (read-only)
│   │   ├── testrail.ps1            # TestRail API (bidirectional)
│   │   ├── confluence.ps1          # Confluence API (read-only)
│   │   ├── excel.ps1               # Excel export generation
│   │   ├── validate.ps1            # Validation runner
│   │   ├── memory.ps1              # Memory/preference utilities
│   │   └── session.ps1             # Session management CLI
│   ├── skills/                     # Skill documentation for agents
│   │   ├── jira_integration.md
│   │   ├── testrail_integration.md
│   │   ├── confluence_integration.md
│   │   ├── excel_generation.md
│   │   └── coverage_analysis.md
│   ├── templates/                  # Output templates
│   │   ├── spec_template.md        # Requirement specification template
│   │   ├── excel_mapping.json      # JSON → Excel column mapping
│   │   └── email_report.html       # Email report template
│   └── validation/checks/          # Validation check scripts
│       ├── schema_compliance.ps1
│       ├── forbidden_values.ps1
│       ├── step_completeness.ps1
│       ├── reference_integrity.ps1
│       ├── duplicate_detection.ps1
│       └── prerequisite_exists.ps1
│
├── context/                        # Fetched requirement context data
│   ├── shared/{Prefix}/{KEY}/      # Team-visible summaries (context.md)
│   │   └── context.md              # Jira requirement summary
│   ├── shared/{SpaceKey}/{Root}/{Page} ({Id})/  # Wiki page summaries
│   │   └── context.md              # Confluence page summary
│   └── local/
│       ├── {Prefix}/{KEY}/         # Raw data, sources, dependencies, attachments
│       └── _metadata/testrail/     # Global TestRail metadata
│           └── projects.json
│
├── artifacts/                      # Generated analysis & design outputs
│   └── {Prefix}/{KEY}/
│       ├── requirements.md         # Requirement specification
│       └── testrail/
│           ├── design.json           # Test case design (source of truth)
│           ├── testrail_import.xlsx  # Excel export (on request)
│           └── testrail_import.csv   # CSV export (on request)
│
├── overrides/                      # Team customizations (override core defaults)
│   ├── prompts/                    # Custom agent personas
│   ├── templates/                  # Custom output templates
│   └── rules/                      # Custom team rules
│
├── plugins/                        # Extensible plugin system
│   └── aira-example/
│       ├── manifest.json
│       ├── skills/
│       └── validation/checks/
│
└── scratch/                        # Temporary workspace
```

### Agent System

AIRA uses a **multi-agent architecture** where the Master orchestrator delegates to specialist agents based on user intent:

```
┌─────────────────────────────────────────────────────┐
│             User (Natural Language)                 │
└───────────────────────┬─────────────────────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │   AIRA Master   │
              │  (Orchestrator) │
              └────────┬────────┘
                       │
          ┌────────────┼───────────────┬──────────────┐
          ▼            ▼               ▼              ▼
   ┌─────────────┐ ┌──────────┐ ┌───────────┐ ┌───────────┐
   │   Context   │ │ Analysis │ │  Design   │ │ TestRail  │
   │   Agent     │ │  Agent   │ │  Agent    │ │ Specialist│
   └──────┬──────┘ └────┬─────┘ └─────┬─────┘ └─────┬─────┘
          │             │             │             │
          ▼             ▼             ▼             ▼
                          ENGINES
   ┌─────────────┐ ┌──────────┐ ┌───────────┐ ┌───────────┐
   │    jira     │ │ Reads    │ │ Produces  │ │ testrail  │
   │ confluence  │ │ context  │ │ design    │ │           │
   │    aira     │ │ + sources│ │ JSON      │ │           │
   └─────────────┘ └──────────┘ └─────┬─────┘ └───────────┘
                                      │
                                      ▼
                               ┌────────────┐
                               │ Validation │
                               │   Agent    │
                               └─────┬──────┘
                                     │
                                     ▼
                              ┌─────────────┐
                              │   Validate  │
                              └─────────────┘
```

### Script & Module Layer

**Modules** (`.psm1`) provide reusable functions. **Scripts** (`.ps1`) are CLI entry points.

| Module | Purpose |
|---|---|
| `Aira.Common` | Shared helpers: repo root, path resolution, directory creation |
| `Aira.Config` | Policy loading, credential management, resource resolution |
| `Aira.Validation` | Validation check orchestration engine |
| `Aira.JiraText` | Jira markup → plain-text converter |
| `Aira.Memory` | Correction logging & preference promotion |
| `Aira.Session` | Session create/read/update lifecycle |
| `Aira.Cache` | API response caching with TTL |
| `Aira.Templating` | Template rendering with placeholder substitution |
| `Aira.Telemetry` | Optional telemetry (opt-in only) |

**Module import order** (critical for PowerShell 5.1):
```
Aira.Common → Aira.Validation → Aira.Config (LAST)
```

### Policy & Configuration

AIRA uses a **four-tier policy system** with merge precedence. Each layer overrides the one below it, with locked fields always protected:

```
admin.policy.json         ← Organization-wide (locked fields enforced)
  ↑ merges into
team.policy.json          ← Generic team defaults (base layer)
  ↑ overrides from
teams/*.policy.json       ← Team-specific overrides (only changed fields)
  ↑ overlays
user_preferences.json     ← Learned user preferences (respects locks)
```

Policies are loaded via `Get-AiraEffectivePolicy` (from `Aira.Config.psm1`), which merges all layers and enforces locked fields. Never hard-code policy values.

#### Policy Files

| File | Location | Purpose |
|---|---|---|
| `admin.policy.json` | `.aira/` | Organization-wide settings; defines `locked_fields` that **cannot** be overridden by any lower layer |
| `team.policy.json` | `.aira/` | Generic team defaults — the base configuration all teams inherit |
| `*.policy.json` | `.aira/teams/` | Per-team overrides — only include fields that differ from `team.policy.json` |
| `schema.policy.json` | `.aira/` | JSON schema defining required fields and types for policy validation |
| `user_preferences.json` | `.aira/memory/` | Auto-promoted from repeated user corrections (highest layer, respects locks) |

#### admin.policy.json — Organization Layer

Controls org-wide rules and **locked fields** that no team or user can override:

```json
{
  "organization": "ProjectName",
  "version": "2.0",
  "testrail": {
    "restrictions": {
      "forbidden_priorities": [],
      "max_cases_per_batch": 50,
      "require_jira_reference": true
    },
    "defaults": { "priority": "Medium", "type": "Functional" }
  },
  "validation": {
    "auto_fail_on_errors": true,
    "require_human_review": false,
    "enabled_checks": [
      "schema_compliance", "forbidden_values", "step_completeness",
      "reference_integrity", "duplicate_detection"
    ]
  },
  "locked_fields": [
    "testrail.restrictions.forbidden_priorities",
    "validation.auto_fail_on_errors"
  ]
}
```

**`locked_fields`** — dot-path references to fields that are frozen at the admin level. Any attempt to override these in `team.policy.json`, `teams/*.policy.json`, or `user_preferences.json` is silently ignored during merge.

#### team.policy.json — Team Defaults Layer

Provides the baseline configuration every team inherits:

```json
{
  "team_name": "Generic",
  "team_id": "generic-001",
  "testrail": {
    "project_id_map": { "*": 212 },
    "default_project_id": 212,
    "default_section_name": "Functional Tests"
  },
  "jira": {
    "allowed_types": ["Story", "Feature"],
    "project": {
      "description": "Default",
      "jira_project_code": "",
      "confluence_space": "",
      "scrum_teams": {}
    }
  },
  "context": {
    "max_dependency_depth": 1,
    "default_scope": "Auto",
    "include_confluence": true
  },
  "preferences": {
    "auto_open_excel": true,
    "default_export_mode": "both",
    "telemetry_opt_in": false
  }
}
```

#### teams/*.policy.json — Team-Specific Overrides

Each file only needs the fields it changes. Example (`teams/ProjectName.policy.json`):

```json
{
  "team_name": "TeamName",
  "team_id": "teamname-001",
  "jira": {
    "project": {
      "description": "ProjectName",
      "jira_project_code": "ACP",
      "confluence_space": "SpaceName",
      "scrum_teams": {
        "Cyberpunks": "CYP",
        "Mavericks": "MAV",
        "Agile Avengers": "AAV",
        "PLAT": "PLAT"
      }
    }
  }
}
```

This team inherits all `testrail`, `context`, `validation`, and `preferences` from `team.policy.json` but overrides only the Jira project mappings.

#### schema.policy.json — Validation Schema

Defines the expected types for every policy field. Used by `Policy.Tests.ps1` to validate policy structure:

```json
{
  "schema_version": "1.0",
  "required": ["testrail", "validation"],
  "types": {
    "testrail.restrictions.forbidden_priorities": "array[string]",
    "testrail.restrictions.max_cases_per_batch": "number",
    "context.max_dependency_depth": "number",
    "context.default_scope": "string",
    "locked_fields": "array[string]"
  }
}
```

#### Key Policy Settings Reference

| Setting | Default | Description |
|---|---|---|
| `testrail.restrictions.forbidden_priorities` | `[]` | Priorities that cannot be used in test cases |
| `testrail.restrictions.max_cases_per_batch` | `50` | Maximum cases per batch create operation |
| `testrail.restrictions.require_jira_reference` | `true` | Every case must reference a Jira key |
| `testrail.project_id_map` | `{ "*": 212 }` | Maps Jira key prefixes to TestRail project IDs (`*` = default) |
| `testrail.default_section_name` | `"Functional Tests"` | Default TestRail section for new cases |
| `jira.allowed_types` | `["Story", "Feature"]` | Issue types AIRA will analyze (Bugs are always blocked) |
| `jira.project.scrum_teams` | `{}` | Maps team names to Jira key prefixes for routing |
| `context.max_dependency_depth` | `1` | How deep to traverse Jira dependency links |
| `context.default_scope` | `Auto` | Default context storage scope (`Auto`, `Local`, `Shared`) |
| `context.include_confluence` | `true` | Whether to include Confluence pages |
| `validation.enabled_checks` | `[5 checks]` | Active validation check scripts |
| `validation.auto_fail_on_errors` | `true` | Whether validation errors auto-fail |
| `preferences.auto_open_excel` | `true` | Automatically open Excel after export |
| `preferences.default_export_mode` | `"both"` | Export both Excel and CSV by default |

#### Adding a New Team Policy

1. Create `.aira/teams/<teamname>.policy.json`
2. Include only the fields your team needs to override
3. Set `team_name` and `team_id` to identify the team
4. AIRA auto-discovers all `*.policy.json` files in `.aira/teams/`

---

## Setup & Installation

### Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| **Windows** | 10+ | PowerShell 5.1 (built-in) |
| **VS Code** | Latest | With GitHub Copilot extension |
| **GitHub Copilot** | Latest | Chat + Agent mode enabled |
| **PowerShell** | 5.1+ | Windows PowerShell (not PowerShell Core required) |
| **Pester** | 5.7+ | Installed automatically via `-InstallDependencies` |
| **ImportExcel** | Latest | Installed automatically via `-InstallDependencies` |

### Step 1: Clone & Open Workspace

```bash
git clone <repository-url> aira
code aira
```

When VS Code opens, **trust the workspace** when prompted.

### Step 2: Configure Environment Variables

Copy `.env.example` to `.env` in the workspace root and fill in your credentials:

```dotenv
# Jira
JIRA_URL=https://yourcompany.atlassian.net
JIRA_EMAIL=your.email@company.com
JIRA_API_TOKEN=your-jira-api-token

# Confluence / Wiki
CONFLUENCE_URL=https://yourcompany.atlassian.net/wiki
CONFLUENCE_EMAIL=your.email@company.com
CONFLUENCE_API_TOKEN=your-confluence-api-token

# TestRail
TESTRAIL_URL=https://company.testrail.io
TESTRAIL_USERNAME=your.username@company.com
TESTRAIL_API_KEY=your-testrail-api-key

# GitHub (optional)
GITHUB_BASE_URL=https://github.com
GITHUB_TOKEN=
GITHUB_OWNER=
GITHUB_REPO=

# Bitbucket (optional)
BITBUCKET_BASE_URL=https://bitbucket.org
BITBUCKET_USERNAME=
BITBUCKET_APP_PASSWORD=
BITBUCKET_WORKSPACE=
BITBUCKET_REPO=
```

> **Security note:** Never commit `.env` to version control. It is listed in `.gitignore`.

### Step 3: Configure Policies

**Organization-level** (`.aira/admin.policy.json`):
```json
{
  "organization": "YourOrg",
  "version": "2.0",
  "testrail": {
    "restrictions": {
      "forbidden_priorities": [],
      "max_cases_per_batch": 50,
      "require_jira_reference": true
    },
    "defaults": {
      "priority": "Medium",
      "type": "Functional"
    }
  },
  "validation": {
    "auto_fail_on_errors": true,
    "require_human_review": false,
    "enabled_checks": [
      "schema_compliance",
      "forbidden_values",
      "step_completeness",
      "reference_integrity",
      "duplicate_detection"
    ]
  },
  "locked_fields": [
    "testrail.restrictions.forbidden_priorities",
    "validation.auto_fail_on_errors"
  ]
}
```

**Team-level** (`.aira/team.policy.json`):
```json
{
  "team_name": "Generic",
  "team_id": "generic-001",
  "testrail": {
    "project_id_map": { "*": 212 },
    "default_project_id": 212,
    "default_section_name": "Functional Tests"
  },
  "jira": {
    "allowed_types": ["Story", "Feature"],
    "project": {
      "description": "Default",
      "jira_project_code": "",
      "confluence_space": "",
      "scrum_teams": {}
    }
  },
  "context": {
    "max_dependency_depth": 1,
    "default_scope": "Auto",
    "include_confluence": true
  }
}
```

**Team-specific override** (`.aira/teams/yourteam.policy.json`) — only include fields you want to change:
```json
{
  "team_name": "YourTeam",
  "team_id": "yourteam-001",
  "jira": {
    "project": {
      "description": "Your Project",
      "jira_project_code": "PROJ",
      "confluence_space": "PROJDOCS",
      "scrum_teams": {
        "Team Alpha": "ALPHA",
        "Team Beta": "BETA"
      }
    }
  }
}
```

### Step 4: Install Dependencies

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/aira.ps1 -InstallDependencies
```

This installs:
- **Pester 5.7+** (test framework)
- **ImportExcel** (Excel generation without Office)

### Step 5: Run Readiness Check

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/aira.ps1 -Doctor
```

The Doctor command:
1. Runs all unit tests (54 tests across 7 test files)
2. Runs all integration tests (5 tests: Jira, TestRail, Confluence, GitHub, Bitbucket)
3. Writes results to `.aira/tests/results/`
4. Updates `.aira/tests/startup.state.json`

If all tests pass, the startup state is set to `Complete` and AIRA is fully operational. If any test fails, AIRA will guide you through fixing configuration issues.

> **Important:** AIRA blocks all external write operations (e.g., TestRail case creation) until readiness is `Complete`.

---

## Agent Reference

### AIRA Master (Orchestrator)

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/aira_master.md` |
| **VS Code agent** | `.github/agents/aira-master.agent.md` |
| **Role** | Routes user intent to specialist agents |
| **Personality** | Conversational, proactive, precise, efficient |

The Master parses natural language, determines intent, and delegates to the appropriate agent pipeline. It enforces:
- Readiness gates (blocks operations until `-Doctor` passes)
- Approval gates (pauses before destructive operations)
- Session continuity (auto-saves checkpoints)
- Policy compliance (loads effective policy chain)

### Context Agent

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/context_agent.md` |
| **VS Code agent** | `.github/agents/aira-context-builder.agent.md` |
| **Backing scripts** | `aira.ps1 -BuildContext`, `jira.ps1`, `confluence.ps1` |
| **Role** | Fetches and synthesizes Jira data into structured context |

**What it does:**
- Fetches Jira issue details (metadata, description, comments, attachments)
- Traverses linked issues to configurable depth
- Downloads attachments (default behavior, configurable max size)
- Writes enriched `context.md` with all issue data, dependencies, and references
- Stores raw JSON payloads under `sources/` for deeper analysis
- Produces diffs on refresh (hash-based change detection)
- Supports Confluence page integration when referenced

### Analysis Agent

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/analysis_agent.md` |
| **VS Code agent** | `.github/agents/aira-analysis.agent.md` |
| **Role** | BA/QE requirement analysis & specification |

**What it produces:**

1. **Impact Assessment** — UI / API / Backend / Database domains
2. **Requirement Specification** — 8-section structured document:
   - Document Summary, Change Tracker, Context & Overview
   - User Story, Technical Alignment & Scope
   - Acceptance Criteria, NFRs, References & Attachments
3. **Coverage Traceability** (when TestRail data available) — scenario-to-case mapping with coverage percentages
4. **Scenario Inventory** — numbered list with triggers, preconditions, expected outcomes, edge cases
5. **Questions / Gaps** — grouped by Business and Technical categories

**Anti-hallucination rules:**
- Never invents API endpoints, payloads, or DB schema
- All data citations reference Jira source (e.g., `[Source: PLAT-1488 Description]`)
- Missing info marked as `[MISSING - NEEDS INPUT]`
- Uncertain technical details marked as `[CONDITIONAL - PENDING CLARIFICATION]`

### Design Agent

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/design_agent.md` |
| **VS Code agent** | `.github/agents/aira-design.agent.md` |
| **Role** | Creates TestRail-ready test case designs |

**Three-category output (mandatory):**

| Category | When Used | Output |
|---|---|---|
| `NEW_CASES` | No existing coverage for scenario | Full test case with steps |
| `ENHANCE_CASES` | Existing case covers ≥80% | New steps to append |
| `PREREQ_CASES` | Existing case needed for setup | Reference as prerequisite |

**Test case format:**
```json
{
  "new_cases": [{
    "title": "TC001 - Verify user can submit form with valid data",
    "priority": "High",
    "type": "Functional",
    "preconditions": "User is logged in, form page is loaded",
    "references": "PROJ-123",
    "prereq_case_ids": [],
    "steps": [
      { "step": 1, "action": "Navigate to form page", "expected": "Form is displayed" },
      { "step": 2, "action": "Fill all required fields", "expected": "Fields accept input" },
      { "step": 3, "action": "Click Submit", "expected": "Success message displayed" }
    ]
  }],
  "enhance_cases": [],
  "prereq_cases": []
}
```

### Validation Agent

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/validation_agent.md` |
| **VS Code agent** | `.github/agents/aira-validation.agent.md` |
| **Backing script** | `validate.ps1` |
| **Role** | Quality gatekeeper for test designs |

**Validation checks:**

| Check | What It Validates |
|---|---|
| `schema_compliance` | Required fields present (`title`, `steps`, `expected`) |
| `forbidden_values` | No forbidden priorities or types |
| `step_completeness` | Every step has both `action` and `expected` |
| `reference_integrity` | Jira references match expected format |
| `duplicate_detection` | No duplicate test case titles |
| `prerequisite_exists` | Referenced prerequisite case IDs exist |

### TestRail Specialist

| Attribute | Value |
|---|---|
| **Persona file** | `core/prompts/testrail_specialist.md` |
| **VS Code agent** | `.github/agents/aira-testrail-specialist.agent.md` |
| **Backing script** | `testrail.ps1` |
| **Role** | All TestRail read and write operations |

**Operations:**

| Operation | Type | Approval Required |
|---|---|---|
| Coverage analysis | Read | No |
| Case retrieval | Read | No |
| Section discovery | Read | No |
| Create new cases | Write | **Yes** |
| Update existing cases | Write | **Yes** |
| Enhance cases (append steps) | Write | **Yes** |
| Batch create (>10 cases) | Write | **Yes + size warning** |

**Safety features:**
- Backups created before every update/enhancement
- Batch create splits by policy `max_cases_per_batch` (default 50)
- Priority-sorted creation (Critical → High → Medium → Low)
- Failure isolation (single case failure doesn't abort batch)
- Before/after diff shown for enhancements

---

## Usage Guide

### Getting Started

Open VS Code in the AIRA workspace and use **GitHub Copilot Chat** (Ctrl+Shift+I or the Chat panel). AIRA responds to natural language:

```
I am AIRA, your AI Requirements & Test Case Assistant.

What would you like to do?
1) Analyze a Jira Feature or Story (paste a ticket key or link)
2) Generate test cases for a Feature or Story
3) Check existing TestRail coverage
4) Enhance existing test cases
5) Import context from Jira/Confluence
6) Test integrations / workspace readiness
7) Review current session

Just tell me what you need in plain English!
```

### Natural Language Interface

AIRA parses intent from conversational input. You don't need to memorize commands — just describe what you need.

### Intent-to-Action Map

| User Says | Intent | Pipeline |
|---|---|---|
| "Analyze PROJ-123" | Requirement Analysis | Context → Analysis |
| "Generate tests for PROJ-123" | Full Pipeline | Context → Analysis → Design → Validation |
| "What coverage exists for PROJ-123?" | TestRail Coverage | `testrail.ps1 -GetCoverage` |
| "Enhance TC-456" | Enhancement | TestRail fetch → propose updates |
| "Fetch context for PROJ-123" | Context Only | `aira.ps1 -BuildContext` |
| "Rescan context" | Context Rescan | `aira.ps1 -Rescan` |

---

## Prompt Examples & Use Cases

### Context Building

**Basic context fetch:**
```
Fetch context for PLAT-1488
```

**With local storage:**
```
Import context for MAV-1852, store locally
```

**With shared storage:**
```
Build context for CIA-2896, store shared
```

**With refresh (re-fetch and diff):**
```
Refresh context for PLAT-1488
```

**Skip attachments:**
```
Fetch context for PROJ-100, skip attachments
```

**With Confluence pages:**
```
Build context for PROJ-100 and include Confluence page 123456
```

---

### Requirement Analysis

**Basic analysis:**
```
Analyze PLAT-1488
```

**Analysis with dependencies:**
```
Analyze PLAT-1488, include dependencies
```

**Analysis with local storage:**
```
Analyze CIA-2896, store locally
```

**Full requirements generation:**
```
Analyze PLAT-1488, analyze dependencies, store locally, generate full requirements
```
This triggers:
1. Context building with dependency traversal
2. Analysis Agent reads all sources + attachments + dependencies
3. Produces full requirement specification
4. Saves to `artifacts/PLAT/PLAT-1488/requirements.md`
5. Generates test design → `artifacts/PLAT/PLAT-1488/testrail/design.json`

**Analysis of a Feature (granular per Story):**
```
Analyze Feature PROJ-500
```
AIRA analyzes each linked Story individually and summarizes the Feature-level dependency graph.

**Request just the gap analysis:**
```
Analyze PROJ-123 and highlight all gaps and missing requirements
```

---

### Test Case Generation (Full Pipeline)

**Generate tests:**
```
Generate test cases for PLAT-1488
```

**Generate and export to Excel:**
```
Generate tests for CIA-2896 and create the Excel export
```

**Generate with validation report:**
```
Generate tests for MAV-1852, validate, and show the validation report
```

**Full pipeline with all outputs:**
```
Generate tests for PLAT-1488, include dependencies, validate, and export to Excel
```

---

### TestRail Coverage Analysis

**Check coverage for a ticket:**
```
What coverage exists for PLAT-1488?
```

**Check coverage across all projects:**
```
Check TestRail coverage for CIA-2896
```

**Scoped coverage (specific project):**
```
Check TestRail coverage for MAV-1852 in project 212
```

**Coverage after analysis (traceability):**
```
Analyze PROJ-123, check coverage, and map scenarios to existing cases
```
This produces the Coverage Traceability & Analysis section in the requirements spec, mapping each scenario to its TestRail case(s) with calculated coverage percentages.

---

### Gap Analysis

**Identify gaps in existing coverage:**
```
What are the coverage gaps for PROJ-123?
```

**Gap analysis with recommendations:**
```
Analyze PROJ-456, check coverage, identify gaps, and recommend which cases to create vs enhance
```

**Cross-ticket gap analysis:**
```
Check coverage for PROJ-100, PROJ-101, and PROJ-102 — which scenarios have no test cases?
```

**Requirement completeness gaps:**
```
Analyze PROJ-789 and list all missing or ambiguous requirements
```

---

### Systems & Dependency Analysis

**Analyze with all dependencies:**
```
Analyze PROJ-123 with dependencies
```

**Deep dependency traversal:**
```
Analyze PROJ-123, include deps, depth 3
```
(Uses `-MaxDependencyDepth 3` instead of the policy default)

**No dependencies:**
```
Analyze PROJ-123, skip deps
```
(Uses `-MaxDependencyDepth 0`)

**Impact assessment across dependencies:**
```
Analyze PROJ-123 with dependencies — which systems are impacted?
```

**Dependency graph visualization:**
```
Show the dependency tree for PROJ-123
```

---

### Batch Context Operations

**Fetch context for multiple tickets:**
```
Build context for PROJ-100, PROJ-101, PROJ-102, and PROJ-103
```

**Analyze a whole feature's stories:**
```
Analyze all stories under Feature PROJ-500
```

**Batch coverage check:**
```
Check TestRail coverage for all stories in the CIA project
```

---

### Context Rescan & Diff

**Rescan all active contexts:**
```
Rescan context
```
Re-fetches all active contexts, compares SHA256 hashes, and writes diff entries for any that changed.

**Rescan with summary:**
```
Rescan all contexts and show me what changed
```

**Targeted refresh:**
```
Refresh context for PLAT-1488 and show the diff
```

---

### Session Management

**View current sessions:**
```
Show my active sessions
```

**Resume a previous session:**
```
Resume session for MAV-1852
```

**Session status:**
```
What's the status of the CIA-2896 session?
```

Sessions track 4 checkpoints: `context` → `analysis` → `design` → `validation`.

---

### Memory & Preferences

**View current preferences:**
```
Show my preferences
```

**Set a preference:**
```
Always set priority to High for Login-related test cases
```

**Promote corrections to preferences:**
```
Promote my corrections to preferences
```

When you override AIRA's decisions (rename a case, change priority, etc.), the correction is automatically logged. After repeated overrides, patterns are promoted to permanent preferences.

---

### Export & Reporting

**Excel export:**
```
Export the test design for CIA-2896 to Excel
```

Produces: `artifacts/CIA/CIA-2896/testrail/testrail_import.xlsx`

**CSV export for TestRail import:**
```
Export CIA-2896 design as CSV for TestRail import
```

**Full package (spec + design + Excel):**
```
Generate the full output package for PLAT-1488
```

Uses `-RunPipeline` to produce a versioned output bundle.

---

### Combined / Advanced Workflows

**Full end-to-end with coverage:**
```
Analyze PLAT-1488, include dependencies, check TestRail coverage, generate tests, validate, and export to Excel
```

**Analysis → Design → Push to TestRail:**
```
Generate tests for MAV-1852 and push approved cases to TestRail section 456
```

**Multiple tickets, one command:**
```
Analyze MAV-1852 and CIA-2896, generate requirements for both
```

**Enhancement workflow:**
```
Enhance TC-1235 with additional steps for the new payment flow from PROJ-789
```

**Confluence-augmented analysis:**
```
Analyze PROJ-123, pull Confluence page 789012 for additional specs, and generate full requirements
```

**Readiness + analysis in one session:**
```
Test integrations, then analyze PROJ-123 if everything passes
```

**Project-wide coverage report:**
```
Generate a coverage report for all stories in project MAV
```

---

## Output Structure & Reporting

### Context Outputs

```
context/
├── shared/{Prefix}/{KEY}/
│   └── context.md              ← Enriched summary (always written)
│
└── local/{Prefix}/{KEY}/
    ├── context.md              ← Copy of shared context
    ├── manifest.json           ← Metadata, timestamps, hashes
    ├── sources/
    │   ├── issue.json          ← Raw Jira issue payload
    │   ├── comments.json       ← Raw Jira comments
    │   ├── linked_issues.json  ← Dependency graph
    │   ├── attachments.json    ← Attachment metadata + hashes
    │   └── sources.json        ← Consolidated source list
    ├── attachments/            ← Downloaded files (on-demand)
    ├── dependencies/           ← Sub-contexts for linked issues (on-demand)
    │   └── {DEP-KEY}/
    │       ├── context.md
    │       └── sources/
    ├── metadata/               ← TestRail coverage (on-demand)
    │   └── testrail/
    │       └── coverage.json
    └── diffs/                  ← Hash diffs from rescan (on-demand)
        └── {timestamp}.json
```

The `context.md` contains:
- Issue metadata (key, summary, type, status, priority, dates)
- Full description text (converted from Jira markup)
- Acceptance criteria
- All comments (numbered, with author, date, body)
- Direct dependencies table
- All linked issues table
- Existing TestRail coverage (when requested, inline — no separate file)
- References & links (Jira URL, Confluence, attachments)
- Concerns / known bugs

#### Confluence / Wiki Context

Wiki page context is stored under `context/shared/` using the Confluence space key and page ancestry:

```
context/shared/{SpaceKey}/{RootPageName}/{PageName} ({PageId})/
└── context.md              ← Wiki page summary
```

| Placeholder | Description | Example |
|---|---|---|
| `{SpaceKey}` | Confluence space key | `POQ`, `ProjectName` |
| `{RootPageName}` | First non-home ancestor page title | `QA Process` |
| `{PageName} ({PageId})` | Page title with numeric ID in parentheses for uniqueness | `AI environment setup (330110221)` |

The `root_page` and `ancestors` array are returned by `confluence.ps1` when fetching a page.
If the page is directly under the space home (no intermediate ancestors), the page title is used as both root and page name.

**Example:** See [context/shared/POQ/QA Process/AI environment setup (330110221)/context.md](context/shared/POQ/QA%20Process/AI%20environment%20setup%20(330110221)/context.md) for a live wiki context file.

> **Example:** See [context/shared/EXAMPLE/EXAMPLE-100/context.md](context/shared/EXAMPLE/EXAMPLE-100/context.md) for a complete shared context example.

### Analysis Outputs (Requirements Spec)

`artifacts/{Prefix}/{KEY}/requirements.md` — always auto-generated during analysis.

Structure follows the BA/QE Requirements Specification Protocol:

| Section | Content |
|---|---|
| **Impact Assessment** | Impacted domains: UI / API / Backend / Database |
| **1. Document Summary** | Title, ID, Status, Priority |
| **2. Change Tracker** | Version history table |
| **3. Context & Overview** | Business context, current behavior, target audience |
| **4. User Story** | As a [Role], I want to [Action], so that [Benefit] |
| **5. Technical Alignment** | UI/UX, API, Backend, Database scope |
| **6. Acceptance Criteria** | Table or Gherkin format |
| **7. NFRs** | Non-functional requirements (when specified) |
| **8. References** | Source documents, Jira links, attachments |
| **Coverage Traceability** | Scenario-to-case mapping, coverage % (when coverage data exists) |
| **Scenario Inventory** | Numbered scenarios for test design |
| **Questions / Gaps** | Business and technical gaps |

### Design Outputs (Test Cases)

`artifacts/{Prefix}/{KEY}/testrail/design.json` — always auto-generated.

```json
{
  "new_cases": [
    {
      "title": "TC001 - Verify [scenario]",
      "priority": "High",
      "type": "Functional",
      "preconditions": "...",
      "references": "PROJ-123",
      "prereq_case_ids": [],
      "steps": [
        { "step": 1, "action": "...", "expected": "..." }
      ]
    }
  ],
  "enhance_cases": [
    {
      "existing_case_id": 1235,
      "existing_title": "Current title",
      "rationale": "Why enhancement needed",
      "new_steps": [{ "step": 7, "action": "...", "expected": "..." }],
      "updated_references": "PROJ-123,PROJ-456"
    }
  ],
  "prereq_cases": [
    {
      "case_id": 1234,
      "title": "Verify login",
      "usage": "Run before TC001, TC002"
    }
  ]
}
```

### Validation Reports

`artifacts/{Prefix}/{KEY}/testrail/validation_results.json`:

```json
{
  "overall": "Pass",
  "checks": [
    { "name": "schema_compliance", "status": "Pass", "details": "All required fields present" },
    { "name": "forbidden_values", "status": "Pass", "details": "No forbidden priorities" },
    { "name": "step_completeness", "status": "Pass", "details": "All steps have action + expected" },
    { "name": "reference_integrity", "status": "Pass", "details": "All references valid" },
    { "name": "duplicate_detection", "status": "Pass", "details": "No duplicate titles" }
  ]
}
```

### Excel & CSV Exports

Generated only when explicitly requested.

`artifacts/{Prefix}/{KEY}/testrail/testrail_import.xlsx` contains 3 sheets:

| Sheet | Content |
|---|---|
| **New Cases** | Title, Priority, Type, Preconditions, References, Prereq Case IDs, Steps |
| **Enhancements** | Existing Case ID, Title, Rationale, New Steps, Updated References |
| **Prerequisites** | Case ID, Title, Usage |

Column mapping is driven by `core/templates/excel_mapping.json` and can be customized via `overrides/templates/excel_mapping.json`.

### Coverage Reports

When TestRail coverage is analyzed, the following data is produced:

**Inline in `context.md`** (under `## Existing Coverage (TestRail)`):
- Run metadata (project, run ID, URL, status)
- Execution summary (passed/failed/untested counts with percentages)
- Full case listing with status icons
- Attention items (failed, untested)

**Coverage Traceability in `requirements.md`** (when scenarios exist):

| Metric | Formula |
|---|---|
| **Fully Covered** | Scenarios with passing case / total scenarios |
| **Partially Covered** | Scenarios with failed/untested case / total |
| **No Coverage** | Scenarios with no mapped case / total |
| **Overall Requirement Coverage** | Scenarios with ≥1 case / total |
| **Effective Pass Rate** | Scenarios with all cases passing / total |

### Session & Memory Data

**Sessions** (`.aira/sessions/session_*.json`):
```json
{
  "jira_key": "MAV-1852",
  "id": "session_20260209_175908_MAV1852",
  "state": "CONTEXT_READY",
  "checkpoints": {
    "context": { "path": "...", "timestamp": "...", "hash": "..." },
    "analysis": null,
    "design": null,
    "validation": null
  }
}
```

**Corrections** (`.aira/memory/corrections.jsonl`):
```json
{"kind":"rename","jira_key":"PROJ-123","before":"Verify login","after":"TC001 - Verify user login","rationale":"Naming convention","timestamp":"2026-02-09T10:00:00"}
```

**Preferences** (`.aira/memory/user_preferences.json`):
```json
{
  "naming": { "prefix_with_tc_number": true },
  "priorities": { "login_features": "High" }
}
```

---

## Script Reference

All scripts are invoked with:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/<script>.ps1 [params]
```

### aira.ps1 — Central CLI

| Mode | Parameters | Description |
|---|---|---|
| `-InitWorkspace` | | Create required folders and files |
| `-InstallDependencies` | | Install Pester 5.7+ and ImportExcel |
| `-Doctor` | `[-Force]` | Run readiness tests, update startup state |
| `-BuildContext` | `-JiraKey <KEY> [-Refresh] [-Scope Auto\|Local\|Shared] [-MaxDependencyDepth N] [-DownloadAttachments] [-MaxAttachmentMB N] [-ConfluencePageIds @()] [-SkipConfluence] [-WithCoverage]` | Fetch Jira context and store |
| `-Rescan` | | Re-fetch all active contexts, compare hashes, write diffs |
| `-RunPipeline` | `-JiraKey <KEY> -Project <name> [-DesignJson <path>] [-SpecPath <path>] [-Scope] [-SkipValidation] [-SkipExcel]` | Package versioned outputs |
| `-ListContext` | | List all stored contexts |
| `-ArchiveContext` | `-JiraKey <KEY>` | Archive a context |

### jira.ps1 — Jira API (Read-Only)

| Mode | Parameters | Description |
|---|---|---|
| `-IssueKey <KEY>` | `[-MaxDependencyDepth N] [-AuthMode auto\|bearer\|basic]` | Fetch issue with full details |
| `-ProjectKey <KEY>` | | List recent issues in project |
| `-TestConnection` | | Verify Jira connectivity |

### testrail.ps1 — TestRail API (Bidirectional)

| Mode | Parameters | Description |
|---|---|---|
| `-GetCoverage` | `-JiraKey <KEY> [-ProjectId N]` | Analyze coverage by Jira refs |
| `-GetCase` | `-CaseId N` | Fetch a single case |
| `-CreateCase` | `-SectionId N -CaseJson <json\|path>` | Create one case |
| `-UpdateCase` | `-CaseId N -CaseJson <json\|path>` | Update a case |
| `-EnhanceCase` | `-CaseId N -CaseJson <json\|path>` | Append steps to existing case |
| `-BatchCreate` | `-SectionId N -CasesJson <json\|path>` | Create multiple cases |
| `-ListProjects` | | List all TestRail projects |
| `-ListRuns` | `[-ProjectId N] [-ProjectName <name>]` | List test runs |
| `-GetSections` | `-ProjectId N` | Get project sections |
| `-CreateSection` | `-ProjectId N -SectionName <name> [-ParentId N]` | Create a new section |
| `-DeleteCase` | `-DeleteCaseId N` | Delete a case |
| `-DeleteSection` | `-DeleteSectionId N [-DeleteCases]` | Delete a section |
| `-TestConnection` | | Verify TestRail connectivity |

### confluence.ps1 — Confluence API (Read-Only)

| Mode | Parameters | Description |
|---|---|---|
| `-PageId <ID>` | `[-Format storage\|view\|both] [-NoBody]` | Fetch page by ID (includes ancestors, root_page) |
| `-PageId <ID> -GetChildren` | `[-Limit N]` | List child pages of a parent |
| `-Query <text>` | `[-SpaceKey <KEY>] [-Limit N]` | CQL text search |
| `-TestConnection` | | Verify Confluence connectivity |

### excel.ps1 — Excel Export

| Parameters | Description |
|---|---|
| `-InputJson <path>` `-OutputPath <path>` `[-MappingPath <path>]` | Generate `.xlsx` from design JSON |

### validate.ps1 — Validation Runner

| Parameters | Description |
|---|---|
| `-TestCasesJson <path>` `[-OutputPath <path>]` `[-PolicyRoot .aira]` | Run validation checks |

### memory.ps1 — Memory Utilities

| Mode | Parameters | Description |
|---|---|---|
| `-LogCorrection` | `-Kind <type> [-JiraKey] -BeforeJson <json> -AfterJson <json> [-Rationale <text>]` | Log a correction |
| `-ShowPreferences` | | Display current preferences |
| `-SetPreference` | `-PreferenceJson <json>` | Set a preference |
| `-PromotePreferences` | `[-Window N] [-Threshold N] [-DryRun]` | Promote frequent corrections |

### session.ps1 — Session Management

| Mode | Parameters | Description |
|---|---|---|
| `-NewSession` | `-JiraKey <KEY>` | Create a new session |
| `-GetSession` | `-SessionId <ID>` | Retrieve session by ID |
| (by Jira key) | `-JiraKey <KEY>` | Find session by Jira key |
| `-UpdateCheckpoint` | `-SessionId <ID> -Name <stage> [-State] [-Path] [-DataJson]` | Update a checkpoint |

---

## Validation System

AIRA includes 6 built-in validation checks that run against the test design JSON before export or TestRail write.

### Built-in Checks

| Check Script | What It Validates |
|---|---|
| `schema_compliance.ps1` | All required fields present: `title`, `steps[]`, each step has `action` + `expected` |
| `forbidden_values.ps1` | No priorities from `testrail.restrictions.forbidden_priorities` |
| `step_completeness.ps1` | Every step has non-empty `action` and `expected` result |
| `reference_integrity.ps1` | Jira references match expected key format (e.g., `PROJ-123`) |
| `duplicate_detection.ps1` | No duplicate case titles within the design |
| `prerequisite_exists.ps1` | Referenced `prereq_case_ids` exist in `prereq_cases` or are valid TestRail IDs |

### Running Validation

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/validate.ps1 `
    -TestCasesJson "artifacts/CIA/CIA-2896/testrail/design.json" `
    -OutputPath    "artifacts/CIA/CIA-2896/testrail/validation_results.json"
```

### Check Statuses

| Status | Meaning |
|---|---|
| **Pass** | All assertions met |
| **Warn** | Minor issues (non-blocking, if policy allows) |
| **Fail** | Blocking issues — must fix before export/push |

---

## Plugin System

Plugins extend AIRA with custom validation checks, skills, prompts, and templates.

### Plugin Structure

```
plugins/<name>/
├── manifest.json          # Required: name, version, enabled, load_order
├── skills/                # Skill documentation
├── validation/checks/     # Custom validation check scripts
├── prompts/               # Custom agent persona extensions
└── templates/             # Custom output templates
```

### manifest.json

```json
{
  "name": "aira-example",
  "version": "1.0.0",
  "description": "Skeleton example plugin.",
  "enabled": false,
  "load_order": 900
}
```

- `enabled`: Set to `true` to activate the plugin
- `load_order`: Lower numbers load first (plugins override higher-numbered plugins)

### Creating a Plugin

1. Copy `plugins/aira-example/` to `plugins/your-plugin/`
2. Edit `manifest.json` with your plugin's details
3. Add skills under `skills/`, checks under `validation/checks/`
4. Set `"enabled": true`
5. Re-run any validation or agent operations — AIRA auto-discovers plugin resources

---

## Override System

Overrides customize AIRA's core behavior without modifying core files.

### Resolution Precedence

```
overrides/          ← Highest priority (team customizations)
  ↓
plugins/            ← Enabled plugins (sorted by load_order)
  ↓
core/               ← Baseline (default behavior)
```

### Available Overrides

| Override | Core Default | Purpose |
|---|---|---|
| `overrides/prompts/aira_master.md` | `core/prompts/aira_master.md` | Custom orchestrator persona |
| `overrides/prompts/analysis_agent.md` | `core/prompts/analysis_agent.md` | Custom analysis behavior |
| `overrides/prompts/design_agent.md` | `core/prompts/design_agent.md` | Custom test design rules |
| `overrides/prompts/context_agent.md` | `core/prompts/context_agent.md` | Custom context building |
| `overrides/prompts/validation_agent.md` | `core/prompts/validation_agent.md` | Custom validation rules |
| `overrides/prompts/testrail_specialist.md` | `core/prompts/testrail_specialist.md` | Custom TestRail behavior |
| `overrides/templates/spec_template.md` | `core/templates/spec_template.md` | Custom requirement template |
| `overrides/templates/excel_mapping.json` | `core/templates/excel_mapping.json` | Custom Excel column mapping |
| `overrides/rules/team_rules.md` | *(none)* | Freeform team-specific rules |

### Activating an Override

1. Copy the `.example` file and remove the `.example` suffix
2. Modify to your needs
3. The filename must **exactly match** the core resource name

Example:
```powershell
Copy-Item overrides/templates/spec_template.md.example overrides/templates/spec_template.md
# Edit overrides/templates/spec_template.md with your customizations
```

---

## Testing

### Test Suite Structure

```
.aira/tests/
├── unit/                               # Fast, no external APIs
│   ├── Modules.Tests.ps1               # Import checks for all modules
│   ├── Policy.Tests.ps1                # Policy loading, merging, locked fields
│   ├── Templating.Tests.ps1            # Template placeholder rendering
│   ├── Memory.Tests.ps1                # Diff computation, preference promotion
│   ├── ValidationChecks.Tests.ps1      # All 6 validation checks
│   ├── ResourceResolution.Tests.ps1    # Override precedence, plugin discovery
│   └── Paths.Tests.ps1                 # Path resolution helpers
│
├── integration/                        # Require API credentials
│   ├── Jira.Tests.ps1
│   ├── TestRail.Tests.ps1
│   ├── Confluence.Tests.ps1
│   ├── GitHub.Tests.ps1
│   └── Bitbucket.Tests.ps1
│
└── results/                            # Test output (never committed)
    ├── test_result.log                 # Human-readable log
    ├── last_doctor.json                # Combined summary
    ├── unit_result.json                # Unit test counts
    ├── integration_result.json         # Integration test counts
    ├── unit_<timestamp>.xml            # NUnit XML reports
    └── integration_<timestamp>.xml
```

### Running Tests

**Full readiness suite (recommended):**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File core/scripts/aira.ps1 -Doctor
```

**Ad-hoc Pester run:**
```powershell
$c = New-PesterConfiguration
$c.Run.Path = '.aira/tests/unit/'
$c.Run.PassThru = $true
$c.TestResult.Enabled = $true
$c.TestResult.OutputPath = '.aira/tests/results/unit_adhoc.xml'
$c.TestResult.OutputFormat = 'NUnitXml'
$c.Output.Verbosity = 'Minimal'
$r = Invoke-Pester -Configuration $c
```

> **Important:** All test output must go to files under `.aira/tests/results/`. Never pipe raw Pester output to the console in automation flows — it can crash the VS Code terminal.

### Current Test Status

| Suite | Tests | Passing | Status |
|---|---|---|---|
| Unit | 54 | 54 | ✅ Pass |
| Integration | 5 | 5 | ✅ Pass |

---

## Future Enhancements

### Planned Features

| Enhancement | Description | Status |
|---|---|---|
| **Confluence Write-Back** | Push requirement specs back to Confluence as formatted pages | Planned |
| **Jira Comment Auto-Post** | Post analysis summaries and gap reports as Jira comments | Planned |
| **TestRail Run Creation** | Create test runs directly from design output | Planned |
| **Multi-Project Coverage** | Cross-project coverage analysis for shared components | Planned |
| **AI-Powered Deduplication** | Semantic similarity matching for duplicate detection | Planned |
| **Regression Impact Analysis** | Identify which test cases are affected by code changes | Planned |
| **Dashboard / Reporting** | HTML dashboard with coverage metrics, trends, and team analytics | Planned |
| **Email Reports** | Send formatted coverage/analysis reports via email (`email_report.html` template exists) | Template Ready |
| **CI/CD Integration** | Run AIRA analysis as part of CI pipelines | Planned |
| **PowerShell Core Support** | Full compatibility with PowerShell 7+ (currently PS 5.1) | Planned |
| **Team Collaboration** | Multi-user session sharing and concurrent analysis | Planned |
| **Custom Check Authoring UI** | Guided plugin creation for validation checks | Planned |
| **Automated Test Maintenance** | Detect stale test cases when requirements change | Planned |
| **Risk-Based Test Prioritization** | Prioritize test execution based on change risk analysis | Planned |
| **Natural Language Test Queries** | "Which tests cover the payment flow?" | Planned |

### Reporting Improvements

| Area | Current | Future |
|---|---|---|
| **Format** | Markdown + JSON + Excel | + HTML dashboards, PDF export, email |
| **Coverage** | Per-story traceability tables | + trend charts, historical comparisons |
| **Quality** | Validation pass/fail | + quality score, complexity metrics |
| **Team Views** | Per-session data | + aggregated team dashboards |
| **Automation** | Manual trigger | + scheduled rescans, CI integration |

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|---|---|
| "Running scripts is disabled" | Run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` or use the `-ExecutionPolicy Bypass` flag |
| Doctor fails on integration tests | Check `.env` credentials, verify VPN connection |
| "Readiness not Complete" | Run `aira.ps1 -Doctor` to diagnose and fix |
| TestRail write blocked | Ensure `startup.state.json` shows `"status": "Complete"` |
| Empty context.md | Verify Jira credentials and issue key exists |
| Excel export fails | Run `aira.ps1 -InstallDependencies` to install ImportExcel |
| Policy merge issues | Check `locked_fields` in `admin.policy.json` — locked fields cannot be overridden |

### Getting Help

In Copilot Chat, just ask:
```
Help
```
or
```
Test integrations
```

---

## License

Proprietary — Internal use only.

---

*AIRA v2.0 — Turning requirements into quality, one test at a time.*
