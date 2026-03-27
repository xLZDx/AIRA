# Example Plugin Skill

This is a skeleton skill provided by the `aira-example` plugin. Use it as a template for writing real plugin skills.

## Capabilities

- Demonstrates the expected skill file format
- Shows how AIRA discovers plugin skills via `plugins/<name>/skills/*.md`

## Usage Examples

### Placeholder action
User: "Run example skill"
- Run: (no real script; this is a template)

## Output Format

```json
{
  "status": "ok",
  "message": "This is an example plugin skill."
}
```

## Notes

- To enable this plugin, set `"enabled": true` in `plugins/aira-example/manifest.json`.
- Real plugins should reference scripts under `plugins/<name>/scripts/` or `core/scripts/`.
