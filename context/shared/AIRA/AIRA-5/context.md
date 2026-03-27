## Issue
- **Key:** AIRA-5
- **Summary:** Add PDF Export for Financial Reports
- **Type:** Story
- **Status:** To Do
- **Priority:** Medium
- **Created:** 2026-03-11
- **Last Updated:** 2026-03-11

## Description
## Overview
As a finance team member, I want to export any financial report to a branded PDF document so that I can share it with stakeholders who don't have system access.

## Business Context
Currently, users screenshot reports or copy data to Excel manually. This is error-prone and wastes ~4 hours/week per finance team member. PDF exports must match the company brand guidelines (logo, fonts, colors).

## Acceptance Criteria
| **ID** | **Scenario** | **Expected Result** |
| --- | --- | --- |
| AC-01 | User clicks "Export PDF" on any report | PDF generated within 10 seconds for reports up to 50 pages |
| AC-02 | PDF includes header with company logo | Logo, report title, date range, and generation timestamp in header |
| AC-03 | PDF includes all visible table data | Tables paginated correctly with repeated headers on each page |
| AC-04 | PDF includes charts/graphs | Charts rendered as vector graphics (SVG-to-PDF), not screenshots |
| AC-05 | User selects date range before export | Only the filtered data appears in the PDF |
| AC-06 | Report has more than 100 pages | Progress bar shown, export completes within 60 seconds |
| AC-07 | PDF export fails (timeout/error) | User notified with retry option, partial file not downloaded |
| AC-08 | Exported PDF opened in Adobe Reader | All fonts embedded, no missing character warnings |
| AC-09 | User exports report with no data | PDF shows "No data available for the selected period" message |

## Technical Notes
- Server-side rendering using Puppeteer (headless Chrome)
- Template engine: Handlebars with SCSS for styling
- Max concurrent exports: 5 (queue additional requests)
- Store generated PDFs in S3 with 24-hour TTL
- Endpoint: `POST /api/v2/reports/export` (async, returns job ID)
- Poll: `GET /api/v2/reports/export/{jobId`}

## Acceptance Criteria
- ID: AC-01 | Scenario: User clicks "Export PDF" on any report | Expected Result: PDF generated within 10 seconds for reports up to 50 pages
- ID: AC-02 | Scenario: PDF includes header with company logo | Expected Result: Logo, report title, date range, and generation timestamp in header
- ID: AC-03 | Scenario: PDF includes all visible table data | Expected Result: Tables paginated correctly with repeated headers on each page
- ID: AC-04 | Scenario: PDF includes charts/graphs | Expected Result: Charts rendered as vector graphics (SVG-to-PDF), not screenshots
- ID: AC-05 | Scenario: User selects date range before export | Expected Result: Only the filtered data appears in the PDF
- ID: AC-06 | Scenario: Report has more than 100 pages | Expected Result: Progress bar shown, export completes within 60 seconds
- ID: AC-07 | Scenario: PDF export fails (timeout/error) | Expected Result: User notified with retry option, partial file not downloaded
- ID: AC-08 | Scenario: Exported PDF opened in Adobe Reader | Expected Result: All fonts embedded, no missing character warnings
- ID: AC-09 | Scenario: User exports report with no data | Expected Result: PDF shows "No data available for the selected period" message

## Comments (4 total)
**Comment #1** by *Administrator* (2026-03-11):
> Puppeteer headless Chrome is our best option for server-side PDF rendering. Alternatives considered: wkhtmltopdf is deprecated, PDFKit is too low-level for complex layouts. Puppeteer gives us pixel-perfect rendering that matches what users see in the browser.

**Comment #2** by *Administrator* (2026-03-11):
> Brand guidelines doc from marketing: use Helvetica Neue for body text, company logo in top-left at 40px height, primary color #1A73E8 for headers. PDF must include page numbers in footer as Page X of Y.

**Comment #3** by *Administrator* (2026-03-11):
> We need to handle reports with very wide tables with 20+ columns. Options: a) landscape mode for wide tables, b) auto-rotate to landscape when table exceeds portrait width. I prefer option b with a per-section rotation.

**Comment #4** by *Administrator* (2026-03-11):
> Security concern: generated PDFs should NOT contain internal URLs or debug information. We need to strip any internal links and replace with public-facing equivalents before rendering.


## Direct Dependencies
| Key | Relationship | Status | Summary | Context Link |
|-----|-------------|--------|---------|-------------|
| [None] | - | - | - | - |

## All Linked Issues (0 total)
| Key | Type | Status | Summary |
|-----|------|--------|---------|
| (none) | - | - | - |

## Existing Coverage (TestRail)
- Status: Not Checked (use -WithCoverage to include)
- Direct cases: -
- Related cases: -

## References & Links
- Jira: [AIRA-5](http://jira.localhost:8080//browse/AIRA-5)
- Confluence:
  - [Reporting and Export Technical Guidelines](http://confluence.localhost:8090/spaces/AIRA/pages/1245191/Reporting+and+Export+Technical+Guidelines)
- Attachments: 3 file(s) (downloaded: 3)
  - `export_template_config.txt` (text/plain, downloaded)
  - `pdf_export_architecture.svg` (image/svg+xml, downloaded)
  - `sample_report_output.pdf` (application/pdf, downloaded)

## Attachment Extractions
<!-- ATTACHMENT_ANALYSIS_PLACEHOLDER -->
*Extracted data from 3 attachment(s) saved to `sources/attachment_extractions.json` for AI analysis.*
*The AI agent will analyze and summarize each file below during the analysis phase.*

- **export_template_config.txt** (Text, 1.3 KB) - extraction: utf8_text_read
- **pdf_export_architecture.svg** (SVG Diagram, 5.8 KB) - extraction: svg_text_elements
- **sample_report_output.pdf** (PDF Document, 2.5 KB) - extraction: pdf_text_scan

## Concerns / Known Bugs (NOT analyzed as requirements)
- (none detected)
