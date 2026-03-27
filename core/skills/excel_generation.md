# Excel Generation Skill

This skill exports the Design Agent output into an Excel file suitable for TestRail workflows.

## Capabilities

- Create an `.xlsx` file with sheets:
  - **New Cases**
  - **Enhancements**
  - **Prerequisites**
- Mapping is driven by `core/templates/excel_mapping.json`.

## Usage Examples

### Export design output to Excel
User: “Create the Excel export”
- Run: `core/scripts/excel.ps1 -InputJson "<path-or-json>" -OutputPath "outputs/<Project>/runs/<KEY>_<timestamp>/testrail.xlsx"`

## Output Format

Script output:

```json
{
  "status": "ok",
  "output_path": "/abs/path/to/testrail.xlsx",
  "sheets": ["New Cases", "Enhancements", "Prerequisites"],
  "counts": { "new_cases": 2, "enhance_cases": 1, "prereq_cases": 1 }
}
```

## Notes

- Requires the `ImportExcel` PowerShell module.
- The export does not push to TestRail; it produces an artifact for review/import.

