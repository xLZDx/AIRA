# aira-prototyping plugin

AIRA plugin for managing requirement prototypes from existing web pages, including complex multi-page scenario recording.

## What it does

Mandatory rules:
- The artifact contract is strict: `source/`, `flows/`, versioned `v{version}/`, `latest/`, and `versions.json` are the supported structure.
- `source/` is the untouched baseline of the original app. Prototype edits must never be written back into `source/`.
- Original app styles must be preserved. New UI such as login overlays belongs in flow step sources or versioned outputs, not in the baseline source.
- A usable prototype is only discoverable and complete after initialization plus publish. `working/` is transient and not a release artifact.

1. **Fetches** an existing web page (HTML + CSS) from a user-provided shared link
2. **Resolves** the project name from the link domain/path (e.g., `https://example.org/dashboard` -> `example-org`)
3. **Injects** user requirements into the source page, annotated as `[PROTOTYPE]` with unique IDs
4. **Records flows** -- multi-page scenarios with ordered steps, actions (click, type, navigate, snapshot), and per-step source capture
5. **Builds flow prototypes** -- generates a single-file navigable SPA from recorded flows with keyboard navigation
6. **Versions** each iteration using SemVer (major.minor.patch) with an immutable changelog
7. **Publishes** versioned prototype packages to `artifacts/prototypes/{project}/`

## Structure

```
plugins/aira-prototyping/
  manifest.json                          # Plugin metadata (enabled, load_order)
  README.md                              # This file
  modules/
    Aira.Prototyping.psm1               # Core prototyping functions
  prompts/
    prototype_agent.md                   # Agent persona for prototyping
  scripts/
    prototype.ps1                        # Main CLI script (6 modes)
  skills/
    prototyping.md                       # Skill documentation
  validation/
    checks/
      prototype_requirements.ps1         # Validation check for requirements
```

## Usage

### 1. Fetch a source page

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -FetchSource -SourceUrl "https://example.org/dashboard"
```

### 1a. Initialize from local baseline files

Use this when the site cannot be fetched from the current environment but you still have the original app HTML/CSS.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
  -InitProject -Project "example-org" `
  -SourceHtmlFile "scratch/example-org/source/index.html" `
  -SourceCssFile "scratch/example-org/source/styles.css" `
  -SourceUrl "https://example.org"
```

### 2. Add requirements

Create a requirements JSON file:
```json
[
  { "title": "Login must support 2FA", "description": "Two-factor auth via TOTP or SMS", "priority": "High" },
  { "title": "Dashboard loads in < 2s", "description": "Performance requirement for main dashboard", "priority": "Medium" }
]
```

Then inject:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -AddRequirements -Project "example-org" -RequirementsFile "path/to/requirements.json"
```

Or pass requirements inline:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -AddRequirements -Project "example-org" `
    -Requirements '[{"title":"2FA Login","description":"Must support TOTP","priority":"High"}]'
```

### 3. Record a complex multi-page scenario

**Create a flow:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction Create `
    -FlowId "login-to-dashboard" -FlowName "Login to Dashboard" -EntryUrl "https://example.org/login"
```

**Add steps:**
```powershell
# Step 1: Login page
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction AddStep `
    -FlowId "login-to-dashboard" -StepPage "login" -StepUrl "https://example.org/login" `
    -StepDescription "User enters credentials" `
    -StepActions '[{"type":"type","selector":"#username","value":"admin"},{"type":"click","selector":"#login-btn"}]'

# Step 2: Dashboard
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction AddStep `
    -FlowId "login-to-dashboard" -StepPage "dashboard" -StepUrl "https://example.org/dashboard" `
    -StepDescription "Dashboard loads after login"
```

**Set captured sources for each step:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction SetSource `
    -FlowId "login-to-dashboard" -StepNumber 1 -SourceHtmlFile "path/to/login.html"

powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction SetSource `
    -FlowId "login-to-dashboard" -StepNumber 2 -SourceHtmlFile "path/to/dashboard.html"
```

**Show or list flows:**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction Show -FlowId "login-to-dashboard"

powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -RecordFlow -Project "example-org" -FlowAction List
```

### 4. Build a flow prototype (SPA)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -BuildFlow -Project "example-org" -FlowId "login-to-dashboard"
```

### 5. Publish a version

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -Publish -Project "example-org"
```

### 6. List versions

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File plugins/aira-prototyping/scripts/prototype.ps1 `
    -ListVersions -Project "example-org"
```

## Artifact output

```
artifacts/prototypes/{project}/
  source/                          <- original page + styles only; never modified by prototype edits
    index.html
    styles.css
    metadata.json
  flows/                           <- flow definitions + step sources
    {flow-id}.json                 <- flow definition
    {flow-id}/
      step-1/
        source.html
        styles.css
      step-2/
        source.html
        styles.css
  v1.0.0/                          <- immutable versioned release
    prototype.html                 <- HTML (single-page or SPA) with [PROTOTYPE] annotations
    requirements.json              <- structured requirements for this version
    CHANGELOG.md                   <- what changed from previous version
    manifest.json                  <- version metadata + hashes
  latest/                          <- copy of the most recent version
  versions.json                    <- version registry
```

Required lifecycle: initialize or fetch baseline -> record flow or add requirements -> build to `working/` -> publish immutable version -> consume `latest/` or `v{version}/`.

## Natural language usage with AIRA

Tell AIRA in plain English:

- *"Fetch the page at https://example.org for prototyping"*
- *"Add these requirements to the example-org prototype: ..."*
- *"Record a login-to-dashboard flow for example-org starting at https://example.org/login"*
- *"Add a step for the dashboard page to the login-to-dashboard flow"*
- *"Build the login-to-dashboard flow prototype"*
- *"Publish the prototype for example-org"*
- *"Show prototype versions for example-org"*
- *"List all flows for example-org"*
