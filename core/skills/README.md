# Skills (AIRA v2)

Skill files document how AIRA should use scripts/modules to perform operations.

## Structure

Each skill should include:
- **Capabilities**
- **Usage Examples** (User says X → run script Y)
- **Output Format** (JSON schema/shape)
- (Optional) **Notes** (policy constraints, caching, edge cases)

## Adding a new skill

1. Create a new `*.md` file under `core/skills/` (or a plugin under `plugins/<name>/skills/`).
2. Reference the script(s) under `core/scripts/` or `plugins/<name>/scripts/`.
3. If the skill introduces validations, add corresponding checks under:
   - `core/validation/checks/` or `plugins/<name>/validation/checks/`

