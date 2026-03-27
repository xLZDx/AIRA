# Prototyping Skill

This skill enables prototype management for AIRA: fetch existing web pages with styles, inject user requirements as prototype sections with versioning, record complex multi-page scenarios, and publish structured prototype artifacts.

## Capabilities

- **Fetch source page** -- Download an existing page (HTML + CSS) from a shared link to use as the prototype base
- **Initialize baseline from local files** -- Seed `source/` from local HTML/CSS when remote fetch is unavailable, while preserving the original app styles
- **Inject requirements** -- Add user-provided requirements into the fetched source, marked with `[PROTOTYPE]` annotations and semantic versioning
- **Record flows** -- Define multi-page scenarios with ordered steps, actions (navigate, click, type, snapshot), and per-step source capture
- **Build flow prototypes** -- Generate a single-file navigable SPA from a recorded flow, with keyboard navigation (arrow keys) and step-level action summaries
- **Version management** -- Track prototype iterations with SemVer (major.minor.patch) and maintain a changelog
- **Publish artifacts** -- Output versioned prototype packages to `artifacts/prototypes/{project}/`
- **Project resolution** -- Resolve the project name from shared links provided by the user

## Usage Examples

### Fetch a source page for prototyping
User: "Fetch the page at https://example.org/dashboard for prototyping"
- Run: `plugins/aira-prototyping/scripts/prototype.ps1 -FetchSource -SourceUrl "https://example.org/dashboard"`

### Initialize a project from local baseline files
User: "Initialize example-org from local HTML/CSS and preserve the original app styles"
- Run: `plugins/aira-prototyping/scripts/prototype.ps1 -InitProject -Project "example-org" -SourceHtmlFile "path/to/index.html" -SourceCssFile "path/to/styles.css" -SourceUrl "https://example.org"`

### Add requirements to a prototype
User: "Add these requirements to the Example.org prototype: login must support 2FA, dashboard must load in under 2s"
- Run: `plugins/aira-prototyping/scripts/prototype.ps1 -AddRequirements -Project "example-org" -RequirementsFile "path/to/requirements.json"`

### Record a complex multi-page scenario
User: "Record a login-to-dashboard flow for example-org"

1. Create the flow:
```powershell
prototype.ps1 -RecordFlow -Project "example-org" -FlowAction Create `
    -FlowId "login-to-dashboard" -FlowName "Login to Dashboard" -EntryUrl "https://example.org/login"
```

2. Add steps:
```powershell
prototype.ps1 -RecordFlow -Project "example-org" -FlowAction AddStep `
    -FlowId "login-to-dashboard" -StepPage "login" -StepUrl "https://example.org/login" `
    -StepDescription "User enters credentials" `
    -StepActions '[{"type":"type","selector":"#username","value":"admin"},{"type":"type","selector":"#password","value":"admin"},{"type":"click","selector":"#login-btn"}]'

prototype.ps1 -RecordFlow -Project "example-org" -FlowAction AddStep `
    -FlowId "login-to-dashboard" -StepPage "dashboard" -StepUrl "https://example.org/dashboard" `
    -StepDescription "Dashboard loads after successful login" `
    -StepActions '[{"type":"snapshot","label":"Dashboard loaded"}]'
```

3. Set captured sources for each step:
```powershell
prototype.ps1 -RecordFlow -Project "example-org" -FlowAction SetSource `
    -FlowId "login-to-dashboard" -StepNumber 1 -SourceHtmlFile "path/to/login.html"

prototype.ps1 -RecordFlow -Project "example-org" -FlowAction SetSource `
    -FlowId "login-to-dashboard" -StepNumber 2 -SourceHtmlFile "path/to/dashboard.html"
```

4. Show or list flows:
```powershell
prototype.ps1 -RecordFlow -Project "example-org" -FlowAction Show -FlowId "login-to-dashboard"
prototype.ps1 -RecordFlow -Project "example-org" -FlowAction List
```

### Build a navigable SPA from a recorded flow
User: "Build the login-to-dashboard flow prototype"
```powershell
prototype.ps1 -BuildFlow -Project "example-org" -FlowId "login-to-dashboard"
```
Then publish:
```powershell
prototype.ps1 -Publish -Project "example-org"
```

### Publish a prototype version
User: "Publish the prototype for example-org as v1.1.0"
- Run: `plugins/aira-prototyping/scripts/prototype.ps1 -Publish -Project "example-org" -Version "1.1.0"`

### List prototype versions
User: "Show all prototype versions for example-org"
- Run: `plugins/aira-prototyping/scripts/prototype.ps1 -ListVersions -Project "example-org"`

## Output Format

### Fetch Source
```json
{
  "status": "ok",
  "project": "example-org",
  "source_url": "https://example.org/dashboard",
  "fetched_at": "2026-03-11T10:00:00",
  "files": {
    "html": "artifacts/prototypes/example-org/source/index.html",
    "styles": "artifacts/prototypes/example-org/source/styles.css"
  }
}
```

### Add Requirements
```json
{
  "status": "ok",
  "project": "example-org",
  "requirements_added": 3,
  "current_version": "1.1.0",
  "prototype_path": "artifacts/prototypes/example-org/v1.1.0/prototype.html"
}
```

### RecordFlow - Create
```json
{
  "status": "ok",
  "action": "create",
  "project": "example-org",
  "flow_id": "login-to-dashboard",
  "name": "Login to Dashboard",
  "entry_url": "https://example.org/login",
  "steps": 0
}
```

### RecordFlow - AddStep
```json
{
  "status": "ok",
  "action": "add_step",
  "project": "example-org",
  "flow_id": "login-to-dashboard",
  "step_number": 2,
  "page": "dashboard",
  "total_steps": 2
}
```

### BuildFlow
```json
{
  "status": "ok",
  "project": "example-org",
  "flow_id": "login-to-dashboard",
  "version": "0.2.0",
  "steps": 3,
  "steps_with_src": 3,
  "requirements": 2,
  "working_path": "artifacts/prototypes/example-org/working/prototype.html"
}
```

### Publish
```json
{
  "status": "ok",
  "project": "example-org",
  "version": "1.1.0",
  "published_at": "2026-03-11T10:05:00",
  "artifacts": {
    "prototype": "artifacts/prototypes/example-org/v1.1.0/prototype.html",
    "requirements": "artifacts/prototypes/example-org/v1.1.0/requirements.json",
    "changelog": "artifacts/prototypes/example-org/v1.1.0/CHANGELOG.md",
    "manifest": "artifacts/prototypes/example-org/v1.1.0/manifest.json"
  }
}
```

## Artifact Structure

```
artifacts/prototypes/{project}/
  source/                          <- original fetched page + styles; never modified by prototype edits
    index.html
    styles.css
    metadata.json                  <- fetch metadata (URL, date, hashes)
  flows/                           <- flow definitions and step sources
    {flow-id}.json                 <- flow definition (steps, actions, metadata)
    {flow-id}/                     <- captured sources per step
      step-1/
        source.html
        styles.css
      step-2/
        source.html
        styles.css
  v{major.minor.patch}/            <- versioned prototype releases
    prototype.html                 <- modified HTML with prototype requirements (single-page or SPA)
    requirements.json              <- structured requirements for this version
    CHANGELOG.md                   <- version changelog
    manifest.json                  <- version metadata + hashes + diff summary
  latest/                          <- copy of the latest published version
  versions.json                    <- version registry (all versions with metadata)
```

## Flow Definition Schema

```json
{
  "flow_id": "login-to-dashboard",
  "name": "Login to Dashboard",
  "project": "example-org",
  "entry_url": "https://example.org/login",
  "steps": [
    {
      "step": 1,
      "page": "login",
      "url": "https://example.org/login",
      "description": "User enters credentials and submits",
      "actions": [
        { "type": "type", "selector": "#username", "value": "admin" },
        { "type": "click", "selector": "#login-btn" }
      ],
      "has_source": true
    }
  ],
  "created_at": "2026-03-11T10:00:00",
  "updated_at": "2026-03-11T10:05:00"
}
```

### Supported action types
| Type | Description | Required keys |
|------|-------------|---------------|
| `navigate` | Navigate to a URL | `url` |
| `click` | Click an element | `selector` |
| `type` | Type text into a field | `selector`, `value` |
| `select` | Select a dropdown option | `selector`, `value` |
| `snapshot` | Capture page state | `label` |
| `wait` | Wait for a condition | `timeout_ms` or `selector` |
| `scroll` | Scroll to an element | `selector` |
| `assert` | Assert element state | `selector`, `value` (expected text) |

## Requirement Annotation Format

Requirements injected into the prototype HTML are wrapped in semantic markers:

```html
<!-- [PROTOTYPE:REQ-001] v1.1.0 | Priority: High | Added: 2026-03-11 -->
<div class="aira-prototype-requirement" data-req-id="REQ-001" data-version="1.1.0">
  <h4>REQ-001: Login must support 2FA</h4>
  <p>The login page must integrate two-factor authentication...</p>
</div>
<!-- [/PROTOTYPE:REQ-001] -->
```

## Notes

- Projects are resolved from the shared link domain/path (e.g., `https://example.org/dashboard` -> project `example-org`).
- The `source/` folder is fetched once and reused across versions unless `-Refresh` is specified.
- `-InitProject` is the supported fallback when the original app cannot be fetched from the current environment.
- Flows live under `flows/` with per-step source directories created on-demand.
- Each version is immutable once published -- new changes create a new version.
- The `latest/` folder always mirrors the most recently published version.
- Style preservation is mandatory: new prototype UI must layer on top of or sit beside the baseline, not replace baseline app styles.
- `working/` is temporary. A discoverable prototype release requires `-Publish`, which creates `v{version}/`, updates `latest/`, and updates `versions.json`.
- Flow SPA prototypes support keyboard navigation (left/right arrow keys) between steps.
- When Playwright MCP is available, use it to capture page sources for each flow step automatically.
- To enable this plugin, ensure `"enabled": true` in `plugins/aira-prototyping/manifest.json`.
