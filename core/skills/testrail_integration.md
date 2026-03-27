# TestRail Integration Skill

This skill enables bidirectional TestRail operations.

## Capabilities

### READ Operations (Source)

1. **Coverage Analysis**
   - Find existing cases by Jira reference
   - Discover related cases in same feature area
   - Calculate coverage percentage

2. **Case Retrieval**
   - Fetch single case by ID
   - Get case with all steps and metadata
   - Cached for 60 minutes

3. **Section Discovery**
   - List all sections in a project
   - Find appropriate section for new cases

### WRITE Operations (Target)

1. **Create Cases**
   - Create single case with full details
   - Batch create multiple cases
   - Auto-create sections if needed

2. **Update Cases**
   - Modify existing case fields
   - Update priority, references, preconditions

3. **Enhance Cases**
   - Add new steps to existing case
   - Append references
   - Preserve existing steps

## Usage Patterns

### Before Generating Tests
Always check existing coverage first:
```
User: "Generate tests for MARD-719"
AIRA: [Runs coverage analysis]
      "Found 2 existing cases. I'll avoid duplicates."
```

### When Coverage Exists
Propose enhancement over creation:
```
AIRA: "TC-1235 partially covers this scenario.
       Recommend: Add 2 steps instead of new case."
```

### For Prerequisites
Reference existing cases:
```
AIRA: "TC-1100 (login flow) should run before new cases.
       I'll mark it as a prerequisite."
```

## Policy Enforcement

- Respect `forbidden_priorities` from policy
- Enforce `max_cases_per_batch` limit
- Validate references format
- Check section permissions

## Caching Strategy

| Data Type | Cache Location | TTL |
|-----------|----------------|-----|
| Coverage analysis | `context/testrail/{ProjectID}/coverage/` | 30 min |
| Individual cases | `context/testrail/{ProjectID}/cases/` | 60 min |
| Sections | `context/testrail/{ProjectID}/sections/` | 60 min |

## Error Handling

- Network failures: Retry with backoff, cache fallback
- Auth failures: Clear instructions to check credentials
- Rate limits: Queue requests, warn user

## Script Interface

Use `core/scripts/testrail.ps1`:
- `-GetCoverage -JiraKey <KEY> [-ProjectId <id>]`
- `-GetCase -CaseId <id>`
- `-CreateCase -SectionId <id> -CaseJson <jsonOrPath>`
- `-UpdateCase -CaseId <id> -CaseJson <jsonOrPath>`
- `-EnhanceCase -CaseId <id> -CaseJson <jsonOrPath>`
- `-BatchCreate -CasesJson <jsonOrPath> -SectionId <id>`
- `-GetSections -ProjectId <id>`
- `-TestConnection`

