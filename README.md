# AIRA — AI Requirements & Test Case Assistant

AIRA is an AI-powered Business Analyst and Quality Engineer assistant that transforms Jira requirements into structured, testable specifications and TestRail-ready test cases — while preventing duplication with existing coverage.

AIRA also acts as a framework and context gateway that enables built-in and custom AI agents to retrieve, enrich, and reuse delivery knowledge across Jira, Confluence, and TestRail workflows.

Designed for regulated environments, AIRA provides transparent, auditable automation aligned with enterprise QA practices.

---

## Key capabilities

• Converts Jira requirements into structured BA/QE specifications  
• Generates TestRail-ready test cases  
• Prevents duplicate test coverage via cross-reference analysis  
• Retrieves structured context from Jira and Confluence  
• Multi-agent architecture supporting custom AI skills and plugins  
• Policy-driven validation and governance controls  
• Excel and CSV export for TestRail import  
• Extensible framework for additional AI agents  

---

## How AIRA works

AIRA operates as a multi-agent orchestration framework inside VS Code via GitHub Copilot Chat.

Specialist AI agents collaborate to:

1. retrieve structured requirement context from Jira and Confluence
2. analyze requirements and identify gaps
3. design test cases aligned with existing TestRail coverage
4. validate outputs according to configurable policies
5. export results in structured formats suitable for TestRail

The framework also enables custom agents to reuse contextual knowledge across delivery workflows.

---

## Architecture overview

Core integrations:

• Jira  
• Confluence  
• TestRail  
• GitHub / Bitbucket  

AIRA provides:

• context retrieval layer  
• agent orchestration layer  
• policy and validation engine  
• extensibility via plugins and overrides  

---

## Quick start

Clone repository:
git clone https://github.com/xLZDx/Aira

Open workspace in VS Code:

code aira

Install dependencies:
powershell -ExecutionPolicy Bypass -File core/scripts/aira.ps1 -InstallDependencies

Run readiness check:
powershell -ExecutionPolicy Bypass -File core/scripts/aira.ps1 -Doctor


Then open GitHub Copilot Chat inside VS Code and interact with AIRA using natural language.

Example:
Analyze PROJ-123
Generate test cases for PROJ-123
Check TestRail coverage for PROJ-123

---

## Documentation

Full user guide and technical reference:

→ docs/USER_GUIDE.md

Includes:

• architecture description  
• agent system reference  
• policy configuration  
• plugin system  
• validation framework  
• usage examples  

---

## Intended users

• Business Analysts  
• Quality Engineers  
• Test Automation Engineers  
• delivery teams working with Jira and TestRail  
• teams adopting AI-assisted SDLC workflows  

---

## Extensibility

AIRA supports extension through:

• custom AI agents  
• plugins  
• policy configuration  
• templates  
• validation rules  

making it suitable as a foundation layer for AI-assisted delivery tooling.

---

## Ownership

Maintained by the AIRA project.

Originally developed for internal QA automation use cases across regulated industries.

No client-specific code or data is included in this repository.

---

## Contributions

This repository is maintained internally. External contributions are currently not accepted.

---

## Disclaimer

This project is provided "as is", without warranties or guarantees of any kind.

It is intended as a reusable engineering framework and reference implementation.

Enterprise support, SLAs, and custom integrations may be provided separately under commercial agreement.

---

## License

See LICENSE file for details.
