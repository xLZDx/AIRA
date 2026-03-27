# aira-example plugin

This is a **skeleton plugin** demonstrating the AIRA v2 plugin pattern.

## Structure

```
plugins/aira-example/
├── manifest.json              # Plugin metadata (name, enabled, load_order)
├── skills/
│   └── example_skill.md       # Skill documentation (discovered by AIRA)
├── validation/
│   └── checks/
│       └── example_check.ps1  # Validation check (discovered by validate.ps1)
└── README.md
```

## How AIRA discovers plugins

1. `Resolve-AiraResourcePath` iterates `plugins/*/` sorted by `load_order` then name.
2. Only plugins with `"enabled": true` in `manifest.json` are considered.
3. Skills, prompts, templates, and validation checks are discovered by matching subfolder names.

## How to create your own plugin

1. Copy this folder: `cp -r plugins/aira-example plugins/my-plugin`
2. Edit `manifest.json` (set `"enabled": true`, adjust name/description).
3. Add your skill `.md` files under `skills/`.
4. Add validation checks under `validation/checks/`.
5. Optionally add prompts under `prompts/` or templates under `templates/`.
