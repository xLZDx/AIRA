# Processed Context: AIRA-5

## Processing Metadata
- **Source**: context/shared/AIRA/AIRA-5/context.md
- **Processed**: 2026-03-23T15:45:00Z
- **Validation Status**: FAIL (user-overridden to proceed)
- **Completeness Grade**: Sufficient
- **Sources Consumed**: issue.json, comments.json (4), attachment_extractions.json (3), Confluence page 1245191

---

## Issue Summary

| Field | Value |
|-------|-------|
| **Key** | AIRA-5 |
| **Summary** | Add PDF Export for Financial Reports |
| **Type** | Story |
| **Status** | To Do |
| **Priority** | Medium |
| **Project** | AIRA DEMO |
| **Created** | 2026-03-11 |
| **Last Updated** | 2026-03-11 |
| **Components** | (none) |
| **Labels** | (none) |
| **Fix Versions** | (none) |
| **Dependencies** | None |
| **Attachments** | 3 (all downloaded and extracted) |
| **Linked Confluence** | Reporting and Export Technical Guidelines (page 1245191) |

---

## Requirements Overview

This story implements branded PDF export functionality for financial reports. Finance team members currently rely on manual screenshots and Excel copy-paste to share report data with external stakeholders, wasting approximately 4 hours per week per team member. The feature will add an "Export PDF" button to all financial reports, generating branded PDFs that match company guidelines (logo, fonts, colors) with proper pagination, embedded charts, and font embedding.

The implementation involves server-side HTML-to-PDF rendering using a template engine (Handlebars + SCSS) to produce styled HTML, which is then converted to PDF. An asynchronous API pattern (POST /api/v2/reports/export returning a job ID, polled via GET /api/v2/reports/export/{jobId}) handles the export lifecycle. Generated PDFs are stored in S3-compatible storage with 24-hour TTL signed download URLs. The system must handle concurrent exports (queuing beyond the limit) and degrade gracefully for very large reports.

> **CRITICAL UNRESOLVED BLOCKER**: The rendering technology is disputed. The Jira story, all 3 attachments, and Comment #1 specify **Puppeteer (headless Chrome)**, but the linked Confluence page documents that the Architecture Review Board (ADR-2025-047) has **approved wkhtmltopdf 0.12.6** and **explicitly REJECTED and PROHIBITED Puppeteer** (SEC-2025-112). This contradiction must be resolved before implementation. See [Unresolved Items U-01](#unresolved-items) for details.

---

## Structured Description

### User Story
**As a** finance team member, **I want to** export any financial report to a branded PDF document **so that** I can share it with stakeholders who don't have system access.

[Source: AIRA-5 Description]

### Business Context
- Finance team members currently screenshot reports or copy data to Excel manually
- This process is error-prone and wastes approximately 4 hours per week per team member
- PDF exports must match company brand guidelines (logo, fonts, colors)

[Source: AIRA-5 Description]

### Technical Architecture

> **NOTE**: The rendering engine specified below (Puppeteer) is subject to the unresolved technology contradiction (U-01). All technical references to Puppeteer should be read as "the selected rendering engine, pending ARB resolution."

- **Rendering**: Server-side HTML-to-PDF rendering using [DISPUTED  see U-01] headless browser
- **Template Engine**: Handlebars 4.x with SCSS for styling [Source: AIRA-5 Description, Attachment: export_template_config.txt]
- **Custom Helpers**: ormatDate, currency, statusBadge, chartImage, 	ableOfContents [Source: Attachment: export_template_config.txt]
- **Runtime**: Node.js 20 LTS [Source: Attachment: pdf_export_architecture.svg]
- **Charts**: Chart.js (server-side rendered) [Source: Attachment: pdf_export_architecture.svg]
- **Concurrency**: Max concurrent exports with queue for additional requests [DISPUTED  see U-03]
- **Storage**: S3-compatible (MinIO) with 24-hour TTL signed URLs [Source: AIRA-5 Description, Attachment: export_template_config.txt, Confluence page 1245191]
- **API Pattern**:
  - Submit export: POST /api/v2/reports/export (async, returns job ID) [Source: AIRA-5 Description]
  - Poll status: GET /api/v2/reports/export/{jobId} [Source: AIRA-5 Description]

### Page Setup
- **Paper**: A4 (210mm x 297mm) [Source: Attachment: export_template_config.txt]
- **Orientation**: Portrait (default), auto-rotate to landscape for wide tables [Source: AIRA-5 Comment #3, Attachment: export_template_config.txt]
- **Margins**: 15mm all sides [Source: Attachment: export_template_config.txt]
- **Header**: Company logo (left), report title (center), date (right) [Source: Attachment: export_template_config.txt]
- **Footer**: Page X of Y (center), "Confidential" watermark (right) [Source: Attachment: export_template_config.txt, Confluence page 1245191]

---

## Acceptance Criteria (Structured)

| # | Criterion | Testable | Refinement Notes | Source |
|---|-----------|----------|------------------|--------|
| AC-01 | User clicks "Export PDF" on any report: PDF generated within 10 seconds for reports up to 50 pages | Yes | Consistent with Confluence performance tier. "Any report" scope is ambiguous  see U-06 | [Source: AIRA-5 Description] |
| AC-02 | PDF includes header with company logo: Logo, report title, date range, and generation timestamp in header | Yes | Consistent across Jira, attachment config, and Confluence. Logo top-left at 40px height. | [Source: AIRA-5 Description, AIRA-5 Comment #2, Confluence page 1245191] |
| AC-03 | PDF includes all visible table data: Tables paginated correctly with repeated headers on each page | Yes | Clear and testable. Wide tables (20+ columns) should auto-rotate to landscape per-section. | [Source: AIRA-5 Description, AIRA-5 Comment #3] |
| AC-04 | PDF includes charts/graphs: Charts rendered as vector graphics (SVG-to-PDF), not screenshots | Yes | Architecture uses Chart.js for server-side chart rendering. SVG vector output is specified. | [Source: AIRA-5 Description, Attachment: pdf_export_architecture.svg] |
| AC-05 | User selects date range before export: Only the filtered data appears in the PDF | Yes | Clear and testable. Implies date range filter UI exists. | [Source: AIRA-5 Description] |
| AC-06 | Report has more than 100 pages: Progress bar shown, export completes within 60 seconds | **Needs Refinement** | **Three-way conflict**: Jira says synchronous with progress bar (60s), attachment config says 200 max pages with 120s timeout, Confluence says 100-page cap with async queue + email notification. See U-02. Also **missing 51100 page tier**  see U-04. | [Source: AIRA-5 Description] |
| AC-07 | PDF export fails (timeout/error): User notified with retry option, partial file not downloaded | Yes | Clear error handling requirement. Should specify notification mechanism (in-app, toast, modal). | [Source: AIRA-5 Description] |
| AC-08 | Exported PDF opened in Adobe Reader: All fonts embedded, no missing character warnings | Yes | Requires Helvetica Neue (body) and Montserrat (headings) to be embedded. See U-05 for heading font gap. | [Source: AIRA-5 Description, AIRA-5 Comment #2, Confluence page 1245191] |
| AC-09 | User exports report with no data: PDF shows "No data available for the selected period" message | Yes | Clear edge case. Should specify whether the empty-data PDF includes headers/branding or is a minimal message. | [Source: AIRA-5 Description] |

**Summary**: 9 acceptance criteria total. 8 are testable as-is. AC-06 has a critical conflict requiring resolution before test design.

---

## Comment Insights

### Decisions

1. **Rendering engine selection (DISPUTED)**: Puppeteer headless Chrome was chosen over wkhtmltopdf ("deprecated") and PDFKit ("too low-level"). Rationale: pixel-perfect rendering matching browser display. **However, this decision conflicts with the Architecture Review Board's approval of wkhtmltopdf and prohibition of Puppeteer  see U-01.** [Source: AIRA-5 Comment #1]

2. **Wide table handling**: Auto-rotate to landscape on a per-section basis when table width exceeds portrait width (option b selected over full landscape mode). [Source: AIRA-5 Comment #3]

3. **Security: URL stripping**: Generated PDFs must NOT contain internal URLs or debug information. Internal links must be stripped and replaced with public-facing equivalents before rendering. [Source: AIRA-5 Comment #4]

### Open Questions
- (None explicitly raised in comments  but significant questions arise from cross-source contradictions; see Unresolved Items)

### Scope Changes
- **Added**: Per-section landscape rotation for wide tables (not in original AC). [Source: AIRA-5 Comment #3]
- **Added**: URL stripping/sanitization security requirement (not in original AC). [Source: AIRA-5 Comment #4]

### Technical Notes
- **Brand guidelines from marketing**: Helvetica Neue body text, company logo top-left at 40px height, primary color #1A73E8 for headers, footer with "Page X of Y". [Source: AIRA-5 Comment #2]
- **Heading font (from Confluence only)**: Montserrat for headings  not mentioned in Jira. [Source: Confluence page 1245191]
- **Footer completeness (merged across sources)**: Page X of Y + generation timestamp + "Confidential" watermark. Jira Comment #2 specifies "Page X of Y" only; Confluence and attachment config add timestamp and "Confidential" watermark. [Source: AIRA-5 Comment #2, Attachment: export_template_config.txt, Confluence page 1245191]

---

## Dependency Analysis

No direct dependencies are linked to AIRA-5 in Jira. [Source: AIRA-5 issue.json  issuelinks array is empty]

| Key | Relevance | Impact | Status |
|-----|-----------|--------|--------|
| (none) |  |  |  |

**Note**: The linked Confluence page (1245191: "Reporting and Export Technical Guidelines") serves as an authoritative architecture/policy reference but is not a Jira dependency. Its content has been incorporated throughout this processed context.

---

## Attachment Analysis

### 1. export_template_config.txt
- **Type**: Text configuration file (1.3 KB)
- **Description**: Handlebars 4.x template engine configuration for PDF export. Defines custom helpers (ormatDate, currency, statusBadge, chartImage, 	ableOfContents), page setup (A4, 15mm margins, portrait default), and output limits.
- **Requirements Implied**:
  - Handlebars 4.x with 5 custom template helpers [Source: Attachment: export_template_config.txt]
  - A4 paper, portrait default, landscape for wide tables [Source: Attachment: export_template_config.txt]
  - Header: logo (left), title (center), date (right) [Source: Attachment: export_template_config.txt]
  - Footer: Page X of Y (center), Confidential watermark (right) [Source: Attachment: export_template_config.txt]
  - **DISPUTED**: Puppeteer 21.x as renderer, wkhtmltopdf explicitly rejected [Source: Attachment: export_template_config.txt  contradicted by Confluence ADR]
  - **DISPUTED**: Max 200 pages, 120s timeout, 4 concurrent renders [Source: Attachment: export_template_config.txt  conflicts with Confluence limits]
  - Max file size: 50MB [Source: Attachment: export_template_config.txt]
  - Storage: S3-compatible (MinIO), 24h TTL signed URLs [Source: Attachment: export_template_config.txt]

### 2. pdf_export_architecture.svg
- **Type**: SVG architecture diagram (5.8 KB)
- **Description**: System architecture diagram showing the PDF export rendering pipeline: User  API Gateway (rate-limited, 10 req/min/user)  Export Service (Node.js, validates request, queues job)  Template Engine (Handlebars + custom helpers, injects data/charts/tables)  PDF Renderer (Puppeteer headless Chrome)  Object Storage (S3, 24h TTL, signed download URL).
- **Requirements Implied**:
  - API Gateway with rate limiting: 10 requests/min/user [Source: Attachment: pdf_export_architecture.svg]
  - Export Service runs on Node.js 20 LTS [Source: Attachment: pdf_export_architecture.svg]
  - Two-step rendering: HTML build then PDF render [Source: Attachment: pdf_export_architecture.svg]
  - Tech stack: Node.js 20 LTS, Puppeteer 21.x [DISPUTED], Handlebars 4.x, Chart.js [Source: Attachment: pdf_export_architecture.svg]
  - Report specs: A4 portrait, 15mm margins, max 200 pages [DISPUTED], 50MB max, CONFIDENTIAL watermark [Source: Attachment: pdf_export_architecture.svg]

### 3. sample_report_output.pdf
- **Type**: PDF document sample (2.5 KB)
- **Description**: A sample monthly analytics report (January 2026) demonstrating the export output format. Shows sections for User Activity, Feature Usage, Performance metrics, and Top Issues. Generated by "Export Service Puppeteer 21.x" on 2026-02-01. Single-page report with "CONFIDENTIAL" watermark and "Page 1 of 1" footer.
- **Requirements Implied**:
  - Report structure: multiple metric sections with headers, tabular data, and percentages [Source: Attachment: sample_report_output.pdf]
  - Footer format confirmed: "Page X of Y" with CONFIDENTIAL watermark [Source: Attachment: sample_report_output.pdf]
  - **Performance insight**: The "Top Issues" section notes "PDF export timeout for reports > 100 pages"  confirming that large report timeout is a known production issue [Source: Attachment: sample_report_output.pdf]
  - **Data sensitivity**: Contains specific operational metrics (user counts, API call volumes, availability percentages). May contain production-like data  flagged for review. [Source: Attachment: sample_report_output.pdf]

---

## Confluence Reference: Reporting and Export Technical Guidelines (page 1245191)

**Owner**: Engineering | **Last Updated**: 2026-01-05 | **Status**: Approved by Architecture Review Board

This Confluence page is the authoritative architecture and policy reference for PDF generation across all reporting features. Key extracts incorporated into this processed context:

### Architecture Decision (ADR-2025-047)
- **Approved**: wkhtmltopdf 0.12.6  lightweight, no browser dependency, fast, proven in production for 3 years
- **Rejected**: Puppeteer (heavy resource usage, security risk, not approved by security team), PDFKit (too low-level), Prince XML (commercial license ,800/server)
- **Security Prohibition**: SEC-2025-112 explicitly prohibits Puppeteer/headless Chrome for server-side PDF generation

[Source: Confluence page 1245191]

### Brand Specifications (Confluence)
| Element | Specification |
|---------|---------------|
| Body Font | Helvetica Neue |
| Heading Font | **Montserrat** (not mentioned in Jira  see U-05) |
| Logo | Top-left, 40px height, full color on white background |
| Primary Color | #1A73E8 (headers, links) |
| Footer | Page X of Y, generation timestamp, "Confidential" watermark |

[Source: Confluence page 1245191]

### Performance Tiers (Confluence)
| Report Size | Target | Handling |
|-------------|--------|----------|
|  50 pages | 10 seconds | Synchronous |
| 51100 pages | 30 seconds | Synchronous |
| 100+ pages | N/A (async) | Background queue + email notification |

[Source: Confluence page 1245191]

### Infrastructure (Confluence)
- Max concurrent renders: 5 (queue additional)
- Storage: S3, 24-hour TTL

[Source: Confluence page 1245191]

---

## Requirements Skeleton

### Functional Requirements

| # | Requirement | Source |
|---|-------------|--------|
| FR-01 | System shall provide an "Export PDF" button on all financial report views | [Source: AIRA-5 Description] |
| FR-02 | System shall generate a branded PDF matching company brand guidelines (logo, fonts, colors) | [Source: AIRA-5 Description, Comment #2, Confluence page 1245191] |
| FR-03 | System shall include the company logo (top-left, 40px height), report title, date range, and generation timestamp in the PDF header | [Source: AIRA-5 AC-02, Comment #2, Confluence page 1245191] |
| FR-04 | System shall paginate table data with repeated column headers on each page | [Source: AIRA-5 AC-03] |
| FR-05 | System shall auto-rotate sections to landscape orientation when table width exceeds portrait width (per-section rotation for tables with 20+ columns) | [Source: AIRA-5 Comment #3, Attachment: export_template_config.txt] |
| FR-06 | System shall render charts/graphs as vector graphics (SVG-to-PDF), not raster screenshots | [Source: AIRA-5 AC-04] |
| FR-07 | System shall filter PDF content based on user-selected date range | [Source: AIRA-5 AC-05] |
| FR-08 | System shall display a progress indicator for large report exports | [Source: AIRA-5 AC-06  specific UX pattern disputed, see U-02] |
| FR-09 | System shall notify the user on export failure with a retry option and shall not download partial files | [Source: AIRA-5 AC-07] |
| FR-10 | System shall embed all required fonts (Helvetica Neue body, Montserrat headings) in the PDF to prevent missing character warnings | [Source: AIRA-5 AC-08, Comment #2, Confluence page 1245191] |
| FR-11 | System shall display "No data available for the selected period" when exporting a report with no data | [Source: AIRA-5 AC-09] |
| FR-12 | System shall include "Page X of Y" page numbering in the PDF footer | [Source: AIRA-5 Comment #2, Confluence page 1245191] |
| FR-13 | System shall include a generation timestamp and "Confidential" watermark in the PDF footer | [Source: Attachment: export_template_config.txt, Confluence page 1245191] |
| FR-14 | System shall expose asynchronous API endpoints: POST /api/v2/reports/export (submit, returns job ID) and GET /api/v2/reports/export/{jobId} (poll status) | [Source: AIRA-5 Description] |
| FR-15 | System shall store generated PDFs in S3-compatible storage with 24-hour TTL signed download URLs | [Source: AIRA-5 Description, Attachment: export_template_config.txt, Confluence page 1245191] |
| FR-16 | System shall provide Handlebars template helpers: ormatDate, currency, statusBadge, chartImage, 	ableOfContents | [Source: Attachment: export_template_config.txt] |

### Non-Functional Requirements

| # | Requirement | Source |
|---|-------------|--------|
| NFR-01 | Reports  50 pages shall generate within 10 seconds | [Source: AIRA-5 AC-01, Confluence page 1245191] |
| NFR-02 | Reports 51100 pages shall generate within 30 seconds | [Source: Confluence page 1245191  **missing from Jira AC, see U-04**] |
| NFR-03 | Reports > 100 pages: handling approach is **DISPUTED**  see U-02 | [Source: AIRA-5 AC-06, Attachment: export_template_config.txt, Confluence page 1245191] |
| NFR-04 | Max concurrent renders: **DISPUTED**  4 (attachment config) vs 5 (Jira, Confluence)  see U-03 | [Source: AIRA-5 Description, Attachment: export_template_config.txt, Confluence page 1245191] |
| NFR-05 | Max file size per PDF: 50 MB | [Source: Attachment: export_template_config.txt] |
| NFR-06 | API rate limit: 10 export requests per minute per user | [Source: Attachment: pdf_export_architecture.svg] |

### Security Requirements

| # | Requirement | Source |
|---|-------------|--------|
| SEC-01 | Generated PDFs shall NOT contain internal URLs or debug information; internal links shall be stripped and replaced with public-facing equivalents before rendering | [Source: AIRA-5 Comment #4] |
| SEC-02 | PDF rendering engine choice is subject to security team assessment SEC-2025-112  Puppeteer is currently **PROHIBITED** for server-side use | [Source: Confluence page 1245191] |

### Constraints & Assumptions

| # | Type | Statement | Source |
|---|------|-----------|--------|
| CON-01 | Constraint | PDF page format is A4 (210mm  297mm) | [Source: Attachment: export_template_config.txt] |
| CON-02 | Constraint | Margins are 15mm on all sides | [Source: Attachment: export_template_config.txt] |
| CON-03 | Constraint | Max page limit per report is **DISPUTED** (100 vs 200)  see U-02 | [Source: Attachment: export_template_config.txt, Confluence page 1245191] |
| CON-04 | Assumption | A date range filter UI already exists on report views (AC-05 implies this) | [Inferred from: AIRA-5 AC-05] |
| CON-05 | Assumption | The Handlebars template engine and SCSS styling pipeline are pre-existing or will be built as part of this story | [Inferred from: AIRA-5 Description, Attachment: export_template_config.txt] |
| CON-06 | Assumption | "Financial reports" refers to report views within the existing application (scope of eligible reports is undefined  see U-06) | [Inferred from: AIRA-5 Description] |

### Out of Scope
- No explicit exclusions mentioned in any source. [Source: all AIRA-5 sources  absence]

---

## Unresolved Items

| # | Item | Type | Severity | Recommendation |
|---|------|------|----------|----------------|
| **U-01** | **Rendering engine contradiction**: Jira + all attachments + Comment #1 specify Puppeteer; Confluence ADR-2025-047 approves wkhtmltopdf and SEC-2025-112 prohibits Puppeteer | Contradictory | **CRITICAL  BLOCKER** | Escalate to Architecture Review Board / Product Owner. Either (a) update Jira story to use wkhtmltopdf per ADR, or (b) file a security exception for Puppeteer and get ADR amended. **All downstream analysis and test design will note this as unresolved.** |
| **U-02** | **Max page limit and large-report UX  three-way conflict**: Jira AC-06 = no explicit max, synchronous with progress bar (60s); attachment config = 200 pages, 120s timeout; Confluence = 100 pages, async queue + email notification | Contradictory | **CRITICAL** | Confirm max page limit (100 or 200). Confirm large-report handling pattern (synchronous progress bar vs async background job with email). Update AC-06 accordingly. |
| **U-03** | **Concurrent render limit inconsistency**: attachment config says 4, Jira description and Confluence both say 5 | Contradictory | High | Confirm whether production cap is 4 or 5 concurrent renders. Update the divergent source. |
| **U-04** | **Missing 51100 page performance tier**: Confluence defines 30-second target for this range; no corresponding Jira AC exists | Missing | High | Add a new acceptance criterion covering 51100 page reports with 30-second target, or explicitly mark this tier as out of scope for this story. |
| **U-05** | **Heading font missing from Jira**: Confluence brand spec defines Montserrat for headings; Jira Comment #2 only mentions Helvetica Neue for body text | Missing | High | Add Montserrat heading font to Jira story brand requirements, or confirm whether Jira or Confluence is the source of truth for typography. |
| **U-06** | **Ambiguous report scope  "any financial report"**: No enumeration of report types, no clarity on whether all reports share the same layout or some need special templates | Ambiguous | Medium | Clarify the specific financial report types in scope. Identify if any require unique layouts (e.g., chart-heavy dashboards vs data-heavy ledgers). |
| **U-07** | **Timeout value inconsistency**: AC-06 says 60 seconds for 100+ page reports; attachment config says 120-second timeout per render | Contradictory | Medium | Align timeout values across AC and implementation config. |
| **U-08** | **Missing non-functional requirements**: No specification for accessibility (PDF/UA compliance), internationalization (RTL, locale formatting), audit/logging, authorization (roles permitted to export), or filename convention | Missing | Medium | Determine if accessibility, i18n, audit logging, authorization, and filename conventions are in scope. If yes, add requirements. If no, explicitly mark as out of scope. |
| **U-09** | **wkhtmltopdf status contradiction**: Jira Comment #1 calls it "deprecated"; attachment config says "rejected due to poor CSS Grid support"; Confluence describes it as "proven in production for 3 years" and APPROVED | Contradictory | High | Directly tied to U-01. The team's assessment of wkhtmltopdf is opposite to the ARB's assessment. Resolution of U-01 will resolve this. |
| **U-10** | **Sample report may contain production data**: The sample_report_output.pdf contains specific operational metrics (2,847 users, 99.94% availability). If real, this data should not be in Jira attachments. | Safety | Low | Confirm whether sample data is synthetic or production-derived. If production data, remove from Jira and regenerate with synthetic data. |

---

## Questions for Stakeholder (Prioritized)

### Critical (blocks test design)
1. **Rendering engine**: Is the team aware of ADR-2025-047 (wkhtmltopdf approved) and SEC-2025-112 (Puppeteer prohibited)? Has a security exception been filed? Should this story be redesigned around wkhtmltopdf? [Related: U-01, U-09]
2. **Large reports (100+ pages)**: Synchronous progress bar with 60-second timeout (Jira AC-06), or async background job with email notification (Confluence)? These require fundamentally different API, frontend, and infrastructure designs. [Related: U-02]
3. **Max page limit**: Is the cap 100 pages (Confluence) or 200 pages (attachment config)? What happens when a user tries to exceed the limit? [Related: U-02]

### High (affects requirements completeness)
4. **Concurrent render limit**: Should production cap be 4 (config) or 5 (Jira + Confluence)? [Related: U-03]
5. **51100 page performance tier**: Should there be an AC for 30-second target per Confluence? [Related: U-04]
6. **Heading font**: Is Montserrat (from Confluence) required, or only Helvetica Neue (from Jira)? [Related: U-05]

### Medium (affects scope)
7. **Report types**: Which specific financial report types are in scope? Do they share templates? [Related: U-06]
8. **Authorization**: Which user roles can export? Does export respect data-level access controls? [Related: U-08]
9. **Timeout**: Should the timeout be 60 seconds (AC-06) or 120 seconds (config)? [Related: U-07]
