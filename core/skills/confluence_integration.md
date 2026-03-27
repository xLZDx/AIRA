# Confluence Integration Skill

This skill enables Confluence (Wiki) read operations for AIRA v2.

## Capabilities

- **Connection test** (read-only)
- **Get page by ID** (metadata + body in storage/view)
- **Search pages** by keyword (CQL text search), optionally constrained by space

## Usage Examples

### Test connectivity
User: “Test Confluence connection”
- Run: `core/scripts/confluence.ps1 -TestConnection`

### Fetch a page by ID
User: “Pull Confluence page 123456”
- Run: `core/scripts/confluence.ps1 -PageId "123456" -Format both`

### Search for relevant documentation
User: “Search Confluence for ‘AUM metrics’ in space MARDOC”
- Run: `core/scripts/confluence.ps1 -Query "AUM metrics" -SpaceKey "MARDOC" -Limit 10`

## Output Format

### Get page

```json
{
  "page_id": "123456",
  "title": "AUM Dashboard Spec",
  "space": { "key": "MARDOC", "name": "MARD Documentation" },
  "version": 12,
  "url": "https://.../pages/123456",
  "labels": ["spec", "dashboard"],
  "fetched_at": "2026-02-06T12:34:56",
  "body_storage": "<p>...</p>",
  "body_view": "<p>...</p>"
}
```

### Search

```json
{
  "query": "AUM metrics",
  "space_key": "MARDOC",
  "results": [
    { "id": "123456", "title": "AUM Dashboard Spec", "space": { "key": "MARDOC", "name": "..." }, "version": 12, "url": "..." }
  ]
}
```

