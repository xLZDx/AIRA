# Jira Integration Skill

This skill enables Jira read operations used by AIRA v2 to build context and analyze requirements.

## Capabilities

- **Connection test** (read-only)
- **Issue fetch** (summary, type, status, description)
- **Comment retrieval** (flattened to text)
- **Linked-issue discovery** (dependency graph traversal up to configured depth)
- **Acceptance criteria extraction** (best-effort from description text)

## Usage Examples

### Test connectivity
User: “Test Jira connection”
- Run: `core/scripts/jira.ps1 -TestConnection`

### Fetch a single issue context
User: “Get Jira context for MARD-719”
- Run: `core/scripts/jira.ps1 -IssueKey "MARD-719"`

### List recent issues in a project
User: “Show recent issues for project MARD”
- Run: `core/scripts/jira.ps1 -ProjectKey "MARD"`

## Output Format

The issue fetch outputs a summarized JSON object:

```json
{
  "jira_key": "MARD-719",
  "summary": "Add AUM Metrics to Dashboard",
  "issue_type": "Story",
  "status": "In Progress",
  "priority": "Medium",
  "description": "...",
  "acceptance_criteria": ["...", "..."],
  "comments": [
    {"id":"10001","author":"...","created":"...","body":"..."}
  ],
  "linked_issues": {
    "direct": [{"key":"MARD-700","relationship":"blocks","direction":"outward","issue_type":"Story","status":"...","summary":"..."}],
    "all": [{"key":"MARD-700","issue_type":"Story","status":"...","summary":"..."}]
  },
  "fetched_at": "2026-02-06T12:34:56"
}
```

