# Coverage Analysis Skill

This skill explains how AIRA determines **coverage gaps** vs **duplicates** using TestRail as a source of truth.

## Capabilities

- Interpret TestRail coverage output into:
  - direct coverage (exact Jira key match in `refs`)
  - related coverage (same project prefix, potential prereqs)
- Recommend the correct output category:
  - `NEW_CASES` for true gaps
  - `ENHANCE_CASES` for partial coverage
  - `PREREQ_CASES` for setup/flows already covered

## Usage Examples

### Coverage-first test generation
User: “Generate tests for MARD-719”
1. Run: `core/scripts/testrail.ps1 -GetCoverage -JiraKey "MARD-719"`
2. Use results to avoid duplicates and decide new vs enhance vs prereq.

## Decision Rules

- **Exact ref match only**: only exact Jira keys in `refs` count as direct coverage.
- If an existing case covers ~80%+ of a scenario → prefer **ENHANCE**.
- If an existing case is required for setup (login, navigation, baseline data) → mark as **PREREQ**.
- If no direct/related case covers the scenario → create **NEW**.

## Output Format (coverage)

Coverage analysis returns:

```json
{
  "jira_key": "MARD-719",
  "project_id": 15,
  "analyzed_at": "2026-02-06T12:34:56",
  "direct_cases": [{ "id": 1234, "title": "...", "refs": "MARD-719", "section_id": 10 }],
  "related_cases": [{ "id": 1200, "title": "...", "refs": "MARD-700", "potential_use": "Prerequisite or Related" }],
  "summary": { "direct_count": 1, "related_count": 1, "has_coverage": true }
}
```

