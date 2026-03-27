# Overrides (Examples)

This folder is for **team-specific customization** without modifying `core/`.

## How AIRA resolves overrides

For prompts/templates/rules, AIRA resolves resources in this order:
1. `overrides/` (highest priority)
2. enabled `plugins/`
3. `core/` (baseline)

Resolution is **by exact filename** (example: `spec_template.md`).

## Why these examples are ignored by default

All example override files in this folder end with **`.example`**, e.g.:
- `overrides/templates/spec_template.md.example`

Because the filename does not exactly match the core resource name, it will **NOT** override anything.

## How to enable an override

1. Copy an example file.
2. Remove the `.example` suffix so the filename matches the core resource name exactly.

Examples:
- Enable a custom spec template:
  - copy `overrides/templates/spec_template.md.example`
  - to `overrides/templates/spec_template.md`

- Enable a custom design agent prompt:
  - copy `overrides/prompts/design_agent.md.example`
  - to `overrides/prompts/design_agent.md`

## Notes

- Keep overrides small and focused; prefer templates for formatting changes.
- Policy constraints in `.aira/*.policy.json` still apply (locked fields cannot be overridden).

